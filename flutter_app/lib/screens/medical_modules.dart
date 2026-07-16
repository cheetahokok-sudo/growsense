// ══════════════════════════════════════════════════════════════════
// Clinical record modules — detail screens pushed from the Medical
// tab's module list. Each keeps the PWA's clinical-grade fields and
// writes the same Supabase tables (bone_age_assessments, lab_results,
// illness_events, puberty_events). X-ray image upload for bone age is
// web-app-only for now.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../growth_evidence.dart';
import '../i18n.dart';
import '../illness_reference.dart';
import '../theme.dart';
import '../widgets/evidence_refs.dart';
import '../widgets/growth_systems.dart';
import '../widgets/lab_viz.dart';
import '../widgets/premium_gate.dart';

// ── Shared scaffolding ──────────────────────────────────────────────

class _ModuleScaffold extends StatelessWidget {
  const _ModuleScaffold(
      {required this.title, required this.entry, required this.history});
  final String title;
  final Widget entry;
  final Widget history;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [entry, const SizedBox(height: 12), history],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: GsColors.accent)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.i18n,
    required this.items,
    required this.rowBuilder,
    required this.onDelete,
  });
  final I18n i18n;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic>) rowBuilder;
  final Future<String?> Function(Map<String, dynamic>) onDelete;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t('flutter.history', 'History'),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GsColors.measured)),
              Text('${items.length} ${t('flutter.records', 'records')}',
                  style:
                      const TextStyle(fontSize: 11, color: GsColors.text3)),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                  t('flutter.nothing_recorded', 'Nothing recorded yet.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: GsColors.text3)),
            )
          else
            for (final item in items)
              Row(
                children: [
                  Expanded(child: rowBuilder(item)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close,
                        size: 16, color: GsColors.text3),
                    onPressed: () async {
                      final err = await onDelete(item);
                      if (err != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            backgroundColor: GsColors.flag,
                            content: Text(
                                '${t('flutter.could_not_remove', 'Could not remove')}: $err')));
                      }
                    },
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

class _TwoLine extends StatelessWidget {
  const _TwoLine({required this.title, required this.meta, this.trailing});
  final String title;
  final String meta;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(meta,
                    style: const TextStyle(
                        fontSize: 11, color: GsColors.text3)),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: GsColors.measured)),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: GsColors.border2),
        foregroundColor: GsColors.text,
        alignment: AlignmentDirectional.centerStart,
      ),
      icon: const Icon(Icons.event, size: 15, color: GsColors.text2),
      label: Text('$label: ${value ?? '—'}',
          style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value != null ? DateTime.parse(value!) : now,
          firstDate: now.subtract(const Duration(days: 365 * 19)),
          lastDate: now,
        );
        onChanged(picked == null ? value : localISO(picked));
      },
    );
  }
}

InputDecoration _dec(String label) =>
    InputDecoration(labelText: label, isDense: true);

void _snack(BuildContext context, String? err, String okMsg, String errMsg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
      content: Text(err == null ? '✅ $okMsg' : '$errMsg: $err')));
}

// ── Bone age ────────────────────────────────────────────────────────
// Moved to bone_age_screen.dart — grew into the flagship module with
// the maturation timeline, X-ray upload, and AI second opinion.

// ── Lab results ─────────────────────────────────────────────────────

class LabResultsScreen extends StatefulWidget {
  const LabResultsScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<LabResultsScreen> createState() => _LabResultsScreenState();
}

class _LabResultsScreenState extends State<LabResultsScreen> {
  String? _date;
  final _analyte = TextEditingController();
  final _value = TextEditingController();
  final _unit = TextEditingController();
  final _refLow = TextEditingController();
  final _refHigh = TextEditingController();
  final _sds = TextEditingController();
  bool _busy = false;

  // Growth-relevant presets a parent is most likely holding a report
  // for — one tap fills analyte + typical unit.
  static const _presets = [
    ('IGF-1', 'ng/mL'),
    ('Vitamin D', 'ng/mL'),
    ('Ferritin', 'ng/mL'),
    ('TSH', 'mIU/L'),
    ('Hemoglobin', 'g/dL'),
  ];

  @override
  void initState() {
    super.initState();
    // Surface the last stored AI interpretation for a returning user.
    widget.appState.loadLatestLabAiReport();
  }

  @override
  void dispose() {
    for (final c in [_analyte, _value, _unit, _refLow, _refHigh, _sds]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    final value = double.tryParse(_value.text);
    if (_date == null ||
        _analyte.text.trim().isEmpty ||
        value == null ||
        _unit.text.trim().isEmpty) {
      _snack(context, t('medical.other_labs.result'), '',
          t('flutter.not_saved', 'Not saved'));
      return;
    }
    setState(() => _busy = true);
    final err = await widget.appState.addLabResult(
      labDate: _date!,
      analyteName: _analyte.text.trim(),
      resultValue: value,
      unit: _unit.text.trim(),
      referenceLow: double.tryParse(_refLow.text),
      referenceHigh: double.tryParse(_refHigh.text),
      sds: double.tryParse(_sds.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, err, t('medical.other_labs.add_btn'),
        t('flutter.not_saved', 'Not saved'));
    if (err == null) {
      _value.clear();
      _sds.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) => _ModuleScaffold(
        title: t('medical.lab_values.title', 'Lab values'),
        entry: _EntryCard(
          title: t('medical.other_labs.add_btn', 'Add lab result'),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (name, unit) in _presets)
                  GestureDetector(
                    onTap: () => setState(() {
                      _analyte.text = name;
                      _unit.text = unit;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _analyte.text == name
                            ? GsColors.accentLight
                            : GsColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: GsColors.text2)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _DateButton(
              label: t('common.date', 'Date'),
              value: _date,
              onChanged: (v) => setState(() => _date = v),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: _analyte,
                decoration:
                    _dec(t('medical.other_labs.analyte', 'Analyte name'))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  flex: 3,
                  child: TextField(
                      controller: _value,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: _dec(
                          t('medical.other_labs.result', 'Result value')))),
              const SizedBox(width: 8),
              Expanded(
                  flex: 2,
                  child: TextField(
                      controller: _unit,
                      decoration:
                          _dec(t('medical.other_labs.unit', 'Unit')))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _refLow,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: _dec(
                          '${t('medical.other_labs.ref_range', 'Reference range')} ↓'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _refHigh,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: _dec(
                          '${t('medical.other_labs.ref_range', 'Reference range')} ↑'))),
            ]),
            const SizedBox(height: 10),
            TextField(
                controller: _sds,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: _dec(t('flutter.lab.sds_field',
                    'SDS / z-score (optional — if your report shows it)'))),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy
                  ? t('flutter.saving', 'Saving…')
                  : t('medical.other_labs.add_btn', 'Add lab result')),
            ),
          ],
        ),
        history: _LabAnalytePanel(
            appState: widget.appState, i18n: widget.i18n),
      ),
    );
  }
}

/// Canonical order for the five focus labs; anything else follows.
const _labOrder = ['igf1', 'vitamin_d', 'ferritin', 'tsh', 'hemoglobin'];

/// The "first look" a parent gets after entering lab values: a swipe row
/// of compact cards (value, range, trend, one plain-language line), each
/// opening a detail card with What-it-means + Evidence & References — all
/// FREE. The AI cross-lab synthesis below is the premium layer.
class _LabAnalytePanel extends StatefulWidget {
  const _LabAnalytePanel({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<_LabAnalytePanel> createState() => _LabAnalytePanelState();
}

class _LabAnalytePanelState extends State<_LabAnalytePanel> {
  GrowthEvidence? _evidence;

  @override
  void initState() {
    super.initState();
    GrowthEvidence.load().then((e) {
      if (mounted) setState(() => _evidence = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final results = widget.appState.labResults;

    // Group by analyte name; labResults is date-desc so each group's
    // first entry is the latest. Order the five focus labs first.
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in results) {
      final key = (r['analyte_name'] as String? ?? '').trim().toLowerCase();
      groups.putIfAbsent(key, () => []).add(r);
    }
    final ordered = groups.values.toList();
    if (_evidence != null) {
      int rank(List<Map<String, dynamic>> g) {
        final k = _evidence!.keyForAnalyteName(g.first['analyte_name'] ?? '');
        final i = k == null ? -1 : _labOrder.indexOf(k);
        return i < 0 ? 99 : i;
      }

      ordered.sort((a, b) => rank(a).compareTo(rank(b)));
    }

    if (groups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GsColors.surface,
          borderRadius: BorderRadius.circular(GsRadius.md),
          border: Border.all(color: GsColors.border),
          boxShadow: gsShadow,
        ),
        child: Text(t('flutter.nothing_recorded', 'Nothing recorded yet.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: GsColors.text3)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(t('flutter.lab.your_results', 'Your results'),
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ),
        // First look — horizontal swipe row.
        SizedBox(
          height: 226,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: ordered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _LabMiniCard(
              entries: ordered[i],
              evidence: _evidence,
              appState: widget.appState,
              i18n: widget.i18n,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
              t('flutter.lab.range_note',
                  'Ranges shown are the ones printed on your lab report — matched to your child\'s age and sex by the lab. Tap a card for details.'),
              style: const TextStyle(
                  fontSize: 10.5, color: GsColors.text3, height: 1.4)),
        ),
        const SizedBox(height: 14),
        _LabAiCard(appState: widget.appState, i18n: widget.i18n),
      ],
    );
  }
}

/// Compact "first look" card. Tap → full detail sheet.
class _LabMiniCard extends StatelessWidget {
  const _LabMiniCard(
      {required this.entries,
      required this.evidence,
      required this.appState,
      required this.i18n});
  final List<Map<String, dynamic>> entries;
  final GrowthEvidence? evidence;
  final AppState appState;
  final I18n i18n;

  double? _d(dynamic v) => (v as num?)?.toDouble();

  @override
  Widget build(BuildContext context) {
    final latest = entries.first;
    final value = _d(latest['result_value']) ?? 0;
    final low = _d(latest['reference_low']);
    final high = _d(latest['reference_high']);
    final unit = latest['unit'] as String? ?? '';
    final sds = _d(latest['sds']);
    final status = labStatusOf(value, low, high);
    final key = evidence?.keyForAnalyteName(latest['analyte_name'] ?? '');
    final band = labStatusBand(status);
    final hint = (key != null && band != null)
        ? evidence?.analytes[key]?.hintFor(band)
        : null;
    final series = [
      for (final r in entries.reversed)
        (
          value: _d(r['result_value']) ?? 0,
          low: _d(r['reference_low']),
          high: _d(r['reference_high']),
        ),
    ];

    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _LabDetailSheet(
            entries: entries,
            evidence: evidence,
            appState: appState,
            i18n: i18n),
      ),
      child: Container(
        width: 168,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: GsColors.surface,
          borderRadius: BorderRadius.circular(GsRadius.md),
          border: Border.all(color: GsColors.border),
          boxShadow: gsShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                    color: labStatusColor(status), shape: BoxShape.circle),
              ),
              Expanded(
                child: Text('${latest['analyte_name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtVal(value),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, height: 1.0)),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(unit,
                    style: const TextStyle(
                        fontSize: 10.5, color: GsColors.text2)),
              ),
              if (sds != null) ...[
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                      '${sds >= 0 ? '+' : '−'}${sds.abs().toStringAsFixed(1)} SDS',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: sds.abs() <= 2
                              ? GsColors.accent
                              : GsColors.estimated)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Row(children: [
              if (low != null || high != null)
                Flexible(
                  child: Text('(${_fmtNum(low)} – ${_fmtNum(high)})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9.5, color: GsColors.text3)),
                ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: labStatusColor(status).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(labStatusShort(status, i18n),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: labStatusColor(status))),
              ),
            ]),
            const SizedBox(height: 6),
            if (series.length >= 2)
              SizedBox(height: 40, child: LabSparkline(points: series))
            else
              const SizedBox(height: 40),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                  hint ??
                      (evidence?.analytes[key]?.meaning ??
                          i18n.t('flutter.lab.tap_more', 'Tap for details.')),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: GsColors.text2, height: 1.35)),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtNum(double? v) => v == null
    ? '—'
    : (v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1));

/// Detail card (mockup 1): big value, range bar, 12-month trend,
/// What-it-means, Evidence & References, and the dated entries + delete.
class _LabDetailSheet extends StatefulWidget {
  const _LabDetailSheet(
      {required this.entries,
      required this.evidence,
      required this.appState,
      required this.i18n});
  final List<Map<String, dynamic>> entries;
  final GrowthEvidence? evidence;
  final AppState appState;
  final I18n i18n;

  @override
  State<_LabDetailSheet> createState() => _LabDetailSheetState();
}

class _LabDetailSheetState extends State<_LabDetailSheet> {
  bool _evidenceOpen = false;
  double? _d(dynamic v) => (v as num?)?.toDouble();

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final latest = widget.entries.first;
    final value = _d(latest['result_value']) ?? 0;
    final low = _d(latest['reference_low']);
    final high = _d(latest['reference_high']);
    final unit = latest['unit'] as String? ?? '';
    final sds = _d(latest['sds']);
    final status = labStatusOf(value, low, high);
    final key = widget.evidence?.keyForAnalyteName(latest['analyte_name'] ?? '');
    final analyte = key == null ? null : widget.evidence?.analytes[key];
    final cards = key == null
        ? const <EvidenceCard>[]
        : (widget.evidence?.cardsForAnalyte(key) ?? const []);
    final series = [
      for (final r in widget.entries.reversed)
        (
          value: _d(r['result_value']) ?? 0,
          low: _d(r['reference_low']),
          high: _d(r['reference_high']),
        ),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.94,
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
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: GsColors.border2,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('${latest['analyte_name'] ?? ''}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtVal(value),
                  style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      color: labStatusColor(status))),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(unit,
                    style: const TextStyle(
                        fontSize: 13, color: GsColors.text2)),
              ),
              const Spacer(),
              LabStatusChip(status: status, i18n: widget.i18n),
            ]),
            if (low != null || high != null) ...[
              const SizedBox(height: 4),
              Text(
                  '${t('flutter.lab.lab_range', 'Lab range')} ${_fmtNum(low)} – ${_fmtNum(high)} $unit',
                  style: const TextStyle(fontSize: 11, color: GsColors.text3)),
              const SizedBox(height: 8),
              LabRangeBar(value: value, low: low, high: high),
            ],
            // Lab-reported standard score (SDS / z-score), age & sex adjusted.
            if (sds != null) ...[
              const SizedBox(height: 18),
              Row(children: [
                Text(
                    '${sds >= 0 ? '+' : '−'}${sds.abs().toStringAsFixed(1)} SDS',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: sds.abs() <= 2
                            ? GsColors.accent
                            : GsColors.estimated)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      t('flutter.lab.sds_note',
                          'Age & sex adjusted — from your lab report. 0 is the average; within ±2 is the usual range.'),
                      style: const TextStyle(
                          fontSize: 10, color: GsColors.text3, height: 1.3)),
                ),
              ]),
              const SizedBox(height: 8),
              SdsBar(sds: sds),
            ],
            if (series.length >= 2) ...[
              const SizedBox(height: 18),
              Text(t('flutter.lab.trend', 'Trend'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: GsColors.measured)),
              const SizedBox(height: 4),
              LabSparkline(points: series),
            ],
            if (analyte != null) ...[
              const SizedBox(height: 18),
              Text(t('flutter.lab.what_means', 'What it means'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(analyte.meaning,
                  style: const TextStyle(
                      fontSize: 12.5, color: GsColors.text2, height: 1.5)),
            ],
            if (cards.isNotEmpty) ...[
              const SizedBox(height: 14),
              InkWell(
                onTap: () => setState(() => _evidenceOpen = !_evidenceOpen),
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: GsColors.bg,
                    borderRadius: BorderRadius.circular(GsRadius.sm),
                    border: Border.all(color: GsColors.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.menu_book_outlined,
                        size: 16, color: GsColors.measured),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          '${t('flutter.gs.evidence', 'Evidence & References')} (${cards.length})',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: GsColors.measured)),
                    ),
                    Icon(_evidenceOpen ? Icons.expand_less : Icons.chevron_right,
                        size: 18, color: GsColors.measured),
                  ]),
                ),
              ),
              if (_evidenceOpen) ...[
                const SizedBox(height: 8),
                EvidenceRefsList(cards: cards),
              ],
            ],
            const SizedBox(height: 18),
            Text(t('flutter.lab.all_entries', 'All entries'),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            for (final r in widget.entries)
              Row(children: [
                Expanded(
                  child: _TwoLine(
                    title: '${r['lab_date'] ?? ''}',
                    meta: (r['reference_low'] != null ||
                            r['reference_high'] != null)
                        ? '${_fmtNum(_d(r['reference_low']))}–${_fmtNum(_d(r['reference_high']))} ${r['unit'] ?? ''}'
                        : '${r['unit'] ?? ''}',
                    trailing: _fmtVal(_d(r['result_value']) ?? 0),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close,
                      size: 16, color: GsColors.text3),
                  onPressed: () async {
                    final err = await widget.appState
                        .deleteLabResult(r['lab_result_id']);
                    if (!context.mounted) return;
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor: GsColors.flag,
                          content: Text(
                              '${t('flutter.could_not_remove', 'Could not remove')}: $err')));
                    } else if (widget.entries.length == 1) {
                      Navigator.of(context).pop(); // last entry gone
                    } else {
                      setState(() => widget.entries.remove(r));
                    }
                  },
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Premium AI interpretation of the lab panel. Free users see a locked
/// teaser → paywall; premium users run it and get the rendered report.
/// Server (lab-ai-analysis) reads the labs itself and enforces the tier.
class _LabAiCard extends StatefulWidget {
  const _LabAiCard({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<_LabAiCard> createState() => _LabAiCardState();
}

class _LabAiCardState extends State<_LabAiCard> {
  Future<void> _run() async {
    final t = widget.i18n.t;
    if (!widget.appState.isPremium) {
      _paywall();
      return;
    }
    final err = await widget.appState.runLabAI();
    if (!mounted || err == null) return;
    if (err == AppState.premiumRequiredError) {
      _paywall();
    } else {
      final msg = err == 'no_labs'
          ? t('flutter.lab.ai_no_labs',
              'Add a lab result first, then run the interpretation.')
          : '${t('flutter.lab.ai_failed', 'Interpretation failed')}: $err';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _paywall() {
    final t = widget.i18n.t;
    showPremiumSheet(
      context,
      appState: widget.appState,
      i18n: widget.i18n,
      emoji: '🧪',
      title: t('flutter.lab.premium_title', 'AI lab interpretation is Premium'),
      body: t(
          'flutter.lab.premium_body',
          'Get a plain-language reading of each result against your own '
              'lab’s reference ranges, what it means for growth, and '
              'questions to raise with your doctor.'),
      freeNote: t('flutter.lab.premium_free_note',
          'Logging and charting your lab values stays free — always.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final app = widget.appState;
    final premium = app.isPremium;
    final running = app.labAiRunning;
    final report = app.labAiReport?['report'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('🤖', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(t('flutter.lab.ai_title', 'AI interpretation'),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: GsColors.accent)),
            const SizedBox(width: 6),
            if (!premium) PremiumBadge(i18n: widget.i18n),
          ]),
          if (report == null && !running) ...[
            const SizedBox(height: 6),
            Text(
                t('flutter.lab.ai_teaser',
                    'A plain-language second read of this panel — measured against your own lab’s ranges, never a made-up “normal”.'),
                style: const TextStyle(
                    fontSize: 11.5, color: GsColors.text2, height: 1.4)),
          ],
          const SizedBox(height: 10),
          if (running)
            Row(children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      t('flutter.lab.ai_running',
                          'Reading the panel against your lab’s ranges…'),
                      style: const TextStyle(
                          fontSize: 11.5, color: GsColors.text2))),
            ])
          else
            OutlinedButton.icon(
              onPressed: _run,
              icon: Icon(premium ? Icons.auto_awesome_outlined : Icons.lock_outline,
                  size: 16),
              label: Text(
                  report == null
                      ? t('flutter.lab.ai_btn', 'Get AI interpretation')
                      : t('flutter.lab.ai_refresh', 'Refresh interpretation'),
                  style: const TextStyle(fontSize: 12)),
            ),
          if (report != null && !running) ...[
            const SizedBox(height: 12),
            GrowthSystemsReport(report: report, i18n: widget.i18n),
          ],
        ],
      ),
    );
  }
}

String _fmtVal(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toString();

// ── Illness log ─────────────────────────────────────────────────────

const _riskColor = {
  'high': GsColors.flag,
  'moderate': GsColors.estimated,
  'neutral': GsColors.accent,
};

class IllnessLogScreen extends StatefulWidget {
  const IllnessLogScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<IllnessLogScreen> createState() => _IllnessLogScreenState();
}

class _IllnessLogScreenState extends State<IllnessLogScreen> {
  IllnessReference? _ref;
  String? _start;
  String? _end;
  String _type = 'fever';
  String _severity = 'mild';
  final Set<String> _meds = {};
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    IllnessReference.load().then((r) {
      if (mounted) {
        setState(() {
          _ref = r;
          if (r.illnesses.isNotEmpty) _type = r.illnesses.first.id;
        });
      }
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Auto-suggest an end date from the illness's typical duration when
  /// the parent picks a start date and hasn't set an end yet.
  void _onStartChanged(String? v) {
    setState(() {
      _start = v;
      final ill = _ref?.illness(_type);
      if (v != null && _end == null && ill != null) {
        final d = DateTime.parse(v).add(Duration(days: ill.durationMax));
        final today = DateTime.now();
        _end = localISO(d.isAfter(today) ? today : d);
      }
    });
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    if (_start == null) return;
    if (_end != null && _end!.compareTo(_start!) < 0) {
      _snack(context, t('medical.illness.end_date'), '',
          t('flutter.not_saved', 'Not saved'));
      return;
    }
    setState(() => _busy = true);
    final details = IllnessDetails(
      severity: _severity,
      medIds: _meds.toList(),
      freeText: _notes.text.trim(),
    );
    final err = await widget.appState.addIllnessEvent(
      startDate: _start!,
      endDate: _end,
      illnessType: _type,
      notes: details.encode(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) {
        _meds.clear();
        _notes.clear();
      }
    });
    _snack(context, err, t('medical.illness.add_btn'),
        t('flutter.not_saved', 'Not saved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final ref = _ref;
    if (ref == null) {
      return Scaffold(
        appBar: AppBar(
            title: Text(
                t('medical.illness.title', 'Development interference log'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final selectedIll = ref.illness(_type);
    // Medications that carry a growth flag, among those selected.
    final flaggedMeds = [
      for (final id in _meds)
        if (ref.med(id) case final m? when m.risk != 'neutral') m,
    ];

    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) => _ModuleScaffold(
        title: t('medical.illness.title', 'Development interference log'),
        entry: _EntryCard(
          title: t('medical.illness.add_btn', 'Add illness episode'),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: _dec(t('common.type', 'Type')),
              items: [
                for (final ill in ref.illnesses)
                  DropdownMenuItem(
                      value: ill.id,
                      child: Text('${ill.emoji}  ${ill.label}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            if (selectedIll != null) ...[
              const SizedBox(height: 6),
              Text(
                  '${t('flutter.illness.typical', 'Typical')}: ${selectedIll.durationMin}–${selectedIll.durationMax} ${t('flutter.illness.days', 'days')} · ${selectedIll.growthNote}',
                  style:
                      const TextStyle(fontSize: 10.5, color: GsColors.text3)),
            ],
            const SizedBox(height: 12),
            // Severity segmented control
            Text(t('flutter.illness.severity', 'Severity'),
                style: const TextStyle(fontSize: 11.5, color: GsColors.text2)),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final s in ['mild', 'moderate', 'severe'])
                  Expanded(
                    child: Padding(
                      padding:
                          EdgeInsets.only(right: s == 'severe' ? 0 : 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _severity = s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _severity == s
                                ? (s == 'severe'
                                    ? GsColors.flag
                                    : s == 'moderate'
                                        ? GsColors.estimated
                                        : GsColors.accent)
                                : GsColors.surface2,
                            borderRadius: BorderRadius.circular(GsRadius.sm),
                          ),
                          child: Text(t('flutter.illness.$s', s),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _severity == s
                                      ? Colors.white
                                      : GsColors.text2)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DateButton(
              label: t('common.start_date', 'Start date'),
              value: _start,
              onChanged: _onStartChanged,
            ),
            const SizedBox(height: 8),
            _DateButton(
              label: t('medical.illness.end_date',
                  'End date (optional — leave blank if ongoing)'),
              value: _end,
              onChanged: (v) => setState(() => _end = v),
            ),
            const SizedBox(height: 12),
            // Medications given
            Text(t('flutter.illness.meds_given', 'Medications given'),
                style: const TextStyle(fontSize: 11.5, color: GsColors.text2)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in ref.medications)
                  GestureDetector(
                    onTap: () => setState(() =>
                        _meds.contains(m.id) ? _meds.remove(m.id) : _meds.add(m.id)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _meds.contains(m.id)
                            ? (_riskColor[m.risk] ?? GsColors.accent)
                                .withValues(alpha: 0.14)
                            : GsColors.surface2,
                        borderRadius: BorderRadius.circular(GsRadius.sm),
                        border: Border.all(
                            color: _meds.contains(m.id)
                                ? (_riskColor[m.risk] ?? GsColors.accent)
                                : Colors.transparent),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsetsDirectional.only(end: 6),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    _riskColor[m.risk] ?? GsColors.accent),
                          ),
                          Flexible(
                            child: Text(m.name,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: GsColors.text)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            // Growth insight callout for any flagged medication
            if (flaggedMeds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GsColors.estimatedLight,
                  borderRadius: BorderRadius.circular(GsRadius.sm),
                  border: Border.all(
                      color: GsColors.estimated.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('⚠️', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                            t('flutter.illness.growth_insight',
                                'Growth insight'),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: GsColors.estimatedDark)),
                      ],
                    ),
                    for (final m in flaggedMeds) ...[
                      const SizedBox(height: 8),
                      Text(m.name,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _riskColor[m.risk])),
                      const SizedBox(height: 2),
                      Text(m.insight,
                          style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: GsColors.estimatedDark)),
                      if (m.citation != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text('Source: ${m.citation}',
                              style: const TextStyle(
                                  fontSize: 9, color: GsColors.text3)),
                        ),
                    ],
                    const SizedBox(height: 8),
                    Text('📏 ${t('flutter.illness.monitor')}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: GsColors.estimatedDark)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
                controller: _notes,
                decoration:
                    _dec(t('common.notes_optional', 'Notes (optional)'))),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy || _start == null ? null : _save,
              child: Text(_busy
                  ? t('flutter.saving', 'Saving…')
                  : t('medical.illness.add_btn', 'Add illness episode')),
            ),
          ],
        ),
        history: _HistoryList(
          i18n: widget.i18n,
          items: widget.appState.illnessEvents,
          onDelete: (r) =>
              widget.appState.deleteIllnessEvent(r['event_id']),
          rowBuilder: (r) {
            final ill = ref.illness(r['illness_type'] as String? ?? '');
            final details =
                IllnessDetails.decode(r['notes'] as String?);
            final sev = details.severity;
            final hasFlaggedMed = details.medIds.any(
                (id) => (ref.med(id)?.risk ?? 'neutral') != 'neutral');
            final title =
                '${ill?.emoji ?? '🤒'} ${ill?.label ?? r['illness_type'] ?? ''}'
                '${sev != null ? ' · ${t('flutter.illness.$sev', sev)}' : ''}'
                '${hasFlaggedMed ? ' ⚠️' : ''}';
            return _TwoLine(
              title: title,
              meta:
                  '${r['start_date'] ?? ''} → ${r['end_date'] ?? t('flutter.ongoing', 'ongoing')}${details.freeText.isNotEmpty ? ' · ${details.freeText}' : ''}',
            );
          },
        ),
      ),
    );
  }
}

// ── Puberty milestones ──────────────────────────────────────────────

// Same event_type values and staging rules as the PWA.
const pubertyTypes = [
  'breast_development', 'genital_development', 'pubic_hair',
  'axillary_hair', 'facial_hair', 'voice_change', 'body_odor', 'acne',
  'growth_spurt_feeling', 'menarche',
];
const pubertyTypesWithoutStage = {
  'voice_change', 'body_odor', 'acne', 'growth_spurt_feeling', 'menarche',
};
// event_type value → medical.puberty.type.* key suffix
const _pubertyKeySuffix = {
  'breast_development': 'breast',
  'genital_development': 'genital',
  'pubic_hair': 'pubic_hair',
  'axillary_hair': 'axillary',
  'facial_hair': 'facial_hair',
  'voice_change': 'voice',
  'body_odor': 'body_odor',
  'acne': 'acne',
  'growth_spurt_feeling': 'growth_spurt',
  'menarche': 'menarche',
};
const _tannerNumerals = {1: 'I', 2: 'II', 3: 'III', 4: 'IV', 5: 'V'};

class PubertyScreen extends StatefulWidget {
  const PubertyScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<PubertyScreen> createState() => _PubertyScreenState();
}

class _PubertyScreenState extends State<PubertyScreen> {
  String? _date;
  String _type = 'growth_spurt_feeling';
  int _stage = 2;
  bool _busy = false;

  Future<void> _save() async {
    final t = widget.i18n.t;
    if (_date == null) return;
    setState(() => _busy = true);
    final err = await widget.appState.addPubertyEvent(
      eventDate: _date!,
      eventType: _type,
      tannerStage:
          pubertyTypesWithoutStage.contains(_type) ? null : _stage,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, err, t('medical.puberty.add_btn'),
        t('flutter.not_saved', 'Not saved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final needsStage = !pubertyTypesWithoutStage.contains(_type);
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) => _ModuleScaffold(
        title: t('medical.puberty.title', 'Puberty milestones'),
        entry: _EntryCard(
          title: t('medical.puberty.add_btn', 'Add milestone'),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: _dec(t('medical.puberty.milestone', 'Milestone')),
              items: [
                for (final type in pubertyTypes)
                  DropdownMenuItem(
                      value: type,
                      child: Text(
                          t('medical.puberty.type.${_pubertyKeySuffix[type]}',
                              type),
                          style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 10),
            _DateButton(
              label: t('medical.puberty.date_observed', 'Date observed'),
              value: _date,
              onChanged: (v) => setState(() => _date = v),
            ),
            if (needsStage) ...[
              const SizedBox(height: 10),
              Text(t('medical.puberty.tanner_stage', 'Tanner stage'),
                  style: const TextStyle(
                      fontSize: 11.5, color: GsColors.text2)),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final s in [1, 2, 3, 4, 5])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: s < 5 ? 6 : 0),
                        child: GestureDetector(
                          onTap: () => setState(() => _stage = s),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 9),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _stage == s
                                  ? GsColors.accent
                                  : GsColors.surface2,
                              borderRadius:
                                  BorderRadius.circular(GsRadius.sm),
                            ),
                            child: Text(_tannerNumerals[s]!,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _stage == s
                                        ? Colors.white
                                        : GsColors.text2)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy || _date == null ? null : _save,
              child: Text(_busy
                  ? t('flutter.saving', 'Saving…')
                  : t('medical.puberty.add_btn', 'Add milestone')),
            ),
          ],
        ),
        history: _HistoryList(
          i18n: widget.i18n,
          items: widget.appState.pubertyEvents,
          onDelete: (r) =>
              widget.appState.deletePubertyEvent(r['event_id']),
          rowBuilder: (r) {
            final stage = (r['tanner_stage'] as num?)?.toInt();
            return _TwoLine(
              title:
                  '🌱 ${t('medical.puberty.type.${_pubertyKeySuffix[r['event_type']] ?? r['event_type']}', r['event_type'] as String? ?? '')}',
              meta: r['event_date'] as String? ?? '',
              trailing: stage != null
                  ? 'Tanner ${_tannerNumerals[stage] ?? stage}'
                  : t('flutter.observed', 'observed'),
            );
          },
        ),
      ),
    );
  }
}
