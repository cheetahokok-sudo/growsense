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
    final (rows, ready) = await HealthStoryRepo.fetch(widget.appState);
    if (!mounted) return;
    setState(() {
      _episodes = rows;
      _tablesReady = ready;
      _loading = false;
    });
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
    return Container(
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
        ],
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
