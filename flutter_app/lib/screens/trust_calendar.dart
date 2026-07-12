// ══════════════════════════════════════════════════════════════════
// Trust calendar — unified month view of all three levers, opened by
// tapping the date on Today or a lever ring on Analytics. Answers the
// backfilling parent's question in one glance: "which days need me?"
//
// Each day cell stacks three dot+bar rows in fixed order — nutrition,
// activity, sleep. The DOT carries provenance (the estimation ladder:
// measured solid blue > recalled light blue > estimated gold > rough
// pale gold > missing hollow) and the BAR carries magnitude as % of
// that lever's daily target, tinted with the same trust colour so no
// new colours enter the system. Attention = a past day with any lever
// missing → soft gold outline ("needs your memory"); red stays
// reserved for clinical flags only, never missing data.
//
// Tap a day → day sheet with all three levers. "Looks right" promotes
// every estimated lever that day to recalled_manual at 0.85/0.7,
// never 1.0; "Log / Correct this day" jumps to the Today editors via
// the onCorrectDay callback (home_shell tab-jump, or setLogDate+pop
// when opened from the Today date selector).
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../activity_data.dart';
import '../analytics.dart' show calcProteinTargetG, calcSleepTargetMin;
import '../app_state.dart';
import '../i18n.dart';
import '../recall_engine.dart';
import '../theme.dart';

// Future days carry no trust state — the grid renders them inert via
// the cell's isFuture flag instead of a ladder rung.
enum _DayTrust { measured, recalled, estimated, rough, missing }

/// One lever's state for one day: provenance + % of daily target +
/// the raw numbers the day sheet shows.
class _LeverDay {
  _DayTrust trust = _DayTrust.missing;
  double pct = 0; // 0..1 of the lever's daily target
  double confidence = 0;
  String method = kMeasured;
  Map<String, double> raw = {};
}

class _DayData {
  final _LeverDay nut = _LeverDay();
  final _LeverDay act = _LeverDay();
  final _LeverDay slp = _LeverDay();
  List<_LeverDay> get levers => [nut, act, slp];
}

class TrustCalendarScreen extends StatefulWidget {
  const TrustCalendarScreen({
    super.key,
    required this.appState,
    required this.i18n,
    this.onCorrectDay,
  });
  final AppState appState;
  final I18n i18n;
  final void Function(String date)? onCorrectDay;

  @override
  State<TrustCalendarScreen> createState() => _TrustCalendarScreenState();
}

class _TrustCalendarScreenState extends State<TrustCalendarScreen> {
  late DateTime _month; // first day of the shown month
  Map<String, _DayData> _days = {};
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

    final results = await Future.wait([
      sb
          .from('daily_nutrition')
          .select('log_date, total_protein_g, calcium_mg, fluids_ml, '
              'estimation_method, confidence')
          .eq('child_id', childId)
          .gte('log_date', first)
          .lte('log_date', last),
      sb
          .from('daily_activity_items')
          .select('log_date, duration_min, tier, estimation_method, '
              'confidence')
          .eq('child_id', childId)
          .gte('log_date', first)
          .lte('log_date', last),
      sb
          .from('daily_sleep')
          .select('log_date, total_sleep_min, sleep_efficiency_score, '
              'estimation_method, confidence')
          .eq('child_id', childId)
          .gte('log_date', first)
          .lte('log_date', last),
    ]);

    // Targets from the active child — same sources Analytics uses.
    final child = widget.appState.activeChildRow;
    final dob = child?['date_of_birth'] as String?;
    final sex = child?['biological_sex'] as String?;
    final proteinTarget = calcProteinTargetG(dob, null, sex).toDouble();
    final sleepTarget = calcSleepTargetMin(dob).toDouble();

    double numOf(dynamic v) => (v as num?)?.toDouble() ?? 0;
    final days = <String, _DayData>{};
    _DayData dayOf(String d) => days.putIfAbsent(d, _DayData.new);
    _DayTrust ladder(String method, double conf) => switch (method) {
          kMeasured => _DayTrust.measured,
          kRecalledManual => _DayTrust.recalled,
          _ => conf >= 0.35 ? _DayTrust.estimated : _DayTrust.rough,
        };

    for (final r in List<Map<String, dynamic>>.from(results[0])) {
      final protein = numOf(r['total_protein_g']);
      final calcium = numOf(r['calcium_mg']);
      final fluids = numOf(r['fluids_ml']);
      if (protein <= 0 && calcium <= 0 && fluids <= 0) continue;
      final l = dayOf(r['log_date'] as String).nut;
      l.method = r['estimation_method'] as String? ?? kMeasured;
      l.confidence = numOf(r['confidence']);
      l.trust = ladder(l.method, l.confidence);
      l.pct = proteinTarget > 0 ? (protein / proteinTarget) : 0;
      l.raw = {'protein': protein, 'calcium': calcium, 'fluids': fluids};
    }

    // Activity aggregates its items — a day is only as trustworthy as
    // its least-trusted item, and the bar is weighted minutes vs the
    // 60-weighted-min day used across Analytics.
    for (final r in List<Map<String, dynamic>>.from(results[1])) {
      final l = dayOf(r['log_date'] as String).act;
      final min = numOf(r['duration_min']);
      final weight =
          (activityTierConfig[r['tier']] ?? activityTierConfig['lifestyle']!)
              .weight;
      final m = r['estimation_method'] as String? ?? kMeasured;
      final c = numOf(r['confidence']);
      final firstItem = l.raw.isEmpty;
      if (firstItem) {
        l.confidence = c == 0 ? 1.0 : c;
        l.method = m;
      } else {
        if (c < l.confidence) l.confidence = c;
        if (m != kMeasured && m != kRecalledManual) {
          l.method = m; // AI estimate dominates the day
        } else if (m == kRecalledManual && l.method == kMeasured) {
          l.method = kRecalledManual;
        }
      }
      l.raw['count'] = (l.raw['count'] ?? 0) + 1;
      l.raw['min'] = (l.raw['min'] ?? 0) + min;
      l.raw['weighted'] = (l.raw['weighted'] ?? 0) + min * weight;
      l.pct = (l.raw['weighted'] ?? 0) / 60;
      l.trust = ladder(l.method, l.confidence);
    }

    for (final r in List<Map<String, dynamic>>.from(results[2])) {
      final min = numOf(r['total_sleep_min']);
      if (min <= 0) continue;
      final l = dayOf(r['log_date'] as String).slp;
      l.method = r['estimation_method'] as String? ?? kMeasured;
      l.confidence = numOf(r['confidence']);
      l.trust = ladder(l.method, l.confidence);
      l.pct = sleepTarget > 0 ? min / sleepTarget : 0;
      l.raw = {
        'min': min,
        'efficiency': numOf(r['sleep_efficiency_score']),
      };
    }

    if (!mounted) return;
    setState(() {
      _days = days;
      _loading = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
    _load();
  }

  _DayData _dataOf(String date) => _days[date] ?? _DayData();

  bool _isFuture(String date) => date.compareTo(localISO(DateTime.now())) > 0;

  /// Past days (not today — today is still in progress) with any lever
  /// missing, oldest first: the backfill worklist.
  List<String> _attentionDates() {
    final today = localISO(DateTime.now());
    final out = <String>[];
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    for (var day = 1; day <= daysInMonth; day++) {
      final date = localISO(DateTime(_month.year, _month.month, day));
      if (date.compareTo(today) >= 0) break;
      if (_dataOf(date).levers.any((l) => l.trust == _DayTrust.missing)) {
        out.add(date);
      }
    }
    return out;
  }

  /// Month data quality: mean confidence over lever-days that have data.
  int? _qualityPct() {
    final confs = <double>[
      for (final d in _days.values)
        for (final l in d.levers)
          if (l.trust != _DayTrust.missing) l.confidence == 0 ? 1.0 : l.confidence,
    ];
    if (confs.isEmpty) return null;
    return (confs.reduce((a, b) => a + b) / confs.length * 100).round();
  }

  String _provenance(_LeverDay l) {
    final t = widget.i18n.t;
    if (l.trust == _DayTrust.missing) {
      return t('flutter.trust.no_data', 'No data for this day');
    }
    switch (l.method) {
      case kMeasured:
        return t('flutter.trust.src_measured', 'Logged on the day');
      case kRecalledManual:
        return t(
            'flutter.trust.src_recalled', 'Backfilled from memory by you');
      case kRelativeRecall:
        return t('flutter.trust.src_relative',
            'One-tap estimate vs the day before');
      case kPatternFill:
        return t('flutter.trust.src_pattern',
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
    final d = _dataOf(date);
    bool isEst(_LeverDay l) =>
        l.trust == _DayTrust.estimated || l.trust == _DayTrust.rough;
    final anyEstimate = d.levers.any(isEst);
    final allMissing = d.levers.every((l) => l.trust == _DayTrust.missing);
    final anyMissing = d.levers.any((l) => l.trust == _DayTrust.missing);

    String nutValue() => d.nut.trust == _DayTrust.missing
        ? '—'
        : '${isEst(d.nut) ? '~' : ''}${(d.nut.raw['protein'] ?? 0).round()} g · ${(d.nut.pct * 100).round()}%';
    String actValue() => d.act.trust == _DayTrust.missing
        ? '—'
        : '${isEst(d.act) ? '~' : ''}${(d.act.raw['min'] ?? 0).round()} ${t('flutter.min', 'min')} · ${(d.act.pct * 100).round()}%';
    String slpValue() => d.slp.trust == _DayTrust.missing
        ? '—'
        : '${isEst(d.slp) ? '~' : ''}${((d.slp.raw['min'] ?? 0) / 60).toStringAsFixed(1)} ${t('flutter.hours', 'hours')} · ${(d.slp.pct * 100).round()}%';

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
            Text(_prettyDate(date),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _LeverSheetRow(
                label: t('common.protein', 'Protein'),
                value: nutValue(),
                sub: _provenance(d.nut),
                lever: d.nut,
                i18n: widget.i18n),
            _LeverSheetRow(
                label: t('common.activity', 'Activity'),
                value: actValue(),
                sub: _provenance(d.act),
                lever: d.act,
                i18n: widget.i18n),
            _LeverSheetRow(
                label: t('common.sleep', 'Sleep'),
                value: slpValue(),
                sub: _provenance(d.slp),
                lever: d.slp,
                i18n: widget.i18n),
            if (anyEstimate || anyMissing) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              if (anyEstimate)
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: GsColors.accent),
                    onPressed: () => Navigator.pop(context, 'confirm'),
                    child:
                        Text(t('flutter.trust.looks_right', '✓ Looks right')),
                  ),
                ),
              if (anyEstimate) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'correct'),
                  child: Text(allMissing
                      ? t('flutter.trust.log_day', 'Log this day')
                      : t('flutter.trust.correct_day', 'Correct this day')),
                ),
              ),
            ]),
            if (anyEstimate) ...[
              const SizedBox(height: 8),
              Text(
                  t('flutter.trust.promote_note_all',
                      '"Looks right" upgrades every estimated lever this day to recalled. Corrections reopen the day\'s editor.'),
                  style:
                      const TextStyle(fontSize: 10.5, color: GsColors.text3)),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final childId = widget.appState.activeChildId;
    if (action == 'confirm' && childId != null) {
      final errs = <String>[];
      if (isEst(d.nut)) {
        final e = await confirmEstimate(widget.appState.sb, childId, date);
        if (e != null) errs.add(e);
      }
      if (isEst(d.act)) {
        final e =
            await confirmActivityEstimates(widget.appState.sb, childId, date);
        if (e != null) errs.add(e);
      }
      if (isEst(d.slp)) {
        final e =
            await confirmSleepEstimate(widget.appState.sb, childId, date);
        if (e != null) errs.add(e);
      }
      if (!mounted) return;
      if (errs.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errs.first)));
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
    final attention = _attentionDates();
    final monthLabel =
        '${t('flutter.month.${_month.month}', _monthFallback(_month.month))} ${_month.year}';
    // Sunday-first week — Thai calendars start on Sunday.
    final leadingBlanks = _month.weekday % 7; // Sun=7 → 0 blanks
    const weekOrder = [7, 1, 2, 3, 4, 5, 6];
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final today = localISO(DateTime.now());
    final canGoForward =
        DateTime(_month.year, _month.month + 1, 1).isBefore(DateTime.now());

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
              const SizedBox(height: 6),
              // Close-up sample cell — teaches which row is which lever
              // so parents never have to guess.
              _LegendSample(i18n: widget.i18n),
              const SizedBox(height: 10),
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
                  childAspectRatio: 0.78,
                  children: [
                    for (final w in weekOrder)
                      Center(
                        child: Text(
                            t('flutter.weekday_short.$w',
                                'MTWTFSS'[w - 1]),
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: GsColors.text3)),
                      ),
                    for (var i = 0; i < leadingBlanks; i++)
                      const SizedBox.shrink(),
                    for (var day = 1; day <= daysInMonth; day++)
                      _DayCell(
                        day: day,
                        date:
                            localISO(DateTime(_month.year, _month.month, day)),
                        data: _dataOf(localISO(
                            DateTime(_month.year, _month.month, day))),
                        isToday: localISO(
                                DateTime(_month.year, _month.month, day)) ==
                            today,
                        isFuture: _isFuture(localISO(
                            DateTime(_month.year, _month.month, day))),
                        attention: attention.contains(localISO(
                            DateTime(_month.year, _month.month, day))),
                        onTap: _openDaySheet,
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (!_loading && attention.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: GsColors.estimatedLight,
              borderRadius: BorderRadius.circular(GsRadius.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                      t('flutter.trust.attention_n',
                          '{n} days need attention', {'n': '${attention.length}'}),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: GsColors.estimatedDark)),
                ),
                TextButton(
                  onPressed: () => _openDaySheet(attention.first),
                  child: Text(t('flutter.trust.fill_next', 'Fill next →'),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: GsColors.estimatedDark)),
                ),
              ],
            ),
          ),
        ],
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

// ── Legend sample ───────────────────────────────────────────────────

/// Enlarged mock day cell with a label pointing at each row — the
/// "how to read this" key parents see before the real grid.
class _LegendSample extends StatelessWidget {
  const _LegendSample({required this.i18n});
  final I18n i18n;

  Widget _sampleRow(Color dot, double pct) => SizedBox(
        height: 14,
        child: Row(
          children: [
            Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: dot)),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: GsColors.border.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: dot, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _label(String name, String detail) => SizedBox(
        height: 14,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '— $name',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: GsColors.text2)),
              TextSpan(
                  text: ' · $detail',
                  style: const TextStyle(color: GsColors.text3)),
            ]),
            style: const TextStyle(fontSize: 10.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              decoration: BoxDecoration(
                color: GsColors.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: GsColors.border),
              ),
              child: Column(
                children: [
                  const Text('17',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: GsColors.text2)),
                  const SizedBox(height: 2),
                  _sampleRow(GsColors.measured, 0.85),
                  _sampleRow(GsColors.measured, 0.45),
                  _sampleRow(GsColors.estimated, 0.7),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 19),
                  _label(t('common.nutrition', 'Nutrition'),
                      t('flutter.trust.key_nut', 'protein vs daily target')),
                  _label(t('common.activity', 'Activity'),
                      t('flutter.trust.key_act', 'exercise vs daily goal')),
                  _label(t('common.sleep', 'Sleep'),
                      t('flutter.trust.key_slp', 'hours vs age target')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Full-width reading key — how far the bar fills and what the
        // dot colour means, so the grid needs no guessing at all.
        SizedBox(
          width: double.infinity,
          child: Text(
              t('flutter.trust.bar_note',
                  'Bar fills toward 100% of that day\'s target · dot colour = how the data was logged — blue measured, gold estimated, hollow missing.'),
              style: const TextStyle(
                  fontSize: 10, height: 1.4, color: GsColors.text3)),
        ),
      ],
    );
  }
}

// ── Cell ────────────────────────────────────────────────────────────

Color _trustColor(_DayTrust t) => switch (t) {
      _DayTrust.measured => GsColors.measured,
      _DayTrust.recalled => GsColors.measuredLight,
      _DayTrust.estimated => GsColors.estimated,
      _DayTrust.rough => GsColors.estimatedLight,
      _ => GsColors.border2,
    };

class _DayCell extends StatelessWidget {
  const _DayCell(
      {required this.day,
      required this.date,
      required this.data,
      required this.isToday,
      required this.isFuture,
      required this.attention,
      required this.onTap});
  final int day;
  final String date;
  final _DayData data;
  final bool isToday;
  final bool isFuture;
  final bool attention;
  final void Function(String date) onTap;

  Widget _leverRow(_LeverDay l) {
    final missing = l.trust == _DayTrust.missing;
    final c = _trustColor(l.trust);
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: missing ? Colors.transparent : c,
            border:
                missing ? Border.all(color: GsColors.border2, width: 1) : null,
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: Container(
            height: 3,
            // Faint track — missing days must read as absence, and a
            // filled bar's % must contrast clearly against it.
            decoration: BoxDecoration(
              color: GsColors.border.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: missing
                ? null
                : FractionallySizedBox(
                    widthFactor: l.pct.clamp(0.06, 1.0),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cell = Container(
      padding: const EdgeInsets.fromLTRB(5, 3, 5, 4),
      decoration: BoxDecoration(
        // Today gets an accent-tinted fill on top of its border so it
        // jumps out of the grid at a glance.
        color: isFuture
            ? Colors.transparent
            : isToday
                ? GsColors.accent.withValues(alpha: 0.14)
                : GsColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: GsColors.accent, width: 1.5)
            : attention
                ? Border.all(color: GsColors.estimated, width: 1.2)
                : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text('$day',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isToday
                      ? GsColors.accent
                      : isFuture
                          ? GsColors.text3.withValues(alpha: 0.35)
                          : GsColors.text2)),
          if (!isFuture) ...[
            const SizedBox(height: 3),
            _leverRow(data.nut),
            const SizedBox(height: 2.5),
            _leverRow(data.act),
            const SizedBox(height: 2.5),
            _leverRow(data.slp),
          ],
        ],
      ),
    );
    if (isFuture) return cell;
    return GestureDetector(onTap: () => onTap(date), child: cell);
  }
}

// ── Day-sheet pieces ────────────────────────────────────────────────

class _LeverSheetRow extends StatelessWidget {
  const _LeverSheetRow(
      {required this.label,
      required this.value,
      required this.sub,
      required this.lever,
      required this.i18n});
  final String label;
  final String value;
  final String sub;
  final _LeverDay lever;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: GsColors.text2)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: GsColors.text)),
                Text(sub,
                    style: const TextStyle(
                        fontSize: 10.5, color: GsColors.text3)),
              ],
            ),
          ),
          _TrustPill(
              trust: lever.trust, confidence: lever.confidence, i18n: i18n),
        ],
      ),
    );
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
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
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
