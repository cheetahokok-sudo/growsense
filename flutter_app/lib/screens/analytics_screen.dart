import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../analytics.dart';
import '../app_state.dart';
import '../citations.dart';
import '../growth_math.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/premium_gate.dart';
import 'medical_screen.dart' show GrowthJourneyScreen;
import 'trust_calendar.dart';

// ── Separated lever rings (7-day averages) ─────────────────────────

class _LeverRings extends StatelessWidget {
  const _LeverRings({required this.a, required this.i18n, this.onOpenHistory});
  final WeeklyAnalytics a;
  final I18n i18n;

  /// Opens the trust calendar for the tapped lever ('nutrition' |
  /// 'activity' | 'sleep').
  final void Function(String lever)? onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    Widget ring({
      required String lever,
      required double pct,
      required double? delta,
      required Color light,
      required Color full,
      required String label,
    }) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpenHistory == null ? null : () => onOpenHistory!(lever),
        child: _MiniRing(
          pct: pct,
          delta: delta,
          expand: false,
          light: light,
          full: full,
          label: label,
          hint: onOpenHistory == null
              ? null
              : t('flutter.trust.tap_history', 'tap for history'),
        ),
      ),
    );
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
          ring(
            lever: 'nutrition',
            pct: a.avgNutPct ?? 0,
            delta: a.deltaNutPct,
            light: const Color(0xFF5FA87E),
            full: GsColors.accent,
            label: t('common.nutrition', 'Nutrition'),
          ),
          ring(
            lever: 'activity',
            pct: a.avgActPct ?? 0,
            delta: a.deltaActPct,
            light: const Color(0xFF5B8FC0),
            full: GsColors.measured,
            label: t('common.activity', 'Activity'),
          ),
          ring(
            lever: 'sleep',
            pct: a.avgSlpPct ?? 0,
            delta: a.deltaSlpPct,
            light: const Color(0xFFC9A45E),
            full: GsColors.estimated,
            label: t('common.sleep', 'Sleep'),
          ),
        ],
      ),
    );
  }
}

/// One Bevel-style ring: single arc, % in the center, label below.
/// Same gradient-as-data-layer treatment as the Today ring — the head
/// deepens toward the full brand color as the average approaches 100%.
class _MiniRing extends StatelessWidget {
  const _MiniRing({
    required this.pct,
    required this.light,
    required this.full,
    required this.label,
    this.delta,
    this.expand = true,
    this.hint,
  });
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
                pct: pct,
                anim: anim,
                light: light,
                full: full,
              ),
              child: Center(
                child: Text(
                  '${(pct * 100 * anim).round()}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color.lerp(light, full, 0.35 + 0.65 * pct),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: GsColors.text2,
          ),
        ),
        if (showDelta)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${up ? '▲' : '▼'} $pts',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: up ? GsColors.accent : GsColors.flag,
              ),
            ),
          ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hint!,
              style: const TextStyle(fontSize: 9.5, color: GsColors.text3),
            ),
          ),
      ],
    );
    return expand ? Expanded(child: column) : column;
  }
}

class _MiniRingPainter extends CustomPainter {
  _MiniRingPainter({
    required this.pct,
    required this.anim,
    required this.light,
    required this.full,
  });
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
        ..strokeWidth = stroke,
    );

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
        ..strokeCap = StrokeCap.butt,
    );

    final endA = start + sweep;
    canvas.drawCircle(
      center + Offset(math.cos(start) * r, math.sin(start) * r),
      stroke / 2,
      Paint()..color = light,
    );
    canvas.drawCircle(
      center + Offset(math.cos(endA) * r, math.sin(endA) * r),
      stroke / 2,
      Paint()..color = head,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniRingPainter old) =>
      old.pct != pct || old.anim != anim;
}

/// Analytics tab — 7-day stat tiles and trend bars, port of the PWA's
/// updateStats() view. Bars are plain widgets; a charting package can
/// come later when the growth percentile curves are ported.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    required this.appState,
    required this.i18n,
    this.onCorrectDay,
  });
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
  bool? _loadedPremium;

  void _loadIfNeeded() {
    final child = widget.appState.activeChildRow;
    if (child == null) return;
    final id = child['child_id'] as String;
    final premium = widget.appState.isPremium;
    // Reload when the tier flips too — the parent who buys from a
    // locked chip comes straight back here expecting the long window,
    // and the free fetch only holds 60 days.
    if (id == _loadedChildId && premium == _loadedPremium) return;
    _loadedChildId = id;
    _loadedPremium = premium;
    _future = loadWeeklyAnalytics(widget.appState.sb, child, premium: premium);
  }

  /// Velocity over the 6-month window — the shortest interval the
  /// clinical literature actually trusts. Premium computes it from the
  /// full measurement history; free sees the locked tile, and tapping
  /// it opens the sheet that explains WHY the honest window is paid.
  Widget _velocityWindowTile(String Function(String, [String?, Map<String, String>?]) t) {
    final label =
        '${t('analytics.insight.height_velocity', 'Height velocity')} · ${t('flutter.6mo', '6mo')}';
    if (widget.appState.isPremium) {
      final v = velocityOverWindow(widget.appState.measurements, 180);
      return _StatTile(
        label: label,
        value: v == null ? '—' : v.toStringAsFixed(1),
        suffix: v == null
            ? t('flutter.iw.velocity_needs_span',
                'needs measurements 3+ months apart')
            : 'cm/yr',
        color: GsColors.measured,
      );
    }
    return GestureDetector(
      onTap: () => _showWindowSheet(cardKey: 'velocity', windowDays: 180),
      child: _StatTile(
        label: label,
        value: '🔒',
        suffix: t('flutter.iw.premium_window',
            'Premium · the clinically valid window'),
        color: GsColors.estimatedDark,
      ),
    );
  }

  /// Locked-chip tap → the app's one premium sheet, with copy naming
  /// the specific benefit of THIS card at THIS window — never a
  /// generic "Go Premium".
  void _showWindowSheet({required String cardKey, required int windowDays}) {
    final t = widget.i18n.t;
    final window = windowDays >= 180
        ? t('flutter.window.6mo', '6 months')
        : t('flutter.window.90d', '90 days');
    final args = {'window': window};
    final (emoji, title, body) = switch (cardKey) {
      'sleep' => (
          '🌙',
          t('flutter.iw.sheet.sleep.title', 'See {window} of sleep, next to growth', args),
          t('flutter.iw.sheet.sleep.body',
              'One late bedtime is nothing. A short-sleep season is a growth lever. Premium keeps the whole record so the pattern can show itself.'),
        ),
      'protein' || 'calcium' || 'zinc' => (
          '🥚',
          t('flutter.iw.sheet.nutrition.title',
              'Was it a low week — or a low season?', args),
          t('flutter.iw.sheet.nutrition.body',
              'A {window} view shows whether nutrition is holding or drifting — something no single month can tell you.', args),
        ),
      'activity' => (
          '⚽',
          t('flutter.iw.sheet.activity.title',
              'See {window} of activity, next to growth', args),
          t('flutter.iw.sheet.activity.body',
              'Term time vs holidays, seasons of sport and rest — the {window} view shows the rhythm a month hides.', args),
        ),
      _ => (
          '📏',
          t('flutter.iw.sheet.velocity.title',
              'Height velocity needs six months to be honest'),
          t('flutter.iw.sheet.velocity.body',
              'Short intervals are mostly measuring noise, so we would rather wait than guess. Premium unlocks the full history and the windows a pediatrician would trust.'),
        ),
    };
    showPremiumSheet(
      context,
      appState: widget.appState,
      i18n: widget.i18n,
      emoji: emoji,
      title: title,
      body: body,
      freeNote: t('flutter.iw.sheet.free_note',
          'Daily logging and the 30-day view stay free, always.'),
      highlightBenefitKey: 'history',
    );
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
            child: Text(
              t('flutter.no_child_selected', 'No child selected'),
              style: const TextStyle(color: GsColors.text3),
            ),
          );
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
                      fontSize: 13,
                      color: GsColors.flagDark,
                    ),
                  ),
                ),
              );
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
                      onOpenHistory: (lever) {
                        // Unified calendar — every ring opens the same
                        // 3-lever month view.
                        final title = t(
                          'flutter.trust.title_all',
                          'Logging history',
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                actions: [
                                  // Explicit way out, alongside back.
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () => Navigator.of(ctx).pop(),
                                  ),
                                ],
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
                        );
                      },
                    ),
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
                        ),
                      ),
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
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: t(
                            'analytics.insight.height_velocity',
                            'Height velocity',
                          ),
                          value: a.velocityCmPerYear == null
                              ? '—'
                              : a.velocityCmPerYear!.toStringAsFixed(1),
                          suffix: a.velocityCmPerYear == null
                              ? t(
                                  'flutter.velocity.not_enough',
                                  a.velocityLabel,
                                )
                              : 'cm/yr · ${t('flutter.velocity.${a.velocityLabel.replaceAll(' ', '_')}', a.velocityLabel)}',
                          color: a.velocityLabel == 'below range'
                              ? GsColors.flag
                              : GsColors.measured,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // The 30-day height-gain tile is retired: one
                      // month of growth is smaller than home measuring
                      // error, so the number was noise wearing a unit.
                      // Its replacement is velocity over a clinically
                      // valid window — premium, because only premium
                      // history reaches that far back.
                      Expanded(child: _velocityWindowTile(t)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      t('flutter.iw.velocity_edu',
                          'Height velocity needs 3+ months between measurements to mean anything — over a single month it is mostly measuring noise.'),
                      style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.4,
                          color: GsColors.text3),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: SourcesLink(
                        topicId: 'percentile',
                        label: 'Velocity vs WHO reference · Sources'),
                  ),
                  const SizedBox(height: 14),
                  _TrendCard(
                    title: t('common.protein', 'Protein'),
                    unit: 'g',
                    color: GsColors.accent,
                    a: a,
                    cardKey: 'protein',
                    isPremium: widget.appState.isPremium,
                    onLockedTap: (k, w) =>
                        _showWindowSheet(cardKey: k, windowDays: w),
                    valueOf: (d) => d.proteinG,
                    i18n: widget.i18n,
                    estimatedOf: (d) => d.nutritionEstimated,
                    target: calcProteinTargetG(
                      child['date_of_birth'] as String?,
                      null,
                      child['biological_sex'] as String?,
                    ).toDouble(),
                  ),
                  const SizedBox(height: 12),
                  _TrendCard(
                    title: t('common.calcium', 'Calcium'),
                    unit: 'mg',
                    color: GsColors.accent,
                    a: a,
                    cardKey: 'calcium',
                    isPremium: widget.appState.isPremium,
                    onLockedTap: (k, w) =>
                        _showWindowSheet(cardKey: k, windowDays: w),
                    valueOf: (d) => d.calciumMg,
                    i18n: widget.i18n,
                    estimatedOf: (d) => d.nutritionEstimated,
                    target: calcCalciumTargetMg(
                      child['date_of_birth'] as String?,
                    ).toDouble(),
                  ),
                  const SizedBox(height: 12),
                  _TrendCard(
                    title: t('common.zinc', 'Zinc'),
                    unit: 'mg',
                    color: GsColors.accent,
                    a: a,
                    cardKey: 'zinc',
                    isPremium: widget.appState.isPremium,
                    onLockedTap: (k, w) =>
                        _showWindowSheet(cardKey: k, windowDays: w),
                    valueOf: (d) => d.zincMg,
                    i18n: widget.i18n,
                    estimatedOf: (d) => d.nutritionEstimated,
                    target: calcZincTargetMg(
                      child['date_of_birth'] as String?,
                      child['biological_sex'] as String?,
                    ).toDouble(),
                  ),
                  const SizedBox(height: 12),
                  _CoFactorCard(appState: widget.appState, i18n: widget.i18n),
                  const SizedBox(height: 12),
                  _TrendCard(
                    title: t('common.sleep', 'Sleep'),
                    unit: 'h',
                    color: GsColors.estimated,
                    a: a,
                    cardKey: 'sleep',
                    isPremium: widget.appState.isPremium,
                    onLockedTap: (k, w) =>
                        _showWindowSheet(cardKey: k, windowDays: w),
                    valueOf: (d) =>
                        d.sleepMin == null ? null : d.sleepMin! / 60,
                    i18n: widget.i18n,
                    estimatedOf: (d) => d.sleepEstimated,
                    target:
                        calcSleepTargetMin(child['date_of_birth'] as String?) /
                        60,
                  ),
                  const SizedBox(height: 12),
                  _TrendCard(
                    title:
                        '${t('common.activity', 'Activity')} (${t('flutter.weighted', 'weighted')})',
                    unit: t('flutter.min', 'min'),
                    color: GsColors.measured,
                    a: a,
                    cardKey: 'activity',
                    isPremium: widget.appState.isPremium,
                    onLockedTap: (k, w) =>
                        _showWindowSheet(cardKey: k, windowDays: w),
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
                  // Growth lives at the bottom on purpose: the tab is
                  // ordered by rate of change (daily levers up top,
                  // per-measurement growth below). The strip is the
                  // summary; the full WHO chart is the drill-in.
                  const SizedBox(height: 12),
                  _GrowthStrip(
                    appState: widget.appState,
                    i18n: widget.i18n,
                    a: a,
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
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    this.suffix,
  });
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
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: GsColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (suffix != null)
            Text(
              suffix!,
              style: const TextStyle(fontSize: 10.5, color: GsColors.text3),
            ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({
    required this.title,
    required this.unit,
    required this.color,
    required this.a,
    required this.valueOf,
    required this.i18n,
    required this.isPremium,
    required this.cardKey,
    required this.onLockedTap,
    this.target,
    this.estimatedOf,
  });
  final String title;
  final String unit;
  final Color color;
  final WeeklyAnalytics a;
  final double? Function(DayMetrics) valueOf;
  final I18n i18n;
  final bool isPremium;
  final String cardKey; // 'protein' | 'calcium' | 'zinc' | 'sleep' | 'activity'
  final void Function(String cardKey, int windowDays) onLockedTap;
  final double? target; // per-day goal for the insight line + goal marker

  /// Per-lever flag: recall-engine estimated days render gold with an
  /// "N of D estimated" note, never the measured colour.
  final bool Function(DayMetrics)? estimatedOf;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  int _window = 7;

  String _windowLabel(String Function(String, [String?, Map<String, String>?]) t,
          int w) =>
      switch (w) {
        7 => t('flutter.7d', '7d'),
        30 => t('flutter.30d', '30d'),
        90 => t('flutter.90d', '90d'),
        _ => t('flutter.6mo', '6mo'),
      };

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final color = widget.color;
    final unit = widget.unit;
    final target = widget.target;

    final stats = computeWindowStats(
      widget.a.allDays,
      _window,
      widget.valueOf,
      estimatedOf: widget.estimatedOf,
    );
    final days = stats.days;
    final values = [for (final d in days) widget.valueOf(d)];
    final estimated = [
      for (final d in days) widget.estimatedOf?.call(d) ?? false,
    ];
    final estCount = stats.estimatedCount;
    final logged = values.whereType<double>().toList();
    final maxVal = logged.fold<double>(target ?? 0, (m, v) => v > m ? v : m);
    final avg = stats.avg;
    // Insight: average vs target.
    String? insight;
    Color insightColor = GsColors.text3;
    if (avg != null && target != null && target > 0) {
      final pct = (avg / target * 100).round();
      final onTrack = pct >= 90;
      insight =
          '${t('flutter.analytics.avg', 'avg')} ${_fmt(avg)} $unit · $pct% ${t('flutter.analytics.of_target', 'of target')}';
      insightColor = onTrack ? GsColors.accent : GsColors.estimatedDark;
    } else if (avg != null) {
      insight = '${t('flutter.analytics.avg', 'avg')} ${_fmt(avg)} $unit';
    }

    // Direction. For the 7-day view keep the within-week halves
    // comparison; longer windows say "vs prior <window>" from
    // WindowStats, which is the Whoop-style like-for-like delta.
    String? trendLabel;
    Color trendColor = GsColors.measured;
    if (_window == 7) {
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
          trendLabel =
              '↗ ${t('flutter.analytics.trending_up', 'trending up')}';
          trendColor = GsColors.measured;
        } else if (rel <= -0.1) {
          trendLabel =
              '↘ ${t('flutter.analytics.trending_down', 'trending down')}';
          trendColor = GsColors.estimatedDark;
        }
      }
    } else if (stats.deltaVsPrior != null && avg != null && avg > 0) {
      final rel = stats.deltaVsPrior! / avg;
      if (rel.abs() >= 0.05) {
        final up = rel > 0;
        trendLabel =
            '${up ? '↗' : '↘'} ${_fmt(stats.deltaVsPrior!.abs())} $unit ${t('flutter.iw.vs_prior', 'vs prior {window}', {
              'window': _windowLabel(t, _window)
            })}';
        trendColor = up ? GsColors.measured : GsColors.estimatedDark;
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
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (maxVal > 0)
                Text(
                  '${t('flutter.max', 'max')} ${_fmt(maxVal)} $unit',
                  style: const TextStyle(fontSize: 10.5, color: GsColors.text3),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final w in kTrendWindows)
                if (windowHasEnoughRecord(w, widget.a.recordSpanDays))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _WindowChip(
                      label: _windowLabel(t, w),
                      selected: _window == w,
                      locked: w > kFreeTrendWindowDays && !widget.isPremium,
                      onTap: () {
                        if (w > kFreeTrendWindowDays && !widget.isPremium) {
                          widget.onLockedTap(widget.cardKey, w);
                        } else {
                          setState(() => _window = w);
                        }
                      },
                    ),
                  ),
            ],
          ),
          if (insight != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    insight,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: insightColor,
                    ),
                  ),
                  if (trendLabel != null)
                    Text(
                      trendLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: trendColor,
                      ),
                    ),
                  if (estCount > 0)
                    Text(
                      t('flutter.analytics.n_of_days_estimated',
                          '{n} of {d} days estimated', {
                        'n': '$estCount',
                        'd': '${stats.loggedCount}',
                      }),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: GsColors.estimatedDark,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (_window == 7)
            SizedBox(
              height: 82,
              child: Stack(
                children: [
                  // Dashed goal line
                  if (target != null && target > 0 && maxVal > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 18 + 40 * (target / maxVal),
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
                                Text(
                                  _fmt(values[i]!),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: GsColors.text2,
                                  ),
                                ),
                              const SizedBox(height: 2),
                              TweenAnimationBuilder<double>(
                                tween: Tween(
                                  begin: 0,
                                  end: values[i] == null || maxVal == 0
                                      ? 3
                                      : 3 + 40 * (values[i]! / maxVal),
                                ),
                                duration:
                                    Duration(milliseconds: 450 + i * 60),
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
                                        ? GsColors.estimated.withValues(
                                            alpha: 0.6,
                                          )
                                        : (target != null &&
                                              target > 0 &&
                                              values[i]! >= target)
                                        ? color
                                        : color.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _weekdayLetters[(DateTime.parse(
                                          days[i].date,
                                        ).weekday -
                                        1) %
                                    7],
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: GsColors.text3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 92,
              width: double.infinity,
              child: CustomPaint(
                painter: _WindowSparklinePainter(
                  days: days,
                  values: values,
                  estimated: estimated,
                  color: color,
                  target: target,
                  emptyLabel: t('flutter.iw.no_data_window',
                      'Nothing logged in this window yet'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One range chip. Locked chips render dashed-gold with a lock — the
/// visible advertisement for the longer window — and route their tap
/// to the contextual premium sheet instead of switching.
class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.selected,
    required this.locked,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? GsColors.accent
              : locked
                  ? Colors.transparent
                  : GsColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? GsColors.accent
                : locked
                    ? GsColors.estimated
                    : GsColors.border2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? GsColors.surface
                    : locked
                        ? GsColors.estimatedDark
                        : GsColors.text2,
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 3),
              const Icon(Icons.lock,
                  size: 9, color: GsColors.estimatedDark),
            ],
          ],
        ),
      ),
    );
  }
}

/// Line sparkline for the 30d+ windows — bars stop working past a
/// week. Whoop/Apple-style: faint target dash, one line, estimated
/// days as gold dots (the brand's measured/estimated split at chart
/// scale), emphasized endpoint, month ticks on long windows.
class _WindowSparklinePainter extends CustomPainter {
  _WindowSparklinePainter({
    required this.days,
    required this.values,
    required this.estimated,
    required this.color,
    required this.target,
    required this.emptyLabel,
  });
  final List<DayMetrics> days;
  final List<double?> values;
  final List<bool> estimated;
  final Color color;
  final double? target;
  final String emptyLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 2.0, padR = 10.0, padT = 8.0, padB = 16.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    final logged = values.whereType<double>().toList();
    if (logged.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
            text: emptyLabel,
            style: const TextStyle(fontSize: 11, color: GsColors.text3)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(canvas,
          Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }
    var maxV = logged.reduce(math.max);
    if (target != null && target! > maxV) maxV = target!;
    if (maxV <= 0) maxV = 1;

    double x(int i) =>
        padL + (days.length <= 1 ? 0 : w * i / (days.length - 1));
    double y(double v) => padT + h - h * (v / maxV);

    // Month ticks: a faint rule + numeric month label wherever a month
    // starts inside the window. Numeric so it reads in all six locales.
    final tickPaint = Paint()
      ..color = GsColors.border
      ..strokeWidth = 1;
    for (var i = 0; i < days.length; i++) {
      final d = DateTime.parse(days[i].date);
      final isFirst = i == 0;
      final isLast = i == days.length - 1;
      final monthStart = d.day == 1 && days.length > 45;
      if (!monthStart && !isFirst && !isLast) continue;
      if (monthStart) {
        canvas.drawLine(Offset(x(i), padT), Offset(x(i), padT + h), tickPaint);
      }
      if (monthStart || isFirst || isLast) {
        final label = monthStart ? '${d.month}' : '${d.day}/${d.month}';
        final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: const TextStyle(fontSize: 9, color: GsColors.text3)),
          textDirection: TextDirection.ltr,
        )..layout();
        var lx = x(i) - tp.width / 2;
        lx = lx.clamp(0.0, size.width - tp.width);
        tp.paint(canvas, Offset(lx, padT + h + 3));
      }
    }

    // Target dash
    if (target != null && target! > 0) {
      final ty = y(target!);
      final dash = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      for (var dx = padL; dx < padL + w; dx += 8) {
        canvas.drawLine(Offset(dx, ty), Offset(dx + 4, ty), dash);
      }
    }

    // The line — broken at unlogged days rather than interpolated
    // through them: a gap is data too.
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    var penDown = false;
    int? lastLogged;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        penDown = false;
        continue;
      }
      if (penDown) {
        path.lineTo(x(i), y(v));
      } else {
        path.moveTo(x(i), y(v));
        penDown = true;
      }
      lastLogged = i;
    }
    canvas.drawPath(path, line);

    // Estimated days: gold dots on the line, never the measured colour.
    final goldDot = Paint()..color = GsColors.estimated;
    for (var i = 0; i < values.length; i++) {
      if (values[i] != null && estimated[i]) {
        canvas.drawCircle(Offset(x(i), y(values[i]!)), 2.2, goldDot);
      }
    }

    // Emphasized endpoint + its value.
    if (lastLogged != null) {
      final ex = x(lastLogged), ey = y(values[lastLogged]!);
      canvas.drawCircle(Offset(ex, ey), 3.4, Paint()..color = color);
      final tp = TextPainter(
        text: TextSpan(
            text: _fmt(values[lastLogged]!),
            style: TextStyle(
                fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset((ex - tp.width).clamp(0.0, size.width - tp.width),
              math.max(0, ey - tp.height - 4)));
    }
  }

  @override
  bool shouldRepaint(covariant _WindowSparklinePainter old) =>
      old.days != days || old.color != color || old.target != target;
}

/// Growth summary strip — bottom of Analytics because height changes
/// per measurement (~monthly), not per week like the levers above it.
/// One line of status; the full WHO chart is a tap away.
class _GrowthStrip extends StatefulWidget {
  const _GrowthStrip({
    required this.appState,
    required this.i18n,
    required this.a,
  });
  final AppState appState;
  final I18n i18n;
  final WeeklyAnalytics a;

  @override
  State<_GrowthStrip> createState() => _GrowthStripState();
}

class _GrowthStripState extends State<_GrowthStrip> {
  String? _loadedChildId;
  int? _percentile;
  String? _latestDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _GrowthStrip old) {
    super.didUpdateWidget(old);
    _load();
  }

  Future<void> _load() async {
    final child = widget.appState.activeChildRow;
    if (child == null) return;
    final id = child['child_id'] as String;
    if (id == _loadedChildId) return;
    _loadedChildId = id;
    final rows = List<Map<String, dynamic>>.from(
      await widget.appState.sb
          .from('measurements')
          .select('recorded_date, stature_height_cm')
          .eq('child_id', id)
          .order('recorded_date', ascending: false)
          .limit(5),
    );
    final dob = child['date_of_birth'] as String?;
    if (!mounted || dob == null) return;
    for (final r in rows) {
      final h = (r['stature_height_cm'] as num?)?.toDouble();
      final date = r['recorded_date'] as String?;
      if (h == null || h <= 0 || date == null) continue;
      final who = await loadWhoReference();
      final bands = who.heightBands(
        child['biological_sex'] as String?,
        ageYearsAt(dob, date) * 12,
      );
      if (!mounted) return;
      setState(() {
        _percentile = zToPercentile(zFromHeight(bands, h)).round();
        _latestDate = date;
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final a = widget.a;
    final parts = <String>[
      if (_percentile != null) 'P$_percentile',
      if (a.velocityCmPerYear != null)
        t(
          'flutter.velocity.${a.velocityLabel.replaceAll(' ', '_')}',
          a.velocityLabel,
        ),
      // "Recent + locked count": the free tier sees its window, and
      // this line names exactly what is behind the paywall — their own
      // real measurements, counted, not a vague "more".
      if (widget.appState.hasLockedHistory)
        t('flutter.growth_strip.locked_n', '{n} earlier measurements 🔒',
            {'n': '${widget.appState.lockedMeasurementCount}'}),
    ];
    final summary = parts.isEmpty
        ? t(
            'flutter.growth_strip.empty',
            'Log a measurement to start the curve',
          )
        : parts.join(' · ');
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              GrowthJourneyScreen(appState: widget.appState, i18n: widget.i18n),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: GsColors.surface,
          borderRadius: BorderRadius.circular(GsRadius.md),
          border: Border.all(color: GsColors.border),
          boxShadow: gsShadow,
        ),
        child: Row(
          children: [
            const Icon(Icons.show_chart, size: 18, color: GsColors.measured),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('flutter.growth_strip.title', 'Growth'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GsColors.measuredDark,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: GsColors.text2,
                    ),
                  ),
                  if (_latestDate != null)
                    Text(
                      t(
                        'flutter.growth_strip.measured_on',
                        'Measured {date} · tap for the WHO curve',
                        {'date': _latestDate!},
                      ),
                      style: const TextStyle(
                        fontSize: 10,
                        color: GsColors.text3,
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: SourcesLink(topicId: 'percentile'),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: GsColors.text3),
          ],
        ),
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
          {'name': who, 'hours': insight.hours},
        );
      case InsightKind.leverDown:
        text = t(
          'flutter.analytics.insight_lever_down',
          '{lever} is the one lever trending down — off about {points} points from last week.',
          {'lever': lever, 'points': '${insight.points}'},
        );
      case InsightKind.leverUp:
        text = t(
          'flutter.analytics.insight_lever_up',
          '{lever} is up about {points} points from last week — nice momentum.',
          {'lever': lever, 'points': '${insight.points}'},
        );
    }
    final accent = insight.positive ? GsColors.accent : GsColors.estimatedDark;
    final tint = insight.positive
        ? GsColors.accentLight
        : GsColors.estimatedLight;
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
          Icon(
            insight.positive ? Icons.lightbulb_outline : Icons.trending_down,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('flutter.analytics.smart_insight', 'Smart insight'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: GsColors.text,
                  ),
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
            ),
          ),
        );
      },
    );
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

// ── Minor growth co-factors (Analytics-only) ────────────────────────
// Iron + vitamin D are auto-captured from food logs but kept off the
// Today page and readiness score (too many parameters for parents).
// This card is their quiet home: a 30-day average vs the age target,
// self-loading from nutrition_log_items. Vitamin D from food is
// normally low — the outdoor-days line reframes it, not alarms.
class _CoFactorCard extends StatefulWidget {
  const _CoFactorCard({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<_CoFactorCard> createState() => _CoFactorCardState();
}

class _CoFactorCardState extends State<_CoFactorCard> {
  bool _loading = true;
  // Collapsed by default: co-factors are secondary to the main nutrients, and
  // this section is the extensible "window" more micronutrients will land in —
  // keeping it folded away stops the Analytics screen getting noisy as it grows.
  bool _expanded = false;
  double? _avgIron;
  double? _avgVitD;
  int _ironTarget = 10;
  int _vitDTarget = 600;
  int _outdoorDays = 0;
  int _loggedDays = 0;
  String? _loadedChildId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final child = widget.appState.activeChildRow;
    final childId = child?['child_id'] as String?;
    _loadedChildId = childId;
    if (childId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _ironTarget = calcIronTargetMg(
      child?['date_of_birth'] as String?,
      child?['biological_sex'] as String?,
    );
    _vitDTarget = calcVitaminDTargetIu(child?['date_of_birth'] as String?);
    final since = localISO(DateTime.now().subtract(const Duration(days: 30)));
    try {
      final rows = List<Map<String, dynamic>>.from(
        await widget.appState.sb
            .from('nutrition_log_items')
            .select('log_date, iron_mg, vitamin_d_iu')
            .eq('child_id', childId)
            .gte('log_date', since),
      );
      final ironByDay = <String, double>{};
      final vitdByDay = <String, double>{};
      final loggedDays = <String>{};
      for (final r in rows) {
        final d = r['log_date'] as String;
        loggedDays.add(d);
        final fe = (r['iron_mg'] as num?)?.toDouble();
        final vd = (r['vitamin_d_iu'] as num?)?.toDouble();
        if (fe != null) ironByDay[d] = (ironByDay[d] ?? 0) + fe;
        if (vd != null) vitdByDay[d] = (vitdByDay[d] ?? 0) + vd;
      }
      _loggedDays = loggedDays.length;
      if (_loggedDays > 0) {
        _avgIron = ironByDay.values.fold(0.0, (a, b) => a + b) / _loggedDays;
        _avgVitD = vitdByDay.values.fold(0.0, (a, b) => a + b) / _loggedDays;
      }
      final act = List<Map<String, dynamic>>.from(
        await widget.appState.sb
            .from('daily_activity_items')
            .select('log_date')
            .eq('child_id', childId)
            .eq('is_outdoor', true)
            .gte('log_date', since),
      );
      _outdoorDays = {for (final r in act) r['log_date'] as String}.length;
    } catch (_) {
      // Non-fatal — card shows its empty state.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    if (_loadedChildId != widget.appState.activeChildId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tappable header — toggles the whole co-factor section open/closed.
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(GsRadius.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('flutter.cofactor.title', 'Minor co-factors'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // When collapsed, name what's inside so it reads as a section.
                if (!_expanded)
                  Text(
                    t('flutter.cofactor.collapsed', 'Iron · Vitamin D'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: GsColors.text3,
                    ),
                  )
                else
                  Text(
                    t('flutter.30d', '30d'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: GsColors.text3,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: GsColors.text3,
                ),
              ],
            ),
          ),
          if (!_expanded)
            const SizedBox.shrink()
          else ...[
          const SizedBox(height: 2),
          Text(
            t(
              'flutter.cofactor.sub',
              'Tracked quietly from your food logs — not part of the daily score.',
            ),
            style: const TextStyle(fontSize: 11.5, color: GsColors.text2),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_loggedDays == 0 || (_avgIron == null && _avgVitD == null))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                t(
                  'flutter.cofactor.empty',
                  'Log a few foods and their iron and vitamin D will appear here.',
                ),
                style: const TextStyle(fontSize: 12.5, color: GsColors.text3),
              ),
            )
          else ...[
            _row(
              label: t('common.iron', 'Iron'),
              role: t(
                'flutter.cofactor.iron_role',
                'oxygen and brain, not height directly',
              ),
              avg: _avgIron ?? 0,
              target: _ironTarget.toDouble(),
              unit: t('flutter.mg', 'mg'),
            ),
            const SizedBox(height: 12),
            _row(
              label: t('common.vitamin_d', 'Vitamin D'),
              role: t(
                'flutter.cofactor.vitd_role',
                'from food only — sunlight adds more',
              ),
              avg: _avgVitD ?? 0,
              target: _vitDTarget.toDouble(),
              unit: 'IU',
              lowFoodExpected: true,
            ),
            if (_outdoorDays > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.wb_sunny_outlined,
                    size: 14,
                    color: GsColors.estimated,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t(
                        'flutter.cofactor.outdoor',
                        '{n} outdoor days logged — sunlight is the bigger vitamin D source',
                        {'n': '$_outdoorDays'},
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: GsColors.text2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
          ],
      ),
    );
  }

  Widget _row({
    required String label,
    required String role,
    required double avg,
    required double target,
    required String unit,
    bool lowFoodExpected = false,
  }) {
    final t = widget.i18n.t;
    final pct = target > 0 ? (avg / target * 100).round() : 0;
    final onTrack = pct >= 90;
    final color = onTrack ? GsColors.accent : GsColors.estimated;
    final verdict = onTrack
        ? t('flutter.cofactor.on_track', 'On track')
        : lowFoodExpected
        ? t('flutter.cofactor.low_food', 'Low from food')
        : t('flutter.cofactor.below', 'Below target');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    role,
                    style: const TextStyle(fontSize: 11, color: GsColors.text3),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: onTrack ? GsColors.accentLight : GsColors.estimatedLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                verdict,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: onTrack ? GsColors.accentDark : GsColors.estimatedDark,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${_fmt(avg)} $unit/${t('flutter.cofactor.day', 'day')} · ${t('flutter.cofactor.of_target', 'of {x} target', {'x': '${_fmt(target)} $unit'})} · $pct%',
          style: const TextStyle(fontSize: 12, color: GsColors.text2),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: GsColors.surface2,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
