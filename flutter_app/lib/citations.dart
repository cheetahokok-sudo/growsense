// ══════════════════════════════════════════════════════════════════
// Medical citations — the sources behind GrowSense's health
// calculations and recommendations (App Store Guideline 1.4.1).
//
// EVERY entry here is a real, published authority. The app never
// generates a citation — this is static, curated data, the same rule
// evidence_refs.dart / growth_evidence.json already follow. PMIDs used
// here are ones already verified in the repo (e.g. NCD-RisC 27458798);
// named standards (WHO, NASEM/IOM DRIs, AASM, Greulich–Pyle) link to
// their official source pages rather than an unverified PMID.
//
// Surfaced two ways, both reading from `kMedicalCitations`:
//   1. Inline `SourcesLink(topicId)` next to a result → opens a sheet.
//   2. The central `MedicalReferencesScreen` (Account → Support & legal).
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// One source. [url] is an official page or a PubMed link; [note] is an
/// optional scope caveat.
class Citation {
  const Citation(this.label, this.detail, this.url, {this.note});
  final String label;
  final String detail;
  final String url;
  final String? note;
}

/// A group of sources for one calculation/recommendation area.
class CitationTopic {
  const CitationTopic({
    required this.id,
    required this.title,
    required this.summary,
    required this.sources,
  });
  final String id;
  final String title;

  /// One-line "how this is derived" + the educational caveat.
  final String summary;
  final List<Citation> sources;
}

/// The universal limitation shown on the references screen and every sheet.
const String kMedicalDisclaimer =
    'GrowSense provides educational growth tracking and general health '
    'information. It does not diagnose, prevent or treat any condition and '
    'is not a substitute for care from a pediatrician or qualified '
    'clinician. Results are estimates; a clinician should interpret them '
    'alongside your child\'s full history.';

/// Curated, verified sources. Referenced by [CitationTopic.id] from the
/// result screens.
const List<CitationTopic> kMedicalCitations = [
  CitationTopic(
    id: 'percentile',
    title: 'Percentiles, BMI-for-age & growth velocity',
    summary:
        'Percentiles, BMI-for-age and height-velocity all compare your '
        'child\'s measurement with the same WHO reference population of '
        'the same age and sex. A position on the chart — or a velocity '
        'between two visits — is context, not a diagnosis.',
    sources: [
      Citation(
        'WHO Child Growth Standards',
        'World Health Organization, 2006 — 0–5 years',
        'https://www.who.int/tools/child-growth-standards',
      ),
      Citation(
        'WHO Growth Reference 2007',
        'World Health Organization — 5–19 years',
        'https://www.who.int/tools/growth-reference-data-for-5to19-years',
      ),
    ],
  ),
  CitationTopic(
    id: 'target_height',
    title: 'Genetic target & adult-height range',
    summary:
        'The target is a range derived from both parents\' heights '
        '(mid-parental method), shown with the current growth channel. '
        'It is an educational projection, never a promise of a single '
        'number.',
    sources: [
      Citation(
        'NCD Risk Factor Collaboration',
        'A century of trends in adult human height. eLife, 2016',
        'https://pubmed.ncbi.nlm.nih.gov/27458798/',
        note: 'Adult height is strongly shaped by early-life nutrition '
            'across generations.',
      ),
    ],
  ),
  CitationTopic(
    id: 'nutrition',
    title: 'Nutrition targets (protein, calcium, zinc, iron, water)',
    summary:
        'Daily targets are the age- and sex-based Dietary Reference '
        'Intakes. They are general guidance, not a prescription.',
    sources: [
      Citation(
        'Dietary Reference Intakes',
        'National Academies (IOM/NASEM): protein & water 2005; '
            'calcium & vitamin D 2011; zinc & iron 2001',
        'https://www.nationalacademies.org/our-work/'
            'dietary-reference-intakes-tables-and-application',
      ),
      Citation(
        'USDA FoodData Central',
        'Per-food nutrient values in the food library',
        'https://fdc.nal.usda.gov/',
      ),
    ],
  ),
  CitationTopic(
    id: 'sleep',
    title: 'Sleep guidance',
    summary:
        'Age-based sleep-duration ranges follow the pediatric consensus '
        'of the American Academy of Sleep Medicine. A different family '
        'rhythm is not an error.',
    sources: [
      Citation(
        'American Academy of Sleep Medicine',
        'Recommended sleep for pediatric populations — 2016 consensus',
        'https://aasm.org/resources/pdf/pediatricsleepdurationconsensus.pdf',
      ),
    ],
  ),
  CitationTopic(
    id: 'bone_age',
    title: 'Bone-age interpretation',
    summary:
        'Bone-age readings use the Greulich–Pyle atlas method; the '
        'app tracks the gap between bone age and calendar age over time. '
        'Any AI reading is educational, not a clinical diagnosis — the '
        'clinician\'s reading leads.',
    sources: [
      Citation(
        'Greulich WW, Pyle SI',
        'Radiographic Atlas of Skeletal Development of the Hand and '
            'Wrist, 2nd ed. Stanford University Press, 1959',
        'https://www.sup.org/books/title/?id=6363',
      ),
    ],
  ),
  CitationTopic(
    id: 'medication',
    title: 'Medication & growth',
    summary:
        'Notes on how some medications may affect growth, for discussion '
        'with your clinician — not medical advice.',
    sources: [
      Citation(
        'Inhaled glucocorticoids & adult height',
        'N Engl J Med, 2012',
        'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3517799/',
      ),
      Citation(
        'Stimulants & final adult height',
        '2022',
        'https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9627528/',
      ),
      Citation(
        'Corticosteroids — growth effects',
        'Indian J Dermatol Venereol Leprol, 2007',
        'https://pubmed.ncbi.nlm.nih.gov/17675727/',
      ),
    ],
  ),
  CitationTopic(
    id: 'labs',
    title: 'Growth-related lab markers',
    summary:
        'Each lab marker card carries its own PubMed-verified evidence '
        '(open a lab result to see "Evidence & References"). The library '
        'is curated and never auto-generated.',
    sources: [
      Citation(
        'Growth-systems evidence library',
        'PubMed-verified sources attached per analyte, shown in the app',
        'https://pubmed.ncbi.nlm.nih.gov/',
      ),
    ],
  ),
];

CitationTopic? citationTopic(String id) {
  for (final t in kMedicalCitations) {
    if (t.id == id) return t;
  }
  return null;
}

// ── UI ─────────────────────────────────────────────────────────────

/// Small tappable "ⓘ Sources" affordance placed next to a result. Opens
/// a bottom sheet with that topic's citations.
class SourcesLink extends StatelessWidget {
  const SourcesLink({super.key, required this.topicId, this.label = 'Sources'});
  final String topicId;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showSourcesSheet(context, topicId),
      borderRadius: BorderRadius.circular(GsRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.info_outline, size: 13, color: GsColors.measured),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: GsColors.measured,
                  decoration: TextDecoration.underline)),
        ]),
      ),
    );
  }
}

/// A single citation row (label · detail · tappable link), reused by the
/// sheet and the references screen.
class CitationTile extends StatelessWidget {
  const CitationTile({super.key, required this.citation});
  final Citation citation;

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
        Text(citation.label,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: GsColors.text)),
        const SizedBox(height: 2),
        Text(citation.detail,
            style: const TextStyle(
                fontSize: 11, color: GsColors.text2, height: 1.35)),
        if (citation.note != null) ...[
          const SizedBox(height: 4),
          Text('⚠ ${citation.note}',
              style: const TextStyle(
                  fontSize: 10,
                  color: GsColors.estimatedDark,
                  height: 1.3,
                  fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 5),
        InkWell(
          onTap: () => launchUrl(Uri.parse(citation.url),
              mode: LaunchMode.externalApplication),
          child: const Text('View source →',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: GsColors.measured,
                  decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }
}

/// Bottom sheet showing one topic's summary + citations + the disclaimer.
void showSourcesSheet(BuildContext context, String topicId) {
  final topic = citationTopic(topicId);
  if (topic == null) return;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: GsColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: GsColors.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(topic.title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: GsColors.text)),
              const SizedBox(height: 6),
              Text(topic.summary,
                  style: const TextStyle(
                      fontSize: 12, color: GsColors.text2, height: 1.5)),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final c in topic.sources) CitationTile(citation: c),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(kMedicalDisclaimer,
                  style: const TextStyle(
                      fontSize: 10, color: GsColors.text3, height: 1.4)),
            ],
          ),
        ),
      ),
    ),
  );
}
