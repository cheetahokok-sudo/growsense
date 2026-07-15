// ══════════════════════════════════════════════════════════════════
// Evidence & References — renders the curated, PubMed-verified evidence
// cards for an analyte (from growth_evidence.json). Citations are static
// data attached by key; the app never generates a PMID. Shown free on
// the lab detail card ("Evidence & References (N)").
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../growth_evidence.dart';
import '../theme.dart';

class EvidenceRefsList extends StatelessWidget {
  const EvidenceRefsList({super.key, required this.cards});
  final List<EvidenceCard> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final c in cards) _EvidenceTile(card: c)],
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.card});
  final EvidenceCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.sm),
        border: Border.all(color: GsColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: GsColors.measuredLight,
                borderRadius: BorderRadius.circular(5)),
            child: Text(card.typeLabel,
                style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: GsColors.measuredDark)),
          ),
          const Spacer(),
          Text('${card.year}',
              style: const TextStyle(fontSize: 9.5, color: GsColors.text3)),
        ]),
        const SizedBox(height: 5),
        Text(card.claim,
            style: const TextStyle(
                fontSize: 11.5, color: GsColors.text, height: 1.4)),
        if (card.scopeNote != null) ...[
          const SizedBox(height: 4),
          Text('⚠ ${card.scopeNote}',
              style: const TextStyle(
                  fontSize: 10,
                  color: GsColors.estimatedDark,
                  height: 1.3,
                  fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 5),
        InkWell(
          onTap: () => launchUrl(Uri.parse(card.pubmedUrl),
              mode: LaunchMode.externalApplication),
          child: Text('${card.authors} · ${card.journal} · PMID ${card.pmid}',
              style: const TextStyle(
                  fontSize: 10,
                  color: GsColors.measured,
                  decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }
}
