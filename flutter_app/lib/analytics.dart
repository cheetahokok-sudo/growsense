// ══════════════════════════════════════════════════════════════════
// Analytics computations — Dart port of updateStats() and
// calcProteinTargetG() from app.js. Same DRI rates (IOM 2005), same
// growth-velocity weighting (Sleep 40 / Activity 30 / Nutrition 30;
// within nutrition Calcium 50 / Protein 30 / Water 20), same
// velocity thresholds (≥5.3 on pace, <4.2 below range).
//
// Deliberately skipped for now: the legacy daily_activity table
// fallback the PWA still carries for pre-items historical data.
// ══════════════════════════════════════════════════════════════════

import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_data.dart';
import 'app_state.dart';

/// DRI protein target in grams (IOM 2005, Table 10-21) — port of
/// calcProteinTargetG.
int calcProteinTargetG(String? dobStr, double? weightKg, String? sex) {
  double? ageYears;
  if (dobStr != null) {
    final dob = DateTime.tryParse(dobStr);
    if (dob != null) {
      ageYears = DateTime.now().difference(dob).inDays / 365.25;
    }
  }
  final isMale = (sex ?? 'male').toLowerCase() != 'female';

  double perKgRate;
  int minimumG;
  if (ageYears == null || ageYears < 1) {
    perKgRate = 1.52;
    minimumG = 11;
  } else if (ageYears < 4) {
    perKgRate = 1.05;
    minimumG = 13;
  } else if (ageYears < 9) {
    perKgRate = 0.95;
    minimumG = 19;
  } else if (ageYears < 14) {
    perKgRate = 0.95;
    minimumG = 34;
  } else if (isMale) {
    perKgRate = 0.85;
    minimumG = 52;
  } else {
    perKgRate = 0.85;
    minimumG = 46;
  }
  if (weightKg == null) return minimumG;
  final weightBased = (weightKg * perKgRate).round();
  return weightBased > minimumG ? weightBased : minimumG;
}

/// Growth-optimized protein target (port of calcProteinBoostTargetG):
/// 1.2 g/kg with an age-dependent safe ceiling, floored at the DRI
/// standard; without a weight, standard × 1.26.
int calcProteinBoostTargetG(String? dobStr, double? weightKg, String? sex) {
  final standard = calcProteinTargetG(dobStr, weightKg, sex);
  double? ageYears;
  if (dobStr != null) {
    final dob = DateTime.tryParse(dobStr);
    if (dob != null) {
      ageYears = DateTime.now().difference(dob).inDays / 365.25;
    }
  }
  double safeMaxPerKg;
  if (ageYears == null || ageYears < 4) {
    safeMaxPerKg = 1.3;
  } else if (ageYears < 14) {
    safeMaxPerKg = 1.5;
  } else {
    safeMaxPerKg = 1.6;
  }
  if (weightKg == null) return (standard * 1.26).round();
  final boost = (weightKg * 1.2).round();
  final safeMax = (weightKg * safeMaxPerKg).round();
  final floored = boost > standard ? boost : standard;
  return floored < safeMax ? floored : safeMax;
}

class DayMetrics {
  final String date;
  double? proteinG;
  double? calciumMg;
  double? fluidsMl;
  double? sleepMin;
  double? sleepEfficiency;
  double weightedActivityMin = 0;

  /// True when the day's nutrition row is an AI estimate (recall
  /// engine) rather than measured/recalled parent data. Estimated
  /// days keep trends continuous but render gold and are excluded
  /// from correlation insights.
  bool nutritionEstimated = false;
  DayMetrics(this.date);

  bool get hasAnyLog =>
      proteinG != null ||
      calciumMg != null ||
      sleepMin != null ||
      weightedActivityMin > 0;
}

/// A single computed cross-lever observation for the insight card.
/// Deliberately structured (not a baked English string) so the widget
/// layer can render it through i18n — this app is Thailand-first.
enum InsightKind { sleepActivity, leverDown, leverUp }

class SmartInsight {
  final InsightKind kind;
  final bool positive; // colours the card: green vs caution-gold
  final String name; // child first name, may be empty
  final String leverId; // 'nutrition' | 'activity' | 'sleep' | ''
  final String hours; // formatted hours diff, for sleepActivity
  final int points; // WoW delta magnitude in whole points
  SmartInsight({
    required this.kind,
    required this.positive,
    this.name = '',
    this.leverId = '',
    this.hours = '',
    this.points = 0,
  });
}

class WeeklyAnalytics {
  final List<DayMetrics> days; // oldest → newest, always 7 entries
  final double? avgScore; // over logged days only, like the PWA
  final double? avgSleepHours;
  final double? velocityCmPerYear;
  final String velocityLabel; // 'on pace' | 'stable' | 'below range' | 'not enough data'
  final double? heightGain30dCm;

  // 7-day lever averages (0..1, over logged days) — feed the
  // separated mini-rings at the top of the Analytics screen, where
  // comparing levers is the point (unlike Today's composite ring).
  final double? avgNutPct;
  final double? avgActPct;
  final double? avgSlpPct;

  // Week-over-week change per lever (this 7d minus the prior 7d) as a
  // signed fraction (−1..1); null when the prior week has no logged
  // days to compare against. Drives the ▲/▼ deltas on the rings.
  final double? deltaNutPct;
  final double? deltaActPct;
  final double? deltaSlpPct;

  // One honest cross-lever observation, or null when the week doesn't
  // have enough logged data to say anything true.
  final SmartInsight? insight;

  WeeklyAnalytics({
    required this.days,
    required this.avgScore,
    required this.avgSleepHours,
    required this.velocityCmPerYear,
    required this.velocityLabel,
    required this.heightGain30dCm,
    required this.avgNutPct,
    required this.avgActPct,
    required this.avgSlpPct,
    required this.deltaNutPct,
    required this.deltaActPct,
    required this.deltaSlpPct,
    required this.insight,
  });
}

/// Lever averages for one window (0..1, over logged days only).
class _Levers {
  final double? score, nut, act, slp;
  _Levers(this.score, this.nut, this.act, this.slp);
}

_Levers _computeLevers(List<DayMetrics> window, int proteinTarget) {
  final logged = window.where((d) => d.hasAnyLog).toList();
  if (logged.isEmpty) return _Levers(null, null, null, null);
  double total = 0, nutSum = 0, actSum = 0, slpSum = 0;
  for (final d in logged) {
    final pR = ((d.proteinG ?? 0) / proteinTarget).clamp(0.0, 1.0);
    final cR = ((d.calciumMg ?? 0) / 1300).clamp(0.0, 1.0);
    final wR = ((d.fluidsMl ?? 0) / 2000).clamp(0.0, 1.0);
    final nutPct = pR * 0.30 + cR * 0.50 + wR * 0.20;
    final actPct = (d.weightedActivityMin / 60).clamp(0.0, 1.0);
    final durR = ((d.sleepMin ?? 0) / (9.5 * 60)).clamp(0.0, 1.0);
    final effR = ((d.sleepEfficiency ?? 0) / 100).clamp(0.0, 1.0);
    final slpPct = durR * 0.6 + effR * 0.4;
    total += nutPct * 30 + actPct * 30 + slpPct * 40;
    nutSum += nutPct;
    actSum += actPct;
    slpSum += slpPct;
  }
  final n = logged.length;
  return _Levers(total / n, nutSum / n, actSum / n, slpSum / n);
}

/// Pick the single most useful thing to say about the week. Priority:
/// (1) a real sleep↔activity pattern within the week, (2) the lever
/// most in decline vs last week, (3) the lever with the best momentum.
/// Returns null rather than inventing an insight from thin data.
SmartInsight? _pickInsight(
  List<DayMetrics> week,
  String firstName, {
  double? dNut,
  double? dAct,
  double? dSlp,
  bool nutritionHasEstimates = false,
}) {
  // Honesty rule: never make a nutrition claim off AI-estimated days —
  // the recall engine must not manufacture its own "insights".
  if (nutritionHasEstimates) dNut = null;
  // (1) Sleep vs activity — split the week's sleep-logged days at their
  // own activity median and compare average sleep between halves.
  final withSleep = week.where((d) => d.sleepMin != null).toList();
  if (withSleep.length >= 4) {
    withSleep.sort(
        (a, b) => a.weightedActivityMin.compareTo(b.weightedActivityMin));
    final half = withSleep.length ~/ 2;
    final low = withSleep.take(half).toList();
    final high = withSleep.skip(withSleep.length - half).toList();
    final lowAct =
        low.fold<double>(0, (s, d) => s + d.weightedActivityMin) / low.length;
    final highAct =
        high.fold<double>(0, (s, d) => s + d.weightedActivityMin) / high.length;
    final lowSleep =
        low.fold<double>(0, (s, d) => s + d.sleepMin!) / low.length;
    final highSleep =
        high.fold<double>(0, (s, d) => s + d.sleepMin!) / high.length;
    final diffH = (highSleep - lowSleep) / 60;
    // Only claim a link when the halves actually differ in activity —
    // a flat-activity week must not read as "more active days".
    if (highAct - lowAct >= 10 && diffH >= 0.4) {
      return SmartInsight(
        kind: InsightKind.sleepActivity,
        positive: true,
        name: firstName,
        hours: diffH.toStringAsFixed(1),
      );
    }
  }

  // (2) Lever most in decline this week (≥5 points down).
  final downs = <String, double>{
    if (dNut != null && dNut <= -0.05) 'nutrition': dNut,
    if (dAct != null && dAct <= -0.05) 'activity': dAct,
    if (dSlp != null && dSlp <= -0.05) 'sleep': dSlp,
  };
  if (downs.isNotEmpty) {
    final worst = downs.entries.reduce((a, b) => a.value < b.value ? a : b);
    return SmartInsight(
      kind: InsightKind.leverDown,
      positive: false,
      leverId: worst.key,
      points: (-worst.value * 100).round(),
    );
  }

  // (3) Best momentum (≥5 points up).
  final ups = <String, double>{
    if (dNut != null && dNut >= 0.05) 'nutrition': dNut,
    if (dAct != null && dAct >= 0.05) 'activity': dAct,
    if (dSlp != null && dSlp >= 0.05) 'sleep': dSlp,
  };
  if (ups.isNotEmpty) {
    final best = ups.entries.reduce((a, b) => a.value > b.value ? a : b);
    return SmartInsight(
      kind: InsightKind.leverUp,
      positive: true,
      leverId: best.key,
      points: (best.value * 100).round(),
    );
  }

  return null;
}

Future<WeeklyAnalytics> loadWeeklyAnalytics(
    SupabaseClient sb, Map<String, dynamic> child) async {
  final childId = child['child_id'] as String;
  final now = DateTime.now();
  final since = localISO(now.subtract(const Duration(days: 13)));
  final since30 = localISO(now.subtract(const Duration(days: 30)));

  final results = await Future.wait([
    sb
        .from('daily_nutrition')
        .select(
            'log_date, total_protein_g, calcium_mg, fluids_ml, estimation_method')
        .eq('child_id', childId)
        .gte('log_date', since),
    sb
        .from('daily_sleep')
        .select('log_date, total_sleep_min, sleep_efficiency_score')
        .eq('child_id', childId)
        .gte('log_date', since),
    sb
        .from('daily_activity_items')
        .select('log_date, tier, duration_min')
        .eq('child_id', childId)
        .gte('log_date', since),
    sb
        .from('child_growth_analytics_ledger')
        .select('recorded_date, height_delta_cm, days_between_measurements')
        .eq('child_id', childId)
        .order('recorded_date', ascending: false)
        .limit(1),
    sb
        .from('measurements')
        .select('recorded_date, stature_height_cm')
        .eq('child_id', childId)
        .gte('recorded_date', since30)
        .order('recorded_date', ascending: false),
  ]);

  // Fourteen day slots, oldest first — the trailing 7 are "this week",
  // the leading 7 are last week, for the week-over-week deltas.
  final days = [
    for (var i = 13; i >= 0; i--)
      DayMetrics(localISO(now.subtract(Duration(days: i)))),
  ];
  final byDate = {for (final d in days) d.date: d};
  final currentWeek = days.sublist(7);
  final priorWeek = days.sublist(0, 7);

  for (final r in results[0] as List) {
    final d = byDate[r['log_date']];
    if (d == null) continue;
    d.proteinG = (r['total_protein_g'] as num?)?.toDouble();
    d.calciumMg = (r['calcium_mg'] as num?)?.toDouble();
    d.fluidsMl = (r['fluids_ml'] as num?)?.toDouble();
    // recalled_manual is parent data — only pure AI estimates
    // (relative_recall / pattern_fill / weekly_survey) render gold.
    final method = r['estimation_method'] as String? ?? 'measured';
    d.nutritionEstimated = method != 'measured' && method != 'recalled_manual';
  }
  for (final r in results[1] as List) {
    final d = byDate[r['log_date']];
    if (d == null) continue;
    d.sleepMin = (r['total_sleep_min'] as num?)?.toDouble();
    d.sleepEfficiency = (r['sleep_efficiency_score'] as num?)?.toDouble();
  }
  for (final r in results[2] as List) {
    final d = byDate[r['log_date']];
    if (d == null) continue;
    final weight =
        (activityTierConfig[r['tier']] ?? activityTierConfig['lifestyle']!)
            .weight;
    d.weightedActivityMin +=
        ((r['duration_min'] as num?)?.toDouble() ?? 0) * weight;
  }

  // Per-day readiness + lever averages over each week's logged days —
  // the honest average, same as updateStats(). The prior week feeds
  // the week-over-week deltas.
  final proteinTarget = calcProteinTargetG(
    child['date_of_birth'] as String?,
    null,
    child['biological_sex'] as String?,
  );
  final cur = _computeLevers(currentWeek, proteinTarget);
  final prior = _computeLevers(priorWeek, proteinTarget);
  final avgScore = cur.score;
  final avgNut = cur.nut, avgAct = cur.act, avgSlp = cur.slp;
  double? delta(double? c, double? p) =>
      (c != null && p != null) ? c - p : null;
  final deltaNut = delta(cur.nut, prior.nut);
  final deltaAct = delta(cur.act, prior.act);
  final deltaSlp = delta(cur.slp, prior.slp);

  final sleepVals = [
    for (final d in currentWeek)
      if (d.sleepMin != null) d.sleepMin!,
  ];
  final avgSleepHours = sleepVals.isEmpty
      ? null
      : sleepVals.reduce((a, b) => a + b) / sleepVals.length / 60;

  // Height velocity from the DB-side LAG() ledger view
  double? velocity;
  var velocityLabel = 'not enough data';
  final ledger = results[3] as List;
  if (ledger.isNotEmpty) {
    final row = ledger[0];
    final delta = (row['height_delta_cm'] as num?)?.toDouble();
    final between = (row['days_between_measurements'] as num?)?.toInt() ?? 0;
    if (delta != null && between > 0) {
      velocity = delta / between * 365.25;
      velocityLabel = velocity >= 5.3
          ? 'on pace'
          : velocity < 4.2
              ? 'below range'
              : 'stable';
    }
  }

  // 30-day height gain from raw measurements
  double? gain;
  final meas = results[4] as List;
  if (meas.length >= 2) {
    final newest = (meas.first['stature_height_cm'] as num?)?.toDouble();
    final oldest = (meas.last['stature_height_cm'] as num?)?.toDouble();
    if (newest != null && oldest != null) gain = newest - oldest;
  }

  final insight = _pickInsight(
    currentWeek,
    ((child['name'] as String?) ?? '').split(' ').first,
    dNut: deltaNut,
    dAct: deltaAct,
    dSlp: deltaSlp,
    nutritionHasEstimates:
        days.any((d) => d.nutritionEstimated), // both weeks feed deltas
  );

  return WeeklyAnalytics(
    days: currentWeek,
    avgScore: avgScore,
    avgSleepHours: avgSleepHours,
    velocityCmPerYear: velocity,
    velocityLabel: velocityLabel,
    heightGain30dCm: gain,
    avgNutPct: avgNut,
    avgActPct: avgAct,
    avgSlpPct: avgSlp,
    deltaNutPct: deltaNut,
    deltaActPct: deltaAct,
    deltaSlpPct: deltaSlp,
    insight: insight,
  );
}
