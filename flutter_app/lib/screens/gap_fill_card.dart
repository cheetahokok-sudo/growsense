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
  String? _lastLogDate;
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
    // If we just filled the date currently open in the editors (e.g.
    // arrived here from the trust calendar), refresh the day view too.
    if (date == widget.appState.logDate) {
      await widget.appState.loadDay();
    }
    await _reload();
  }

  /// Days between [date] and today (positive = past).
  int _daysBack(String date) {
    final p = date.split('-').map(int.parse).toList();
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(p[0], p[1], p[2]))
        .inDays;
  }

  /// The date currently open in the Today editors is a past day with
  /// no nutrition data — the card should offer to fill exactly it.
  bool get _selectedDayEmpty {
    final a = widget.appState;
    if (a.loadingDay) return false;
    final n = a.nutrition;
    double v(String c) => (n?[c] as num?)?.toDouble() ?? 0;
    final hasRow = n != null &&
        (v('total_protein_g') > 0 || v('calcium_mg') > 0 || v('fluids_ml') > 0);
    return !hasRow && a.nutritionLogItems.isEmpty;
  }

  bool get _selectedActivityEmpty =>
      !widget.appState.loadingDay && widget.appState.activityItems.isEmpty;

  bool get _selectedSleepEmpty =>
      !widget.appState.loadingDay && widget.appState.sleep == null;

  /// Routine-recognition sheet: the engine mines what the child
  /// usually does on this weekday ("tennis most Fridays") and the
  /// parent confirms concrete items by recognition.
  Future<void> _openActivitySheet(String date) async {
    final t = widget.i18n.t;
    final childId = widget.appState.activeChildId;
    if (childId == null) return;
    setState(() => _busy = true);
    final suggestions =
        await loadActivitySuggestions(widget.appState.sb, childId, date);
    if (!mounted) return;
    setState(() => _busy = false);
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('flutter.recall.no_routine',
              'No routine found yet — a few weeks of activity logs teach the engine.'))));
      return;
    }
    final selected = {for (var i = 0; i < suggestions.length; i++) i};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: GsColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  t('flutter.recall.activity_title',
                      'What did {day} usually look like?',
                      {'day': _weekdayName(date)}),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  t('flutter.recall.activity_sub',
                      'From the last 8 weeks of logs — untick anything that didn\'t happen.'),
                  style:
                      const TextStyle(fontSize: 12, color: GsColors.text2)),
              const SizedBox(height: 10),
              for (var i = 0; i < suggestions.length; i++)
                CheckboxListTile(
                  value: selected.contains(i),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: GsColors.measured,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => setSheetState(() =>
                      v == true ? selected.add(i) : selected.remove(i)),
                  title: Text(suggestions[i].displayName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${suggestions[i].medianDurationMin.round()} ${t('flutter.min', 'min')} · ${suggestions[i].isWeekdayRoutine ? t('flutter.recall.most_weekday', 'most {day}s', {
                          'day': _weekdayName(date)
                        }) : t('flutter.recall.most_days', 'most days')}',
                      style: const TextStyle(
                          fontSize: 11, color: GsColors.text3)),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: GsColors.measured),
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, true),
                    child: Text(t('flutter.recall.log_n_activities',
                        'Log {n} activities', {'n': '${selected.length}'})),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child:
                        Text(t('flutter.recall.leave_empty', 'Leave empty')),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                  t('flutter.recall.activity_note',
                      'Saved as confirmed routine — durations are typical, so it counts as an estimate, not measured data.'),
                  style: const TextStyle(
                      fontSize: 10.5, color: GsColors.estimatedDark)),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final picked = [
      for (var i = 0; i < suggestions.length; i++)
        if (selected.contains(i)) suggestions[i]
    ];
    final err = await applyActivitySuggestions(
        widget.appState.sb, childId, date, picked);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
    if (date == widget.appState.logDate) await widget.appState.loadDay();
    await _reload();
  }

  /// Typical-night sheet with the gentler sleep "vs usual" bands.
  Future<void> _openSleepSheet(String date) async {
    final t = widget.i18n.t;
    final childId = widget.appState.activeChildId;
    if (childId == null) return;
    setState(() => _busy = true);
    final typical = await loadTypicalNight(widget.appState.sb, childId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (typical == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('flutter.recall.no_sleep_history',
              'Not enough sleep history yet to estimate a night.'))));
      return;
    }
    final chips = <(RecallChoice, String)>[
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
    var choice = RecallChoice.same;
    double m() => sleepMultipliers[choice]!;
    final multiplier = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: GsColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  t('flutter.recall.sleep_title',
                      'How was {day} night compared with usual?',
                      {'day': _weekdayName(date)}),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  t('flutter.recall.sleep_sub',
                      'Usual night: {h} h over the last {n} logged nights', {
                    'h': (typical.totalSleepMin / 60).toStringAsFixed(1),
                    'n': '${typical.sampleNights}'
                  }),
                  style:
                      const TextStyle(fontSize: 12, color: GsColors.text2)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (c, label) in chips)
                    _RecallChip(
                        label: label,
                        highlight: c == choice,
                        onTap: () => setSheetState(() => choice = c)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                  '~${(typical.totalSleepMin * m() / 60).toStringAsFixed(1)} ${t('flutter.hours', 'hours')}',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: GsColors.estimatedDark)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: GsColors.estimated),
                    onPressed: () => Navigator.pop(context, m()),
                    child:
                        Text(t('flutter.recall.fill_night', 'Fill night')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child:
                        Text(t('flutter.recall.leave_empty', 'Leave empty')),
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
        ),
      ),
    );
    if (multiplier == null || !mounted) return;
    setState(() => _busy = true);
    final err = await applySleepFill(
        widget.appState.sb, childId, date, typical, multiplier);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
    if (date == widget.appState.logDate) await widget.appState.loadDay();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    // Arriving on a different date (date arrows or the trust
    // calendar's "Log/Correct this day") is fresh intent — undo any
    // earlier dismissal so the selected-date offer can show.
    if (widget.appState.logDate != _lastLogDate) {
      _lastLogDate = widget.appState.logDate;
      _dismissed = false;
    }
    final s = _state;
    // NOTE: do not gate on s.hasAnything here — the selected-date
    // offer below must render even when there are no auto-detected
    // recent gaps. The combined visibility check happens after it is
    // computed.
    if (s == null || _dismissed) {
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

    // Selected-date fill: the parent navigated to a specific past day
    // (date arrows or the trust calendar). Within the 7-day estimate
    // cap the same fill sheet applies; beyond it, stay honest — no
    // median fill, manual logging only (saved as recalled).
    final selDate = widget.appState.logDate;
    final selBack = _daysBack(selDate);
    final selInWindow = selBack >= 1 && selBack <= 7;
    final selEmpty = selBack >= 1 && _selectedDayEmpty;
    final selFillable =
        selEmpty && selBack <= 7 && s.typicalFor(selDate) != null;
    final selTooOld = selEmpty && selBack > 7;
    // Phase 2 levers, same window: activity via routine recognition,
    // sleep via typical-night fill.
    final selActivity = selInWindow && _selectedActivityEmpty;
    final selSleep = selInWindow && _selectedSleepEmpty;

    // Only offer pattern fill when there's enough history to compute a
    // typical day; otherwise the card stays honest and offers nothing.
    // The selected date gets its own row above, so keep it out of the
    // generic gap list.
    final fillableGaps = s.olderGaps
        .where((d) => d != selDate && s.typicalFor(d) != null)
        .toList();
    if (s.recallDate == null &&
        fillableGaps.isEmpty &&
        !selFillable &&
        !selTooOld &&
        !selActivity &&
        !selSleep) {
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
                              : (selFillable ||
                                          selTooOld ||
                                          selActivity ||
                                          selSleep) &&
                                      fillableGaps.isEmpty
                                  ? t('flutter.recall.this_day_unlogged',
                                      'This day is unlogged')
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
                // The day currently open in the editors, front and
                // centre — this is what the parent navigated to.
                if (selFillable && selDate != s.recallDate) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: GsColors.estimatedLight,
                      borderRadius: BorderRadius.circular(GsRadius.sm),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                              t('flutter.recall.selected_day_empty',
                                  '{day} · {date} has no food log', {
                                'day': _weekdayName(selDate),
                                'date': selDate
                              }),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: GsColors.estimatedDark)),
                        ),
                        GestureDetector(
                          onTap: () => _openFillSheet(selDate),
                          child: Text(
                              t('flutter.recall.fill_typical',
                                  'Fill with a typical day'),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: GsColors.accent)),
                        ),
                      ],
                    ),
                  ),
                ],
                if (selTooOld) ...[
                  const SizedBox(height: 8),
                  Text(
                      t('flutter.recall.too_old',
                          'This day is too far back for an estimate. Log what you remember below — it will be saved as a recalled day.'),
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: GsColors.text2)),
                ],
                if (selActivity)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                              t('flutter.recall.activity_unlogged',
                                  'No activity logged'),
                              style: const TextStyle(
                                  fontSize: 12, color: GsColors.text2)),
                        ),
                        GestureDetector(
                          onTap: () => _openActivitySheet(selDate),
                          child: Text(
                              t('flutter.recall.review_routine',
                                  'Review the usual routine'),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: GsColors.measured)),
                        ),
                      ],
                    ),
                  ),
                if (selSleep)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                              t('flutter.recall.sleep_unlogged',
                                  'Sleep unlogged'),
                              style: const TextStyle(
                                  fontSize: 12, color: GsColors.text2)),
                        ),
                        GestureDetector(
                          onTap: () => _openSleepSheet(selDate),
                          child: Text(
                              t('flutter.recall.fill_typical_night',
                                  'Fill a typical night'),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: GsColors.estimatedDark)),
                        ),
                      ],
                    ),
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
