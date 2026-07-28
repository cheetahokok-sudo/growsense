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

import 'dart:math' as math;

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

/// Calcium RDA by age band (IOM 2011): 700 mg 1-3y, 1000 mg 4-8y,
/// 1300 mg 9-18y. The old flat 1300 was only right for 9-18s and
/// over-asked younger children (deflating their nutrition score).
int calcCalciumTargetMg(String? dobStr) {
  final age = _ageYears(dobStr);
  if (age == null || age >= 9) return 1300;
  if (age >= 4) return 1000;
  return 700;
}

/// Beverage-water adequate intake by age/sex (IOM 2005), in ml.
/// 1 glass = 250 ml. The old flat 2000 ml (8 glasses) was an adult
/// figure.
int calcWaterTargetMl(String? dobStr, String? sex) {
  final age = _ageYears(dobStr);
  final isMale = (sex ?? 'male').toLowerCase() != 'female';
  if (age == null) return 1800;
  if (age < 4) return 900;
  if (age < 9) return 1200;
  if (age < 14) return isMale ? 1800 : 1600;
  return isMale ? 2600 : 1800;
}

/// Nutrition subscore (0..1) — evidence-weighted components with a
/// bounded balance penalty. Weights track the LINEAR-GROWTH evidence
/// (see FORMULAS.md + PubMed refs): protein 40 (IGF-1/height, carries
/// the food matrix), calcium 30, zinc 15 (meta-analytic linear-growth
/// effect), water 15. The balance term multiplies by 0.80..1.00: a
/// day dominated by a single nutrient (e.g. a calcium pill, nothing
/// else) is discounted up to 20%, but NEVER zeroed — the day still
/// carries into the analytics. ε-smoothing keeps one legitimately
/// missing nutrient (patchy zinc coverage) from over-penalizing.
double nutritionSubscore(num rProtein, num rCalcium, num rZinc, num rWater) {
  const wP = 0.40, wCa = 0.30, wZn = 0.15, wW = 0.15;
  final p = rProtein.toDouble(),
      ca = rCalcium.toDouble(),
      zn = rZinc.toDouble(),
      w = rWater.toDouble();
  final base = p * wP + ca * wCa + zn * wZn + w * wW;
  const eps = 0.12;
  double s(double r) => (r + eps) / (1 + eps);
  final sP = s(p), sCa = s(ca), sZn = s(zn), sW = s(w);
  final geo = (math.pow(sP, wP) *
          math.pow(sCa, wCa) *
          math.pow(sZn, wZn) *
          math.pow(sW, wW))
      .toDouble();
  final arith = sP * wP + sCa * wCa + sZn * wZn + sW * wW;
  final evenness = arith <= 0 ? 1.0 : (geo / arith).clamp(0.0, 1.0);
  return base * (0.80 + 0.20 * evenness);
}

/// Zinc RDA by age/sex band (IOM 2001): 3mg 1-3y, 5mg 4-8y, 8mg
/// 9-13y, 11mg boys / 9mg girls 14-18y. Display target only — zinc
/// is not part of the readiness score.
int calcZincTargetMg(String? dobStr, String? sex) {
  final age = _ageYears(dobStr);
  final isMale = (sex ?? 'male').toLowerCase() != 'female';
  if (age == null) return 8;
  if (age < 4) return 3;
  if (age < 9) return 5;
  if (age < 14) return 8;
  return isMale ? 11 : 9;
}

/// Growth-oriented sleep target by age band, in minutes. Keeps the
/// app's long-standing 9.5h for the core 6-12y demographic and bands
/// the edges (AASM ranges: 1-2y 11-14h, 3-5y 10-13h, 6-12y 9-12h,
/// 13-18y 8-10h).
int calcSleepTargetMin(String? dobStr) {
  final age = _ageYears(dobStr);
  if (age == null) return (9.5 * 60).round();
  if (age < 3) return 12 * 60;
  if (age < 6) return 11 * 60;
  if (age < 13) return (9.5 * 60).round();
  return (8.5 * 60).round();
}

/// Iron RDA (mg/day) by age band (IOM 2001). Teen girls need more for
/// menstrual loss, so 14–18 splits by sex. A minor co-factor shown only
/// in Analytics — not part of the readiness score.
int calcIronTargetMg(String? dobStr, String? sex) {
  final age = _ageYears(dobStr);
  final isMale = (sex ?? 'male').toLowerCase() != 'female';
  if (age == null) return 10;
  if (age < 4) return 7;
  if (age < 9) return 10;
  if (age < 14) return 8;
  return isMale ? 11 : 15;
}

/// Vitamin D RDA (IU/day). 600 IU after infancy, 400 IU under 1 y
/// (IOM 2011). Food alone rarely reaches this — sunlight and fortified
/// foods carry most of it — so a low food number is expected, not alarming.
int calcVitaminDTargetIu(String? dobStr) {
  final age = _ageYears(dobStr);
  if (age == null) return 600;
  return age < 1 ? 400 : 600;
}

double? _ageYears(String? dobStr) {
  if (dobStr == null) return null;
  final dob = DateTime.tryParse(dobStr);
  if (dob == null) return null;
  return DateTime.now().difference(dob).inDays / 365.25;
}

class DayMetrics {
  final String date;
  double? proteinG;
  double? calciumMg;
  double? zincMg;
  double? fluidsMl;
  double? sleepMin;
  double? sleepEfficiency;
  double weightedActivityMin = 0;

  /// True when the day's nutrition row is an AI estimate (recall
  /// engine) rather than measured/recalled parent data. Estimated
  /// days keep trends continuous but render gold and are excluded
  /// from correlation insights.
  bool nutritionEstimated = false;

  /// Phase 2: same flags for the other levers. Activity is true when
  /// ANY of the day's items is an estimate (routine-confirmed items
  /// carry typical durations).
  bool activityEstimated = false;
  bool sleepEstimated = false;
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

// ── Insight Windows ─────────────────────────────────────────────────
// Candidate trend windows, in days. 7 and 30 are free; anything longer
// is premium. Mirrors AppState.kFreeHistoryDays — the free cap is
// enforced IN THE FETCH (loadWeeklyAnalytics only requests 2×30 days
// for free accounts), not by slicing in the widget, so a free client
// never holds locked history in memory.
const List<int> kTrendWindows = [7, 30, 90, 180];
const int kFreeTrendWindowDays = 30;

/// A window chip is only offered once the family's record actually
/// spans ~60% of it. A parent who unlocks "6 months" onto 40 days of
/// data sees a mostly-empty chart — the unlock moment becomes a refund
/// moment. Locked chips appearing as the record grows is the better
/// mechanic.
bool windowHasEnoughRecord(int windowDays, int recordSpanDays) =>
    windowDays <= kFreeTrendWindowDays ||
    recordSpanDays >= (windowDays * 0.6).round();

/// Stats for one card over one window — pure, computed client-side
/// from the already-fetched [WeeklyAnalytics.allDays] slice, so chip
/// taps never refetch.
class WindowStats {
  final int windowDays;
  final List<DayMetrics> days; // the window slice, oldest → newest
  final double? avg; // over logged days only
  final int loggedCount;
  final int estimatedCount;
  final double? deltaVsPrior; // avg minus the prior same-length window
  WindowStats({
    required this.windowDays,
    required this.days,
    required this.avg,
    required this.loggedCount,
    required this.estimatedCount,
    required this.deltaVsPrior,
  });
}

WindowStats computeWindowStats(
  List<DayMetrics> allDays, // oldest → newest
  int windowDays,
  double? Function(DayMetrics) valueOf, {
  bool Function(DayMetrics)? estimatedOf,
}) {
  final n = allDays.length;
  final start = math.max(0, n - windowDays);
  final window = allDays.sublist(start);
  final prior = allDays.sublist(
      math.max(0, start - windowDays), start);

  double? avgOf(List<DayMetrics> slice) {
    final vals = [
      for (final d in slice)
        if (valueOf(d) != null) valueOf(d)!,
    ];
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  final avg = avgOf(window);
  final priorAvg = avgOf(prior);
  return WindowStats(
    windowDays: windowDays,
    days: window,
    avg: avg,
    loggedCount: window.where((d) => valueOf(d) != null).length,
    estimatedCount: estimatedOf == null
        ? 0
        : window
            .where((d) => valueOf(d) != null && estimatedOf(d))
            .length,
    deltaVsPrior: (avg != null && priorAvg != null) ? avg - priorAvg : null,
  );
}

/// Height velocity (cm/yr) from the earliest and latest measurement
/// inside [windowDays], or null when the pair spans less than
/// [minSpanDays]. The floor is the clinical validity rule, not a
/// technicality: velocity over a short interval is mostly measuring
/// noise (a 0.5 cm error over 3 months reads as 2 cm/yr), so we refuse
/// to print a number a pediatrician wouldn't trust.
double? velocityOverWindow(
  List<Map<String, dynamic>> measurements, // newest-first, like AppState
  int windowDays, {
  int minSpanDays = 90,
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: windowDays));
  Map<String, dynamic>? newest, oldest;
  for (final m in measurements) {
    final dateStr = m['recorded_date'] as String?;
    final h = (m['stature_height_cm'] as num?)?.toDouble();
    if (dateStr == null || h == null || h <= 0) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null || date.isBefore(cutoff)) continue;
    newest ??= m;
    oldest = m; // list is newest-first, so the last hit is the oldest
  }
  if (newest == null || oldest == null || identical(newest, oldest)) {
    return null;
  }
  final span = DateTime.parse(newest['recorded_date'] as String)
      .difference(DateTime.parse(oldest['recorded_date'] as String))
      .inDays;
  if (span < minSpanDays) return null;
  final delta = ((newest['stature_height_cm'] as num).toDouble()) -
      ((oldest['stature_height_cm'] as num).toDouble());
  return delta / span * 365.25;
}

class WeeklyAnalytics {
  final List<DayMetrics> days; // oldest → newest, always 7 entries

  /// Every fetched day slot, oldest → newest — 2× the widest window
  /// this tier may open, so any chip (and its vs-prior-period delta)
  /// slices from here without another fetch.
  final List<DayMetrics> allDays;

  /// Days since the family's earliest daily log, for the
  /// [windowHasEnoughRecord] chip rule.
  final int recordSpanDays;

  final double? avgScore; // over logged days only, like the PWA
  final double? avgSleepHours;
  final double? velocityCmPerYear;
  final String velocityLabel; // 'on pace' | 'stable' | 'below range' | 'not enough data'

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
    required this.allDays,
    required this.recordSpanDays,
    required this.avgScore,
    required this.avgSleepHours,
    required this.velocityCmPerYear,
    required this.velocityLabel,
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

_Levers _computeLevers(List<DayMetrics> window, int proteinTarget,
    int calciumTarget, int zincTarget, int waterTargetMl, int sleepTargetMin) {
  final logged = window.where((d) => d.hasAnyLog).toList();
  if (logged.isEmpty) return _Levers(null, null, null, null);
  double total = 0, nutSum = 0, actSum = 0, slpSum = 0;
  for (final d in logged) {
    final pR = ((d.proteinG ?? 0) / proteinTarget).clamp(0.0, 1.0);
    final cR = ((d.calciumMg ?? 0) / calciumTarget).clamp(0.0, 1.0);
    final znR = ((d.zincMg ?? 0) / zincTarget).clamp(0.0, 1.0);
    final wR = ((d.fluidsMl ?? 0) / waterTargetMl).clamp(0.0, 1.0);
    final nutPct = nutritionSubscore(pR, cR, znR, wR);
    final actPct = (d.weightedActivityMin / 60).clamp(0.0, 1.0);
    final durR = ((d.sleepMin ?? 0) / sleepTargetMin).clamp(0.0, 1.0);
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
  bool activityHasEstimates = false,
  bool sleepHasEstimates = false,
}) {
  // Honesty rule: never make a lever claim off AI-estimated days —
  // the recall engine must not manufacture its own "insights".
  if (nutritionHasEstimates) dNut = null;
  if (activityHasEstimates) dAct = null;
  if (sleepHasEstimates) dSlp = null;
  // (1) Sleep vs activity — split the week's sleep-logged days at their
  // own activity median and compare average sleep between halves.
  // Estimated sleep or activity days are excluded: a correlation built
  // on typical-value fills would just rediscover the fill algorithm.
  final withSleep = week
      .where((d) =>
          d.sleepMin != null && !d.sleepEstimated && !d.activityEstimated)
      .toList();
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
    SupabaseClient sb, Map<String, dynamic> child,
    {bool premium = false}) async {
  final childId = child['child_id'] as String;
  final now = DateTime.now();

  // One fetch at 2× the widest window this tier may open (the ×2 is
  // what makes "vs prior period" computable for every chip). This is
  // the free-tier lock: a free account's request never asks for more
  // than 60 days, so the locked history is absent, not hidden.
  final maxWindow = premium ? kTrendWindows.last : kFreeTrendWindowDays;
  final fetchDays = maxWindow * 2;
  final since = localISO(now.subtract(Duration(days: fetchDays - 1)));

  // Earliest-ever log per lever, for the record-span chip rule. Three
  // one-row probes — cheaper than widening the main fetch to forever.
  Future<dynamic> earliest(String table) => sb
      .from(table)
      .select('log_date')
      .eq('child_id', childId)
      .order('log_date', ascending: true)
      .limit(1);

  final results = await Future.wait(<Future<dynamic>>[
    sb
        .from('daily_nutrition')
        .select(
            'log_date, total_protein_g, calcium_mg, zinc_mg, fluids_ml, estimation_method')
        .eq('child_id', childId)
        .gte('log_date', since),
    sb
        .from('daily_sleep')
        .select('log_date, total_sleep_min, sleep_efficiency_score, '
            'estimation_method')
        .eq('child_id', childId)
        .gte('log_date', since),
    // Activity is per-ITEM, not per-day, so a premium 360-day fetch
    // can brush PostgREST's 1000-row cap (~3 items/day). Order newest
    // first so if the cap ever truncates, it eats the oldest tail of
    // the chart — deterministic and visibly "record fades out", never
    // silent holes in this week.
    sb
        .from('daily_activity_items')
        .select('log_date, tier, duration_min, estimation_method')
        .eq('child_id', childId)
        .gte('log_date', since)
        .order('log_date', ascending: false),
    sb
        .from('child_growth_analytics_ledger')
        .select('recorded_date, height_delta_cm, days_between_measurements')
        .eq('child_id', childId)
        .order('recorded_date', ascending: false)
        .limit(1),
    earliest('daily_nutrition'),
    earliest('daily_sleep'),
    earliest('daily_activity_items'),
  ]);

  // fetchDays slots oldest first. The trailing 7 are "this week", the
  // 7 before those are last week (for the ring deltas); trend cards
  // slice any window from the full list via computeWindowStats.
  final days = [
    for (var i = fetchDays - 1; i >= 0; i--)
      DayMetrics(localISO(now.subtract(Duration(days: i)))),
  ];
  final byDate = {for (final d in days) d.date: d};
  final currentWeek = days.sublist(days.length - 7);
  final priorWeek = days.sublist(days.length - 14, days.length - 7);
  final tail14 = days.sublist(days.length - 14);

  var recordSpanDays = 0;
  for (final probe in results.sublist(4)) {
    final rows = probe as List;
    if (rows.isEmpty) continue;
    final first = DateTime.tryParse(rows[0]['log_date'] as String? ?? '');
    if (first == null) continue;
    final span = now.difference(first).inDays + 1;
    if (span > recordSpanDays) recordSpanDays = span;
  }

  for (final r in results[0] as List) {
    final d = byDate[r['log_date']];
    if (d == null) continue;
    d.proteinG = (r['total_protein_g'] as num?)?.toDouble();
    d.calciumMg = (r['calcium_mg'] as num?)?.toDouble();
    d.zincMg = (r['zinc_mg'] as num?)?.toDouble();
    d.fluidsMl = (r['fluids_ml'] as num?)?.toDouble();
    // recalled_manual is parent data — only pure AI estimates
    // (relative_recall / pattern_fill / weekly_survey) render gold.
    final method = r['estimation_method'] as String? ?? 'measured';
    d.nutritionEstimated = method != 'measured' && method != 'recalled_manual';
  }
  bool isEstimate(dynamic method) =>
      method != null && method != 'measured' && method != 'recalled_manual';
  for (final r in results[1] as List) {
    final d = byDate[r['log_date']];
    if (d == null) continue;
    d.sleepMin = (r['total_sleep_min'] as num?)?.toDouble();
    d.sleepEfficiency = (r['sleep_efficiency_score'] as num?)?.toDouble();
    d.sleepEstimated = isEstimate(r['estimation_method']);
  }
  for (final r in results[2] as List) {
    final d = byDate[r['log_date']];
    if (d == null) continue;
    final weight =
        (activityTierConfig[r['tier']] ?? activityTierConfig['lifestyle']!)
            .weight;
    d.weightedActivityMin +=
        ((r['duration_min'] as num?)?.toDouble() ?? 0) * weight;
    if (isEstimate(r['estimation_method'])) d.activityEstimated = true;
  }

  // Per-day readiness + lever averages over each week's logged days —
  // the honest average, same as updateStats(). The prior week feeds
  // the week-over-week deltas.
  final proteinTarget = calcProteinTargetG(
    child['date_of_birth'] as String?,
    null,
    child['biological_sex'] as String?,
  );
  final dob = child['date_of_birth'] as String?;
  final sex = child['biological_sex'] as String?;
  final calciumTarget = calcCalciumTargetMg(dob);
  final zincTarget = calcZincTargetMg(dob, sex);
  final waterTargetMl = calcWaterTargetMl(dob, sex);
  final sleepTargetMin = calcSleepTargetMin(dob);
  final cur = _computeLevers(currentWeek, proteinTarget, calciumTarget,
      zincTarget, waterTargetMl, sleepTargetMin);
  final prior = _computeLevers(priorWeek, proteinTarget, calciumTarget,
      zincTarget, waterTargetMl, sleepTargetMin);
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

  // (The old 30-day height gain stat is retired: over one month the
  // number was mostly measurement noise. Windowed velocity via
  // velocityOverWindow replaces it with intervals that mean something.)

  final insight = _pickInsight(
    currentWeek,
    ((child['name'] as String?) ?? '').split(' ').first,
    dNut: deltaNut,
    dAct: deltaAct,
    dSlp: deltaSlp,
    nutritionHasEstimates:
        tail14.any((d) => d.nutritionEstimated), // both weeks feed deltas
    activityHasEstimates: tail14.any((d) => d.activityEstimated),
    sleepHasEstimates: tail14.any((d) => d.sleepEstimated),
  );

  return WeeklyAnalytics(
    days: currentWeek,
    allDays: days,
    recordSpanDays: recordSpanDays,
    avgScore: avgScore,
    avgSleepHours: avgSleepHours,
    velocityCmPerYear: velocity,
    velocityLabel: velocityLabel,
    avgNutPct: avgNut,
    avgActPct: avgAct,
    avgSlpPct: avgSlp,
    deltaNutPct: deltaNut,
    deltaActPct: deltaAct,
    deltaSlpPct: deltaSlp,
    insight: insight,
  );
}
