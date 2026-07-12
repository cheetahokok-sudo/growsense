import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../food_data.dart';
import '../i18n.dart';
import '../theme.dart';

/// Food tab — the preset library with search + category filter,
/// mirroring the PWA's food browse modal. Tapping Log records a
/// nutrition_log_items row for the active child + logDate under the
/// selected meal slot. Also hosts the parent's own custom foods and a
/// one-time explainer about why the app tracks protein, not calories.
class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  List<FoodItem> _reference = [];
  String _query = '';
  String? _category; // null = all
  bool _showExplainer = false;
  String? _loadedChildId;

  static const _explainerPrefKey = 'gs_food_explainer_dismissed';

  @override
  void initState() {
    super.initState();
    loadFoodReference().then((foods) {
      if (mounted) setState(() => _reference = foods);
    });
    SharedPreferences.getInstance().then((p) {
      if (mounted && p.getBool(_explainerPrefKey) != true) {
        setState(() => _showExplainer = true);
      }
    });
    widget.appState.loadCustomFoods();
    widget.appState.loadFoodFrequency();
  }

  Future<void> _dismissExplainer() async {
    setState(() => _showExplainer = false);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_explainerPrefKey, true);
  }

  /// A custom_foods row stores values for THE serving, not per-100g.
  /// Back-calculate per-100g so the shared FoodItem math reproduces the
  /// parent's entered numbers exactly.
  FoodItem _customToFoodItem(Map<String, dynamic> r) {
    final grams = (r['serving_grams'] as num?)?.toDouble() ?? 100;
    double? per100(dynamic v) =>
        (v == null || grams <= 0) ? null : (v as num).toDouble() / grams * 100;
    return FoodItem.fromJson({
      'id': 'custom_${r['custom_food_id']}',
      'name': r['name'],
      'emoji': '⭐',
      'region': 'global',
      'category': 'custom',
      'prepNote': r['serving_description'],
      'per100g': {
        'protein_g': per100(r['protein_g']) ?? 0,
        'zinc_mg': per100(r['zinc_mg']),
        'calcium_mg': per100(r['calcium_mg']),
      },
      'servingGrams': grams,
      'source': 'Custom food',
    });
  }

  List<FoodItem> _filtered(List<FoodItem> all) {
    final q = _query.trim().toLowerCase();
    return [
      for (final f in all)
        if ((_category == null || f.category == _category) &&
            (q.isEmpty ||
                f.name.toLowerCase().contains(q) ||
                (f.prepNote ?? '').toLowerCase().contains(q)))
          f,
    ];
  }

  Future<void> _log(FoodItem food) async {
    final err = await widget.appState.recordNutritionLogItem(
      foodId: food.id,
      foodName: food.name,
      proteinG: _round1(food.proteinPerServing),
      zincMg: food.zincPerServing == null
          ? null
          : _round2(food.zincPerServing!),
      calciumMg: food.calciumPerServing == null
          ? null
          : _round1(food.calciumPerServing!),
    );
    if (!mounted) return;
    final t = widget.i18n.t;
    final slot = t(
      'meal.${widget.appState.activeMealSlot}',
      widget.appState.activeMealSlot,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
        content: Text(
          err == null
              ? '${food.emoji} ${food.name} · ${_fmtG(food.proteinPerServing)} ${t('flutter.g_protein', 'g protein')} → $slot'
              : '${t('flutter.not_saved', 'Not saved')}: $err',
        ),
      ),
    );
  }

  /// The custom_foods row backing a merged ⭐ FoodItem, by its list id.
  Map<String, dynamic>? _customRowFor(String itemId) {
    for (final r in widget.appState.customFoods) {
      if ('custom_${r['custom_food_id']}' == itemId) return r;
    }
    return null;
  }

  Future<void> _openCustomFoodSheet({Map<String, dynamic>? existing}) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GsColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(GsRadius.lg)),
      ),
      builder: (context) => _CustomFoodSheet(
        appState: widget.appState,
        i18n: widget.i18n,
        existing: existing,
      ),
    );
    if (result == null || !mounted) return;
    final t = widget.i18n.t;
    final msg = switch (result) {
      'deleted' => t('flutter.food.custom_deleted', 'Custom food removed'),
      'saved' => t('flutter.food.custom_saved', 'Custom food updated'),
      _ => t('flutter.food.custom_added', 'Custom food added'),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: GsColors.accentDark,
        content: Text(msg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        // Keep custom foods + frequency in sync with the active child.
        if (_loadedChildId != appState.activeChildId) {
          _loadedChildId = appState.activeChildId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            appState.loadCustomFoods();
            appState.loadFoodFrequency();
          });
        }
        final custom = [
          for (final r in appState.customFoods) _customToFoodItem(r),
        ];
        // Frequency boost: often-logged foods float up. Stable sort —
        // ties keep the curated order (customs first) — and the counts
        // refresh at most once a day, so nothing jumps mid-session.
        final counts = appState.foodLogCounts;
        final indexed = [...custom, ..._reference].asMap().entries.toList()
          ..sort((a, b) {
            final ca = counts[a.value.id] ?? 0;
            final cb = counts[b.value.id] ?? 0;
            if (ca != cb) return cb - ca;
            return a.key - b.key;
          });
        final all = [for (final e in indexed) e.value];
        final filtered = _filtered(all);
        return Column(
          children: [
            if (_showExplainer)
              _ExplainerCard(i18n: widget.i18n, onDismiss: _dismissExplainer),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: t('flutter.search_foods', 'Search {n} foods…', {
                    'n': '${all.length}',
                  }),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: GsColors.text3,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _CategoryChip(
                    label: t('flutter.all', 'All'),
                    selected: _category == null,
                    onTap: () => setState(() => _category = null),
                  ),
                  // "Mine" sits right next to All so parents discover
                  // (and can start) their own foods without hunting.
                  _CategoryChip(
                    label: t('flutter.food.cat_custom', '⭐ Mine'),
                    selected: _category == 'custom',
                    onTap: () => setState(() => _category = 'custom'),
                  ),
                  for (final c in foodCategories)
                    _CategoryChip(
                      label: t('flutter.cat.$c', c),
                      selected: _category == c,
                      onTap: () => setState(() => _category = c),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _MealSlotBar(appState: appState, i18n: widget.i18n),
            Expanded(
              child: _reference.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _category == 'custom'
                  // "Mine" view: the add button leads, then this
                  // child's own foods (or a hint when there are none
                  // yet) — so creating one is the obvious first step.
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: 1 + (filtered.isEmpty ? 1 : filtered.length),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _AddCustomTile(
                            i18n: widget.i18n,
                            onTap: _openCustomFoodSheet,
                          );
                        }
                        if (filtered.isEmpty) {
                          return _CustomEmptyHint(i18n: widget.i18n);
                        }
                        final f = filtered[i - 1];
                        return _FoodRow(
                          food: f,
                          onLog: _log,
                          i18n: widget.i18n,
                          onTapCard: f.category == 'custom'
                              ? () => _openCustomFoodSheet(
                                  existing: _customRowFor(f.id),
                                )
                              : null,
                        );
                      },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filtered.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i == filtered.length) {
                          return _AddCustomTile(
                            i18n: widget.i18n,
                            onTap: _openCustomFoodSheet,
                          );
                        }
                        final f = filtered[i];
                        return _FoodRow(
                          food: f,
                          onLog: _log,
                          i18n: widget.i18n,
                          onTapCard: f.category == 'custom'
                              ? () => _openCustomFoodSheet(
                                  existing: _customRowFor(f.id),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// One-time "why protein, not everything" card. Dismissible; the choice
/// is remembered per device.
class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard({required this.i18n, required this.onDismiss});
  final I18n i18n;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: GsColors.accentLight,
        borderRadius: BorderRadius.circular(GsRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '🌱 ${t('flutter.food.explainer_title', 'Why we track protein, not everything')}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: GsColors.accentDark,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, size: 18, color: GsColors.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            t(
              'flutter.food.explainer_body',
              "GrowSense isn't a calorie counter — it follows the nutrients that drive a child's height: protein, zinc and calcium. Log the protein part of a meal (the egg, chicken, milk, tofu) — you don't need to log every potato or piece of fruit.",
            ),
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: GsColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://www.growsense.life/blog/protein-and-height'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              t('flutter.food.explainer_link', 'Learn why →'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: GsColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GsColors.accent : GsColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? GsColors.accent : GsColors.border2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : GsColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Logging for" segmented control — same four slots as the PWA.
class _MealSlotBar extends StatelessWidget {
  const _MealSlotBar({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  static const _slots = ['breakfast', 'lunch', 'dinner', 'snack'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: GsColors.surface2,
          borderRadius: BorderRadius.circular(GsRadius.sm + 3),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _slots.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => appState.setMealSlot(_slots[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: appState.activeMealSlot == _slots[i]
                          ? GsColors.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(GsRadius.sm),
                      boxShadow: appState.activeMealSlot == _slots[i]
                          ? gsShadow
                          : null,
                    ),
                    child: Text(
                      i18n.t('meal.${_slots[i]}', _slots[i]),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: appState.activeMealSlot == _slots[i]
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: appState.activeMealSlot == _slots[i]
                            ? GsColors.text
                            : GsColors.text2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({
    required this.food,
    required this.onLog,
    required this.i18n,
    this.onTapCard,
  });
  final FoodItem food;
  final void Function(FoodItem) onLog;
  final I18n i18n;

  /// Custom foods: tapping the card body (not Log) opens edit/delete.
  final VoidCallback? onTapCard;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
      ),
      child: Row(
        children: [
          Text(food.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        food.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (food.isHighSodium) ...[
                      const SizedBox(width: 6),
                      _SaltyChip(i18n: i18n),
                    ],
                  ],
                ),
                Text(
                  [
                    if (food.prepNote != null) food.prepNote!,
                    '${_fmtG(food.servingGrams)} g · ${i18n.t('flutter.serving', 'serving')}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: GsColors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_fmtG(food.proteinPerServing)} g',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: GsColors.accent,
                ),
              ),
              Text(
                i18n.t('flutter.protein', 'protein'),
                style: const TextStyle(fontSize: 10.5, color: GsColors.text3),
              ),
            ],
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(52, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () => onLog(food),
              child: Text(
                i18n.t('flutter.log_btn', 'Log'),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
    if (onTapCard == null) return card;
    return GestureDetector(onTap: onTapCard, child: card);
  }
}

/// Amber "Salty" flag for high-sodium (processed/deli) foods — uses the
/// estimated-gold token, never the red clinical-flag colour.
class _SaltyChip extends StatelessWidget {
  const _SaltyChip({required this.i18n});
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: GsColors.estimatedLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '⚠ ${i18n.t('flutter.food.salty', 'Salty')}',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: GsColors.estimatedDark,
        ),
      ),
    );
  }
}

/// Shown in the "Mine" tab when the parent hasn't added any food yet —
/// turns an empty list into a gentle prompt instead of a blank screen.
class _CustomEmptyHint extends StatelessWidget {
  const _CustomEmptyHint({required this.i18n});
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
      child: Text(
        i18n.t(
          'flutter.food.custom_empty',
          'Foods you add appear here — tap ＋ above to create your first one. Great for a favourite brand, a home recipe, or a supplement.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: GsColors.text3,
        ),
      ),
    );
  }
}

class _AddCustomTile extends StatelessWidget {
  const _AddCustomTile({required this.i18n, required this.onTap});
  final I18n i18n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: GsColors.surface,
          borderRadius: BorderRadius.circular(GsRadius.md),
          border: Border.all(color: GsColors.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 18, color: GsColors.accent),
            const SizedBox(width: 6),
            Text(
              i18n.t('flutter.food.add_custom', 'Add your own food'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: GsColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add / edit custom-food sheet — mirror of the PWA's addCustomFood:
/// name + serving grams + protein are required; zinc / calcium optional.
/// Values are for one serving as written on the label. With [existing]
/// it opens prefilled in edit mode with Save changes + Delete; deleting
/// never touches history (log items snapshot values at log time).
class _CustomFoodSheet extends StatefulWidget {
  const _CustomFoodSheet({
    required this.appState,
    required this.i18n,
    this.existing,
  });
  final AppState appState;
  final I18n i18n;
  final Map<String, dynamic>? existing;

  @override
  State<_CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends State<_CustomFoodSheet> {
  final _name = TextEditingController();
  final _grams = TextEditingController();
  final _desc = TextEditingController();
  final _protein = TextEditingController();
  final _zinc = TextEditingController();
  final _calcium = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      String fmtNum(dynamic v) {
        final d = (v as num?)?.toDouble();
        if (d == null) return '';
        return d == d.roundToDouble() ? d.toInt().toString() : '$d';
      }

      _name.text = e['name'] as String? ?? '';
      _grams.text = fmtNum(e['serving_grams']);
      _desc.text = e['serving_description'] as String? ?? '';
      _protein.text = fmtNum(e['protein_g']);
      _zinc.text = fmtNum(e['zinc_mg']);
      _calcium.text = fmtNum(e['calcium_mg']);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _grams, _desc, _protein, _zinc, _calcium]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _delete() async {
    final t = widget.i18n.t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GsColors.surface,
        title: Text(
          t('flutter.food.custom_delete_q', 'Remove this food?'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          t(
            'flutter.food.custom_delete_note',
            'Days you already logged keep their values — only the reusable card is removed.',
          ),
          style: const TextStyle(fontSize: 12.5, color: GsColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              t('flutter.food.custom_delete', 'Remove'),
              style: const TextStyle(color: GsColors.flag),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final err = await widget.appState.deleteCustomFood(
      widget.existing!['custom_food_id'],
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    Navigator.pop(context, 'deleted');
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    final name = _name.text.trim();
    final grams = double.tryParse(_grams.text.trim());
    final protein = double.tryParse(_protein.text.trim());
    if (name.isEmpty) {
      setState(
        () => _error = t('flutter.food.custom_need_name', 'Enter a food name'),
      );
      return;
    }
    if (grams == null || grams <= 0) {
      setState(
        () => _error = t(
          'flutter.food.custom_need_serving',
          'Enter a valid serving size',
        ),
      );
      return;
    }
    if (protein == null || protein < 0) {
      setState(
        () => _error = t(
          'flutter.food.custom_need_protein',
          'Enter the protein for this serving',
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = _isEdit
        ? await widget.appState.updateCustomFood(
            widget.existing!['custom_food_id'],
            name: name,
            servingGrams: grams,
            description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
            proteinG: protein,
            zincMg: double.tryParse(_zinc.text.trim()),
            calciumMg: double.tryParse(_calcium.text.trim()),
          )
        : await widget.appState.addCustomFood(
            name: name,
            servingGrams: grams,
            description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
            proteinG: protein,
            zincMg: double.tryParse(_zinc.text.trim()),
            calciumMg: double.tryParse(_calcium.text.trim()),
          );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    Navigator.pop(context, _isEdit ? 'saved' : 'added');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit
                ? t('flutter.food.custom_edit_title', 'Edit custom food')
                : t('flutter.food.custom_title', 'Add a custom food'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            t(
              'flutter.food.custom_hint',
              "Enter what's on the label for one serving.",
            ),
            style: const TextStyle(fontSize: 11.5, color: GsColors.text3),
          ),
          const SizedBox(height: 14),
          _field(_name, t('flutter.food.custom_name', 'Food name')),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  _grams,
                  t('flutter.food.custom_grams', 'Serving size (g)'),
                  number: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  _protein,
                  t('flutter.food.custom_protein', 'Protein (g)'),
                  number: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _field(
            _desc,
            t('flutter.food.custom_desc', 'Portion note (optional)'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _field(
                  _zinc,
                  t('flutter.food.custom_zinc', 'Zinc (mg) · opt'),
                  number: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  _calcium,
                  t('flutter.food.custom_calcium', 'Calcium (mg) · opt'),
                  number: true,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: GsColors.flag),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? t('flutter.saving', 'Saving…')
                  : _isEdit
                  ? t('flutter.food.custom_save_changes', 'Save changes')
                  : t('flutter.food.custom_save', 'Save food'),
            ),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _saving ? null : _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: GsColors.flag,
                side: BorderSide(color: GsColors.flag.withValues(alpha: 0.45)),
              ),
              child: Text(
                t('flutter.food.custom_delete', 'Remove'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) {
    return TextField(
      controller: c,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

double _round1(double v) => (v * 10).roundToDouble() / 10;
double _round2(double v) => (v * 100).roundToDouble() / 100;

String _fmtG(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
