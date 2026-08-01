// ══════════════════════════════════════════════════════════════════
// Food Lens — typed results from the food-scan Edge Function.
//
// The model returns library food ids and gram RANGES only; nutrients
// are computed client-side from the app's own cited per-100g data
// (no-guess rule — the AI never emits nutrient numbers in meal mode).
// Label mode transcribes what is printed on a photographed label; the
// photo is the citation.
// ══════════════════════════════════════════════════════════════════

class MealScanItem {
  final String foodId;
  final int lowG;
  final int bestG;
  final int highG;
  final String confidence; // high | medium | low (identification only)
  final String container; // plate | bowl | cup | skewer | other
  final String note;

  MealScanItem.fromJson(Map<String, dynamic> j)
    : foodId = j['food_id'] as String? ?? '',
      lowG = (j['low_g'] as num?)?.round() ?? 0,
      bestG = (j['best_g'] as num?)?.round() ?? 0,
      highG = (j['high_g'] as num?)?.round() ?? 0,
      confidence = j['confidence'] as String? ?? 'low',
      container = j['container'] as String? ?? 'plate',
      note = j['note'] as String? ?? '';

  bool get isBowl => container == 'bowl' || container == 'cup';
}

class MealScanUnmatched {
  final String name;
  final int bestG;
  final String category;
  final List<String> proxyCandidates; // valid library ids, <=3

  MealScanUnmatched.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String? ?? '',
      bestG = (j['best_g'] as num?)?.round() ?? 0,
      category = j['category'] as String? ?? 'other',
      proxyCandidates = [
        for (final c in (j['proxy_candidates'] as List? ?? [])) c.toString(),
      ];
}

class LabelScanResult {
  final String name;
  final double? servingGrams;
  final String basis; // per_serving | per_100g | unknown
  final double? energyKcal;
  final double? proteinG;
  final double? calciumMg;
  final double? zincMg;
  final String labelLanguage;
  final List<String> needsReview; // field names to highlight amber
  final bool unreadable;
  final String unreadableReason;

  LabelScanResult.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String? ?? '',
      servingGrams = (j['serving_grams'] as num?)?.toDouble(),
      basis = j['basis'] as String? ?? 'unknown',
      energyKcal = ((j['values']?['energy_kcal']) as num?)?.toDouble(),
      proteinG = ((j['values']?['protein_g']) as num?)?.toDouble(),
      calciumMg = ((j['values']?['calcium_mg']) as num?)?.toDouble(),
      zincMg = ((j['values']?['zinc_mg']) as num?)?.toDouble(),
      labelLanguage = j['label_language'] as String? ?? '',
      needsReview = [
        for (final f in (j['needs_review'] as List? ?? [])) f.toString(),
      ],
      unreadable = j['unreadable'] as bool? ?? false,
      unreadableReason = j['unreadable_reason'] as String? ?? '';
}

/// What the label scan hands to the custom-food sheet: per-SERVING
/// values (basis conversion already applied), plus which fields the
/// validation pass wants the parent to double-check.
class LabelPrefill {
  final String name;
  final double? servingGrams;
  final double? proteinG;
  final double? calciumMg;
  final double? zincMg;
  final double? energyKcal; // stored silently, no visible field
  final Set<String> needsReview;

  LabelPrefill({
    required this.name,
    required this.servingGrams,
    required this.proteinG,
    required this.calciumMg,
    required this.zincMg,
    required this.energyKcal,
    required this.needsReview,
  });

  factory LabelPrefill.fromLabel(LabelScanResult l) {
    final review = {...l.needsReview};
    double? scale(double? v) {
      if (v == null) return v;
      if (l.basis == 'per_100g' && l.servingGrams != null) {
        return v * l.servingGrams! / 100;
      }
      return v;
    }

    if (l.basis == 'unknown') {
      // Can't tell per-serving from per-100g — everything needs eyes.
      for (final f in ['protein_g', 'calcium_mg', 'zinc_mg', 'energy_kcal']) {
        review.add(f);
      }
    }
    return LabelPrefill(
      name: l.name,
      servingGrams:
          l.servingGrams ?? (l.basis == 'per_100g' ? 100 : null),
      proteinG: scale(l.proteinG),
      calciumMg: scale(l.calciumMg),
      zincMg: scale(l.zincMg),
      energyKcal: scale(l.energyKcal),
      needsReview: review,
    );
  }
}

class FoodScanResult {
  final String mode; // meal | label
  final List<MealScanItem> items;
  final List<MealScanUnmatched> unmatched;
  final bool wantsSideView;
  final String notFoodNote;
  final LabelScanResult? label;

  /// Human-readable failure, or AppState.premiumRequiredError sentinel.
  /// null error + this object = success.
  final String? error;

  FoodScanResult.failure(this.error)
    : mode = '',
      items = const [],
      unmatched = const [],
      wantsSideView = false,
      notFoodNote = '',
      label = null;

  FoodScanResult.fromJson(Map<String, dynamic> j)
    : mode = j['mode'] as String? ?? '',
      items = [
        for (final it in ((j['result']?['items']) as List? ?? []))
          MealScanItem.fromJson((it as Map).cast<String, dynamic>()),
      ],
      unmatched = [
        for (final u in ((j['result']?['unmatched']) as List? ?? []))
          MealScanUnmatched.fromJson((u as Map).cast<String, dynamic>()),
      ],
      wantsSideView = (j['result']?['wants_side_view']) as bool? ?? false,
      notFoodNote = (j['result']?['not_food_note']) as String? ?? '',
      label = j['mode'] == 'label' && j['result'] is Map
          ? LabelScanResult.fromJson(
              (j['result'] as Map).cast<String, dynamic>(),
            )
          : null,
      error = null;
}
