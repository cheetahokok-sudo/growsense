// ══════════════════════════════════════════════════════════════════
// AI cross-lab synthesis (PREMIUM). The per-lab cards + evidence are the
// FREE layer (see the lab detail card); this is the paid intelligence
// that ties the five labs together: a headline, the overall picture,
// patterns across markers, what would sharpen it, and questions for the
// doctor. Plain text, light theme — no diagram (the orbit was cut).
//
// The AI writes prose only; it never emits citations.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

class GrowthSystemsReport extends StatelessWidget {
  const GrowthSystemsReport(
      {super.key, required this.report, required this.i18n});
  final Map<String, dynamic> report;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final headline = report['headline'] as String?;
    final confidence = report['overall_confidence'] as String?;
    final parentSummary = report['parent_summary'] as String?;
    final patterns = (report['patterns'] as List?) ?? const [];
    final missing =
        (report['missing_context'] as List?)?.cast<dynamic>() ?? const [];
    final discuss =
        (report['clinician_discussion_points'] as List?)?.cast<dynamic>() ??
            const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headline != null && headline.isNotEmpty)
          Text(headline,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: GsColors.text)),
        if (confidence != null) ...[
          const SizedBox(height: 6),
          _ConfidenceChip(confidence: confidence, i18n: i18n),
        ],

        if (parentSummary != null && parentSummary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GsColors.accentLight,
              borderRadius: BorderRadius.circular(GsRadius.sm),
            ),
            child: Text(parentSummary,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: GsColors.accentDark)),
          ),
        ],

        if (patterns.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(t('flutter.gs.patterns', 'Patterns across markers'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GsColors.measured)),
          for (final p in patterns.whereType<Map>())
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  ',
                    style: TextStyle(fontSize: 12, color: GsColors.measured)),
                Expanded(
                    child: Text('${p['reading'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: GsColors.text2,
                            height: 1.4))),
              ]),
            ),
        ],

        if (missing.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(t('flutter.gs.missing', 'What would sharpen this'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GsColors.estimatedDark)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in missing)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: GsColors.estimatedLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$m',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: GsColors.estimatedDark)),
                ),
            ],
          ),
        ],

        if (discuss.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GsColors.measuredLight,
              borderRadius: BorderRadius.circular(GsRadius.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('flutter.gs.discuss', 'Questions for your doctor'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: GsColors.measuredDark)),
                const SizedBox(height: 4),
                for (final d in discuss)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ',
                              style: TextStyle(
                                  fontSize: 12, color: GsColors.measuredDark)),
                          Expanded(
                              child: Text('$d',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: GsColors.measuredDark,
                                      height: 1.4))),
                        ]),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence, required this.i18n});
  final String confidence;
  final I18n i18n;
  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final label = switch (confidence) {
      'high' => t('flutter.gs.conf_high', 'High confidence'),
      'moderate' => t('flutter.gs.conf_mod', 'Moderate confidence'),
      _ => t('flutter.gs.conf_low', 'Low confidence'),
    };
    final color = switch (confidence) {
      'high' => GsColors.accent,
      'moderate' => GsColors.measured,
      _ => GsColors.estimated,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_outlined, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}
