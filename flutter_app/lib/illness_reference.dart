// ══════════════════════════════════════════════════════════════════
// Illness & medication growth-interference reference — loaded from
// assets/illness_reference.json. Common childhood illnesses with
// typical durations + growth mechanism, and medications classified by
// growth-interference risk (high / moderate / neutral) with a
// parent-friendly insight and a verified citation where available.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class IllnessType {
  final String id;
  final String emoji;
  final String label;
  final int durationMin;
  final int durationMax;
  final String growthNote;
  IllnessType.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        emoji = j['emoji'] as String? ?? '📋',
        label = j['label'] as String? ?? '',
        durationMin = ((j['durationDays'] as List?)?[0] as num?)?.toInt() ?? 1,
        durationMax = ((j['durationDays'] as List?)?[1] as num?)?.toInt() ?? 7,
        growthNote = j['growthNote'] as String? ?? '';
}

class GrowthMedication {
  final String id;
  final String name;
  final String drugClass;
  final String risk; // high | moderate | neutral
  final String insight;
  final String? citation;
  GrowthMedication.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        drugClass = j['drugClass'] as String? ?? '',
        risk = j['risk'] as String? ?? 'neutral',
        insight = j['insight'] as String? ?? '',
        citation = j['citation'] as String?;
}

class IllnessReference {
  final List<IllnessType> illnesses;
  final List<GrowthMedication> medications;
  IllnessReference(this.illnesses, this.medications);

  static IllnessReference? _cache;

  static Future<IllnessReference> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/illness_reference.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    _cache = IllnessReference(
      [for (final e in j['illnesses'] as List) IllnessType.fromJson(e)],
      [for (final e in j['medications'] as List) GrowthMedication.fromJson(e)],
    );
    return _cache!;
  }

  IllnessType? illness(String id) {
    for (final i in illnesses) {
      if (i.id == id) return i;
    }
    return null;
  }

  GrowthMedication? med(String id) {
    for (final m in medications) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// The extra fields (severity + medications) don't have their own
/// columns in illness_events yet, so they're encoded as compact JSON
/// in the existing `notes` column. Legacy plain-text notes still read
/// back fine (parsed as free text). A schema migration is the eventual
/// production path.
class IllnessDetails {
  final String? severity; // mild | moderate | severe
  final List<String> medIds;
  final String freeText;
  IllnessDetails({this.severity, this.medIds = const [], this.freeText = ''});

  String encode() => jsonEncode({
        if (severity != null) 'sev': severity,
        if (medIds.isNotEmpty) 'meds': medIds,
        if (freeText.isNotEmpty) 'txt': freeText,
      });

  static IllnessDetails decode(String? notes) {
    if (notes == null || notes.trim().isEmpty) return IllnessDetails();
    try {
      final j = jsonDecode(notes);
      if (j is Map<String, dynamic>) {
        return IllnessDetails(
          severity: j['sev'] as String?,
          medIds: List<String>.from(j['meds'] as List? ?? const []),
          freeText: j['txt'] as String? ?? '',
        );
      }
    } catch (_) {
      // Legacy free-text note.
    }
    return IllnessDetails(freeText: notes);
  }
}
