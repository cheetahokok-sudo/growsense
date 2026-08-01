// ══════════════════════════════════════════════════════════════════
// Food Lens capture flows — Snap-a-Meal + Scan-a-Label.
//
// Honesty rules baked into this UI:
//   * grams are RANGES rounded to 5 g — no fake decimals, ever;
//   * every number is parent-confirmable before anything is logged;
//   * unmatched foods are never force-fit — the parent explicitly
//     picks a cited stand-in ("log as…") or adds a custom food;
//   * bowls/soups get fullness chips because no camera can see under
//     the rice.
// Photos are transient: downscaled, EXIF-stripped, sent, discarded.
// ══════════════════════════════════════════════════════════════════

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../food_data.dart';
import '../food_scan_models.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/premium_gate.dart';
import 'food_screen.dart' show showCustomFoodSheet;

/// Map the app language to a food-library region so the model can
/// break ties between similar dishes. English gives no hint.
String? regionHintForLang(String lang) => switch (lang) {
  'th' => 'th',
  'vi' => 'vn',
  'ko' => 'kr',
  'zh' => 'cn',
  'ar' => 'ae',
  _ => null,
};

bool _gate(BuildContext context, AppState appState, I18n i18n) {
  if (appState.canUseFoodScan) return true;
  final t = i18n.t;
  showPremiumSheet(
    context,
    appState: appState,
    i18n: i18n,
    emoji: '📸',
    title: t('flutter.fscan.premium_title', 'Food Lens is a Premium tool'),
    body: t(
      'flutter.fscan.premium_body',
      'Photograph a meal or a nutrition label and let AI find the foods and portions — you confirm, GrowSense computes the growth nutrients from verified data.',
    ),
    freeNote: t(
      'flutter.fscan.premium_free_note',
      'Logging foods by hand, the full food library and your custom foods stay free.',
    ),
    highlightBenefitKey: 'foodscan',
  );
  return false;
}

Future<Uint8List?> _pickPhoto(BuildContext context, I18n i18n) async {
  final t = i18n.t;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: GsColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(GsRadius.lg)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(t('flutter.fscan.take_photo', 'Take a photo')),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(t('flutter.fscan.from_gallery', 'Choose from gallery')),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    final f = await ImagePicker().pickImage(source: source);
    return f == null ? null : await f.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Modal spinner shown while the Edge Function runs (a few seconds).
Future<FoodScanResult> _runWithSpinner(
  BuildContext context,
  I18n i18n,
  Future<FoodScanResult> future,
) async {
  final t = i18n.t;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: GsColors.surface,
            borderRadius: BorderRadius.circular(GsRadius.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                t('flutter.fscan.analyzing', 'Analyzing photo…'),
                style: const TextStyle(
                  fontSize: 13,
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w600,
                  color: GsColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  final result = await future;
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  return result;
}

void _showError(BuildContext context, AppState appState, I18n i18n, String error) {
  if (error == AppState.premiumRequiredError) {
    _gateSheetForServerRefusal(context, appState, i18n);
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(backgroundColor: GsColors.flag, content: Text(error)),
  );
}

void _gateSheetForServerRefusal(
  BuildContext context,
  AppState appState,
  I18n i18n,
) {
  // Server said 402 (stale local tier) — same sheet as the local gate.
  _gate(context, appState, i18n);
}

// ── Meal scan ──────────────────────────────────────────────────────

Future<void> startMealScan(
  BuildContext context,
  AppState appState,
  I18n i18n,
) async {
  if (!_gate(context, appState, i18n)) return;
  final photo = await _pickPhoto(context, i18n);
  if (photo == null || !context.mounted) return;

  // The loop exists for ONE re-entry path: the confirm sheet can ask
  // for a side-angle photo (bowls, food hidden under rice/soup) — the
  // meal is then re-analyzed with BOTH shots.
  Uint8List? sidePhoto;
  while (true) {
    final result = await _runWithSpinner(
      context,
      i18n,
      appState.runFoodScan(
        photos: [photo, ?sidePhoto],
        mode: 'meal',
        regionHint: regionHintForLang(i18n.code),
      ),
    );
    if (!context.mounted) return;
    if (result.error != null) {
      _showError(context, appState, i18n, result.error!);
      return;
    }

    if (result.items.isEmpty && result.unmatched.isEmpty) {
      // Not a meal. If it's a packaged product / printed label, don't
      // refuse — offer to analyze the label and let the parent decide
      // how to log (owner call, 2026-08-01).
      if (result.looksLikeLabel) {
        final analyze = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: GsColors.surface,
            title: Text(
              i18n.t('flutter.fscan.looks_label_title',
                  'This looks like a nutrition label'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: Text(
              i18n.t('flutter.fscan.looks_label_body',
                  'No prepared food found in the photo — but the label can be read into a food you can log or save.'),
              style: const TextStyle(fontSize: 12.5, color: GsColors.text2),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(i18n.t('common.cancel', 'Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  i18n.t('flutter.fscan.analyze_label', 'Analyze label'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
        if (analyze == true && context.mounted) {
          await _analyzeLabelPhoto(context, appState, i18n, photo);
        }
        return;
      }
      final note = result.notFoodNote;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: GsColors.estimatedDark,
          content: Text(
            note.isNotEmpty
                ? note
                : i18n.t('flutter.fscan.no_food', "Couldn't find food in this photo — try a closer, brighter shot."),
          ),
        ),
      );
      return;
    }

    final foods = {for (final f in await loadFoodReference()) f.id: f};
    final ids = [for (final it in result.items) it.foodId];
    final usualProtein = await appState.latestLoggedProtein(ids);
    if (!context.mounted) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GsColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(GsRadius.lg)),
      ),
      builder: (_) => _MealConfirmSheet(
        appState: appState,
        i18n: i18n,
        result: result,
        foods: foods,
        usualProtein: usualProtein,
        // Kept so a packaged unmatched item can have its label read from
        // the SAME shot — no re-photograph.
        photoBytes: photo,
        // The side-view button hides once a second angle was provided.
        hasSideView: sidePhoto != null,
      ),
    );
    if (action != 'side_view' || !context.mounted) return;
    final side = await _pickPhoto(context, i18n);
    if (side == null || !context.mounted) return;
    sidePhoto = side; // loop: re-analyze with both photos (one more scan)
  }
}

// ── Label scan ─────────────────────────────────────────────────────

/// Analyze [photo] as a nutrition label and open the custom-food sheet
/// (prefilled on success, empty on an unreadable label). Shared by the
/// direct label-scan entry, the meal-scan handoff dialog, and the
/// packaged-unmatched chip. Returns the sheet result ('added' | ...).
Future<String?> _analyzeLabelPhoto(
  BuildContext context,
  AppState appState,
  I18n i18n,
  Uint8List photo,
) async {
  final result = await _runWithSpinner(
    context,
    i18n,
    appState.runFoodScan(photos: [photo], mode: 'label'),
  );
  if (!context.mounted) return null;
  if (result.error != null) {
    _showError(context, appState, i18n, result.error!);
    return null;
  }

  final label = result.label;
  if (label == null || label.unreadable) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: GsColors.estimatedDark,
        content: Text(
          label != null && label.unreadableReason.isNotEmpty
              ? label.unreadableReason
              : i18n.t('flutter.fscan.label_unreadable', "Couldn't read this label — try a flatter, brighter shot of the nutrition panel."),
        ),
      ),
    );
    // Open the empty sheet anyway so the parent can type what they see.
    return showCustomFoodSheet(context, appState: appState, i18n: i18n);
  }

  return showCustomFoodSheet(
    context,
    appState: appState,
    i18n: i18n,
    prefill: LabelPrefill.fromLabel(label),
  );
}

Future<void> startLabelScan(
  BuildContext context,
  AppState appState,
  I18n i18n,
) async {
  if (!_gate(context, appState, i18n)) return;
  final photo = await _pickPhoto(context, i18n);
  if (photo == null || !context.mounted) return;
  await _analyzeLabelPhoto(context, appState, i18n, photo);
}

// ── Meal confirm sheet ─────────────────────────────────────────────

class _RowState {
  _RowState({
    required this.foodId,
    required this.servedG,
    required this.lowG,
    required this.highG,
    required this.confidence,
    required this.isBowl,
    this.nameOverride,
    this.usualG,
  });

  final String foodId;
  int servedG;
  final int lowG;
  final int highG;
  final String confidence;
  final bool isBowl;
  final String? nameOverride;

  /// The family's last confirmed portion, offered as a tappable chip —
  /// the PHOTO estimate always wins the prefill (owner call, 2026-08-01:
  /// early logs are fixed library servings, so memory was worse than
  /// the photo).
  final int? usualG;
  bool included = true;
  double fullness = 1.0; // bowls: how full it was served
}

class _MealConfirmSheet extends StatefulWidget {
  const _MealConfirmSheet({
    required this.appState,
    required this.i18n,
    required this.result,
    required this.foods,
    required this.usualProtein,
    required this.photoBytes,
    required this.hasSideView,
  });

  final AppState appState;
  final I18n i18n;
  final FoodScanResult result;
  final Map<String, FoodItem> foods;
  final Map<String, double> usualProtein;
  final Uint8List photoBytes;

  /// True when this analysis already used a second (side-angle) photo —
  /// the "add side view" button hides then.
  final bool hasSideView;

  @override
  State<_MealConfirmSheet> createState() => _MealConfirmSheetState();
}

class _MealConfirmSheetState extends State<_MealConfirmSheet> {
  final List<_RowState> _rows = [];
  final List<MealScanUnmatched> _pendingUnmatched = [];
  late final Map<String, FoodItem> _foods = {...widget.foods};
  double _eaten = 1.0; // all | most (~2/3) | a little (~1/3)
  bool _logging = false;

  static int _snap5(num g) => (g / 5).round().clamp(1, 100) * 5;

  @override
  void initState() {
    super.initState();
    for (final it in widget.result.items) {
      final food = widget.foods[it.foodId];
      if (food == null) continue;
      // Prefill is ALWAYS the photo's best estimate. The family's last
      // confirmed portion (derived from their own logs) is offered as a
      // one-tap chip instead — memory assists, the photo decides.
      int? usualG;
      final lastProtein = widget.usualProtein[it.foodId];
      if (lastProtein != null && food.proteinPer100g > 0) {
        final grams = _snap5(lastProtein / food.proteinPer100g * 100);
        if (grams >= 5 && grams <= 500 && grams != it.bestG) usualG = grams;
      }
      _rows.add(_RowState(
        foodId: it.foodId,
        servedG: it.bestG,
        lowG: it.lowG,
        highG: it.highG,
        confidence: it.confidence,
        isBowl: it.isBowl,
        usualG: usualG,
      ));
    }
    _pendingUnmatched.addAll(widget.result.unmatched);
  }

  /// A just-saved custom_foods row → FoodItem (per-100g back-calc, same
  /// convention as the food screen's browse merge).
  FoodItem _customRowToFoodItem(Map<String, dynamic> r) {
    final grams = (r['serving_grams'] as num?)?.toDouble() ?? 100;
    double? per100(dynamic v) =>
        (v == null || grams <= 0) ? null : (v as num).toDouble() / grams * 100;
    return FoodItem.fromJson({
      'id': 'custom_${r['custom_food_id']}',
      'name': r['name'],
      'emoji': '⭐',
      'region': 'global',
      'category': 'custom',
      'per100g': {
        'protein_g': per100(r['protein_g']) ?? 0,
        'zinc_mg': per100(r['zinc_mg']),
        'calcium_mg': per100(r['calcium_mg']),
        'energy_kcal': per100(r['energy_kcal']),
      },
      'servingGrams': grams,
      'source': 'Custom food',
    });
  }

  /// Packaged product spotted in the meal photo: read its nutrition
  /// label from the SAME shot (one more scan against the cap), save it
  /// as a custom food, and drop it into this meal ready to log.
  Future<void> _readLabel(MealScanUnmatched u) async {
    final appState = widget.appState;
    final saved = await _analyzeLabelPhoto(
      context,
      appState,
      widget.i18n,
      widget.photoBytes,
    );
    if (!mounted || saved != 'added') return;
    // addCustomFood prepends the new row.
    final row = appState.customFoods.isNotEmpty ? appState.customFoods.first : null;
    if (row == null) return;
    final item = _customRowToFoodItem(row);
    setState(() {
      _foods[item.id] = item;
      _rows.add(_RowState(
        foodId: item.id,
        servedG: _snap5(item.servingGrams),
        lowG: 0,
        highG: 0,
        confidence: 'high', // read from the label, not estimated
        isBowl: false,
      ));
      _pendingUnmatched.remove(u);
    });
  }

  void _adoptProxy(MealScanUnmatched u, String proxyId) {
    final food = _foods[proxyId];
    if (food == null) return;
    setState(() {
      _rows.add(_RowState(
        foodId: proxyId,
        servedG: _snap5(u.bestG == 0 ? food.servingGrams : u.bestG),
        lowG: 0,
        highG: 0,
        confidence: 'medium',
        isBowl: false,
        nameOverride: '${u.name} · ${food.name}',
      ));
      _pendingUnmatched.remove(u);
    });
  }

  double _finalGrams(_RowState r) => r.servedG * r.fullness * _eaten;

  Future<void> _log() async {
    final t = widget.i18n.t;
    final included = [for (final r in _rows) if (r.included) r];
    if (included.isEmpty) return;
    setState(() => _logging = true);
    var failures = 0;
    for (final r in included) {
      final food = _foods[r.foodId]!;
      final g = _finalGrams(r);
      double perG(double per100) => per100 * g / 100;
      double r1(double v) => (v * 10).roundToDouble() / 10;
      double r2(double v) => (v * 100).roundToDouble() / 100;
      final err = await widget.appState.recordNutritionLogItem(
        foodId: food.id,
        foodName: r.nameOverride ?? food.name,
        proteinG: r1(perG(food.proteinPer100g)),
        zincMg: food.zincPer100g == null ? null : r2(perG(food.zincPer100g!)),
        calciumMg:
            food.calciumPer100g == null ? null : r1(perG(food.calciumPer100g!)),
        ironMg: food.ironPer100g == null ? null : r2(perG(food.ironPer100g!)),
        vitaminDIu: food.vitaminDIuPer100g == null
            ? null
            : r1(perG(food.vitaminDIuPer100g!)),
        // Quiet energy layer — logged, never displayed.
        energyKcal:
            food.energyPer100g == null ? null : r1(perG(food.energyPer100g!)),
        logMethod: 'photo_ai',
      );
      if (err != null) failures++;
    }
    if (!mounted) return;
    Navigator.pop(context);
    final slot = t(
      'meal.${widget.appState.activeMealSlot}',
      widget.appState.activeMealSlot,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: failures == 0 ? GsColors.accentDark : GsColors.flag,
        content: Text(
          failures == 0
              ? t('flutter.fscan.logged_n', '{n} foods → {slot}', {
                  'n': '${included.length}',
                  'slot': slot,
                })
              : t('flutter.fscan.logged_partial',
                  'Some items could not be saved ({n} failed)', {'n': '$failures'}),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final anyLow =
        _rows.any((r) => r.included && r.confidence == 'low');
    final anyBowl = _rows.any((r) => r.included && r.isBowl);
    final protein = [
      for (final r in _rows)
        if (r.included)
          _foods[r.foodId]!.proteinPer100g * _finalGrams(r) / 100,
    ].fold<double>(0, (a, b) => a + b);
    // Energy surfaces at scan time (owner call 2026-08-01) — summed over
    // foods whose kcal is collected; omitted entirely when none are.
    double kcal = 0;
    var anyKcal = false;
    for (final r in _rows) {
      final e = _foods[r.foodId]!.energyPer100g;
      if (r.included && e != null) {
        kcal += e * _finalGrams(r) / 100;
        anyKcal = true;
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('flutter.fscan.confirm_title', 'Check before logging'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              t(
                'flutter.fscan.grams_hint',
                'Estimated from one photograph — grams are rough. Adjust anything, then log.',
              ),
              style: const TextStyle(fontSize: 11.5, color: GsColors.text3),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in _rows) _itemRow(r),
                  for (final u in _pendingUnmatched) _unmatchedRow(u),
                ],
              ),
            ),
            // Second-angle photo: bowls/soups hide food from a top-down
            // shot — a ~45° side view lets the AI re-estimate with depth.
            if (!widget.hasSideView &&
                (widget.result.wantsSideView ||
                    _rows.any((r) => r.included && r.isBowl)))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'side_view'),
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: Text(
                    t('flutter.fscan.side_view_btn',
                        'Add a side-angle photo — better for bowls & soups'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GsColors.accentDark,
                    side: BorderSide(
                      color: GsColors.accent.withValues(alpha: 0.45),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            _eatenControl(t),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    anyLow
                        ? t('flutter.fscan.conf_low',
                            'Some foods were identified with low confidence — check them.')
                        : anyBowl
                            ? t('flutter.fscan.conf_bowl',
                                'Bowl contents are partly hidden — fullness chips help.')
                            : t('flutter.fscan.conf_ok',
                                'Estimated from a photo · confirmed by you.'),
                    style: const TextStyle(fontSize: 10.5, color: GsColors.text3),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '≈ ${protein.toStringAsFixed(protein >= 10 ? 0 : 1)} ${t('flutter.g_protein', 'g protein')}'
                  '${anyKcal ? ' · ≈ ${kcal.round()} kcal' : ''}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: GsColors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _logging || _rows.every((r) => !r.included)
                  ? null
                  : _log,
              child: Text(
                _logging
                    ? t('flutter.saving', 'Saving…')
                    : t('flutter.fscan.log_btn', 'Log to {slot}', {
                        'slot': t(
                          'meal.${widget.appState.activeMealSlot}',
                          widget.appState.activeMealSlot,
                        ),
                      }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eatenControl(String Function(String, [String?, Map<String, String>?]) t) {
    final options = <(double, String)>[
      (0.33, t('flutter.fscan.ate_little', 'A little')),
      (0.67, t('flutter.fscan.ate_most', 'Most of it')),
      (1.0, t('flutter.fscan.ate_all', 'All')),
    ];
    return Row(
      children: [
        Text(
          t('flutter.fscan.ate_label', 'Child ate:'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        for (final (v, label) in options)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 11.5)),
              selected: _eaten == v,
              onSelected: (_) => setState(() => _eaten = v),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  Widget _itemRow(_RowState r) {
    final t = widget.i18n.t;
    final food = _foods[r.foodId]!;
    final showRange = r.lowG > 0 && r.highG > r.lowG;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: r.included ? GsColors.surface : GsColors.surface2,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: r.included,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => r.included = v ?? true),
              ),
              Text(food.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.nameOverride ?? food.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (showRange)
                          '${r.lowG}–${r.highG} g',
                        if (r.confidence == 'low')
                          t('flutter.fscan.conf_low_chip', 'low confidence'),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: r.confidence == 'low'
                            ? GsColors.estimatedDark
                            : GsColors.text3,
                      ),
                    ),
                    if (r.usualG != null && r.usualG != r.servedG)
                      GestureDetector(
                        onTap: () => setState(() => r.servedG = r.usualG!),
                        child: Text(
                          t('flutter.fscan.usual_chip', 'usual: {g} g — tap to use',
                              {'g': '${r.usualG}'}),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: GsColors.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _gramsStepper(r),
            ],
          ),
          if (r.isBowl && r.included)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 2),
              child: Row(
                children: [
                  Text(
                    t('flutter.fscan.bowl_full', 'Bowl was:'),
                    style: const TextStyle(fontSize: 11, color: GsColors.text2),
                  ),
                  const SizedBox(width: 6),
                  for (final (v, label) in [(0.5, '½'), (0.75, '¾'), (1.0, t('flutter.fscan.bowl_full_full', 'full'))])
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(label, style: const TextStyle(fontSize: 11)),
                        selected: r.fullness == v,
                        onSelected: (_) => setState(() => r.fullness = v),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _gramsStepper(_RowState r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBtn(Icons.remove, () {
          if (r.servedG > 5) setState(() => r.servedG = _snap5(r.servedG - 5));
        }),
        SizedBox(
          width: 52,
          child: Text(
            '${r.servedG} g',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        _stepBtn(Icons.add, () {
          if (r.servedG < 500) setState(() => r.servedG = _snap5(r.servedG + 5));
        }),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GsColors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: GsColors.border2),
        ),
        child: Icon(icon, size: 16, color: GsColors.text2),
      ),
    );
  }

  Widget _unmatchedRow(MealScanUnmatched u) {
    final t = widget.i18n.t;
    final candidates = [
      for (final id in u.proxyCandidates)
        if (_foods.containsKey(id)) _foods[id]!,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GsColors.surface2,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${u.name} · ${t('flutter.fscan.not_in_library', 'not in the library')}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: GsColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Packaged product: the best answer is its own label, read
              // from the same photo — leads the chip row.
              if (u.packaged)
                ActionChip(
                  avatar: const Icon(Icons.document_scanner_outlined,
                      size: 14, color: GsColors.accentDark),
                  label: Text(
                    t('flutter.fscan.read_label', 'Read nutrition label'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: GsColors.accentDark,
                    ),
                  ),
                  backgroundColor: GsColors.accentLight,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _readLabel(u),
                ),
              for (final f in candidates)
                ActionChip(
                  label: Text(
                    '${t('flutter.fscan.log_as', 'Log as')} ${f.emoji} ${f.name}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _adoptProxy(u, f.id),
                ),
              ActionChip(
                label: Text(
                  t('flutter.food.add_custom', 'Add your own food'),
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final appState = widget.appState;
                  final i18n = widget.i18n;
                  setState(() => _pendingUnmatched.remove(u));
                  await showCustomFoodSheet(
                    context,
                    appState: appState,
                    i18n: i18n,
                    prefill: LabelPrefill(
                      name: u.name,
                      servingGrams: u.bestG > 0 ? u.bestG.toDouble() : null,
                      proteinG: null,
                      calciumMg: null,
                      zincMg: null,
                      energyKcal: null,
                      needsReview: const {},
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
