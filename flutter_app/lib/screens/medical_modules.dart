// ══════════════════════════════════════════════════════════════════
// Clinical record modules — detail screens pushed from the Medical
// tab's module list. Each keeps the PWA's clinical-grade fields and
// writes the same Supabase tables (bone_age_assessments, lab_results,
// illness_events, puberty_events). X-ray image upload for bone age is
// web-app-only for now.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../growth_math.dart' show ageYearsAt;
import '../i18n.dart';
import '../theme.dart';

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

class BoneAgeScreen extends StatefulWidget {
  const BoneAgeScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<BoneAgeScreen> createState() => _BoneAgeScreenState();
}

class _BoneAgeScreenState extends State<BoneAgeScreen> {
  String? _date;
  final _years = TextEditingController();
  final _months = TextEditingController();
  final _sd = TextEditingController();
  final _doctor = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'greulich_pyle';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_years, _months, _sd, _doctor, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    final years = int.tryParse(_years.text) ?? 0;
    final months = int.tryParse(_months.text) ?? 0;
    final total = years * 12 + months;
    final dob =
        widget.appState.activeChildRow?['date_of_birth'] as String?;
    if (_date == null || total <= 0 || dob == null) {
      _snack(context, t('medical.bone_age.label_sub'),
          '', t('flutter.not_saved', 'Not saved'));
      return;
    }
    setState(() => _busy = true);
    final err = await widget.appState.addBoneAge(
      studyDate: _date!,
      boneAgeMonths: total,
      sdMonths: double.tryParse(_sd.text),
      method: _method,
      chronologicalAgeMonths:
          (ageYearsAt(dob, _date!) * 12 * 10).round() / 10,
      reportDoctor: _doctor.text.trim().isEmpty ? null : _doctor.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, err, t('medical.bone_age.save_btn'),
        t('flutter.not_saved', 'Not saved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) => _ModuleScaffold(
        title: t('medical.bone_age.title', 'Bone age assessment'),
        entry: _EntryCard(
          title: t('medical.bone_age.label', 'Bone age (from report)'),
          children: [
            Text(t('medical.bone_age.label_sub',
                "Enter years + months from the radiologist's report"),
                style:
                    const TextStyle(fontSize: 11, color: GsColors.text3)),
            const SizedBox(height: 10),
            _DateButton(
              label: t('medical.bone_age.study_date', 'Study date'),
              value: _date,
              onChanged: (v) => setState(() => _date = v),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _years,
                      keyboardType: TextInputType.number,
                      decoration: _dec('y'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _months,
                      keyboardType: TextInputType.number,
                      decoration: _dec('m'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _sd,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: _dec(
                          t('medical.bone_age.sd_label', 'SD')))),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: _dec(t('common.method', 'Method')),
              items: const [
                DropdownMenuItem(
                    value: 'greulich_pyle',
                    child: Text('Greulich-Pyle (GP)',
                        style: TextStyle(fontSize: 13))),
                DropdownMenuItem(
                    value: 'tw3',
                    child: Text('TW3 (Tanner-Whitehouse)',
                        style: TextStyle(fontSize: 13))),
                DropdownMenuItem(
                    value: 'other',
                    child: Text('Other', style: TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => setState(() => _method = v!),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: _doctor,
                decoration: _dec(t('medical.bone_age.report_doctor',
                    'Report doctor (optional)'))),
            const SizedBox(height: 10),
            TextField(
                controller: _notes,
                decoration: _dec(
                    t('common.notes_optional', 'Notes (optional)'))),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy
                  ? t('flutter.saving', 'Saving…')
                  : t('medical.bone_age.save_btn', 'Save bone age record')),
            ),
          ],
        ),
        history: _HistoryList(
          i18n: widget.i18n,
          items: widget.appState.boneAgeAssessments,
          onDelete: (r) =>
              widget.appState.deleteBoneAge(r['assessment_id']),
          rowBuilder: (r) {
            final ba = (r['bone_age_months'] as num?)?.toInt() ?? 0;
            final chrono =
                (r['chronological_age_months'] as num?)?.toDouble();
            final delta =
                chrono == null ? null : (ba - chrono) / 12;
            return _TwoLine(
              title:
                  '🦴 ${ba ~/ 12}y ${ba % 12}m (${r['method'] ?? ''})',
              meta:
                  '${r['study_date'] ?? ''}${chrono != null ? ' · ${t('flutter.chronological_age', 'Chronological age')} ${(chrono / 12).toStringAsFixed(1)}y' : ''}',
              trailing: delta == null
                  ? null
                  : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}y',
            );
          },
        ),
      ),
    );
  }
}

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
  void dispose() {
    for (final c in [_analyte, _value, _unit, _refLow, _refHigh]) {
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
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, err, t('medical.other_labs.add_btn'),
        t('flutter.not_saved', 'Not saved'));
    if (err == null) {
      _value.clear();
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
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy
                  ? t('flutter.saving', 'Saving…')
                  : t('medical.other_labs.add_btn', 'Add lab result')),
            ),
          ],
        ),
        history: _HistoryList(
          i18n: widget.i18n,
          items: widget.appState.labResults,
          onDelete: (r) =>
              widget.appState.deleteLabResult(r['lab_result_id']),
          rowBuilder: (r) {
            final low = (r['reference_low'] as num?)?.toDouble();
            final high = (r['reference_high'] as num?)?.toDouble();
            final value = (r['result_value'] as num?)?.toDouble() ?? 0;
            final flagged = (low != null && value < low) ||
                (high != null && value > high);
            return _TwoLine(
              title: '🧪 ${r['analyte_name'] ?? ''}',
              meta:
                  '${r['lab_date'] ?? ''}${low != null || high != null ? ' · ${low ?? '—'}–${high ?? '—'}' : ''}',
              trailing:
                  '${value % 1 == 0 ? value.toInt() : value} ${r['unit'] ?? ''}${flagged ? ' ⚠' : ''}',
            );
          },
        ),
      ),
    );
  }
}

// ── Illness log ─────────────────────────────────────────────────────

const illnessTypes = [
  'fever', 'cold', 'flu', 'ear', 'stomach', 'skin', 'injury', 'hospital',
];

class IllnessLogScreen extends StatefulWidget {
  const IllnessLogScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<IllnessLogScreen> createState() => _IllnessLogScreenState();
}

class _IllnessLogScreenState extends State<IllnessLogScreen> {
  String? _start;
  String? _end;
  String _type = 'fever';
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
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
    final err = await widget.appState.addIllnessEvent(
      startDate: _start!,
      endDate: _end,
      illnessType: _type,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, err, t('medical.illness.add_btn'),
        t('flutter.not_saved', 'Not saved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) => _ModuleScaffold(
        title: t('medical.illness.title', 'Development interference log'),
        entry: _EntryCard(
          title: t('medical.illness.add_btn', 'Add illness episode'),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: _dec(t('common.type', 'Type')),
              items: [
                for (final type in illnessTypes)
                  DropdownMenuItem(
                      value: type,
                      child: Text(t('medical.illness.type.$type', type),
                          style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 10),
            _DateButton(
              label: t('common.start_date', 'Start date'),
              value: _start,
              onChanged: (v) => setState(() => _start = v),
            ),
            const SizedBox(height: 8),
            _DateButton(
              label: t('medical.illness.end_date',
                  'End date (optional — leave blank if ongoing)'),
              value: _end,
              onChanged: (v) => setState(() => _end = v),
            ),
            const SizedBox(height: 10),
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
          rowBuilder: (r) => _TwoLine(
            title:
                '🤒 ${t('medical.illness.type.${r['illness_type']}', r['illness_type'] as String? ?? '')}',
            meta:
                '${r['start_date'] ?? ''} → ${r['end_date'] ?? t('flutter.ongoing', 'ongoing')}${r['notes'] != null ? ' · ${r['notes']}' : ''}',
          ),
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
