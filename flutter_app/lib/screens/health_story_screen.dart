// ══════════════════════════════════════════════════════════════════
// Health Story — beta, Gate 1 (capture / read face).
//
// Reads illness_episodes for the active child and shows the Phase 0
// "P0 · know-normal-first" face: a 12-month frequency judged against
// the age-usual range, then the episode list. A guided capture form
// adds an episode. NO pattern flags (Gate 2), NO diagnosis generated —
// the doctor's verdict is only ever entered by the parent. Every
// surface repeats the claim boundary.
// See content/specs/health-story-pattern-engine.md
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../health_story.dart';
import '../i18n.dart';
import '../theme.dart';

class HealthStoryScreen extends StatefulWidget {
  const HealthStoryScreen({
    super.key,
    required this.appState,
    required this.i18n,
  });

  final AppState appState;
  final I18n i18n;

  @override
  State<HealthStoryScreen> createState() => _HealthStoryScreenState();
}

class _HealthStoryScreenState extends State<HealthStoryScreen> {
  List<Map<String, dynamic>> _episodes = [];
  bool _loading = true;
  bool _tablesReady = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Never let an unexpected error strand the spinner.
    try {
      final (rows, ready) = await HealthStoryRepo.fetch(widget.appState);
      if (!mounted) return;
      setState(() {
        _episodes = rows;
        _tablesReady = ready;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _episodes = [];
        _tablesReady = false;
        _loading = false;
      });
    }
  }

  int _last12mCount() {
    final now = DateTime.now();
    var n = 0;
    for (final e in _episodes) {
      final d = DateTime.tryParse((e['onset_date'] ?? '').toString());
      if (d != null && !d.isAfter(now) && now.difference(d).inDays <= 365) n++;
    }
    return n;
  }

  Future<void> _addEpisode() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EpisodeCaptureScreen(appState: widget.appState),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final count12 = _last12mCount();
    const usualUpper = 10;
    final withinRange = count12 <= usualUpper;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Health Story'),
            const SizedBox(width: 8),
            _betaChip(),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _boundaryBanner(),
                const SizedBox(height: 14),
                if (!_tablesReady) ...[
                  _setupNote(),
                  const SizedBox(height: 14),
                ],
                _frequencyCard(count12, withinRange),
                const SizedBox(height: 20),
                _sectionLabel('Episodes'),
                const SizedBox(height: 6),
                if (_episodes.isEmpty)
                  _emptyState()
                else
                  for (final e in _episodes) _episodeRow(e),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _addEpisode,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Log an illness'),
                  ),
                ),
                const SizedBox(height: 14),
                _footNote(),
              ],
            ),
    );
  }

  Widget _betaChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: GsColors.estimatedLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('beta',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: GsColors.estimatedDark)),
      );

  Widget _boundaryBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GsColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GsColors.border),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 17, color: GsColors.text2),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'A record for you and your doctor — not a diagnosis. '
                'Health Story remembers your child’s illnesses over time so '
                'a pattern is easy to show a clinician.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.45, color: GsColors.text2),
              ),
            ),
          ],
        ),
      );

  Widget _setupNote() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GsColors.estimatedLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Setup pending: the Health Story tables aren’t in Supabase yet. '
          'Apply 2026-07-19_health_story_episodes.sql, then reopen. '
          '(Logging will fail until then.)',
          style: TextStyle(
              fontSize: 12, height: 1.45, color: GsColors.estimatedDark),
        ),
      );

  Widget _frequencyCard(int count12, bool withinRange) {
    final tint = withinRange ? GsColors.accentLight : GsColors.estimatedLight;
    final ink = withinRange ? GsColors.accentDark : GsColors.estimatedDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration:
          BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Illnesses in the last 12 months',
              style: TextStyle(fontSize: 12.5, color: ink)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$count12',
                  style: TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w600, color: ink)),
              const SizedBox(width: 8),
              Text(withinRange ? 'within the usual range' : 'worth a mention',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            withinRange
                ? 'About 6–10 a year is usual for a young child (more in '
                    'daycare). This looks typical — nothing here needs a '
                    'doctor visit on its own.'
                : 'You’ve logged more than the usual ~6–10 a year. That can '
                    'be normal, but the count is worth mentioning to your '
                    'doctor.',
            style: TextStyle(fontSize: 11.5, height: 1.45, color: ink),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String s) => Text(
        s.toUpperCase(),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: GsColors.text3),
      );

  Widget _episodeRow(Map<String, dynamic> e) {
    final system = (e['primary_system'] ?? '').toString();
    final label = kPrimarySystemLabels[system] ?? 'Illness';
    final onset = (e['onset_date'] ?? '').toString();
    final resolved = (e['resolved_date'] ?? '').toString();
    final status = (e['status'] ?? '').toString();
    final range =
        resolved.isNotEmpty && resolved != onset ? '$onset → $resolved' : onset;
    final diagnosis = (e['diagnosis'] ?? '').toString();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                EpisodeDetailScreen(appState: widget.appState, episode: e),
          ),
        );
        if (mounted) _load();
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: GsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GsColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.sick_outlined, size: 18, color: GsColors.text2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (range.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                          diagnosis.isNotEmpty ? '$range · $diagnosis' : range,
                          style: const TextStyle(
                              fontSize: 11.5, color: GsColors.text3)),
                    ),
                ],
              ),
            ),
            if (status == 'resolved')
              const Icon(Icons.check_circle_outline,
                  size: 16, color: GsColors.accent)
            else if (status == 'active')
              Text('active',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: GsColors.estimatedDark)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: GsColors.text3),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: GsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GsColors.border),
        ),
        child: const Column(
          children: [
            Icon(Icons.history_edu_outlined, size: 30, color: GsColors.text3),
            SizedBox(height: 8),
            Text('No episodes yet',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text(
              'Log each illness while it’s fresh. Months later, the list '
              'tells a story a short appointment never could.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12, height: 1.45, color: GsColors.text2),
            ),
          ],
        ),
      );

  Widget _footNote() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          'Beta · a reassuring count is not a medical all-clear. If your '
          'child is unwell or growing slowly, always speak with a doctor.',
          style: TextStyle(fontSize: 11, height: 1.45, color: GsColors.text3),
        ),
      );
}

// ── Guided capture ───────────────────────────────────────────────────

class EpisodeCaptureScreen extends StatefulWidget {
  const EpisodeCaptureScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<EpisodeCaptureScreen> createState() => _EpisodeCaptureScreenState();
}

class _EpisodeCaptureScreenState extends State<EpisodeCaptureScreen> {
  String? _system;
  DateTime _onset = DateTime.now();
  final Set<String> _symptoms = {};
  final _tempCtrl = TextEditingController();
  String? _tempRoute;
  final _medCtrl = TextEditingController();
  String? _medClass;
  String? _medResponse;
  String _careSought = 'none';
  bool _saving = false;

  @override
  void dispose() {
    _tempCtrl.dispose();
    _medCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_system == null) {
      _snack('Pick the main thing first');
      return;
    }
    setState(() => _saving = true);
    final tempC = double.tryParse(_tempCtrl.text.trim());
    final err = await HealthStoryRepo.create(
      widget.appState,
      primarySystem: _system!,
      onsetDate: _onset,
      careSought: _careSought,
      symptoms: _symptoms.toList(),
      tempC: tempC,
      tempRoute: _tempRoute,
      medName: _medCtrl.text,
      medClass: _medClass,
      medResponse: _medResponse,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      _snack(err);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final showFever = _system == 'febrile' || _symptoms.contains('fever');
    final breathingFlag = _symptoms.contains('breathing_difficulty');
    return Scaffold(
      appBar: AppBar(title: const Text('Log an illness')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        children: [
          _q('What’s the main thing you’re noticing?'),
          _chips(
            kPrimarySystemLabels.keys.toList(),
            (k) => kPrimarySystemLabels[k]!,
            selected: (k) => _system == k,
            onTap: (k) => setState(() => _system = k),
          ),
          const SizedBox(height: 20),
          _q('When did it start?'),
          _dateRow(),
          const SizedBox(height: 20),
          _q('Symptoms (tap any that apply)'),
          _chips(
            kSymptomLabels.keys.toList(),
            (k) => kSymptomLabels[k]!,
            selected: _symptoms.contains,
            onTap: (k) => setState(
                () => _symptoms.contains(k) ? _symptoms.remove(k) : _symptoms.add(k)),
            warnKeys: const {'breathing_difficulty'},
          ),
          if (breathingFlag) ...[
            const SizedBox(height: 10),
            _safetyBanner(),
          ],
          if (showFever) ...[
            const SizedBox(height: 20),
            _q('Temperature (optional)'),
            _tempRow(),
          ],
          const SizedBox(height: 20),
          _q('Medicine given (optional)'),
          _medBlock(),
          const SizedBox(height: 20),
          _q('Did you seek care?'),
          _chips(
            const ['none', 'pharmacy', 'gp', 'er'],
            (k) => const {
              'none': 'Not yet',
              'pharmacy': 'Pharmacy',
              'gp': 'GP',
              'er': 'Hospital / ER'
            }[k]!,
            selected: (k) => _careSought == k,
            onTap: (k) => setState(() => _careSought = k),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save episode'),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'A record for your doctor — not a diagnosis. The doctor’s '
            'verdict is only ever what you enter from them.',
            style: TextStyle(fontSize: 11, height: 1.45, color: GsColors.text3),
          ),
        ],
      ),
    );
  }

  Widget _q(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(s,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      );

  Widget _chips(
    List<String> keys,
    String Function(String) label, {
    required bool Function(String) selected,
    required void Function(String) onTap,
    Set<String> warnKeys = const {},
  }) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in keys)
            _Chip(
              label: label(k),
              selected: selected(k),
              warn: warnKeys.contains(k),
              onTap: () => onTap(k),
            ),
        ],
      );

  Widget _dateRow() {
    final iso = _onset.toIso8601String().substring(0, 10);
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text(iso),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _onset,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now(),
        );
        if (picked != null) setState(() => _onset = picked);
      },
    );
  }

  Widget _tempRow() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _tempCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '38.9',
                    suffixText: '°C',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _chips(
            const ['tympanic', 'axillary', 'oral', 'forehead'],
            (k) => const {
              'tympanic': 'Ear',
              'axillary': 'Armpit',
              'oral': 'Mouth',
              'forehead': 'Forehead'
            }[k]!,
            selected: (k) => _tempRoute == k,
            onTap: (k) => setState(() => _tempRoute = k),
          ),
        ],
      );

  Widget _medBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _medCtrl,
            decoration: const InputDecoration(
              hintText: 'e.g. Salbutamol, Paracetamol',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          _chips(
            const [
              'antipyretic',
              'antibiotic',
              'bronchodilator',
              'antihistamine',
              'steroid',
              'other'
            ],
            (k) => k[0].toUpperCase() + k.substring(1),
            selected: (k) => _medClass == k,
            onTap: (k) => setState(() => _medClass = k),
          ),
          const SizedBox(height: 10),
          _chips(
            const ['improved', 'no_change', 'worsened'],
            (k) => const {
              'improved': 'Improved after',
              'no_change': 'No change',
              'worsened': 'Worsened'
            }[k]!,
            selected: (k) => _medResponse == k,
            onTap: (k) => setState(() => _medResponse = k),
          ),
        ],
      );

  Widget _safetyBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: GsColors.flagLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GsColors.flag),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: GsColors.flag),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Fast or laboured breathing needs same-day medical attention. '
                'Log it here, but contact a doctor now if you haven’t.',
                style: TextStyle(
                    fontSize: 12, height: 1.45, color: GsColors.flagDark),
              ),
            ),
          ],
        ),
      );
}

// ── Episode detail ───────────────────────────────────────────────────

class EpisodeDetailScreen extends StatefulWidget {
  const EpisodeDetailScreen({
    super.key,
    required this.appState,
    required this.episode,
  });
  final AppState appState;
  final Map<String, dynamic> episode;

  @override
  State<EpisodeDetailScreen> createState() => _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState extends State<EpisodeDetailScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _symptoms = [];
  List<Map<String, dynamic>> _temps = [];
  List<Map<String, dynamic>> _meds = [];
  List<Map<String, dynamic>> _childMeds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = widget.episode['episode_id'];
      final (sy, tp, md) = await HealthStoryRepo.fetchDetail(widget.appState, id as Object);
      final cm = await HealthStoryRepo.fetchChildMedications(widget.appState);
      if (!mounted) return;
      setState(() {
        _symptoms = sy;
        _temps = tp;
        _meds = md;
        _childMeds = cm;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  double? _peakTemp() {
    double? peak;
    for (final t in _temps) {
      final v = (t['temp_c'] as num?)?.toDouble();
      if (v != null && (peak == null || v > peak)) peak = v;
    }
    return peak;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    final system = (e['primary_system'] ?? '').toString();
    final label = kPrimarySystemLabels[system] ?? 'Illness';
    final onset = (e['onset_date'] ?? '').toString();
    final resolved = (e['resolved_date'] ?? '').toString();
    final status = (e['status'] ?? '').toString();
    final care = (e['care_sought'] ?? 'none').toString();
    final diagnosis = (e['diagnosis'] ?? '').toString();
    final peak = _peakTemp();
    final abxCount =
        _childMeds.where((m) => m['med_class'] == 'antibiotic').length;
    final hasAntihistamine =
        _childMeds.any((m) => m['med_class'] == 'antihistamine');

    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                _card([
                  _kv('Onset',
                      resolved.isNotEmpty && resolved != onset
                          ? '$onset → $resolved'
                          : onset),
                  _kv('Status', status.isEmpty ? '—' : status),
                  if (peak != null)
                    _kv('Peak fever', '${peak.toStringAsFixed(1)} °C',
                        color: GsColors.estimatedDark),
                  _kv('Care', _careLabel(care)),
                  if (diagnosis.isNotEmpty)
                    _kv('Diagnosis (from doctor)', diagnosis,
                        color: GsColors.measuredDark),
                ]),
                if (_temps.isNotEmpty) ...[
                  _label('Temperatures'),
                  for (final t in _temps) _tempRow(t),
                ],
                if (_symptoms.isNotEmpty) ...[
                  _label('Symptoms'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _symptoms)
                        _tag(kSymptomLabels[(s['symptom'] ?? '').toString()] ??
                            (s['symptom'] ?? '').toString()),
                    ],
                  ),
                ],
                if (_meds.isNotEmpty) ...[
                  _label('Medicines given → response'),
                  for (final m in _meds) _medRow(m),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '“Improved after” is a timing note — not proof the '
                      'medicine caused it.',
                      style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                          color: GsColors.text3),
                    ),
                  ),
                ],
                if (abxCount > 0 || hasAntihistamine) ...[
                  const SizedBox(height: 16),
                  _cumulativeCard(abxCount, hasAntihistamine),
                ],
                const SizedBox(height: 16),
                const Text(
                  'A record for your doctor — not a diagnosis.',
                  style: TextStyle(
                      fontSize: 11, height: 1.4, color: GsColors.text3),
                ),
              ],
            ),
    );
  }

  String _careLabel(String c) =>
      const {
        'none': 'Not sought',
        'pharmacy': 'Pharmacy',
        'gp': 'GP',
        'er': 'Hospital / ER',
        'admitted': 'Admitted',
      }[c] ??
      c;

  Widget _card(List<Widget> rows) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: GsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GsColors.border),
        ),
        child: Column(children: rows),
      );

  Widget _kv(String k, String v, {Color color = GsColors.text}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: const TextStyle(fontSize: 12, color: GsColors.text3)),
            const Spacer(),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ),
          ],
        ),
      );

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: GsColors.text3)),
      );

  Widget _tempRow(Map<String, dynamic> t) {
    final v = (t['temp_c'] as num?)?.toDouble();
    final route = (t['route'] ?? '').toString();
    final at = (t['measured_at'] ?? '').toString();
    final when = at.length >= 16 ? at.substring(0, 16).replaceFirst('T', ' ') : at;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(v == null ? '—' : '${v.toStringAsFixed(1)} °C',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          if (route.isNotEmpty)
            Text(route, style: const TextStyle(fontSize: 11.5, color: GsColors.text3)),
          const Spacer(),
          Text(when, style: const TextStyle(fontSize: 11, color: GsColors.text3)),
        ],
      ),
    );
  }

  Widget _tag(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: GsColors.surface2,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(s,
            style: const TextStyle(fontSize: 12, color: GsColors.text2)),
      );

  Widget _medRow(Map<String, dynamic> m) {
    final name = (m['medication'] ?? '').toString();
    final cls = (m['med_class'] ?? '').toString();
    final resp = (m['response'] ?? '').toString();
    final dose = (m['dose_amount'] as num?)?.toString();
    final unit = (m['dose_unit'] ?? '').toString();
    final freq = (m['frequency'] ?? '').toString();
    final respLabel = const {
      'improved': 'Improved after',
      'no_change': 'No change',
      'worsened': 'Worsened',
      'resolved': 'Resolved',
    }[resp];
    final sub = [
      if (dose != null) '$dose${unit.isNotEmpty ? ' $unit' : ''}',
      if (freq.isNotEmpty) freq,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (cls.isNotEmpty) ...[
                const SizedBox(width: 6),
                _tag(cls),
              ],
              const Spacer(),
              if (respLabel != null)
                Text(respLabel,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: GsColors.accentDark)),
            ],
          ),
          if (sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sub,
                  style:
                      const TextStyle(fontSize: 11, color: GsColors.text3)),
            ),
        ],
      ),
    );
  }

  Widget _cumulativeCard(int abxCount, bool hasAntihistamine) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: GsColors.estimatedLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('LIFETIME EXPOSURE · ALL EPISODES',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: GsColors.estimatedDark)),
            const SizedBox(height: 6),
            if (abxCount > 0)
              _kv('Antibiotic courses', '$abxCount',
                  color: GsColors.estimatedDark),
            if (hasAntihistamine)
              _kv('Antihistamines', 'given', color: GsColors.estimatedDark),
            const SizedBox(height: 6),
            const Text(
              'Counts only — worth reviewing with your doctor. Most '
              'childhood infections are viral, so an antibiotic “working” '
              'isn’t proof it was needed.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: GsColors.estimatedDark),
            ),
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.warn = false,
  });
  final String label;
  final bool selected;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg, border, fg;
    if (selected && warn) {
      bg = GsColors.flagLight;
      border = GsColors.flag;
      fg = GsColors.flagDark;
    } else if (selected) {
      bg = GsColors.accentLight;
      border = GsColors.accent;
      fg = GsColors.accentDark;
    } else {
      bg = GsColors.surface;
      border = GsColors.border2;
      fg = GsColors.text2;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: selected ? 1.4 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: fg)),
      ),
    );
  }
}
