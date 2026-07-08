import 'package:flutter/material.dart';

import '../analytics.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

/// Analytics tab — 7-day stat tiles and trend bars, port of the PWA's
/// updateStats() view. Bars are plain widgets; a charting package can
/// come later when the growth percentile curves are ported.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

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
                    i18n: widget.i18n,
                  ),
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
  });
  final String title;
  final String unit;
  final Color color;
  final List<DayMetrics> days;
  final double? Function(DayMetrics) valueOf;
  final I18n i18n;
  final double? target; // per-day goal for the insight line + goal marker

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final values = [for (final d in days) valueOf(d)];
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
              child: Text(insight,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: insightColor)),
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
                                  color: values[i] == null
                                      ? GsColors.surface2
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
