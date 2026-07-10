import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import 'trust_calendar.dart';

// ── Separated lever rings (7-day averages) ─────────────────────────

class _LeverRings extends StatelessWidget {
  const _LeverRings(
      {required this.a, required this.i18n, this.onOpenHistory});
  final WeeklyAnalytics a;
  final I18n i18n;

  /// Opens the trust calendar (nutrition history). Only the nutrition
  /// ring is wired for now — activity/sleep join in phase 2 once their
  /// tables carry estimation columns.
  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenHistory,
              child: _MiniRing(
                  pct: a.avgNutPct ?? 0,
                  delta: a.deltaNutPct,
                  expand: false,
                  light: const Color(0xFF5FA87E),
                  full: GsColors.accent,
                  label: t('common.nutrition', 'Nutrition'),
                  hint: t('flutter.trust.tap_history', 'tap for history')),
            ),
          ),
          _MiniRing(
              pct: a.avgActPct ?? 0,
              delta: a.deltaActPct,
              light: const Color(0xFF5B8FC0),
              full: GsColors.measured,
              label: t('common.activity', 'Activity')),
          _MiniRing(
              pct: a.avgSlpPct ?? 0,
              delta: a.deltaSlpPct,
              light: const Color(0xFFC9A45E),
              full: GsColors.estimated,
              label: t('common.sleep', 'Sleep')),
        ],
      ),
    );
  }
}

/// One Bevel-style ring: single arc, % in the center, label below.
/// Same gradient-as-data-layer treatment as the Today ring — the head
/// deepens toward the full brand color as the average approaches 100%.
class _MiniRing extends StatelessWidget {
  const _MiniRing(
      {required this.pct,
      required this.light,
      required this.full,
      required this.label,
      this.delta,
      this.expand = true,
      this.hint});
  final double pct;
  final Color light;
  final Color full;
  final String label;
  final double? delta; // week-over-week change as a signed fraction
  final bool expand; // false when the caller supplies its own Expanded
  final String? hint; // tiny affordance line under the label

  @override
  Widget build(BuildContext context) {
    // Round to whole points; hide the chip when there's no prior week
    // or the move is negligible (rounds to 0).
    final pts = ((delta ?? 0).abs() * 100).round();
    final showDelta = delta != null && pts > 0;
    final up = (delta ?? 0) >= 0;
    final column = Column(
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(pct),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, anim, _) => SizedBox(
              width: 74,
              height: 74,
              child: CustomPaint(
                painter: _MiniRingPainter(
                    pct: pct, anim: anim, light: light, full: full),
                child: Center(
                  child: Text('${(pct * 100 * anim).round()}%',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color.lerp(
                              light, full, 0.35 + 0.65 * pct))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GsColors.text2)),
          if (showDelta)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${up ? '▲' : '▼'} $pts',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: up ? GsColors.accent : GsColors.flag)),
            ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint!,
                  style: const TextStyle(
                      fontSize: 9.5, color: GsColors.text3)),
            ),
        ],
      );
    return expand ? Expanded(child: column) : column;
  }
}

class _MiniRingPainter extends CustomPainter {
  _MiniRingPainter(
      {required this.pct,
      required this.anim,
      required this.light,
      required this.full});
  final double pct, anim;
  final Color light, full;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 5;
    final rect = Rect.fromCircle(center: center, radius: r);
    const stroke = 7.5;

    canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = GsColors.surface2
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);

    final p = (pct.clamp(0.0, 1.0)) * anim;
    if (p <= 0.001) return;
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * p;
    final head = Color.lerp(light, full, 0.35 + 0.65 * pct.clamp(0.0, 1.0))!;

    canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..shader = SweepGradient(
            endAngle: sweep,
            colors: [light, head],
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt);

    final endA = start + sweep;
    canvas.drawCircle(
        center + Offset(math.cos(start) * r, math.sin(start) * r),
        stroke / 2,
        Paint()..color = light);
    canvas.drawCircle(
        center + Offset(math.cos(endA) * r, math.sin(endA) * r),
        stroke / 2,
        Paint()..color = head);
  }

  @override
  bool shouldRepaint(covariant _MiniRingPainter old) =>
      old.pct != pct || old.anim != anim;
}

/// Analytics tab — 7-day stat tiles and trend bars, port of the PWA's
/// updateStats() view. Bars are plain widgets; a charting package can
/// come later when the growth percentile curves are ported.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen(
      {super.key,
      required this.appState,
      required this.i18n,
      this.onCorrectDay});
  final AppState appState;
  final I18n i18n;

  /// From home_shell: switch the log date and jump to the Today tab so
  /// the parent can correct/log the tapped calendar day.
  final void Function(String date)? onCorrectDay;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Future<WeeklyAnalytics>? _future;
  String? _loadedChildId;

  void _loadIfNeeded() {
    final child = widget.appState.activeChildRow;
    if (child == null) return;
    final id = child['child_id'] as String;
    if (id == _loadedChildId) return;
    _loadedChildId = id;
    _future = loadWeeklyAnalytics(widget.appState.sb, child);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        _loadIfNeeded();
        if (_future == null) {
          return Center(
              child: Text(t('flutter.no_child_selected', 'No child selected'),
                  style: const TextStyle(color: GsColors.text3)));
        }
        return FutureBuilder<WeeklyAnalytics>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    '${t('flutter.could_not_load', 'Could not load')}: ${snap.error}',
                    style: const TextStyle(
                        fontSize: 13, color: GsColors.flagDark)),
              ));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final a = snap.data!;
            final child = widget.appState.activeChildRow ?? const {};
            return RefreshIndicator(
              onRefresh: () async {
                _loadedChildId = null;
                setState(_loadIfNeeded);
                await _future;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // Separated lever rings — Bevel-style: one ring per
                  // metric with the number inside, because Analytics is
                  // about comparing levers (Today keeps the composite).
                  if (a.avgNutPct != null)
                    _LeverRings(
                        a: a,
                        i18n: widget.i18n,
                        onOpenHistory: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: Text(
                                        t('flutter.trust.title',
                                            'Nutrition history'),
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  body: TrustCalendarScreen(
                                    appState: widget.appState,
                                    i18n: widget.i18n,
                                    onCorrectDay: (date) {
                                      Navigator.of(context).pop();
                                      widget.onCorrectDay?.call(date);
                                    },
                                  ),
                                ),
                              ),
                            )),
                  if (a.avgNutPct != null) const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _StatTile(
                        label:
                            '${t('analytics.stats.avg_readiness', 'Avg readiness')} · ${t('flutter.7d', '7d')}',
                        value: a.avgScore == null
                            ? '—'
                            : a.avgScore!.round().toString(),
                        suffix: a.avgScore == null
                            ? null
                            : t('today.hud.score_suffix', 'of 100'),
                        color: GsColors.accent,
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _StatTile(
                        label:
                            '${t('analytics.stats.avg_sleep', 'Avg sleep')} · ${t('flutter.7d', '7d')}',
                        value: a.avgSleepHours == null
                            ? '—'
                            : a.avgSleepHours!.toStringAsFixed(1),
                        suffix: a.avgSleepHours == null
                            ? null
                            : t('flutter.hours', 'hours'),
                        color: GsColors.estimated,
                      )),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _StatTile(
                        label: t('analytics.insight.height_velocity',
                            'Height velocity'),
                        value: a.velocityCmPerYear == null
                            ? '—'
                            : a.velocityCmPerYear!.toStringAsFixed(1),
                        suffix: a.velocityCmPerYear == null
                            ? t('flutter.velocity.not_enough',
                                a.velocityLabel)
                            : 'cm/yr · ${t('flutter.velocity.${a.velocityLabel.replaceAll(' ', '_')}', a.velocityLabel)}',
                        color: a.velocityLabel == 'below range'
                            ? GsColors.flag
                            : GsColors.measured,
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _StatTile(
                        label:
                            '${t('analytics.stats.height_gain', 'Height gain')} · ${t('flutter.30d', '30d')}',
                        value: a.heightGain30dCm == null
                            ? '—'
                            : '${a.heightGain30dCm! >= 0 ? '+' : ''}${a.heightGain30dCm!.toStringAsFixed(1)}',
                        suffix: a.heightGain30dCm == null
                            ? t('flutter.needs_two_measurements',
                                'needs 2+ measurements')
                            : 'cm',
                        color: GsColors.measured,
                      )),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _TrendCard(
                    title: t('common.protein', 'Protein'),
                    unit: 'g',
                    color: GsColors.accent,
                    days: a.days,
                    valueOf: (d) => d.proteinG,
                    i18n: widget.i18n,
                    estimatedOf: (d) => d.nutritionEstimated,
                    target: calcProteinTargetG(
                            child['date_of_birth'] as String?,
                            null,
                            child['biological_sex'] as String?)
                        .toDouble(),
                  ),
                  const SizedBox(height: 12),
                  _TrendCard(
                    title: t('common.calcium', 'Calcium'),
                    unit: 'mg',
                    color: GsColors.accent,
                    days: a.days,
                    valueOf: (d) => d.calciumMg,
                    i18n: widget.i18n,
                    estimatedOf: (d) => d.nutritionEstimated,
                    target: 1300,
                  ),
                  const SizedBox(height: 12),
                  _TrendCard(
                    title: t('common.sleep', 'Sleep'),
                    unit: 'h',
                    color: GsColors.estimated,
                    days: a.days,
                    valueOf: (d) =>
                        d.sleepMin == null ? null : d.sleepMin! / 60,
                    i18n: widget.i18n,
                    estimatedOf: (d) => d.sleepEstimated,
                    target: 9.5,
                  ),
                  const SizedBox(height: 12),
                  _TrendCard(
                    title:
                        '${t('common.activity', 'Activity')} (${t('flutter.weighted', 'weighted')})',
                    unit: t('flutter.min', 'min'),
                    color: GsColors.measured,
                    days: a.days,
                    valueOf: (d) => d.weightedActivityMin == 0
                        ? null
                        : d.weightedActivityMin,
                    target: 60,
                    estimatedOf: (d) => d.activityEstimated,
                    i18n: widget.i18n,
                  ),
                  if (a.insight != null) ...[
                    const SizedBox(height: 12),
                    _InsightCard(insight: a.insight!, i18n: widget.i18n),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label,
      required this.value,
      required this.color,
      this.suffix});
  final String label;
  final String value;
  final String? suffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GsColors.text2)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700, color: color)),
          if (suffix != null)
            Text(suffix!,
                style: const TextStyle(fontSize: 10.5, color: GsColors.text3)),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.unit,
    required this.color,
    required this.days,
    required this.valueOf,
    required this.i18n,
    this.target,
    this.estimatedOf,
  });
  final String title;
  final String unit;
  final Color color;
  final List<DayMetrics> days;
  final double? Function(DayMetrics) valueOf;
  final I18n i18n;
  final double? target; // per-day goal for the insight line + goal marker

  /// Per-lever flag: recall-engine estimated days render gold with an
  /// "N of 7 estimated" note, never the measured colour.
  final bool Function(DayMetrics)? estimatedOf;

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final values = [for (final d in days) valueOf(d)];
    final estimated = [
      for (final d in days) estimatedOf?.call(d) ?? false
    ];
    final estCount =
        estimated.where((e) => e).length;
    final logged = values.whereType<double>().toList();
    final maxVal =
        logged.fold<double>(target ?? 0, (m, v) => v > m ? v : m);
    final avg = logged.isEmpty
        ? null
        : logged.reduce((a, b) => a + b) / logged.length;
    // Insight: average vs target, and simple direction (first vs last half).
    String? insight;
    Color insightColor = GsColors.text3;
    if (avg != null && target != null && target! > 0) {
      final pct = (avg / target! * 100).round();
      final onTrack = pct >= 90;
      insight =
          '${t('flutter.analytics.avg', 'avg')} ${_fmt(avg)} $unit · $pct% ${t('flutter.analytics.of_target', 'of target')}';
      insightColor = onTrack ? GsColors.accent : GsColors.estimatedDark;
    } else if (avg != null) {
      insight = '${t('flutter.analytics.avg', 'avg')} ${_fmt(avg)} $unit';
    }

    // Direction: mean of the logged first half vs last half of the week.
    // Finishes the intent noted above — a bare average hides whether the
    // week is climbing or slipping.
    String? trendLabel;
    Color trendColor = GsColors.measured;
    final firstHalf = <double>[];
    final lastHalf = <double>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      (i < values.length / 2 ? firstHalf : lastHalf).add(v);
    }
    if (firstHalf.isNotEmpty && lastHalf.isNotEmpty) {
      final f = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
      final l = lastHalf.reduce((a, b) => a + b) / lastHalf.length;
      final rel = f == 0 ? (l > 0 ? 1.0 : 0.0) : (l - f) / f;
      if (rel >= 0.1) {
        trendLabel = '↗ ${t('flutter.analytics.trending_up', 'trending up')}';
        trendColor = GsColors.measured;
      } else if (rel <= -0.1) {
        trendLabel =
            '↘ ${t('flutter.analytics.trending_down', 'trending down')}';
        trendColor = GsColors.estimatedDark;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              if (maxVal > 0)
                Text('${t('flutter.max', 'max')} ${_fmt(maxVal)} $unit',
                    style: const TextStyle(
                        fontSize: 10.5, color: GsColors.text3)),
            ],
          ),
          if (insight != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(insight,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: insightColor)),
                  if (trendLabel != null)
                    Text(trendLabel,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: trendColor)),
                  if (estCount > 0)
                    Text(
                        t('flutter.analytics.n_estimated',
                            '{n} of 7 estimated', {'n': '$estCount'}),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: GsColors.estimatedDark)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            height: 82,
            child: Stack(
              children: [
                // Dashed goal line
                if (target != null && target! > 0 && maxVal > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 18 + 40 * (target! / maxVal),
                    child: _DashedLine(color: color.withValues(alpha: 0.5)),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < days.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (values[i] != null)
                              Text(_fmt(values[i]!),
                                  style: const TextStyle(
                                      fontSize: 9, color: GsColors.text2)),
                            const SizedBox(height: 2),
                            TweenAnimationBuilder<double>(
                              tween: Tween(
                                  begin: 0,
                                  end: values[i] == null || maxVal == 0
                                      ? 3
                                      : 3 + 40 * (values[i]! / maxVal)),
                              duration: Duration(
                                  milliseconds: 450 + i * 60),
                              curve: Curves.easeOutCubic,
                              builder: (context, h, _) => Container(
                                height: h,
                                decoration: BoxDecoration(
                                  // Estimated days are gold, never the
                                  // measured colour — same rule as the
                                  // brand's measured/estimated split.
                                  color: values[i] == null
                                      ? GsColors.surface2
                                      : estimated[i]
                                          ? GsColors.estimated
                                              .withValues(alpha: 0.6)
                                          : (target != null &&
                                                  target! > 0 &&
                                                  values[i]! >= target!)
                                              ? color
                                              : color.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _weekdayLetters[
                                  (DateTime.parse(days[i].date).weekday - 1) %
                                      7],
                              style: const TextStyle(
                                  fontSize: 9.5, color: GsColors.text3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cross-lever "smart insight" — one honest observation about the week,
/// rendered from the structured SmartInsight so it stays translatable.
class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.i18n});
  final SmartInsight insight;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final lever = insight.leverId.isEmpty
        ? ''
        : t('common.${insight.leverId}', insight.leverId);
    final who = insight.name.isEmpty
        ? t('flutter.analytics.insight_they', 'They')
        : insight.name;
    final String text;
    switch (insight.kind) {
      case InsightKind.sleepActivity:
        text = t(
            'flutter.analytics.insight_sleep_activity',
            '{name} slept about {hours} h longer on the week’s more active days.',
            {'name': who, 'hours': insight.hours});
      case InsightKind.leverDown:
        text = t(
            'flutter.analytics.insight_lever_down',
            '{lever} is the one lever trending down — off about {points} points from last week.',
            {'lever': lever, 'points': '${insight.points}'});
      case InsightKind.leverUp:
        text = t(
            'flutter.analytics.insight_lever_up',
            '{lever} is up about {points} points from last week — nice momentum.',
            {'lever': lever, 'points': '${insight.points}'});
    }
    final accent = insight.positive ? GsColors.accent : GsColors.estimatedDark;
    final tint =
        insight.positive ? GsColors.accentLight : GsColors.estimatedLight;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(insight.positive ? Icons.lightbulb_outline : Icons.trending_down,
              size: 18, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('flutter.analytics.smart_insight', 'Smart insight'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent)),
                const SizedBox(height: 2),
                Text(text,
                    style: const TextStyle(
                        fontSize: 12, height: 1.45, color: GsColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin dashed horizontal line used as the goal marker on trend bars.
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const dash = 5.0, gap = 4.0;
        final count = (c.maxWidth / (dash + gap)).floor();
        return Row(
          children: List.generate(
              count,
              (_) => Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: Container(width: dash, height: 1.2, color: color),
                  )),
        );
      },
    );
  }
}

String _fmt(double v) => v == v.roundToDouble()
    ? v.toInt().toString()
    : v.toStringAsFixed(1);
