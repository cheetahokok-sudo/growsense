// ══════════════════════════════════════════════════════════════════
// Gap-fill card (Nutrition Recall Engine UI) — appears on Today when
// recent days are unlogged. Two modes, per the agreed estimation
// ladder:
//   - yesterday unlogged + day-before measured → one-tap relative
//     recall ("compared with <anchor>, they ate…");
//   - gaps 2–7 days back → typical-day pattern fill via a sheet.
// Everything it writes is gold/estimated, never blue; a parent's
// later manual edit of the day upgrades it through saveNutrition's
// manualEntryMeta tiering.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../recall_engine.dart';
import '../theme.dart';

class GapFillCard extends StatefulWidget {
  const GapFillCard({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<GapFillCard> createState() => _GapFillCardState();
}

class _GapFillCardState extends State<GapFillCard> {
  GapFillState? _state;
  String? _loadedChildId;
  bool _busy = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_maybeReload);
    _maybeReload();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_maybeReload);
    super.dispose();
  }

  Future<void> _maybeReload() async {
    final childId = widget.appState.activeChildId;
    if (childId == null || childId == _loadedChildId) return;
    _loadedChildId = childId;
    _dismissed = false;
    final s = await loadGapFillState(widget.appState.sb, childId);
    if (!mounted || childId != widget.appState.activeChildId) return;
    setState(() => _state = s);
  }

  Future<void> _reload() async {
    final childId = widget.appState.activeChildId;
    if (childId == null) return;
    final s = await loadGapFillState(widget.appState.sb, childId);
    if (!mounted) return;
    setState(() {
      _state = s;
      _busy = false;
    });
  }

  String _weekdayName(String date) {
    final wd = DateTime.parse(date).weekday; // 1 = Monday
    const fallbacks = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return widget.i18n.t('flutter.weekday.$wd', fallbacks[wd - 1]);
  }

  Future<void> _onRecall(RecallChoice choice) async {
    final s = _state;
    final childId = widget.appState.activeChildId;
    if (s?.recallDate == null || s?.anchorRow == null || childId == null) {
      return;
    }
    setState(() => _busy = true);
    final err = await applyRelativeRecall(
        widget.appState.sb, childId, s!.recallDate!, s.anchorRow!, choice);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.i18n.t('flutter.recall.saved_estimate',
              'Saved as estimate — tap any number on that day to correct it'))));
    }
    await _reload();
  }

  Future<void> _openFillSheet(String date) async {
    final s = _state;
    final childId = widget.appState.activeChildId;
    if (s == null || childId == null) return;
    final t = widget.i18n.t;
    final typical = s.typicalFor(date);
    if (typical == null) return;
    final adjustChips = <(RecallChoice, String)>[
      (RecallChoice.muchLess, t('flutter.recall.much_less', 'Much less')),
      (
        RecallChoice.slightlyLess,
        t('flutter.recall.slightly_less', 'A bit less')
      ),
      (RecallChoice.same, t('flutter.recall.same', 'About the same')),
      (
        RecallChoice.slightlyMore,
        t('flutter.recall.slightly_more', 'A bit more')
      ),
      (RecallChoice.muchMore, t('flutter.recall.much_more', 'Much more')),
    ];
    // Returns the chosen multiplier, or null for "leave empty".
    var choice = RecallChoice.same;
    double m() => recallMultipliers[choice]!;
    final multiplier = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: GsColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      t('flutter.recall.fill_title',
                          'Fill {day} with a typical day?',
                          {'day': _weekdayName(date)}),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      typical.weekdaySpecific
                          ? t('flutter.recall.based_on_weekday',
                              'Based on {n} logged {day}s', {
                              'n': '${typical.sampleDays}',
                              'day': _weekdayName(date)
                            })
                          : t('flutter.recall.based_on_days',
                              'Based on the last {n} logged days',
                              {'n': '${typical.sampleDays}'}),
                      style: const TextStyle(
                          fontSize: 12, color: GsColors.text2)),
                  const SizedBox(height: 12),
                  Text(
                      t('flutter.recall.vs_usual',
                          'Compared with usual, that day was…'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: GsColors.text2)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (c, label) in adjustChips)
                        _RecallChip(
                            label: label,
                            highlight: c == choice,
                            onTap: () => setSheetState(() => choice = c)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    _PreviewStat(
                        label: t('common.protein', 'Protein'),
                        value:
                            '~${(typical.totalProteinG * m()).round()} g'),
                    _PreviewStat(
                        label: t('common.calcium', 'Calcium'),
                        value: '~${(typical.calciumMg * m()).round()} mg'),
                    _PreviewStat(
                        label: t('flutter.fluids', 'Fluids'),
                        value:
                            '~${(typical.fluidsMl * m() / 1000).toStringAsFixed(1)} L'),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: GsColors.accent),
                        onPressed: () => Navigator.pop(context, m()),
                        child:
                            Text(t('flutter.recall.fill_day', 'Fill day')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                            t('flutter.recall.leave_empty', 'Leave empty')),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                      t('flutter.recall.estimate_note',
                          'Shown in gold as an estimate — never counted as measured data.'),
                      style: const TextStyle(
                          fontSize: 11, color: GsColors.estimatedDark)),
                ],
              ),
            );
        },
      ),
    );
    if (multiplier == null || !mounted) return;
    setState(() => _busy = true);
    final err = await applyPatternFill(
        widget.appState.sb, childId, date, typical,
        multiplier: multiplier);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final s = _state;
    if (s == null || !s.hasAnything || _dismissed) {
      return const SizedBox.shrink();
    }

    final recallChips = <(RecallChoice, String)>[
      (RecallChoice.muchLess, t('flutter.recall.much_less', 'Much less')),
      (
        RecallChoice.slightlyLess,
        t('flutter.recall.slightly_less', 'A bit less')
      ),
      (RecallChoice.same, t('flutter.recall.same', 'About the same')),
      (
        RecallChoice.slightlyMore,
        t('flutter.recall.slightly_more', 'A bit more')
      ),
      (RecallChoice.muchMore, t('flutter.recall.much_more', 'Much more')),
    ];

    // Only offer pattern fill when there's enough history to compute a
    // typical day; otherwise the card stays honest and offers nothing.
    final fillableGaps =
        s.olderGaps.where((d) => s.typicalFor(d) != null).toList();
    if (s.recallDate == null && fillableGaps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF5),
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.estimated.withValues(alpha: 0.35)),
      ),
      child: _busy
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.history_toggle_off,
                        size: 18, color: GsColors.estimated),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          s.recallDate != null
                              ? t('flutter.recall.forgot_yesterday',
                                  'Forgot to log yesterday?')
                              : t('flutter.recall.missing_days',
                                  'Some recent days are unlogged'),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: GsColors.estimatedDark)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _dismissed = true),
                      child: const Icon(Icons.close,
                          size: 16, color: GsColors.text3),
                    ),
                  ],
                ),
                if (s.recallDate != null) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 26),
                    child: Text(
                        t('flutter.recall.compared_with',
                            'Compared with {day}, they ate…',
                            {'day': _weekdayName(s.anchorDate!)}),
                        style: const TextStyle(
                            fontSize: 11.5, color: GsColors.text2)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (choice, label) in recallChips)
                        _RecallChip(
                            label: label,
                            highlight: choice == RecallChoice.same,
                            onTap: () => _onRecall(choice)),
                    ],
                  ),
                ],
                if (fillableGaps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final date in fillableGaps)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                t('flutter.recall.gap_day',
                                    '{day} is unlogged',
                                    {'day': _weekdayName(date)}),
                                style: const TextStyle(
                                    fontSize: 12, color: GsColors.text2)),
                          ),
                          GestureDetector(
                            onTap: () => _openFillSheet(date),
                            child: Text(
                                t('flutter.recall.fill_typical',
                                    'Fill with a typical day'),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: GsColors.accent)),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _RecallChip extends StatelessWidget {
  const _RecallChip(
      {required this.label, required this.onTap, this.highlight = false});
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: highlight ? GsColors.accentLight : GsColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: highlight
                  ? GsColors.accent.withValues(alpha: 0.4)
                  : GsColors.border2),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: highlight ? GsColors.accent : GsColors.text2)),
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GsColors.text2)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: GsColors.estimatedDark)),
        ],
      ),
    );
  }
}
