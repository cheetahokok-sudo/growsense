// ══════════════════════════════════════════════════════════════════
// Trust calendar — month view of nutrition data provenance, opened by
// tapping the Nutrition ring on Analytics. Answers exactly one
// question: "which days can I trust?" Values live one tap deeper in
// the day sheet.
//
// Cell states map 1:1 to the estimation ladder: measured solid blue >
// recalled light blue > estimated solid gold > rough fill pale gold >
// missing dashed outline (never red — red is clinical-flag only).
// "Looks right" promotes an estimate to recalled_manual at 0.85/0.7,
// never 1.0; "Correct this day" jumps to the Today editors via the
// onCorrectDay callback wired through home_shell.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../recall_engine.dart';
import '../theme.dart';

enum _DayTrust { measured, recalled, estimated, rough, missing, future }

class TrustCalendarScreen extends StatefulWidget {
  const TrustCalendarScreen({
    super.key,
    required this.appState,
    required this.i18n,
    this.lever = 'nutrition',
    this.onCorrectDay,
  });
  final AppState appState;
  final I18n i18n;

  /// Which lever's provenance to show: 'nutrition' | 'activity' |
  /// 'sleep'. Activity days aggregate their items — a day is only as
  /// trustworthy as its least-trusted item.
  final String lever;
  final void Function(String date)? onCorrectDay;

  @override
  State<TrustCalendarScreen> createState() => _TrustCalendarScreenState();
}

class _TrustCalendarScreenState extends State<TrustCalendarScreen> {
  late DateTime _month; // first day of the shown month
  Map<String, Map<String, dynamic>> _rows = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _load();
  }

  Future<void> _load() async {
    final childId = widget.appState.activeChildId;
    if (childId == null) return;
    setState(() => _loading = true);
    final first = localISO(_month);
    final last = localISO(DateTime(_month.year, _month.month + 1, 0));
    final sb = widget.appState.sb;
    Map<String, Map<String, dynamic>> byDate;
    switch (widget.lever) {
      case 'sleep':
        final rows = List<Map<String, dynamic>>.from(await sb
            .from('daily_sleep')
            .select('log_date, total_sleep_min, sleep_efficiency_score, '
                'estimation_method, confidence')
            .eq('child_id', childId)
            .gte('log_date', first)
            .lte('log_date', last));
        byDate = {for (final r in rows) r['log_date'] as String: r};
      case 'activity':
        final items = List<Map<String, dynamic>>.from(await sb
            .from('daily_activity_items')
            .select('log_date, duration_min, estimation_method, confidence')
            .eq('child_id', childId)
            .gte('log_date', first)
            .lte('log_date', last));
        // Aggregate items into one row per day. Trust is conservative:
        // any AI-estimated item makes the day estimated, and the day's
        // confidence is its weakest item's.
        byDate = {};
        for (final r in items) {
          final d = r['log_date'] as String;
          final agg = byDate.putIfAbsent(
              d,
              () => {
                    'count': 0,
                    'total_min': 0.0,
                    'estimation_method': kMeasured,
                    'confidence': 1.0,
                  });
          agg['count'] = (agg['count'] as int) + 1;
          agg['total_min'] = (agg['total_min'] as double) +
              ((r['duration_min'] as num?)?.toDouble() ?? 0);
          final m = r['estimation_method'] as String? ?? kMeasured;
          final c = (r['confidence'] as num?)?.toDouble() ?? 1.0;
          if (c < (agg['confidence'] as double)) agg['confidence'] = c;
          final cur = agg['estimation_method'] as String;
          if (m != kMeasured && m != kRecalledManual) {
            agg['estimation_method'] = m; // AI estimate dominates
          } else if (m == kRecalledManual && cur == kMeasured) {
            agg['estimation_method'] = kRecalledManual;
          }
        }
      default:
        final rows = List<Map<String, dynamic>>.from(await sb
            .from('daily_nutrition')
            .select('log_date, total_protein_g, calcium_mg, fluids_ml, '
                'estimation_method, confidence')
            .eq('child_id', childId)
            .gte('log_date', first)
            .lte('log_date', last));
        byDate = {for (final r in rows) r['log_date'] as String: r};
    }
    if (!mounted) return;
    setState(() {
      _rows = byDate;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;

  bool _hasValues(Map<String, dynamic> r) {
    switch (widget.lever) {
      case 'sleep':
        return _num(r['total_sleep_min']) > 0;
      case 'activity':
        return (r['count'] as int? ?? 0) > 0;
      default:
        return _num(r['total_protein_g']) > 0 ||
            _num(r['calcium_mg']) > 0 ||
            _num(r['fluids_ml']) > 0;
    }
  }

  _DayTrust _trustOf(String date) {
    final today = localISO(DateTime.now());
    if (date.compareTo(today) > 0) return _DayTrust.future;
    final r = _rows[date];
    if (r == null || !_hasValues(r)) return _DayTrust.missing;
    final method = r['estimation_method'] as String? ?? kMeasured;
    final conf = _num(r['confidence']);
    switch (method) {
      case kMeasured:
        return _DayTrust.measured;
      case kRecalledManual:
        return _DayTrust.recalled;
      default:
        return conf >= 0.35 ? _DayTrust.estimated : _DayTrust.rough;
    }
  }

  /// Month data quality: mean confidence over days that have data.
  int? _qualityPct() {
    final confs = <double>[
      for (final r in _rows.values)
        if (_hasValues(r)) _num(r['confidence']),
    ];
    if (confs.isEmpty) return null;
    return (confs.reduce((a, b) => a + b) / confs.length * 100).round();
  }

  String _provenance(Map<String, dynamic>? r) {
    final t = widget.i18n.t;
    if (r == null || !_hasValues(r)) {
      return t('flutter.trust.no_data', 'No data for this day');
    }
    switch (r['estimation_method'] as String? ?? kMeasured) {
      case kMeasured:
        return t('flutter.trust.src_measured', 'Logged on the day');
      case kRecalledManual:
        return t('flutter.trust.src_recalled',
            'Backfilled from memory by you');
      case kRelativeRecall:
        return t('flutter.trust.src_relative',
            'One-tap estimate vs the day before');
      case kPatternFill:
        return widget.lever == 'sleep'
            ? t('flutter.trust.src_pattern_sleep',
                "Filled from this child's typical nights")
            : t('flutter.trust.src_pattern',
                "Filled from this child's typical days");
      case kPatternSuggest:
        return t('flutter.trust.src_routine',
            'Confirmed from the usual routine — durations are typical');
      default:
        return t('flutter.trust.src_survey', 'Adjusted by weekly survey');
    }
  }

  Future<void> _openDaySheet(String date) async {
    final t = widget.i18n.t;
    final r = _rows[date];
    final trust = _trustOf(date);
    final conf = r == null ? 0.0 : _num(r['confidence']);
    final isEstimate =
        trust == _DayTrust.estimated || trust == _DayTrust.rough;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: GsColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_prettyDate(date),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                _TrustPill(trust: trust, confidence: conf, i18n: widget.i18n),
              ],
            ),
            const SizedBox(height: 2),
            Text(_provenance(r),
                style:
                    const TextStyle(fontSize: 12, color: GsColors.text2)),
            if (r != null && _hasValues(r)) ...[
              const SizedBox(height: 12),
              Row(children: [
                if (widget.lever == 'sleep') ...[
                  _Stat(
                      label: t('common.sleep', 'Sleep'),
                      value:
                          '${isEstimate ? '~' : ''}${(_num(r['total_sleep_min']) / 60).toStringAsFixed(1)} ${t('flutter.hours', 'hours')}'),
                  _Stat(
                      label: t('flutter.trust.efficiency', 'Efficiency'),
                      value:
                          '${_num(r['sleep_efficiency_score']).round()}%'),
                ] else if (widget.lever == 'activity') ...[
                  _Stat(
                      label: t('common.activity', 'Activity'),
                      value:
                          '${isEstimate ? '~' : ''}${_num(r['total_min']).round()} ${t('flutter.min', 'min')}'),
                  _Stat(
                      label: t('flutter.trust.items', 'Items'),
                      value: '${r['count']}'),
                ] else ...[
                  _Stat(
                      label: t('common.protein', 'Protein'),
                      value:
                          '${isEstimate ? '~' : ''}${_num(r['total_protein_g']).round()} g'),
                  _Stat(
                      label: t('common.calcium', 'Calcium'),
                      value:
                          '${isEstimate ? '~' : ''}${_num(r['calcium_mg']).round()} mg'),
                  _Stat(
                      label: t('flutter.fluids', 'Fluids'),
                      value:
                          '${isEstimate ? '~' : ''}${(_num(r['fluids_ml']) / 1000).toStringAsFixed(1)} L'),
                ],
              ]),
            ],
            if (isEstimate || trust == _DayTrust.missing) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: GsColors.bg,
                  borderRadius: BorderRadius.circular(GsRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.photo_library_outlined,
                        size: 15, color: GsColors.accent),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                          t('flutter.trust.photo_nudge',
                              'Your camera roll or chat photos from that day can jog memory — was there a party, a sick day, a restaurant?'),
                          style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: GsColors.text2)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [
              if (isEstimate)
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: GsColors.accent),
                    onPressed: () => Navigator.pop(context, 'confirm'),
                    child: Text(
                        t('flutter.trust.looks_right', '✓ Looks right')),
                  ),
                ),
              if (isEstimate) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'correct'),
                  child: Text(trust == _DayTrust.missing
                      ? t('flutter.trust.log_day', 'Log this day')
                      : t('flutter.trust.correct_day', 'Correct this day')),
                ),
              ),
            ]),
            if (isEstimate) ...[
              const SizedBox(height: 8),
              Text(
                  t('flutter.trust.promote_note',
                      '"Looks right" upgrades this to a recalled day. Corrections reopen the day\'s editor.'),
                  style: const TextStyle(
                      fontSize: 10.5, color: GsColors.text3)),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final childId = widget.appState.activeChildId;
    if (action == 'confirm' && childId != null) {
      final err = switch (widget.lever) {
        'sleep' => await confirmSleepEstimate(
            widget.appState.sb, childId, date),
        'activity' => await confirmActivityEstimates(
            widget.appState.sb, childId, date),
        _ => await confirmEstimate(widget.appState.sb, childId, date),
      };
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
      await _load();
    } else if (action == 'correct') {
      widget.onCorrectDay?.call(date);
    }
  }

  String _prettyDate(String date) {
    final d = DateTime.parse(date);
    const fallbacks = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final wd =
        widget.i18n.t('flutter.weekday.${d.weekday}', fallbacks[d.weekday - 1]);
    return '$wd · $date';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final quality = _qualityPct();
    final monthLabel =
        '${t('flutter.month.${_month.month}', _monthFallback(_month.month))} ${_month.year}';
    final firstWeekday = _month.weekday; // 1 = Monday
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final today = localISO(DateTime.now());
    final canGoForward = DateTime(_month.year, _month.month + 1, 1)
        .isBefore(DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: GsColors.surface,
            borderRadius: BorderRadius.circular(GsRadius.md),
            border: Border.all(color: GsColors.border),
            boxShadow: gsShadow,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                      onPressed: () => _shiftMonth(-1),
                      icon: const Icon(Icons.chevron_left, size: 20)),
                  Expanded(
                    child: Text(monthLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                      onPressed: canGoForward ? () => _shiftMonth(1) : null,
                      icon: const Icon(Icons.chevron_right, size: 20)),
                  if (quality != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: GsColors.measuredLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                          t('flutter.trust.quality', 'Quality {n}%',
                              {'n': '$quality'}),
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: GsColors.measuredDark)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  children: [
                    for (var w = 1; w <= 7; w++)
                      Center(
                        child: Text(
                            t('flutter.weekday_short.$w',
                                'MTWTFSS'[w - 1]),
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: GsColors.text3)),
                      ),
                    for (var i = 1; i < firstWeekday; i++)
                      const SizedBox.shrink(),
                    for (var day = 1; day <= daysInMonth; day++)
                      _DayCell(
                        day: day,
                        date: localISO(
                            DateTime(_month.year, _month.month, day)),
                        trust: _trustOf(localISO(
                            DateTime(_month.year, _month.month, day))),
                        isToday: localISO(DateTime(
                                _month.year, _month.month, day)) ==
                            today,
                        onTap: _openDaySheet,
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _LegendPill(
                label: t('flutter.trust.measured', 'Measured'),
                bg: GsColors.measured,
                fg: Colors.white),
            _LegendPill(
                label: t('flutter.trust.recalled', 'Recalled'),
                bg: GsColors.measuredLight,
                fg: GsColors.measuredDark),
            _LegendPill(
                label: t('flutter.trust.estimated', 'Estimated'),
                bg: GsColors.estimated,
                fg: Colors.white),
            _LegendPill(
                label: t('flutter.trust.rough', 'Rough fill'),
                bg: GsColors.estimatedLight,
                fg: GsColors.estimatedDark),
            _LegendPill(
                label: t('flutter.trust.missing', 'Missing'),
                bg: GsColors.surface,
                fg: GsColors.text3,
                dashed: true),
          ],
        ),
        const SizedBox(height: 10),
        Text(
            t('flutter.trust.footer',
                'Tap a day to see where its numbers came from, confirm an estimate, or correct it.'),
            style: const TextStyle(fontSize: 11.5, color: GsColors.text3)),
      ],
    );
  }

  static String _monthFallback(int m) => const [
        'January', 'February', 'March', 'April', 'May', 'June', 'July',
        'August', 'September', 'October', 'November', 'December',
      ][m - 1];
}

class _DayCell extends StatelessWidget {
  const _DayCell(
      {required this.day,
      required this.date,
      required this.trust,
      required this.isToday,
      required this.onTap});
  final int day;
  final String date;
  final _DayTrust trust;
  final bool isToday;
  final void Function(String date) onTap;

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (trust) {
      case _DayTrust.measured:
        bg = GsColors.measured;
        fg = Colors.white;
      case _DayTrust.recalled:
        bg = GsColors.measuredLight;
        fg = GsColors.measuredDark;
      case _DayTrust.estimated:
        bg = GsColors.estimated;
        fg = Colors.white;
      case _DayTrust.rough:
        bg = GsColors.estimatedLight;
        fg = GsColors.estimatedDark;
      case _DayTrust.missing:
        bg = Colors.transparent;
        fg = GsColors.text3;
      case _DayTrust.future:
        bg = Colors.transparent;
        fg = GsColors.text3.withValues(alpha: 0.35);
    }
    final cell = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: trust == _DayTrust.missing
            ? Border.all(color: GsColors.border2, width: 1.2)
            : isToday
                ? Border.all(color: GsColors.accent, width: 1.5)
                : null,
      ),
      alignment: Alignment.center,
      child: Text('$day',
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
    );
    if (trust == _DayTrust.future) return cell;
    return GestureDetector(onTap: () => onTap(date), child: cell);
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill(
      {required this.trust, required this.confidence, required this.i18n});
  final _DayTrust trust;
  final double confidence;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    String label;
    Color bg, fg;
    switch (trust) {
      case _DayTrust.measured:
        label = t('flutter.trust.measured', 'Measured');
        bg = GsColors.measuredLight;
        fg = GsColors.measuredDark;
      case _DayTrust.recalled:
        label =
            '${t('flutter.trust.recalled', 'Recalled')} · ${(confidence * 100).round()}%';
        bg = GsColors.measuredLight;
        fg = GsColors.measuredDark;
      case _DayTrust.estimated:
      case _DayTrust.rough:
        label =
            '${t('flutter.trust.estimated', 'Estimated')} · ${(confidence * 100).round()}%';
        bg = GsColors.estimatedLight;
        fg = GsColors.estimatedDark;
      default:
        label = t('flutter.trust.missing', 'Missing');
        bg = GsColors.surface2;
        fg = GsColors.text2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill(
      {required this.label,
      required this.bg,
      required this.fg,
      this.dashed = false});
  final String label;
  final Color bg, fg;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: dashed ? Border.all(color: GsColors.border2) : null,
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
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
                  color: GsColors.text)),
        ],
      ),
    );
  }
}
