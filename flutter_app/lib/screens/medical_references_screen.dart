// ══════════════════════════════════════════════════════════════════
// Medical information & sources — the central evidence library (App
// Store Guideline 1.4.1). Lists every health calculation/recommendation
// area with its verified sources, plus the educational-use limitation.
// Opened from Account → Support & legal. Data lives in citations.dart;
// individual results also link here inline via SourcesLink.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../citations.dart';
import '../i18n.dart';
import '../theme.dart';

class MedicalReferencesScreen extends StatelessWidget {
  const MedicalReferencesScreen({super.key, required this.i18n});
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            t('flutter.refs.title', 'Medical information & sources'),
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // Limitations / safety block, first and prominent.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GsColors.estimatedLight,
              borderRadius: BorderRadius.circular(GsRadius.md),
              border: Border.all(color: GsColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.health_and_safety_outlined,
                    size: 18, color: GsColors.estimatedDark),
                SizedBox(width: 8),
                Text('Educational use & limitations',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: GsColors.estimatedDark)),
              ]),
              const SizedBox(height: 8),
              Text(kMedicalDisclaimer,
                  style: const TextStyle(
                      fontSize: 12, color: GsColors.text2, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 18),
          Text(
              t('flutter.refs.intro',
                  'The sources behind each calculation and recommendation. '
                      'You can also open "Sources" directly from a result.'),
              style: const TextStyle(fontSize: 12, color: GsColors.text3)),
          const SizedBox(height: 14),
          for (final topic in kMedicalCitations) _TopicSection(topic: topic),
        ],
      ),
    );
  }
}

class _TopicSection extends StatelessWidget {
  const _TopicSection({required this.topic});
  final CitationTopic topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(topic.title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: GsColors.accent)),
        const SizedBox(height: 6),
        Text(topic.summary,
            style: const TextStyle(
                fontSize: 12, color: GsColors.text2, height: 1.5)),
        const SizedBox(height: 12),
        for (final c in topic.sources) CitationTile(citation: c),
      ]),
    );
  }
}
