// ══════════════════════════════════════════════════════════════════
// Coach food digest — grounds a live AI answer in the child's food
// history without ever letting the model touch the database.
//
// Three-layer contract (design of record: docs/AI_COACH.md):
//   1. This module owns the QUANTITIES. One nutrition_log_items row is
//      exactly one serving; grams = tap count × servingGrams. Every
//      sum and percentage is precomputed here — the model reads
//      answers, it never does arithmetic.
//   2. The model owns general nutrition knowledge (nutrient content,
//      intake guidance), which the prompt forces into labelled
//      typical-value ranges.
//   3. Ratios use measured days only: Recall-Engine estimated days
//      carry protein that no specific food produced, which would
//      corrupt a "% of protein from X" denominator.
//
// Everything here is pure — rows in, string out — so the serving
// math, window clamps and honesty lines are unit-testable without
// Supabase.
// ══════════════════════════════════════════════════════════════════

import 'food_data.dart';

/// Hard ceiling on the digest window. "The last 10 years" becomes the
/// last 12 months — stated to the parent in the answer, so the clamp
/// is honest, not silent. Bounds DB reads regardless of the question.
const int kCoachWindowMaxDays = 365;
const int kCoachWindowDefaultDays = 30;

/// Caps that keep the digest inside the prompt budget (~3.5k chars of
/// an 8k-char server-side system cap).
const int kDigestTopFoods = 10;
const int kDigestMaxChars = 3500;

/// What the question scan decided. Matching only shapes WHAT data is
/// fetched — a missed match falls back to the generic top-foods
/// digest, so recall failures degrade gracefully instead of breaking.
class CoachQuestionScan {
  final bool nutritionRelated;
  final int windowDays;

  /// Reference food ids explicitly named in the question.
  final List<String> foodIds;

  /// True when the question asks about fish/omega-3 generally, so the
  /// digest should carry the fish & seafood breakdown.
  final bool wantsFish;

  const CoachQuestionScan({
    required this.nutritionRelated,
    required this.windowDays,
    required this.foodIds,
    required this.wantsFish,
  });
}

// Thai aliases for the foods parents actually ask about, mapped to
// English search tokens. Longest-first matching so ปลาทูน่า (tuna)
// wins over ปลาทู (mackerel) wins over ปลา (fish in general). Food
// names have no localisation anywhere in the app (English-only
// reference data), so this small curated map is the v1 bridge; the
// generic digest fallback covers everything it misses.
const Map<String, String> _thaiFoodAliases = {
  'ปลาแซลมอน': 'salmon',
  'แซลมอน': 'salmon',
  'ปลาทูน่า': 'tuna',
  'ทูน่า': 'tuna',
  'ปลาทู': 'mackerel',
  'ปลานิล': 'tilapia',
  'ปลา': 'fish',
  'กุ้ง': 'shrimp',
  'ไข่': 'egg',
  'นม': 'milk',
  'เต้าหู้': 'tofu',
  'ไก่': 'chicken',
  'หมู': 'pork',
  'เนื้อวัว': 'beef',
  'อกไก่': 'chicken breast',
};

const List<String> _nutritionKeywords = [
  // en
  'eat', 'ate', 'eaten', 'food', 'meal', 'diet', 'nutrition', 'nutrient',
  'protein', 'calcium', 'zinc', 'iron', 'vitamin', 'dha', 'epa', 'omega',
  'drink', 'drank', 'snack', 'breakfast', 'lunch', 'dinner',
  // th
  'กิน', 'ทาน', 'อาหาร', 'โปรตีน', 'แคลเซียม', 'สารอาหาร', 'มื้อ',
  'ดื่ม', 'ของว่าง',
];

/// "since last month" → 30, "last year" → 365, "past 2 weeks" → 14.
/// Unknown phrasing defaults to 30 days; everything clamps to
/// [7, kCoachWindowMaxDays].
int resolveCoachWindowDays(String question) {
  final q = question.toLowerCase();
  int? days;

  // Explicit counts: "last 3 months", "past 10 days", "2 สัปดาห์", "10 ปี".
  final m = RegExp(
    r'(\d+)\s*(day|days|week|weeks|month|months|year|years|วัน|สัปดาห์|อาทิตย์|เดือน|ปี)',
  ).firstMatch(q);
  if (m != null) {
    final n = int.tryParse(m.group(1)!) ?? 1;
    days = switch (m.group(2)!) {
      'day' || 'days' || 'วัน' => n,
      'week' || 'weeks' || 'สัปดาห์' || 'อาทิตย์' => n * 7,
      'month' || 'months' || 'เดือน' => n * 30,
      _ => n * 365,
    };
  } else if (q.contains('year') || q.contains('ปีที่แล้ว') || q.contains('ปีที่ผ่านมา')) {
    days = 365;
  } else if (q.contains('week') ||
      q.contains('สัปดาห์') ||
      q.contains('อาทิตย์')) {
    days = 7;
  } else if (q.contains('month') ||
      q.contains('เดือนที่แล้ว') ||
      q.contains('เดือนก่อน') ||
      q.contains('เดือนนี้')) {
    days = 30;
  }

  return (days ?? kCoachWindowDefaultDays).clamp(7, kCoachWindowMaxDays);
}

CoachQuestionScan scanCoachQuestion(String question, List<FoodItem> foods) {
  final q = question.toLowerCase();

  // Expand Thai aliases into English tokens, longest alias first so
  // the most specific food wins.
  var expanded = q;
  final aliases = _thaiFoodAliases.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final th in aliases) {
    if (q.contains(th)) {
      expanded += ' ${_thaiFoodAliases[th]!}';
      // Consume so ปลาแซลมอน doesn't also trigger the bare ปลา alias.
      expanded = expanded.replaceAll(th, ' ');
    }
  }

  final matched = <String>[];
  for (final f in foods) {
    final name = f.name.toLowerCase();
    if (expanded.contains(name) ||
        expanded.contains(f.id.replaceAll('_', ' ')) ||
        expanded.contains(f.id)) {
      matched.add(f.id);
    }
  }

  final wantsFish = expanded.contains('fish') ||
      expanded.contains('seafood') ||
      expanded.contains('omega') ||
      expanded.contains('dha') ||
      expanded.contains('epa') ||
      foods
          .where((f) => matched.contains(f.id))
          .any((f) => f.category == 'fish' || f.category == 'seafood');

  final nutritionRelated = matched.isNotEmpty ||
      wantsFish ||
      _nutritionKeywords.any(expanded.contains);

  return CoachQuestionScan(
    nutritionRelated: nutritionRelated,
    windowDays: resolveCoachWindowDays(question),
    foodIds: matched,
    wantsFish: wantsFish,
  );
}

String _g(num v) => v.toStringAsFixed(v >= 100 ? 0 : 1);

/// Rows in, digest out. `itemRows` are nutrition_log_items
/// (log_date, food_id, food_name, protein_g); `dailyRows` are
/// daily_nutrition (log_date, total_protein_g, estimation_method).
String buildFoodDigest({
  required CoachQuestionScan scan,
  required List<Map<String, dynamic>> itemRows,
  required List<Map<String, dynamic>> dailyRows,
  required Map<String, FoodItem> foodsById,
  required DateTime today,
  double? proteinTargetG,
}) {
  final start = today.subtract(Duration(days: scan.windowDays - 1));
  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Measured days only — estimated rows (Recall Engine) carry protein
  // with no per-food items behind it. A null method predates the
  // estimation columns and is a real save.
  final measured = dailyRows.where((r) {
    final m = r['estimation_method'] as String?;
    final ok = m == null || m == 'measured' || m == 'recalled_manual';
    return ok && ((r['total_protein_g'] as num?) ?? 0) > 0;
  }).toList();
  final measuredDays = measured.map((r) => r['log_date']).toSet();
  final totalProteinG = measured.fold<double>(
      0, (s, r) => s + ((r['total_protein_g'] as num?)?.toDouble() ?? 0));

  // Per-food aggregation. One row = one serving, by design of the
  // tap-to-log flow; a food_id missing from the reference (custom or
  // manual boost) aggregates by name with grams unknown.
  final byFood = <String, ({String label, int count, double proteinG, FoodItem? ref})>{};
  for (final r in itemRows) {
    final id = r['food_id'] as String?;
    final ref = id == null ? null : foodsById[id];
    final key = id ?? 'name:${r['food_name'] ?? 'unknown'}';
    final label = ref?.name ?? (r['food_name'] as String? ?? 'Unknown food');
    final prev = byFood[key];
    byFood[key] = (
      label: label,
      count: (prev?.count ?? 0) + 1,
      proteinG: (prev?.proteinG ?? 0) +
          ((r['protein_g'] as num?)?.toDouble() ?? 0),
      ref: ref,
    );
  }

  String foodLine(({String label, int count, double proteinG, FoodItem? ref}) f) {
    final grams = f.ref == null ? null : f.ref!.servingGrams * f.count;
    final share = totalProteinG > 0 && f.proteinG > 0
        ? ' (${(f.proteinG / totalProteinG * 100).round()}% of logged protein)'
        : '';
    final gramsTxt =
        grams == null ? 'serving size unknown' : '~${_g(grams)} g';
    return '- ${f.label}: ${f.count} serving${f.count == 1 ? '' : 's'} '
        '$gramsTxt, protein ${_g(f.proteinG)} g$share';
  }

  final lines = <String>[
    'FOOD LOG DIGEST',
    'WINDOW ${iso(start)} -> ${iso(today)} '
        '(${scan.windowDays} calendar days, ${measuredDays.length} with food logs)',
  ];

  // Explicitly named foods — including the honest "no entries" case,
  // which is the answer to "how much durian?".
  if (scan.foodIds.isNotEmpty) {
    lines.add('Foods the question asked about:');
    for (final id in scan.foodIds.take(kDigestTopFoods)) {
      final agg = byFood[id];
      if (agg != null) {
        lines.add(foodLine(agg));
      } else {
        final name = foodsById[id]?.name ?? id;
        lines.add('- $name: no entries in this window');
      }
    }
  }

  if (scan.wantsFish) {
    final fish = byFood.entries
        .where((e) =>
            e.value.ref?.category == 'fish' ||
            e.value.ref?.category == 'seafood')
        .toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));
    lines.add(fish.isEmpty
        ? 'Fish & seafood: none logged in this window'
        : 'All fish & seafood in the window (for omega-3 totals):');
    lines.addAll(fish.take(kDigestTopFoods).map((e) => foodLine(e.value)));
  }

  final top = byFood.values.toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  if (top.isNotEmpty) {
    lines.add('Most-logged foods:');
    lines.addAll(top.take(kDigestTopFoods).map(foodLine));
  } else {
    lines.add('No food items logged in this window.');
  }

  if (totalProteinG > 0 && measuredDays.isNotEmpty) {
    final avg = totalProteinG / measuredDays.length;
    final target = proteinTargetG == null
        ? ''
        : ' vs target ${_g(proteinTargetG)} g';
    final met = proteinTargetG == null
        ? ''
        : ', target met ${measured.where((r) => ((r['total_protein_g'] as num?) ?? 0) >= proteinTargetG).length}/${measuredDays.length} logged days';
    lines.add('Daily protein (logged days only): total ${_g(totalProteinG)} g, '
        'avg ${_g(avg)} g/day$target$met');
  }

  final digest = lines.join('\n');
  return digest.length <= kDigestMaxChars
      ? digest
      : digest.substring(0, kDigestMaxChars);
}
