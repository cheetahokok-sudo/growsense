// ══════════════════════════════════════════════════════════════════
// Health Story repository (beta, Gate 1 capture).
//
// Kept OUT of AppState's global clinical-load path on purpose: the
// illness_episodes tables may not be migrated yet, so this loads on its
// own and degrades gracefully (tablesReady=false) rather than breaking
// the live Medical tab. A record for parent + doctor — never a
// diagnosis; no pattern flags here (that's Gate 2, read-only, later).
// See supabase/migrations/2026-07-19_health_story_episodes.sql
// ══════════════════════════════════════════════════════════════════

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';

class HealthStoryRepo {
  static bool _missingTable(PostgrestException e) =>
      e.code == '42P01' || e.message.contains('does not exist');

  /// Episodes for the active child, newest first. Returns the rows and
  /// whether the tables exist yet (false → migration not applied).
  static Future<(List<Map<String, dynamic>>, bool)> fetch(AppState s) async {
    final childId = s.activeChildId;
    if (childId == null) return (<Map<String, dynamic>>[], true);
    try {
      final rows = await s.sb
          .from('illness_episodes')
          .select()
          .eq('child_id', childId)
          .order('onset_date', ascending: false);
      return (List<Map<String, dynamic>>.from(rows), true);
    } on PostgrestException catch (e) {
      if (_missingTable(e)) return (<Map<String, dynamic>>[], false);
      rethrow;
    }
  }

  /// Create an episode plus optional first temperature, medication and
  /// symptom rows. Returns null on success, or a message on failure.
  static Future<String?> create(
    AppState s, {
    required String primarySystem,
    required DateTime onsetDate,
    String onsetPrecision = 'exact',
    String careSought = 'none',
    String? labelParent,
    List<String> symptoms = const [],
    double? tempC,
    String? tempRoute,
    String? medName,
    String? medClass,
    String? medResponse,
  }) async {
    final childId = s.activeChildId;
    if (childId == null) return 'No child selected';
    try {
      final episodeRow = <String, dynamic>{
        'child_id': childId,
        'created_by': s.sb.auth.currentUser?.id,
        'primary_system': primarySystem,
        'onset_date': onsetDate.toIso8601String().substring(0, 10),
        'onset_precision': onsetPrecision,
        'status': 'active',
        'care_sought': careSought,
        'source': 'recorded',
        'confidence': 'high',
      };
      final label = labelParent?.trim() ?? '';
      if (label.isNotEmpty) episodeRow['label_parent'] = label;

      final ep = await s.sb
          .from('illness_episodes')
          .insert(episodeRow)
          .select('episode_id')
          .single();

      final episodeId = ep['episode_id'];

      if (tempC != null) {
        final tempRow = <String, dynamic>{
          'episode_id': episodeId,
          'temp_c': tempC,
        };
        if (tempRoute != null) tempRow['route'] = tempRoute;
        await s.sb.from('episode_temperatures').insert(tempRow);
      }
      final med = medName?.trim() ?? '';
      if (med.isNotEmpty) {
        final medRow = <String, dynamic>{
          'episode_id': episodeId,
          'medication': med,
        };
        if (medClass != null) medRow['med_class'] = medClass;
        if (medResponse != null) medRow['response'] = medResponse;
        await s.sb.from('episode_medications').insert(medRow);
      }
      if (symptoms.isNotEmpty) {
        await s.sb.from('episode_symptoms').insert([
          for (final sym in symptoms) {'episode_id': episodeId, 'symptom': sym},
        ]);
      }
      return null;
    } on PostgrestException catch (e) {
      if (_missingTable(e)) {
        return 'Health Story tables aren’t set up yet — apply the '
            'migration in Supabase, then try again.';
      }
      return e.message;
    }
  }
}

/// Human labels for the controlled enums (parent-facing).
const Map<String, String> kPrimarySystemLabels = {
  'febrile': 'Fever',
  'respiratory': 'Cough or breathing',
  'ent': 'Ear or throat',
  'gi': 'Tummy',
  'skin': 'Skin (rash / spots)',
  'other': 'Something else',
};

const Map<String, String> kSymptomLabels = {
  'fever': 'Fever',
  'cough': 'Cough',
  'wheeze': 'Wheeze',
  'breathing_difficulty': 'Fast / hard breathing',
  'runny_nose': 'Runny nose',
  'sore_throat': 'Sore throat',
  'ear_pain': 'Ear pain',
  'mouth_ulcers': 'Mouth ulcers',
  'rash': 'Rash',
  'vomiting': 'Vomiting',
  'diarrhoea': 'Diarrhoea',
};
