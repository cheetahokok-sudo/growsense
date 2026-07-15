// ══════════════════════════════════════════════════════════════════
// Growth-evidence knowledge base — loaded from assets/growth_evidence.json.
// The curated, PubMed-verified source of domains, analytes, mechanistic
// relationships and evidence cards behind Growth Systems Intelligence.
//
// The lab-AI report (from the edge function) contains only interpretation
// PROSE tagged with domain/analyte keys — never citations. This class is
// how the app attaches the verified evidence cards + mechanism edges by
// key, so fabricated references are impossible.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class GrowthDomain {
  final String id;
  final String label;
  final String icon;
  final String question;
  final String importance;
  final List<String> primaryInputs;
  GrowthDomain.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        label = j['label'] as String? ?? '',
        icon = j['icon'] as String? ?? '•',
        question = j['question'] as String? ?? '',
        importance = j['importance'] as String? ?? 'moderate',
        primaryInputs =
            (j['primary_inputs'] as List?)?.cast<String>() ?? const [];
}

class GrowthAnalyte {
  final String id;
  final String label;
  final String domain;
  final String meaning;
  final List<String> cautions;
  final List<String> evidence; // evidence-card keys
  GrowthAnalyte.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        label = j['label'] as String? ?? '',
        domain = j['domain'] as String? ?? '',
        meaning = j['meaning'] as String? ?? '',
        cautions = (j['cautions'] as List?)?.cast<String>() ?? const [],
        evidence = (j['evidence'] as List?)?.cast<String>() ?? const [];
}

class EvidenceCard {
  final String key;
  final String pmid;
  final String title;
  final String authors;
  final String journal;
  final int year;
  final String type; // human_clinical | human_observational | animal | ...
  final String claim;
  final String confidence;
  final String? scopeNote;
  EvidenceCard.fromJson(this.key, Map<String, dynamic> j)
      : pmid = j['pmid'] as String? ?? '',
        title = j['title'] as String? ?? '',
        authors = j['authors'] as String? ?? '',
        journal = j['journal'] as String? ?? '',
        year = (j['year'] as num?)?.toInt() ?? 0,
        type = j['type'] as String? ?? '',
        claim = j['claim'] as String? ?? '',
        confidence = j['confidence'] as String? ?? '',
        scopeNote = j['scope_note'] as String?;

  String get pubmedUrl => 'https://pubmed.ncbi.nlm.nih.gov/$pmid/';

  /// Short human label for the evidence-type badge.
  String get typeLabel => switch (type) {
        'human_clinical' => 'Human trial',
        'human_observational' => 'Human cohort',
        'animal' => 'Animal model',
        'cell_molecular' => 'Cell/molecular',
        'expert_review' => 'Expert review',
        _ => 'Evidence',
      };
}

class GrowthEvidence {
  final List<GrowthDomain> domains;
  final Map<String, GrowthAnalyte> analytes; // keyed by id
  final Map<String, EvidenceCard> cards; // keyed by key
  final String disclaimer;
  GrowthEvidence(this.domains, this.analytes, this.cards, this.disclaimer);

  static GrowthEvidence? _cache;

  static Future<GrowthEvidence> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/growth_evidence.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final domains = (j['domains'] as List)
        .map((d) => GrowthDomain.fromJson(d as Map<String, dynamic>))
        .toList();
    final analytes = <String, GrowthAnalyte>{};
    for (final a in (j['analytes'] as List)) {
      final ga = GrowthAnalyte.fromJson(a as Map<String, dynamic>);
      analytes[ga.id] = ga;
    }
    final cards = <String, EvidenceCard>{};
    (j['evidence_cards'] as Map<String, dynamic>).forEach((k, v) {
      cards[k] = EvidenceCard.fromJson(k, v as Map<String, dynamic>);
    });
    return _cache = GrowthEvidence(
        domains, analytes, cards, j['disclaimer'] as String? ?? '');
  }

  GrowthDomain? domain(String id) {
    for (final d in domains) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Evidence cards for an analyte key, in the curated order.
  List<EvidenceCard> cardsForAnalyte(String analyteKey) {
    final a = analytes[analyteKey];
    if (a == null) return const [];
    return [
      for (final k in a.evidence)
        if (cards[k] != null) cards[k]!,
    ];
  }
}
