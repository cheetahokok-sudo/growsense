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
  DayMetrics(this.date);

  bool get hasAnyLog =>
      proteinG != null ||
      calciumMg != null ||
      sleepMin != null ||
      weightedActivityMin > 0;
}

class WeeklyAnalytics {
  final List<DayMetrics> days; // oldest → newest, always 7 entries
  final double? avgScore; // over logged days only, like the PWA
  final double? avgSleepHours;
  final double? velocityCmPerYear;
  final String velocityLabel; // 'on pace' | 'stable' | 'below range' | 'not enough data'
  final double? heightGain30dCm;
  WeeklyAnalytics({
    required this.days,
    required this.avgScore,
    required this.avgSleepHours,
    required this.velocityCmPerYear,
    required this.velocityLabel,
    required this.heightGain30dCm,
  });
}

Future<WeeklyAnalytics> loadWeeklyAnalytics(
    SupabaseClient sb, Map<String, dynamic> child) async {
  final childId = child['child_id'] as String;
  final now = DateTime.now();
  final since = localISO(now.subtract(const Duration(days: 6)));
  final since30 = localISO(now.subtract(const Duration(days: 30)));

  final results = await Future.wait([
    sb
        .from('daily_nutrition')
        .select('log_date, total_protein_g, calcium_mg, fluids_ml')
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

  // Seven day slots, oldest first
  final days = [
    for (var i = 6; i >= 0; i--)
      DayMetrics(localISO(now.subtract(Duration(days: i)))),
  ];
  final byDate = {for (final d in days) d.date: d};

  for (final r in results[0] as List) {
    final d = byDate[r['log_date']];
    if (d == null) continue;
    d.proteinG = (r['total_protein_g'] as num?)?.toDouble();
    d.calciumMg = (r['calcium_mg'] as num?)?.toDouble();
    d.fluidsMl = (r['fluids_ml'] as num?)?.toDouble();
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

  // Per-day readiness score over days that have any log — the honest
  // average, same as updateStats().
  final proteinTarget = calcProteinTargetG(
    child['date_of_birth'] as String?,
    null,
    child['biological_sex'] as String?,
  );
  final logged = days.where((d) => d.hasAnyLog).toList();
  double? avgScore;
  if (logged.isNotEmpty) {
    double total = 0;
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
    }
    avgScore = total / logged.length;
  }

  final sleepVals = [
    for (final d in days)
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

  return WeeklyAnalytics(
    days: days,
    avgScore: avgScore,
    avgSleepHours: avgSleepHours,
    velocityCmPerYear: velocity,
    velocityLabel: velocityLabel,
    heightGain30dCm: gain,
  );
}
