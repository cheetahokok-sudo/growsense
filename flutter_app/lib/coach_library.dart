// ══════════════════════════════════════════════════════════════════
// Coach question library + template answer engine — Dart port of the
// PWA's ai_coach_questions system (template mode, zero API cost).
//
// Sources merged at load time:
//   1. ai_coach_questions (Supabase) — the ~182 live questions
//   2. assets/coach_library.json — the reviewed pilot expansion batch
//
// The engine mirrors app.js exactly: build a child-data context with
// the same field names the templates reference, fill {{placeholder}}
// tokens, match free text by stop-worded word-overlap, and gate each
// question by the data it needs (requires_data tags) + age range so a
// parent only sees questions their child actually has data for.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics.dart' show calcProteinTargetG, calcProteinBoostTargetG;
import 'app_state.dart';
import 'growth_math.dart';

class CoachQuestion {
  final String category;
  final String text;
  final List<String> requiresData;
  final double? minAge;
  final double? maxAge;
  final int priority;
  final String? answerTemplate;
  final String? citation;

  CoachQuestion({
    required this.category,
    required this.text,
    required this.requiresData,
    this.minAge,
    this.maxAge,
    this.priority = 50,
    this.answerTemplate,
    this.citation,
  });

  factory CoachQuestion.fromDb(Map<String, dynamic> j) => CoachQuestion(
        category: j['category'] as String? ?? 'general_understanding',
        text: j['question_text'] as String? ?? '',
        requiresData:
            List<String>.from(j['requires_data'] as List? ?? ['none']),
        minAge: (j['min_age_years'] as num?)?.toDouble(),
        maxAge: (j['max_age_years'] as num?)?.toDouble(),
        priority: (j['display_priority'] as num?)?.toInt() ?? 50,
        answerTemplate: j['answer_template'] as String?,
        citation: j['citation_source'] as String?,
      );
}

const coachCategoryLabels = {
  'growth_trend': 'Growth trend',
  'bmi_weight': 'BMI & weight',
  'nutrition': 'Nutrition',
  'sleep': 'Sleep',
  'activity': 'Activity',
  'puberty': 'Puberty',
  'target_height': 'Target height',
  'sga_catchup': 'Catch-up growth',
  'labs': 'Labs',
  'medical': 'Medical',
  'clinic_prep': 'Clinic prep',
  'general_understanding': 'General',
};

class CoachLibrary {
  final List<CoachQuestion> questions;
  CoachLibrary(this.questions);

  static CoachLibrary? _cache;

  /// Live table first (source of truth); merge the bundled pilot asset,
  /// skipping any question_text already present so a later DB migration
  /// of the pilot doesn't create duplicates.
  static Future<CoachLibrary> load(SupabaseClient sb) async {
    if (_cache != null) return _cache!;
    final all = <CoachQuestion>[];
    final seen = <String>{};

    try {
      final rows = await sb
          .from('ai_coach_questions')
          .select()
          .eq('is_active', true)
          .order('display_priority');
      for (final r in rows as List) {
        final q = CoachQuestion.fromDb(r as Map<String, dynamic>);
        if (seen.add(q.text)) all.add(q);
      }
    } on PostgrestException {
      // Fall through to asset-only if the table can't be read.
    }

    for (final asset in const [
      'assets/coach_library.json', // pilot batch
      'assets/coach_library_food_activity.json', // 200 food+activity batch
    ]) {
      try {
        final raw = await rootBundle.loadString(asset);
        final j = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in j['questions'] as List) {
          final q = CoachQuestion.fromDb(e as Map<String, dynamic>);
          if (seen.add(q.text)) all.add(q);
        }
      } catch (_) {
        // Asset optional.
      }
    }

    _cache = CoachLibrary(all);
    return _cache!;
  }
}

// ── Child-data context (matches app.js buildAICoachContext field names) ──

Map<String, dynamic> buildCoachContext(AppState appState, WhoReference? who) {
  final child = appState.activeChildRow;
  if (child == null) return {'hasChild': false};
  final dob = child['date_of_birth'] as String?;
  final sex = child['biological_sex'] as String?;
  final ctx = <String, dynamic>{
    'hasChild': true,
    'name': child['name'] ?? '',
    'sex': sex ?? '',
  };
  double? ageYears;
  if (dob != null) {
    ageYears = DateTime.now().difference(DateTime.parse(dob)).inDays / 365.25;
    ctx['ageYears'] = ageYears.toStringAsFixed(1);
  }

  final meas = appState.measurements; // newest first

  // Per-child protein targets (IOM 2005 DRI + the growth-optimized
  // boost) — computed from THIS child's age, sex, and latest weight.
  // Never a fixed figure: the old hardcoded 44 g was only correct for
  // a ~46 kg 9-13-year-old (see calcProteinTargetG in app.js).
  final weightKg = meas.isNotEmpty
      ? (meas.first['mass_weight_kg'] as num?)?.toDouble()
      : null;
  ctx['proteinTargetG'] = calcProteinTargetG(dob, weightKg, sex);
  ctx['proteinBoostTargetG'] = calcProteinBoostTargetG(dob, weightKg, sex);

  if (meas.isNotEmpty) {
    final latest = meas.first;
    final h = (latest['stature_height_cm'] as num?)?.toDouble();
    ctx['latestHeightCm'] = h;
    ctx['latestWeightKg'] = latest['mass_weight_kg'];
    ctx['latestMeasurementDate'] = latest['recorded_date'];
    if (h != null && who != null && ageYears != null) {
      final table = who.tableFor(sex);
      // WHO 5–19 table only; younger falls outside (matches app limits).
      if (ageYears * 12 >= table.first[0]) {
        final bands = interpolateBands(table, ageYears * 12);
        final z = zFromHeight(bands, h);
        ctx['heightPercentile'] = zToPercentile(z).round();
        ctx['heightZ'] = z.toStringAsFixed(2);
      }
    }
  }

  if (meas.length >= 2) {
    final a = meas[0], b = meas[1];
    final ha = (a['stature_height_cm'] as num?)?.toDouble();
    final hb = (b['stature_height_cm'] as num?)?.toDouble();
    final da = a['recorded_date'] as String?, db = b['recorded_date'] as String?;
    if (ha != null && hb != null && da != null && db != null) {
      final days = DateTime.parse(da).difference(DateTime.parse(db)).inDays;
      if (days > 0) {
        ctx['heightVelocityCmYr'] =
            ((ha - hb) / days * 365.25).toStringAsFixed(1);
      }
    }
  }

  final th = calculateTargetHeight(
    motherHeightCm: (child['mother_height_cm'] as num?)?.toDouble(),
    fatherHeightCm: (child['father_height_cm'] as num?)?.toDouble(),
    motherAge: (child['mother_current_age'] as num?)?.toInt(),
    fatherAge: (child['father_current_age'] as num?)?.toInt(),
    childSex: sex,
  );
  if (th != null) {
    ctx['targetHeightCm'] = th.targetHeightCm.toStringAsFixed(1);
    ctx['targetHeightRangeLow'] = th.rangeLowCm.toStringAsFixed(1);
    ctx['targetHeightRangeHigh'] = th.rangeHighCm.toStringAsFixed(1);
  }

  if (appState.labResults.isNotEmpty) {
    ctx['recentLabs'] = [
      for (final r in appState.labResults.take(5))
        '${r['analyte_name']}: ${r['result_value']}${r['unit'] ?? ''} (${r['lab_date']})',
    ];
  }
  if (appState.pubertyEvents.isNotEmpty) {
    ctx['recentPubertyEvents'] = [
      for (final e in appState.pubertyEvents.take(5))
        '${e['event_type']}${e['tanner_stage'] != null ? ' (Tanner ${e['tanner_stage']})' : ''} on ${e['event_date']}',
    ];
  }
  ctx['ageYearsNum'] = ageYears;
  return ctx;
}

String fillTemplate(String template, Map<String, dynamic> ctx) {
  return template.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (m) {
    final v = ctx[m.group(1)];
    if (v == null) return '(not yet logged)';
    if (v is List) return v.join('; ');
    return '$v';
  });
}

// ── Adaptive index: which questions are answerable right now ─────────

Set<String> availableDataTags(Map<String, dynamic> ctx) {
  final tags = <String>{'none'};
  if (ctx['latestHeightCm'] != null) tags.add('measurements_1plus');
  if (ctx['heightVelocityCmYr'] != null) tags.add('measurements_2plus');
  if (ctx['heightPercentile'] != null || ctx['bmi'] != null) tags.add('bmi');
  if (ctx['targetHeightCm'] != null) tags.add('target_height');
  if (ctx['recentLabs'] != null) tags.add('labs');
  if (ctx['recentPubertyEvents'] != null) tags.add('puberty_events');
  return tags;
}

bool questionAnswerable(
    CoachQuestion q, Set<String> tags, double? ageYears) {
  if (!q.requiresData.every(tags.contains)) return false;
  if (q.minAge != null && ageYears != null && ageYears < q.minAge!) {
    return false;
  }
  if (q.maxAge != null && ageYears != null && ageYears > q.maxAge!) {
    return false;
  }
  return true;
}

// ── Free-text matcher (stop-worded word overlap, same as app.js) ─────

const _stopwords = {
  'what', 'does', 'the', 'for', 'and', 'this', 'that', 'with', 'from',
  'about', 'how', 'why', 'when', 'where', 'who', 'which', 'can', 'could',
  'should', 'would', 'will', 'are', 'is', 'was', 'were', 'has', 'have',
  'had', 'not', 'but', 'they', 'their', 'them', 'you', 'your', 'our',
  'out', 'into', 'than', 'then', 'there', 'here', 'his', 'her', 'its',
  'also', 'just', 'more', 'most', 'some', 'any', 'all', 'each',
};

Set<String> _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w\s]'), '')
    .split(RegExp(r'\s+'))
    .where((w) => w.length > 2 && !_stopwords.contains(w))
    .toSet();

CoachQuestion? findBestMatch(
    String userText, List<CoachQuestion> questions, {String? exactHint}) {
  if (exactHint != null) {
    for (final q in questions) {
      if (q.text == exactHint) return q;
    }
  }
  final userWords = _normalize(userText);
  if (userWords.isEmpty) return null;
  CoachQuestion? best;
  double bestScore = 0;
  for (final q in questions) {
    final qw = _normalize(q.text);
    if (qw.isEmpty) continue;
    final overlap = qw.where(userWords.contains).length;
    final score = overlap /
        (userWords.length < qw.length ? userWords.length : qw.length);
    if (score > bestScore) {
      bestScore = score;
      best = q;
    }
  }
  return bestScore >= 0.5 ? best : null;
}
