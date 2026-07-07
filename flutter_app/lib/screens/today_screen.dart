import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'today_hud.dart';

/// Today tab — read-only first pass: child switcher, date selector,
/// and the day's nutrition / sleep / activity as saved by the PWA.
/// Logging (writes) comes after the read path is proven.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.loadingChildren) {
          return const Center(child: CircularProgressIndicator());
        }
        if (appState.children.isEmpty) {
          return _EmptyNote(i18n.t('flutter.no_children'));
        }
        return RefreshIndicator(
          onRefresh: appState.loadDay,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _ChildSwitcher(appState: appState),
              const SizedBox(height: 12),
              _DateSelector(appState: appState, i18n: i18n),
              const SizedBox(height: 12),
              if (appState.lastError != null)
                _ErrorCard(message: appState.lastError!),
              if (appState.loadingDay)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ReadinessCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                ConsistencyCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                NutritionEditorCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                _LoggedFoodCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                SleepEditorCard(appState: appState, i18n: i18n),
                const SizedBox(height: 12),
                _ActivityCard(
                    items: appState.activityItems,
                    appState: appState,
                    i18n: i18n),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Child switcher ──────────────────────────────────────────────────

class _ChildSwitcher extends StatelessWidget {
  const _ChildSwitcher({required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: appState.children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = appState.children[i];
          final name = (c['name'] as String? ?? '?');
          final active = i == appState.activeChild;
          return GestureDetector(
            onTap: () => appState.setActiveChild(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: active ? GsColors.accent : GsColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active ? GsColors.accent : GsColors.border2),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor:
                        active ? Colors.white : GsColors.accentLight,
                    child: Text(
                      (c['avatar'] as String? ?? name.characters.first)
                          .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 12,
                          color: GsColors.accent,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    name.split(' ').first,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : GsColors.text,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Date selector ───────────────────────────────────────────────────

class _DateSelector extends StatelessWidget {
  const _DateSelector({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final isToday = appState.logDate == todayISO();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(
            color: isToday ? GsColors.border : GsColors.estimated),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: GsColors.text2),
            onPressed: () => appState.shiftLogDate(-1),
          ),
          Expanded(
            child: Center(
              child: Text(
                isToday
                    ? '${i18n.t('nav.today', 'Today')} · ${appState.logDate}'
                    : appState.logDate,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isToday ? GsColors.text : GsColors.estimated,
                ),
              ),
            ),
          ),
          if (!isToday)
            TextButton(
              onPressed: () => appState.setLogDate(todayISO()),
              child: Text(i18n.t('nav.today', 'Today'),
                  style: const TextStyle(
                      fontSize: 12, color: GsColors.accent)),
            ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: GsColors.text2),
            onPressed: isToday ? null : () => appState.shiftLogDate(1),
          ),
        ],
      ),
    );
  }
}

// ── Cards ───────────────────────────────────────────────────────────

/// Nutrition totals editor — food-card logs feed the numbers, but
/// every total can be manually overridden with steppers (supplements,
/// meals eaten away from the app), exactly like the PWA's manual
/// steppers. Save writes daily_nutrition via the PWA-compatible
/// meal-slot attribution in AppState.saveNutrition.
class NutritionEditorCard extends StatefulWidget {
  const NutritionEditorCard(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<NutritionEditorCard> createState() => _NutritionEditorCardState();
}

class _NutritionEditorCardState extends State<NutritionEditorCard> {
  double? _protein;
  double? _calcium;
  double? _zinc;
  int? _water;
  bool _busy = false;
  String? _seededFor;
  double _itemsProtein = 0;

  void _seedFromState() {
    final s = widget.appState;
    final key = '${s.activeChildId}|${s.logDate}|${s.nutritionLogItems.length}';
    if (_seededFor == key) return;
    _seededFor = key;

    double items(String col) => s.nutritionLogItems.fold<double>(
        0, (sum, i) => sum + ((i[col] as num?)?.toDouble() ?? 0));
    double saved(String col) =>
        (s.nutrition?[col] as num?)?.toDouble() ?? 0;

    _itemsProtein = items('protein_g');
    final savedProtein = saved('protein_breakfast_g') +
        saved('protein_lunch_g') +
        saved('protein_dinner_g');
    _protein = math.max(_itemsProtein, savedProtein);
    _calcium = math.max(items('calcium_mg'), saved('calcium_mg'));
    _zinc = math.max(items('zinc_mg'), saved('zinc_mg'));
    _water = (saved('fluids_ml') / 250).round();
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    setState(() => _busy = true);
    final err = await widget.appState.saveNutrition(
      proteinTotalG: _protein!,
      calciumMg: _calcium!,
      zincMg: _zinc!,
      waterGlasses: _water!,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _seededFor = null; // re-seed from the fresh save
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
        content: Text(err == null
            ? '✅ ${t('flutter.nutrition_saved', 'Nutrition saved')}'
            : '${t('flutter.not_saved', 'Not saved')}: $err')));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        _seedFromState();
        return _GsCard(
          title: t('common.nutrition', 'Nutrition'),
          accentColor: GsColors.accent,
          trailing: _itemsProtein > 0
              ? Text(
                  '${_fmt(_itemsProtein)} g ${t('flutter.from_food_log', 'from food log')}',
                  style: const TextStyle(
                      fontSize: 10.5, color: GsColors.text3))
              : null,
          child: Column(
            children: [
              _StepperRow(
                label: t('today.nutrition.protein_total', 'Protein total'),
                value: '${_fmt(_protein!)} g',
                onMinus: _protein! > 0
                    ? () => setState(
                        () => _protein = math.max(0, _protein! - 1))
                    : null,
                onPlus: () => setState(() => _protein = _protein! + 1),
              ),
              _StepperRow(
                label: t('today.nutrition.calcium_label', 'Calcium total'),
                sub: t('today.nutrition.calcium_target',
                    'Target: 1300mg / day'),
                value: '${_fmt(_calcium!)} mg',
                onMinus: _calcium! > 0
                    ? () => setState(
                        () => _calcium = math.max(0, _calcium! - 100))
                    : null,
                onPlus: () => setState(() => _calcium = _calcium! + 100),
              ),
              _StepperRow(
                label: t('today.nutrition.zinc_label', 'Zinc total'),
                sub: t('today.nutrition.zinc_sub',
                    'Growth plate co-factor · target 8mg/day'),
                value: '${_fmt(_zinc!)} mg',
                onMinus: _zinc! > 0
                    ? () => setState(
                        () => _zinc = math.max(0, _zinc! - 0.5))
                    : null,
                onPlus: () => setState(() => _zinc = _zinc! + 0.5),
              ),
              _StepperRow(
                label: t('today.nutrition.hydration', 'Hydration'),
                value:
                    '$_water ${t('flutter.glasses', 'glasses')} · ${_water! * 250} ml',
                onMinus: _water! > 0
                    ? () => setState(() => _water = _water! - 1)
                    : null,
                onPlus: () => setState(() => _water = _water! + 1),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _busy ? null : _save,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42)),
                child: Text(_busy
                    ? t('flutter.saving', 'Saving…')
                    : t('today.save_btn', "Save Today's Data")),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.sub,
  });
  final String label;
  final String? sub;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: GsColors.text)),
                if (sub != null)
                  Text(sub!,
                      style: const TextStyle(
                          fontSize: 9.5, color: GsColors.text3)),
              ],
            ),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: GsColors.accentDark)),
          const SizedBox(width: 10),
          _RoundStepBtn(icon: Icons.remove, onTap: onMinus),
          const SizedBox(width: 6),
          _RoundStepBtn(icon: Icons.add, onTap: onPlus),
        ],
      ),
    );
  }
}

class _RoundStepBtn extends StatelessWidget {
  const _RoundStepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? GsColors.surface2 : GsColors.accentLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 15,
            color: onTap == null ? GsColors.text3 : GsColors.accentDark),
      ),
    );
  }
}

/// Per-item food log for the selected date — the reviewable list the
/// PWA shows under "Logged today", with the same per-item delete undo.
class _LoggedFoodCard extends StatelessWidget {
  const _LoggedFoodCard({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final items = appState.nutritionLogItems;
    final totalProtein = items.fold<double>(
        0, (sum, i) => sum + ((i['protein_g'] as num?)?.toDouble() ?? 0));
    return _GsCard(
      title: t('flutter.food_log', 'Food log'),
      accentColor: GsColors.accent,
      trailing: items.isEmpty
          ? null
          : Text(
              '${items.length} ${t('flutter.items', 'items')} · ${_fmt(totalProtein)} ${t('flutter.g_protein', 'g protein')}',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: GsColors.accent)),
      child: items.isEmpty
          ? _EmptyNote(t('today.nutrition.empty'))
          : Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['food_name'] as String? ?? 'Food',
                            style: const TextStyle(fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${item['meal_slot'] ?? ''} · ${_fmt((item['protein_g'] as num?)?.toDouble() ?? 0)} g',
                          style: const TextStyle(
                              fontSize: 12, color: GsColors.text2),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close,
                              size: 16, color: GsColors.text3),
                          onPressed: () async {
                            final err = await appState
                                .deleteNutritionLogItem(item['item_id']);
                            if (err != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      backgroundColor: GsColors.flag,
                                      content: Text(
                                          '${t('flutter.could_not_remove', 'Could not remove')}: $err')));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard(
      {required this.items, required this.appState, required this.i18n});
  final List<Map<String, dynamic>> items;
  final AppState appState;
  final I18n i18n;

  static const _tierColor = {
    'high_impact': GsColors.flag,
    'weight_bearing': GsColors.accent,
    'cardio': GsColors.measured,
    'flexibility': GsColors.estimated,
    'lifestyle': GsColors.estimated,
  };

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final totalMin = items.fold<double>(
        0, (sum, i) => sum + ((i['duration_min'] as num?)?.toDouble() ?? 0));

    return _GsCard(
      title: t('common.activity', 'Activity'),
      accentColor: GsColors.measured,
      trailing: items.isEmpty
          ? null
          : Text('${_fmt(totalMin)} ${t('flutter.min', 'min')}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GsColors.measured)),
      child: items.isEmpty
          ? _EmptyNote(t('flutter.no_activity_logged'))
          : Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _tierColor[item['tier']] ?? GsColors.text3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item['display_name'] as String? ?? 'Activity',
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                        Text(
                          item['unit'] == 'reps'
                              ? '${item['duration_value'] ?? '?'} ${t('flutter.reps', 'reps')}'
                              : '${_fmt((item['duration_min'] as num?)?.toDouble() ?? 0)} ${t('flutter.min', 'min')}',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: GsColors.text2,
                              fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close,
                              size: 16, color: GsColors.text3),
                          onPressed: () async {
                            final err = await appState
                                .deleteActivityItem(item['item_id']);
                            if (err != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      backgroundColor: GsColors.flag,
                                      content: Text(
                                          '${t('flutter.could_not_remove', 'Could not remove')}: $err')));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _GsCard extends StatelessWidget {
  const _GsCard({
    required this.title,
    required this.accentColor,
    required this.child,
    this.trailing,
  });
  final String title;
  final Color accentColor;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(GsRadius.md)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: accentColor)),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: GsColors.text3)),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GsColors.flagLight,
        borderRadius: BorderRadius.circular(GsRadius.sm),
        border: Border.all(color: GsColors.flag),
      ),
      child: Text(message,
          style: const TextStyle(fontSize: 12.5, color: GsColors.flagDark)),
    );
  }
}
