// ══════════════════════════════════════════════════════════════════
// Growth Systems Intelligence — renders the lab-AI report as five
// connected growth systems instead of one opaque score.
//
//   • Headline + overall confidence
//   • Growth Ecosystem orbit: observed growth at the centre, five domain
//     nodes around it, connectors styled by relationship type
//     (direct = solid, supporting = dashed, association = dotted). Tap a
//     node for its detail sheet.
//   • Parent summary, per-analyte plain-language notes with curated
//     evidence cards (verified PMIDs from growth_evidence.json — never
//     AI-generated), cross-analyte patterns, missing context, and
//     questions for the doctor.
//
// Light theme, GrowSense design tokens. All citations come from the
// curated evidence base by key; the AI text supplies only prose.
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../growth_evidence.dart';
import '../i18n.dart';
import '../theme.dart';
import 'lab_viz.dart';

/// One analyte's serial values, oldest → newest, for the inline chart.
typedef LabSeries = List<({double value, double? low, double? high})>;

// Domain → how it connects to observed growth (edge style in the orbit).
const _domainEdge = {
  'growth_signaling': 'direct',
  'growth_plate_response': 'direct',
  'thyroid': 'supporting',
  'bone_support': 'supporting',
  'iron_oxygen': 'association',
};

Color _statusColor(String? status) => switch (status) {
      'supported' => GsColors.accent,
      'needs_attention' => GsColors.estimated,
      'insufficient_data' => GsColors.text3,
      _ => GsColors.text3,
    };

String _statusLabel(String? status, I18n i18n) {
  final t = i18n.t;
  return switch (status) {
    'supported' => t('flutter.gs.supported', 'Supported'),
    'needs_attention' => t('flutter.gs.review', 'Needs review'),
    'insufficient_data' => t('flutter.gs.no_data', 'Needs data'),
    _ => t('flutter.gs.no_data', 'Needs data'),
  };
}

class GrowthSystemsReport extends StatelessWidget {
  const GrowthSystemsReport(
      {super.key,
      required this.report,
      required this.evidence,
      required this.i18n,
      this.labSeries = const {}});
  final Map<String, dynamic> report;
  final GrowthEvidence evidence;
  final I18n i18n;

  /// The child's real logged values per analyte key (oldest → newest),
  /// used for the inline range bar + trend chart in each tile.
  final Map<String, LabSeries> labSeries;

  Map<String, dynamic> _domainData(String id) {
    final d = (report['domains'] as Map?)?[id];
    return d is Map ? d.cast<String, dynamic>() : const {};
  }

  List<Map<String, dynamic>> get _analytes =>
      ((report['analytes'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

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
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: GsColors.text)),
        if (confidence != null) ...[
          const SizedBox(height: 6),
          _ConfidenceChip(confidence: confidence, i18n: i18n),
        ],

        // Growth Ecosystem orbit
        const SizedBox(height: 12),
        _GrowthOrbit(
          evidence: evidence,
          domainStatus: {
            for (final d in evidence.domains)
              d.id: _domainData(d.id)['status'] as String?,
          },
          onTapDomain: (dom) => _openDomainSheet(context, dom),
        ),
        const SizedBox(height: 6),
        const _OrbitLegend(),

        if (parentSummary != null && parentSummary.isNotEmpty) ...[
          const SizedBox(height: 14),
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

        // Per-analyte plain-language notes + inline chart + evidence
        for (final a in _analytes) ...[
          const SizedBox(height: 10),
          _AnalyteTile(
              data: a,
              evidence: evidence,
              i18n: i18n,
              series: labSeries[a['key']]),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
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

        const SizedBox(height: 12),
        Text(evidence.disclaimer,
            style: const TextStyle(
                fontSize: 10,
                color: GsColors.text3,
                height: 1.4,
                fontStyle: FontStyle.italic)),
      ],
    );
  }

  void _openDomainSheet(BuildContext context, GrowthDomain dom) {
    final data = _domainData(dom.id);
    final domainAnalytes =
        _analytes.where((a) => evidence.analytes[a['key']]?.domain == dom.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scroll) => Container(
          decoration: const BoxDecoration(
            color: GsColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: GsColors.border2,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(children: [
                Text(dom.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(dom.label,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                _StatusPill(
                    status: data['status'] as String?, i18n: i18n),
              ]),
              const SizedBox(height: 8),
              Text(dom.question,
                  style: const TextStyle(
                      fontSize: 12, color: GsColors.text3, height: 1.4)),
              if ((data['note'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Text('${data['note']}',
                    style: const TextStyle(
                        fontSize: 13, color: GsColors.text, height: 1.5)),
              ],
              for (final a in domainAnalytes) ...[
                const SizedBox(height: 14),
                _AnalyteTile(
                    data: a,
                    evidence: evidence,
                    i18n: i18n,
                    series: labSeries[a['key']],
                    startOpen: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Confidence + status chips ───────────────────────────────────────

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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.i18n});
  final String? status;
  final I18n i18n;
  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(_statusLabel(status, i18n),
          style:
              TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

// ── Orbit ───────────────────────────────────────────────────────────

class _GrowthOrbit extends StatelessWidget {
  const _GrowthOrbit(
      {required this.evidence,
      required this.domainStatus,
      required this.onTapDomain});
  final GrowthEvidence evidence;
  final Map<String, String?> domainStatus;
  final void Function(GrowthDomain) onTapDomain;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      const h = 300.0;
      final centre = Offset(w / 2, h / 2);
      final ringR = math.min(w, h) / 2 - 46;
      final doms = evidence.domains;
      // Positions: evenly spaced, first node at top.
      final positions = <String, Offset>{};
      for (var i = 0; i < doms.length; i++) {
        final angle = -math.pi / 2 + i * 2 * math.pi / doms.length;
        positions[doms[i].id] = centre +
            Offset(math.cos(angle) * ringR, math.sin(angle) * ringR);
      }

      return SizedBox(
        width: w,
        height: h,
        child: Stack(children: [
          CustomPaint(
            size: Size(w, h),
            painter: _OrbitPainter(
              centre: centre,
              nodes: positions,
              status: domainStatus,
            ),
          ),
          // Centre label
          Positioned(
            left: centre.dx - 44,
            top: centre.dy - 44,
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: GsColors.deepGreen,
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Text('Child\ngrowth',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ),
          // Domain nodes
          for (final d in doms)
            Positioned(
              left: positions[d.id]!.dx - 34,
              top: positions[d.id]!.dy - 34,
              child: _OrbitNode(
                  domain: d,
                  status: domainStatus[d.id],
                  onTap: () => onTapDomain(d)),
            ),
        ]),
      );
    });
  }
}

class _OrbitNode extends StatelessWidget {
  const _OrbitNode(
      {required this.domain, required this.status, required this.onTap});
  final GrowthDomain domain;
  final String? status;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    final dim = status == 'insufficient_data';
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dim ? GsColors.surface2 : c.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: c, width: 2),
            ),
            child: Text(domain.icon,
                style: TextStyle(
                    fontSize: 20,
                    color: dim ? GsColors.text3 : null)),
          ),
          const SizedBox(height: 3),
          Text(domain.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 8.8,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: GsColors.text2)),
        ]),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(
      {required this.centre, required this.nodes, required this.status});
  final Offset centre;
  final Map<String, Offset> nodes;
  final Map<String, String?> status;

  @override
  void paint(Canvas canvas, Size size) {
    nodes.forEach((id, pos) {
      final edge = _domainEdge[id] ?? 'association';
      final c = _statusColor(status[id]).withValues(alpha: 0.55);
      final paint = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge == 'direct' ? 2.0 : 1.4;
      // Trim the line so it starts/ends outside the centre + node discs.
      final dir = (pos - centre);
      final len = dir.distance;
      final unit = dir / len;
      final start = centre + unit * 46;
      final end = pos - unit * 28;
      _drawStyledLine(canvas, start, end, edge, paint);
    });
  }

  void _drawStyledLine(
      Canvas canvas, Offset a, Offset b, String edge, Paint paint) {
    if (edge == 'direct') {
      canvas.drawLine(a, b, paint);
      return;
    }
    // dashed (supporting) or dotted (association)
    final total = (b - a).distance;
    final unit = (b - a) / total;
    final dash = edge == 'supporting' ? 7.0 : 2.0;
    final gap = edge == 'supporting' ? 5.0 : 4.0;
    var d = 0.0;
    while (d < total) {
      final s = a + unit * d;
      final e = a + unit * math.min(d + dash, total);
      canvas.drawLine(s, e, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) =>
      old.status != status || old.nodes != nodes;
}

class _OrbitLegend extends StatelessWidget {
  const _OrbitLegend();
  @override
  Widget build(BuildContext context) {
    Widget item(String dashKind, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 20,
                height: 8,
                child: CustomPaint(painter: _LegendLinePainter(dashKind))),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(fontSize: 9, color: GsColors.text3)),
          ],
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        item('direct', 'Direct'),
        item('supporting', 'Supporting'),
        item('association', 'Association'),
      ],
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  _LegendLinePainter(this.kind);
  final String kind;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = GsColors.text3
      ..strokeWidth = kind == 'direct' ? 2 : 1.4;
    final y = size.height / 2;
    if (kind == 'direct') {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    } else {
      final dash = kind == 'supporting' ? 5.0 : 1.6;
      final gap = kind == 'supporting' ? 3.0 : 3.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + dash, size.width), y), p);
        x += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter old) => old.kind != kind;
}

// ── Analyte tile with curated evidence ──────────────────────────────

class _AnalyteTile extends StatefulWidget {
  const _AnalyteTile(
      {required this.data,
      required this.evidence,
      required this.i18n,
      this.series,
      this.startOpen = false});
  final Map<String, dynamic> data;
  final GrowthEvidence evidence;
  final I18n i18n;
  final LabSeries? series;
  final bool startOpen;

  @override
  State<_AnalyteTile> createState() => _AnalyteTileState();
}

class _AnalyteTileState extends State<_AnalyteTile> {
  late bool _open = widget.startOpen;

  Color _analyteStatusColor(String? s) => switch (s) {
        'below_range' || 'above_range' => GsColors.flag,
        'in_range' => GsColors.accent,
        _ => GsColors.text3,
      };

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final d = widget.data;
    final key = d['key'] as String?;
    final cards =
        key == null ? <EvidenceCard>[] : widget.evidence.cardsForAnalyte(key);
    final valueNote = d['value_note'] as String?;
    final trend = d['trend_note'] as String?;
    final meaning = d['meaning'] as String?;
    final growth = d['growth_relevance'] as String?;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: GsColors.bg,
        borderRadius: BorderRadius.circular(GsRadius.sm),
        border: Border.all(color: GsColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
                color: _analyteStatusColor(d['status'] as String?),
                shape: BoxShape.circle),
          ),
          Expanded(
            child: Text('${d['name'] ?? ''}',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (valueNote != null && valueNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Text(valueNote,
                style: const TextStyle(
                    fontSize: 11.5, color: GsColors.text, height: 1.4)),
          ),
        // Inline multidimension chart from the child's own logged values.
        if (widget.series != null && widget.series!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6),
            child: LabRangeBar(
                value: widget.series!.last.value,
                low: widget.series!.last.low,
                high: widget.series!.last.high),
          ),
          if (widget.series!.length >= 2)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: LabSparkline(points: widget.series!),
            ),
        ],
        if (trend != null && trend.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Text('📈 $trend',
                style: const TextStyle(
                    fontSize: 11, color: GsColors.measured, height: 1.4)),
          ),
        if (meaning != null && meaning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Text(meaning,
                style: const TextStyle(
                    fontSize: 11.5, color: GsColors.text2, height: 1.4)),
          ),
        if (growth != null && growth.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Text('🌱 $growth',
                style: const TextStyle(
                    fontSize: 11,
                    color: GsColors.accent,
                    height: 1.4,
                    fontWeight: FontWeight.w600)),
          ),
        if (cards.isNotEmpty) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
              child: Row(children: [
                Icon(_open ? Icons.expand_less : Icons.menu_book_outlined,
                    size: 14, color: GsColors.measured),
                const SizedBox(width: 5),
                Text(
                    '${t('flutter.gs.evidence', 'Evidence')} (${cards.length})',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: GsColors.measured)),
              ]),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Column(
                children: [for (final c in cards) _EvidenceTile(card: c)],
              ),
            ),
        ],
      ]),
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
      padding: const EdgeInsets.all(9),
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
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: GsColors.measuredDark)),
          ),
          const Spacer(),
          Text('${card.year}',
              style: const TextStyle(fontSize: 9, color: GsColors.text3)),
        ]),
        const SizedBox(height: 4),
        Text(card.claim,
            style: const TextStyle(
                fontSize: 11, color: GsColors.text, height: 1.4)),
        if (card.scopeNote != null) ...[
          const SizedBox(height: 3),
          Text('⚠ ${card.scopeNote}',
              style: const TextStyle(
                  fontSize: 9.5,
                  color: GsColors.estimatedDark,
                  height: 1.3,
                  fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 4),
        InkWell(
          onTap: () => launchUrl(Uri.parse(card.pubmedUrl),
              mode: LaunchMode.externalApplication),
          child: Text(
              '${card.authors} · ${card.journal} · PMID ${card.pmid}',
              style: const TextStyle(
                  fontSize: 9.5,
                  color: GsColors.measured,
                  decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }
}
