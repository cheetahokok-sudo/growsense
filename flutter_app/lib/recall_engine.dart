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
const kPatternSuggest = 'pattern_suggest';

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

/// Sleep varies far less night-to-night than food intake does day to
/// day, so its "vs usual" bands are gentler (±10/20% not ±17/35%).
const sleepMultipliers = {
  RecallChoice.muchLess: 0.8,
  RecallChoice.slightlyLess: 0.9,
  RecallChoice.same: 1.0,
  RecallChoice.slightlyMore: 1.1,
  RecallChoice.muchMore: 1.2,
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

/// Parent confirmed an estimated day as accurate ("Looks right" in the
/// trust calendar). Confirmation is itself a recall, so it promotes to
/// recalled_manual at the time-tiered confidence — NEVER to measured
/// 1.0. Values are untouched; only provenance changes.
Future<String?> confirmEstimate(
    SupabaseClient sb, String childId, String date) async {
  final parts = date.split('-').map(int.parse).toList();
  final today = DateTime.now();
  final gap = DateTime(today.year, today.month, today.day)
      .difference(DateTime(parts[0], parts[1], parts[2]))
      .inDays;
  try {
    await sb
        .from('daily_nutrition')
        .update({
          'estimation_method': kRecalledManual,
          'confidence': gap <= 7 ? 0.85 : 0.7,
        })
        .eq('child_id', childId)
        .eq('log_date', date)
        .neq('estimation_method', kMeasured); // measured rows are immutable here
    return null;
  } on PostgrestException catch (e) {
    return e.message;
  }
}

/// "Looks right" for an estimated night — same promotion rule as
/// nutrition: recalled_manual at time-tiered confidence, never 1.0.
Future<String?> confirmSleepEstimate(
    SupabaseClient sb, String childId, String date) async {
  final gap = _daysAgo(date);
  try {
    await sb
        .from('daily_sleep')
        .update({
          'estimation_method': kRecalledManual,
          'confidence': gap <= 7 ? 0.85 : 0.7,
        })
        .eq('child_id', childId)
        .eq('log_date', date)
        .neq('estimation_method', kMeasured);
    return null;
  } on PostgrestException catch (e) {
    return e.message;
  }
}

/// "Looks right" for a day of routine-confirmed activity items —
/// promotes every AI-estimated item on the day; measured and already-
/// recalled items are untouched.
Future<String?> confirmActivityEstimates(
    SupabaseClient sb, String childId, String date) async {
  final gap = _daysAgo(date);
  try {
    await sb
        .from('daily_activity_items')
        .update({
          'estimation_method': kRecalledManual,
          'confidence': gap <= 7 ? 0.85 : 0.7,
        })
        .eq('child_id', childId)
        .eq('log_date', date)
        .neq('estimation_method', kMeasured)
        .neq('estimation_method', kRecalledManual);
    return null;
  } on PostgrestException catch (e) {
    return e.message;
  }
}

int _daysAgo(String date) {
  final p = date.split('-').map(int.parse).toList();
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day)
      .difference(DateTime(p[0], p[1], p[2]))
      .inDays;
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

// ══════════════════════════════════════════════════════════════════
// Phase 2 — Activity: routine recognition, not quantity estimation.
// Parents remember EVENTS ("tennis class every Friday"), so the
// engine mines the child's own measured history for weekday routines
// and daily habits, and the parent confirms concrete items by
// recognition. Occurrence is parent-verified; durations are the
// routine's medians — hence pattern_suggest at 0.75, between
// relative_recall and recalled_manual on the ladder.
// ══════════════════════════════════════════════════════════════════

class ActivitySuggestion {
  final String? activityId;
  final String displayName;
  final String? category;
  final String tier;
  final String? unit;
  final bool isOutdoor;
  final double medianDurationMin;
  final double medianValue;

  /// True when this activity recurs on the target date's weekday
  /// ("most Fridays"); false for everyday habits ("most days").
  final bool isWeekdayRoutine;
  final int occurrences;
  ActivitySuggestion({
    required this.activityId,
    required this.displayName,
    required this.category,
    required this.tier,
    required this.unit,
    required this.isOutdoor,
    required this.medianDurationMin,
    required this.medianValue,
    required this.isWeekdayRoutine,
    required this.occurrences,
  });
}

/// Mine the last 8 weeks of MEASURED activity items for what the
/// child usually does on [date]'s weekday (at least half of those
/// weekdays, seen at least twice) plus everyday habits (at least 40%
/// of all logged days, seen at least 4 times). Weekday routines rank
/// first. Estimated items never feed the miner — the engine must not
/// learn from its own guesses.
Future<List<ActivitySuggestion>> loadActivitySuggestions(
    SupabaseClient sb, String childId, String date) async {
  final since = localISO(DateTime.now().subtract(const Duration(days: 56)));
  final rows = List<Map<String, dynamic>>.from(await sb
      .from('daily_activity_items')
      .select('log_date, activity_id, display_name, category, tier, '
          'duration_min, duration_value, unit, is_outdoor, estimation_method')
      .eq('child_id', childId)
      .gte('log_date', since)
      .lt('log_date', localISO(DateTime.now())));

  final measured = rows
      .where((r) =>
          (r['estimation_method'] as String? ?? kMeasured) == kMeasured)
      .toList();
  if (measured.isEmpty) return [];

  final targetWd = DateTime.parse(date).weekday;
  final allDates = <String>{};
  final wdDates = <String>{};
  for (final r in measured) {
    final d = r['log_date'] as String;
    allDates.add(d);
    if (DateTime.parse(d).weekday == targetWd) wdDates.add(d);
  }

  // Group by activity identity (preset id, falling back to name).
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final r in measured) {
    final key =
        (r['activity_id'] as String?) ?? (r['display_name'] as String? ?? '?');
    groups.putIfAbsent(key, () => []).add(r);
  }

  final routines = <ActivitySuggestion>[];
  final habits = <ActivitySuggestion>[];
  for (final items in groups.values) {
    final first = items.first;
    final datesWith = {for (final r in items) r['log_date'] as String};
    final wdWith = datesWith.where(wdDates.contains).length;
    final isRoutine = wdDates.length >= 2 &&
        wdWith >= 2 &&
        wdWith / wdDates.length >= 0.5;
    final isHabit = !isRoutine &&
        datesWith.length >= 4 &&
        datesWith.length / allDates.length >= 0.4;
    if (!isRoutine && !isHabit) continue;

    // Duration medians from the same-weekday pool for routines (a
    // Friday tennis class has a Friday-typical length), else overall.
    final pool = isRoutine
        ? items
            .where((r) =>
                DateTime.parse(r['log_date'] as String).weekday == targetWd)
            .toList()
        : items;
    final suggestion = ActivitySuggestion(
      activityId: first['activity_id'] as String?,
      displayName: first['display_name'] as String? ?? '?',
      category: first['category'] as String?,
      tier: first['tier'] as String? ?? 'cardio',
      unit: first['unit'] as String?,
      isOutdoor: first['is_outdoor'] as bool? ?? false,
      medianDurationMin: _median([
        for (final r in pool) ((r['duration_min'] as num?)?.toDouble() ?? 0)
      ]),
      medianValue: _median([
        for (final r in pool) ((r['duration_value'] as num?)?.toDouble() ?? 0)
      ]),
      isWeekdayRoutine: isRoutine,
      occurrences: isRoutine ? wdWith : datesWith.length,
    );
    (isRoutine ? routines : habits).add(suggestion);
  }

  routines.sort((a, b) => b.occurrences.compareTo(a.occurrences));
  habits.sort((a, b) => b.occurrences.compareTo(a.occurrences));
  return [...routines, ...habits].take(5).toList();
}

/// Insert the parent-confirmed routine items for [date]. Only offered
/// on days with no activity items; the guard re-checks to be safe.
Future<String?> applyActivitySuggestions(SupabaseClient sb, String childId,
    String date, List<ActivitySuggestion> confirmed) async {
  if (confirmed.isEmpty) return null;
  try {
    final existing = await sb
        .from('daily_activity_items')
        .select('item_id')
        .eq('child_id', childId)
        .eq('log_date', date)
        .limit(1);
    if ((existing as List).isNotEmpty) {
      return 'Day already has activity data';
    }
    await sb.from('daily_activity_items').insert([
      for (final s in confirmed)
        {
          'child_id': childId,
          'log_date': date,
          'activity_id': s.activityId,
          'display_name': s.displayName,
          'category': s.category,
          'tier': s.tier,
          'duration_min': _r1(s.medianDurationMin),
          'duration_value':
              _r1(s.medianValue > 0 ? s.medianValue : s.medianDurationMin),
          'unit': s.unit ?? 'min',
          'is_outdoor': s.isOutdoor,
          'is_custom': false,
          'estimation_method': kPatternSuggest,
          'confidence': 0.75,
        }
    ]);
    return null;
  } on PostgrestException catch (e) {
    return e.message;
  }
}

// ══════════════════════════════════════════════════════════════════
// Phase 2 — Sleep: typical-night fill with gentle "vs usual" bands.
// Wearable rows are device-measured and are never touched.
// ══════════════════════════════════════════════════════════════════

class TypicalNight {
  final double totalSleepMin;
  final int sampleNights;
  TypicalNight({required this.totalSleepMin, required this.sampleNights});
}

/// Median measured night from the last 30 days; null under 3 nights.
Future<TypicalNight?> loadTypicalNight(
    SupabaseClient sb, String childId) async {
  final since = localISO(DateTime.now().subtract(const Duration(days: 30)));
  final rows = List<Map<String, dynamic>>.from(await sb
      .from('daily_sleep')
      .select('total_sleep_min, estimation_method')
      .eq('child_id', childId)
      .gte('log_date', since));
  final mins = [
    for (final r in rows)
      if ((r['estimation_method'] as String? ?? kMeasured) == kMeasured)
        ((r['total_sleep_min'] as num?)?.toDouble() ?? 0),
  ]..removeWhere((v) => v <= 0);
  if (mins.length < 3) return null;
  return TypicalNight(
      totalSleepMin: _median(mins), sampleNights: mins.length);
}

/// Fill [date]'s night as typical × the "vs usual" multiplier.
/// Efficiency is recomputed with the same duration-adequacy rule as
/// saveTodayData; never overwrites a measured (incl. wearable) row.
Future<String?> applySleepFill(SupabaseClient sb, String childId, String date,
    TypicalNight t, double multiplier,
    {int sleepTargetMin = 570}) async {
  try {
    final existing = await sb
        .from('daily_sleep')
        .select('estimation_method')
        .eq('child_id', childId)
        .eq('log_date', date)
        .maybeSingle();
    if (existing != null &&
        (existing['estimation_method'] as String? ?? kMeasured) ==
            kMeasured) {
      return 'Night already has measured data';
    }
    final total = (t.totalSleepMin * multiplier).round();
    await sb.from('daily_sleep').upsert({
      'child_id': childId,
      'log_date': date,
      'total_sleep_min': total,
      'sleep_efficiency_score':
          ((total / sleepTargetMin) * 100).round().clamp(0, 100),
      'data_source': 'manual',
      'estimation_method': kPatternFill,
      'confidence': multiplier == 1.0 ? 0.3 : 0.35,
    }, onConflict: 'child_id,log_date');
    return null;
  } on PostgrestException catch (e) {
    return e.message;
  }
}
