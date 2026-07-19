// ══════════════════════════════════════════════════════════════════
// Health Story — beta, Gate 1 (capture / read face only).
//
// Reads the existing illness_events for the active child and presents
// the Phase 0 "P0 · know-normal-first" face: a frequency count judged
// against the age-usual range, then the episode list. NO pattern flags
// (Gate 2), NO diagnosis. Every surface repeats the claim boundary:
// this is a record, not a diagnosis; an absence of concern is not a
// medical all-clear.
//
// Capture today reuses the existing "Development interference log";
// richer episode/temperature/medication capture is the next slice.
// See content/specs/health-story-pattern-engine.md
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'medical_modules.dart' show IllnessLogScreen;

class HealthStoryScreen extends StatelessWidget {
  const HealthStoryScreen({
    super.key,
    required this.appState,
    required this.i18n,
  });

  final AppState appState;
  final I18n i18n;

  /// Count of episodes whose start_date falls within the last 365 days.
  int _last12mCount() {
    final now = DateTime.now();
    var n = 0;
    for (final e in appState.illnessEvents) {
      final d = DateTime.tryParse((e['start_date'] ?? '').toString());
      if (d != null && now.difference(d).inDays <= 365 && !d.isAfter(now)) {
        n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final events = appState.illnessEvents;
    final count12 = _last12mCount();
    // P0 — age norm. Young children average ~6–8 colds/year, more in
    // daycare (Heikkinen 2003; Chonmaitree 2008). We use a generous
    // upper bound and only *gently* note above it — reassurance first.
    const usualUpper = 10;
    final withinRange = count12 <= usualUpper;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Health Story'),
            const SizedBox(width: 8),
            Container(
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
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _boundaryBanner(),
          const SizedBox(height: 14),
          _frequencyCard(count12, withinRange, usualUpper),
          const SizedBox(height: 20),
          _sectionLabel('Episodes'),
          const SizedBox(height: 6),
          if (events.isEmpty)
            _emptyState()
          else
            for (final e in events.reversed) _episodeRow(e),
          const SizedBox(height: 20),
          _addButton(context),
          const SizedBox(height: 14),
          _footNote(),
        ],
      ),
    );
  }

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
                'Health Story remembers your child’s illnesses over time '
                'so a pattern is easy to show a clinician.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.45, color: GsColors.text2),
              ),
            ),
          ],
        ),
      );

  Widget _frequencyCard(int count12, bool withinRange, int usualUpper) {
    final tint = withinRange ? GsColors.accentLight : GsColors.estimatedLight;
    final ink = withinRange ? GsColors.accentDark : GsColors.estimatedDark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
      ),
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
                : 'You’ve logged more than the usual ~6–10 a year. '
                    'That can be normal, but the count is worth mentioning to '
                    'your doctor.',
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
    final type = (e['illness_type'] ?? 'Illness').toString();
    final start = (e['start_date'] ?? '').toString();
    final end = (e['end_date'] ?? '').toString();
    final range = end.isNotEmpty && end != start ? '$start → $end' : start;
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
                Text(type,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (range.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(range,
                        style: const TextStyle(
                            fontSize: 11.5, color: GsColors.text3)),
                  ),
              ],
            ),
          ),
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
            Text('No illnesses logged yet',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text(
              'Log each illness while it’s fresh. Months later, the list '
              'tells a story a short appointment never could.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.45, color: GsColors.text2),
            ),
          ],
        ),
      );

  Widget _addButton(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => IllnessLogScreen(appState: appState, i18n: i18n),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Log an illness'),
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
