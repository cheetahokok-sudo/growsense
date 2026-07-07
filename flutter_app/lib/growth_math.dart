// ══════════════════════════════════════════════════════════════════
// Growth math — Dart port of growth-percentile.js and target-height.js.
//
// Percentile method: WHO publishes height-for-age as five percentile
// bands (P3/P15/P50/P85/P97). Interpolate bands to exact age, place
// the child between adjacent band z-values, convert z → percentile
// via the normal CDF. Same approach and same known tail limitation
// as the PWA (see growth-percentile.js header).
//
// Target height: Zeevi et al. 2024 (Children 11(8):916) — age-
// shrinkage correction (Sorkin 1999), sex handling via per-sex
// z-standardization, regression to the mean (Z' = 0.79·Z − 0.077),
// real empirical residual SD (±4.5 cm sons / ±4.2 cm daughters).
//
// Projection (Flutter addition, replaces the PWA's linear velocity
// extrapolation): a child tends to track their current percentile
// channel; genetics pulls the channel toward the mid-parental target
// over the remaining growth years. We project the z-score, not the
// height: z(t) drifts linearly in time from the child's current z to
// the genetic target z (± a small recent-habits nudge, capped at
// ±0.15 SD), and height(t) is read off the WHO bands at z(t) — so
// the projected curve automatically follows the physiologic WHO
// curve shape (including the pubertal slowdown built into the
// reference) instead of a straight line. This is a transparent
// heuristic for parents, not a clinical prediction model.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

const percentileZ = {
  'p3': -1.881,
  'p15': -1.036,
  'p50': 0.0,
  'p85': 1.036,
  'p97': 1.881,
};

class WhoReference {
  final List<List<double>> hfaBoys; // rows: [months, p3, p15, p50, p85, p97]
  final List<List<double>> hfaGirls;
  WhoReference(this.hfaBoys, this.hfaGirls);

  List<List<double>> tableFor(String? sex) =>
      (sex ?? 'male').toLowerCase() == 'female' ? hfaGirls : hfaBoys;
}

WhoReference? _whoCache;

Future<WhoReference> loadWhoReference() async {
  if (_whoCache != null) return _whoCache!;
  final raw = await rootBundle.loadString('assets/who_reference.json');
  final j = jsonDecode(raw) as Map<String, dynamic>;
  List<List<double>> rows(String key) => [
        for (final r in j[key] as List)
          [for (final v in r as List) (v as num).toDouble()],
      ];
  _whoCache = WhoReference(rows('hfa_boys_5_19'), rows('hfa_girls_5_19'));
  return _whoCache!;
}

/// Abramowitz & Stegun 7.1.26, same as growth-percentile.js.
double erf(double x) {
  final sign = x < 0 ? -1.0 : 1.0;
  x = x.abs();
  const a1 = 0.254829592,
      a2 = -0.284496736,
      a3 = 1.421413741,
      a4 = -1.453152027,
      a5 = 1.061405429,
      p = 0.3275911;
  final t = 1.0 / (1.0 + p * x);
  final y = 1.0 -
      (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-x * x);
  return sign * y;
}

double zToPercentile(double z) => 50 * (1 + erf(z / math.sqrt(2)));

/// Linear interpolation of the five band values to an exact age.
/// Returns [p3, p15, p50, p85, p97]; clamps outside the table range.
List<double> interpolateBands(List<List<double>> table, double ageMonths) {
  if (ageMonths <= table.first[0]) return table.first.sublist(1);
  if (ageMonths >= table.last[0]) return table.last.sublist(1);
  for (var i = 0; i < table.length - 1; i++) {
    final r0 = table[i], r1 = table[i + 1];
    if (ageMonths >= r0[0] && ageMonths <= r1[0]) {
      final frac = (ageMonths - r0[0]) / (r1[0] - r0[0]);
      return [for (var k = 1; k <= 5; k++) r0[k] + frac * (r1[k] - r0[k])];
    }
  }
  return table.last.sublist(1);
}

const _bandZs = [-1.881, -1.036, 0.0, 1.036, 1.881];

/// Height → z-score against interpolated bands, extrapolating the
/// local band slope beyond P3/P97 (same as the PWA).
double zFromHeight(List<double> bands, double heightCm) {
  if (heightCm <= bands[0]) {
    final slope = (_bandZs[1] - _bandZs[0]) / (bands[1] - bands[0]);
    return _bandZs[0] + (heightCm - bands[0]) * slope;
  }
  if (heightCm >= bands[4]) {
    final slope = (_bandZs[4] - _bandZs[3]) / (bands[4] - bands[3]);
    return _bandZs[4] + (heightCm - bands[4]) * slope;
  }
  for (var i = 0; i < 4; i++) {
    if (heightCm >= bands[i] && heightCm <= bands[i + 1]) {
      final frac = (heightCm - bands[i]) / (bands[i + 1] - bands[i]);
      return _bandZs[i] + frac * (_bandZs[i + 1] - _bandZs[i]);
    }
  }
  return 0;
}

/// Inverse of [zFromHeight]: read a height off the bands at a z-score.
double heightAtZ(List<double> bands, double z) {
  if (z <= _bandZs[0]) {
    final slope = (bands[1] - bands[0]) / (_bandZs[1] - _bandZs[0]);
    return bands[0] + (z - _bandZs[0]) * slope;
  }
  if (z >= _bandZs[4]) {
    final slope = (bands[4] - bands[3]) / (_bandZs[4] - _bandZs[3]);
    return bands[4] + (z - _bandZs[4]) * slope;
  }
  for (var i = 0; i < 4; i++) {
    if (z >= _bandZs[i] && z <= _bandZs[i + 1]) {
      final frac = (z - _bandZs[i]) / (_bandZs[i + 1] - _bandZs[i]);
      return bands[i] + frac * (bands[i + 1] - bands[i]);
    }
  }
  return bands[2];
}

// ── Target height (Zeevi et al. 2024) ───────────────────────────────

const adultMean = {'male': 176.5, 'female': 163.2};
const adultSD = {'male': 7.31, 'female': 6.54};

double _ageShrinkageCm(int? age, String sex) {
  if (age == null || age <= 30) return 0;
  final totalAt70 = sex == 'female' ? 5.0 : 3.0;
  final totalAt80 = sex == 'female' ? 8.0 : 5.0;
  if (age <= 70) return (age - 30) / 40 * totalAt70;
  return totalAt70 + math.min(age - 70, 10) / 10 * (totalAt80 - totalAt70);
}

class TargetHeight {
  final double targetHeightCm;
  final double rangeLowCm;
  final double rangeHighCm;
  final double correctedZ;
  final double tannerMidParentalCm;
  TargetHeight(this.targetHeightCm, this.rangeLowCm, this.rangeHighCm,
      this.correctedZ, this.tannerMidParentalCm);
}

TargetHeight? calculateTargetHeight({
  required double? motherHeightCm,
  required double? fatherHeightCm,
  int? motherAge,
  int? fatherAge,
  required String? childSex,
}) {
  if (motherHeightCm == null || fatherHeightCm == null) return null;
  final motherCorrected = motherHeightCm + _ageShrinkageCm(motherAge, 'female');
  final fatherCorrected = fatherHeightCm + _ageShrinkageCm(fatherAge, 'male');
  final motherZ = (motherCorrected - adultMean['female']!) / adultSD['female']!;
  final fatherZ = (fatherCorrected - adultMean['male']!) / adultSD['male']!;
  final midParentalZ = (motherZ + fatherZ) / 2;
  final correctedZ = 0.79 * midParentalZ - 0.077;
  final sex = childSex == 'female' ? 'female' : 'male';
  final target = adultMean[sex]! + correctedZ * adultSD[sex]!;
  final residualSD = sex == 'female' ? 4.2 : 4.5;
  final tanner = sex == 'female'
      ? (motherHeightCm + (fatherHeightCm - 13)) / 2
      : ((motherHeightCm + 13) + fatherHeightCm) / 2;
  return TargetHeight(target, target - residualSD, target + residualSD,
      correctedZ, tanner);
}

// ── Trajectory projection ───────────────────────────────────────────

class ProjectionPoint {
  final double ageYears;
  final double heightCm;
  ProjectionPoint(this.ageYears, this.heightCm);
}

/// Projects height from the latest measurement toward the genetic
/// target channel. [readinessScore] (0–100, from 7-day analytics)
/// nudges the destination channel by up to ±0.15 SD around neutral 50
/// — deliberately small; habits shift trajectories at the margin,
/// they don't override genetics.
List<ProjectionPoint> projectGrowth({
  required List<List<double>> table,
  required double currentAgeYears,
  required double currentHeightCm,
  double? targetZ, // from TargetHeight.correctedZ; null = hold channel
  double? readinessScore,
  double horizonYears = 19,
}) {
  final startBands = interpolateBands(table, currentAgeYears * 12);
  final z0 = zFromHeight(startBands, currentHeightCm);

  var destZ = targetZ ?? z0;
  if (readinessScore != null) {
    destZ += ((readinessScore - 50) / 50).clamp(-1.0, 1.0) * 0.15;
  }

  final endAge = math.min(horizonYears, table.last[0] / 12);
  if (endAge <= currentAgeYears) return [];

  final points = <ProjectionPoint>[
    ProjectionPoint(currentAgeYears, currentHeightCm),
  ];
  const stepYears = 0.25;
  final steps = ((endAge - currentAgeYears) / stepYears).ceil();
  for (var i = 1; i <= steps; i++) {
    final age = math.min(currentAgeYears + i * stepYears, endAge);
    final frac = (age - currentAgeYears) / (endAge - currentAgeYears);
    final z = z0 + (destZ - z0) * frac;
    final bands = interpolateBands(table, age * 12);
    points.add(ProjectionPoint(age, heightAtZ(bands, z)));
  }
  return points;
}

double ageYearsAt(String dobStr, String dateStr) {
  final dob = DateTime.parse(dobStr);
  final d = DateTime.parse(dateStr);
  return d.difference(dob).inDays / 365.25;
}
