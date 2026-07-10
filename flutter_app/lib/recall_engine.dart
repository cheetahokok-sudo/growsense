// ══════════════════════════════════════════════════════════════════
// Nutrition Recall Engine — fills missed log days with honest,
// clearly-labelled estimates instead of leaving holes (or worse,
// fabricating "logged" data).
//
// The estimation ladder (see migrations/2026-07-10_nutrition_
// estimation_columns.sql): measured 1.00 > recalled_manual .85/.70
// > relative_recall .70 > weekly_survey .50 (future) > pattern_fill
// .30. Rules that must never break:
//   - relative recall anchors to a MEASURED day, max 1 day back —
//     chained estimates compound error and are not offered;
//   - estimator inputs stay independent of analyzed outcomes (no
//     growth-phase priors — that would bake nutrition→growth
//     correlation into the data the Analytics tab then "finds");
//   - an estimate never overwrites a measured row;
//   - backfill is offered at most 7 days back; older gaps stay
//     honest holes.
// ══════════════════════════════════════════════════════════════════

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart' show localISO;

const kMeasured = 'measured';
const kRecalledManual = 'recalled_manual';
const kRelativeRecall = 'relative_recall';
const kPatternFill = 'pattern_fill';

/// One-tap answer to "compared with `anchor day`, they ate…".
enum RecallChoice { muchLess, slightlyLess, same, slightlyMore, muchMore }

/// Band midpoints: <75%, 75–90%, 90–110%, 110–125%, >125%.
const recallMultipliers = {
  RecallChoice.muchLess: 0.65,
  RecallChoice.slightlyLess: 0.825,
  RecallChoice.same: 1.0,
  RecallChoice.slightlyMore: 1.175,
  RecallChoice.muchMore: 1.35,
};

/// Method + confidence for a manual save to [logDate], inferred from
/// elapsed time — the parent is never asked "how sure are you?".
/// ≤2 days: memory is still reliable → full measured. 3–7 days:
/// items hold up, portions blur → recalled. Beyond: portions are
/// guesses. Recalled data feeds trends and insights but must never
/// trigger red clinical flags.
({String method, double confidence}) manualEntryMeta(String logDate) {
  final parts = logDate.split('-').map(int.parse).toList();
  final d = DateTime(parts[0], parts[1], parts[2]);
  final today = DateTime.now();
  final gap = DateTime(today.year, today.month, today.day)
      .difference(d)
      .inDays;
  if (gap <= 2) return (method: kMeasured, confidence: 1.0);
  if (gap <= 7) return (method: kRecalledManual, confidence: 0.85);
  return (method: kRecalledManual, confidence: 0.7);
}

/// Median-of-medians "typical day" from the child's own measured
/// history — the per-column medians the pattern fill writes.
class TypicalDay {
  final double proteinBreakfastG, proteinLunchG, proteinDinnerG;
  final double calciumMg, zincMg, fluidsMl;
  final int sampleDays;
  final bool weekdaySpecific;
  TypicalDay({
    required this.proteinBreakfastG,
    required this.proteinLunchG,
    required this.proteinDinnerG,
    required this.calciumMg,
    required this.zincMg,
    required this.fluidsMl,
    required this.sampleDays,
    required this.weekdaySpecific,
  });

  double get totalProteinG =>
      proteinBreakfastG + proteinLunchG + proteinDinnerG;
}

/// Everything the Today-screen gap card needs, from one query.
class GapFillState {
  /// Yesterday's date when it is unlogged AND the day before it is
  /// measured — the only configuration relative recall is offered in.
  final String? recallDate;

  /// The measured anchor row relative recall multiplies.
  final Map<String, dynamic>? anchorRow;
  final String? anchorDate;

  /// Unlogged dates 2–7 days back (oldest first), for pattern fill.
  final List<String> olderGaps;

  /// Typical-day medians, null when history is too thin (<3 measured
  /// days) — in that case pattern fill is not offered either.
  final TypicalDay? Function(String date) typicalFor;

  GapFillState({
    required this.recallDate,
    required this.anchorRow,
    required this.anchorDate,
    required this.olderGaps,
    required this.typicalFor,
  });

  bool get hasAnything => recallDate != null || olderGaps.isNotEmpty;
}

double _median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

/// A row counts as a real nutrition log only if it was measured (or
/// manually recalled) and actually contains something — a zero row
/// created as a side effect elsewhere is still a gap.
bool _isLogged(Map<String, dynamic> r) =>
    _num(r['total_protein_g']) > 0 ||
    _num(r['calcium_mg']) > 0 ||
    _num(r['fluids_ml']) > 0;

bool _isMeasured(Map<String, dynamic> r) =>
    (r['estimation_method'] as String? ?? kMeasured) == kMeasured &&
    _isLogged(r);

Future<GapFillState> loadGapFillState(
    SupabaseClient sb, String childId) async {
  final now = DateTime.now();
  final since = localISO(now.subtract(const Duration(days: 30)));
  final rows = List<Map<String, dynamic>>.from(await sb
      .from('daily_nutrition')
      .select('log_date, protein_breakfast_g, protein_lunch_g, '
          'protein_dinner_g, total_protein_g, calcium_mg, zinc_mg, '
          'fluids_ml, estimation_method')
      .eq('child_id', childId)
      .gte('log_date', since));
  final byDate = {for (final r in rows) r['log_date'] as String: r};

  String dateAgo(int d) => localISO(now.subtract(Duration(days: d)));

  // Relative recall: yesterday empty, day-before measured.
  final yesterday = dateAgo(1);
  final dayBefore = dateAgo(2);
  final anchor = byDate[dayBefore];
  final recallOk = byDate[yesterday] == null &&
      anchor != null &&
      _isMeasured(anchor);

  // Older gaps: 2–7 days back with no row at all. Yesterday is
  // handled by recall when possible, else it joins this list.
  final olderGaps = <String>[
    for (var i = 7; i >= 2; i--)
      if (byDate[dateAgo(i)] == null) dateAgo(i),
    if (!recallOk && byDate[yesterday] == null) yesterday,
  ];

  // Typical day: measured rows only — estimates must not feed the
  // estimator. Weekday-specific when that weekday has ≥3 samples.
  final measured = rows.where(_isMeasured).toList();
  TypicalDay? typicalFor(String date) {
    if (measured.length < 3) return null;
    final wd = DateTime.parse(date).weekday;
    final sameWd = measured
        .where((r) => DateTime.parse(r['log_date'] as String).weekday == wd)
        .toList();
    final pool = sameWd.length >= 3 ? sameWd : measured;
    List<double> col(String c) => [for (final r in pool) _num(r[c])];
    return TypicalDay(
      proteinBreakfastG: _median(col('protein_breakfast_g')),
      proteinLunchG: _median(col('protein_lunch_g')),
      proteinDinnerG: _median(col('protein_dinner_g')),
      calciumMg: _median(col('calcium_mg')),
      zincMg: _median(col('zinc_mg')),
      fluidsMl: _median(col('fluids_ml')),
      sampleDays: pool.length,
      weekdaySpecific: pool == sameWd,
    );
  }

  return GapFillState(
    recallDate: recallOk ? yesterday : null,
    anchorRow: recallOk ? anchor : null,
    anchorDate: recallOk ? dayBefore : null,
    olderGaps: olderGaps,
    typicalFor: typicalFor,
  );
}

double _r1(double v) => (v * 10).roundToDouble() / 10;

/// Guard shared by both writers: never overwrite a measured row.
Future<bool> _dateIsFree(
    SupabaseClient sb, String childId, String date) async {
  final existing = await sb
      .from('daily_nutrition')
      .select('estimation_method')
      .eq('child_id', childId)
      .eq('log_date', date)
      .maybeSingle();
  return existing == null ||
      (existing['estimation_method'] as String? ?? kMeasured) != kMeasured;
}

/// One-tap relative recall: anchor × band multiplier → estimate for
/// [date]. Returns an error message or null on success.
Future<String?> applyRelativeRecall(SupabaseClient sb, String childId,
    String date, Map<String, dynamic> anchor, RecallChoice choice) async {
  final m = recallMultipliers[choice]!;
  try {
    if (!await _dateIsFree(sb, childId, date)) {
      return 'Day already has measured data';
    }
    await sb.from('daily_nutrition').upsert({
      'child_id': childId,
      'log_date': date,
      'protein_breakfast_g': _r1(_num(anchor['protein_breakfast_g']) * m),
      'protein_lunch_g': _r1(_num(anchor['protein_lunch_g']) * m),
      'protein_dinner_g': _r1(_num(anchor['protein_dinner_g']) * m),
      'calcium_mg': (_num(anchor['calcium_mg']) * m).roundToDouble(),
      'zinc_mg': _r1(_num(anchor['zinc_mg']) * m),
      'fluids_ml': (_num(anchor['fluids_ml']) * m).roundToDouble(),
      'estimation_method': kRelativeRecall,
      'confidence': 0.7,
    }, onConflict: 'child_id,log_date');
    return null;
  } on PostgrestException catch (e) {
    return e.message;
  }
}

/// Typical-day pattern fill for an older gap day. [multiplier] is the
/// parent's "compared with usual" adjustment — it scales the measured
/// medians, so it stays anchored to real data (no estimate chaining).
/// An adjusted fill carries a parent memory signal, so it rates
/// slightly above a blind fill.
Future<String?> applyPatternFill(
    SupabaseClient sb, String childId, String date, TypicalDay t,
    {double multiplier = 1.0}) async {
  final m = multiplier;
  try {
    if (!await _dateIsFree(sb, childId, date)) {
      return 'Day already has measured data';
    }
    await sb.from('daily_nutrition').upsert({
      'child_id': childId,
      'log_date': date,
      'protein_breakfast_g': _r1(t.proteinBreakfastG * m),
      'protein_lunch_g': _r1(t.proteinLunchG * m),
      'protein_dinner_g': _r1(t.proteinDinnerG * m),
      'calcium_mg': (t.calciumMg * m).roundToDouble(),
      'zinc_mg': _r1(t.zincMg * m),
      'fluids_ml': (t.fluidsMl * m).roundToDouble(),
      'estimation_method': kPatternFill,
      'confidence': m == 1.0 ? 0.3 : 0.35,
    }, onConflict: 'child_id,log_date');
    return null;
  } on PostgrestException catch (e) {
    return e.message;
  }
}
