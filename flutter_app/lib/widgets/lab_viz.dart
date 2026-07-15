// ══════════════════════════════════════════════════════════════════
// Lab-value visualization — evidence-based patient-facing patterns.
//
// Design sources (patient lab-result communication literature):
//  • A number-line "range bar" with the reference interval shaded is
//    the best-validated way to show where a value falls.
//  • Graded urgency beats a binary abnormal flag: values barely
//    outside the interval cause outsized alarm when painted red, so
//    a "slightly outside" tier sits between in-range and clearly-out.
//  • Plain-language status ("Within range", "Slightly above") instead
//    of clinical "abnormal".
//  • Serial trend beats a single snapshot — the sparkline draws the
//    reference band behind the series.
// The reference interval used is ALWAYS the one printed on the family's
// own lab report (entered with the result) — pediatric intervals are
// age- and sex-dependent, so the lab's own interval is the only one
// that is guaranteed age-matched. GrowSense never substitutes its own.
//
// Color semantics follow the app-wide scheme (same as the illness
// module's risk colors): accent = fine, estimated gold = caution,
// flag = clearly outside, measured blue = the data line itself.
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

// ── Status model ────────────────────────────────────────────────────

enum LabStatus { low, borderlineLow, inRange, borderlineHigh, high, noRange }

/// Fraction of the reference-interval width a value may sit beyond a
/// bound and still read as "slightly outside" rather than clearly out.
const _borderlineFrac = 0.15;

LabStatus labStatusOf(double value, double? low, double? high) {
  if (low == null && high == null) return LabStatus.noRange;
  // Borderline margin: 15% of the interval width; with a single bound
  // fall back to 10% of that bound's magnitude.
  final width = (low != null && high != null) ? high - low : null;
  final margin = width != null && width > 0
      ? width * _borderlineFrac
      : ((low ?? high)!.abs()) * 0.10;
  if (low != null && value < low) {
    return (low - value) <= margin ? LabStatus.borderlineLow : LabStatus.low;
  }
  if (high != null && value > high) {
    return (value - high) <= margin
        ? LabStatus.borderlineHigh
        : LabStatus.high;
  }
  return LabStatus.inRange;
}

Color labStatusColor(LabStatus s) => switch (s) {
      LabStatus.inRange => GsColors.accent,
      LabStatus.borderlineLow || LabStatus.borderlineHigh =>
        GsColors.estimated,
      LabStatus.low || LabStatus.high => GsColors.flag,
      LabStatus.noRange => GsColors.text3,
    };

String labStatusLabel(LabStatus s, I18n i18n) {
  final t = i18n.t;
  return switch (s) {
    LabStatus.inRange => t('flutter.lab.in_range', 'Within range'),
    LabStatus.borderlineLow =>
      t('flutter.lab.slightly_below', 'Slightly below range'),
    LabStatus.borderlineHigh =>
      t('flutter.lab.slightly_above', 'Slightly above range'),
    LabStatus.low => t('flutter.lab.below', 'Below range'),
    LabStatus.high => t('flutter.lab.above', 'Above range'),
    LabStatus.noRange => t('flutter.lab.no_range', 'No range given'),
  };
}

/// Colored pill with the plain-language status.
class LabStatusChip extends StatelessWidget {
  const LabStatusChip({super.key, required this.status, required this.i18n});
  final LabStatus status;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final color = labStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(labStatusLabel(status, i18n),
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Range bar (number line) ────────────────────────────────────────

/// Horizontal number line: grey track, shaded reference band, value
/// dot with a white ring. Bounds labelled beneath the band edges.
class LabRangeBar extends StatelessWidget {
  const LabRangeBar(
      {super.key,
      required this.value,
      required this.low,
      required this.high});
  final double value;
  final double? low;
  final double? high;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      width: double.infinity,
      child: CustomPaint(
        painter: _RangeBarPainter(
            value: value,
            low: low,
            high: high,
            status: labStatusOf(value, low, high)),
      ),
    );
  }
}

class _RangeBarPainter extends CustomPainter {
  _RangeBarPainter(
      {required this.value,
      required this.low,
      required this.high,
      required this.status});
  final double value;
  final double? low;
  final double? high;
  final LabStatus status;

  @override
  void paint(Canvas canvas, Size size) {
    const trackH = 8.0;
    final trackY = 8.0;
    final r = trackH / 2;

    // Scale: pad the interval by 35% each side so out-of-range values
    // have somewhere to land; degenerate cases fall back gracefully.
    final lo = low ?? (high != null ? high! - (high! - value).abs() - 1 : 0);
    final hi = high ?? (low != null ? low! + (value - low!).abs() + 1 : 1);
    final w = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    var min = lo - w * 0.35;
    var max = hi + w * 0.35;
    if (value < min) min = value - w * 0.08;
    if (value > max) max = value + w * 0.08;
    double x(double v) => (v - min) / (max - min) * size.width;

    // Track
    final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY, size.width, trackH), Radius.circular(r));
    canvas.drawRRect(track, Paint()..color = GsColors.surface2);

    // Reference band
    if (low != null || high != null) {
      final bandL = low != null ? x(low!) : 0.0;
      final bandR = high != null ? x(high!) : size.width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(bandL, trackY, bandR - bandL, trackH),
            Radius.circular(r)),
        Paint()..color = GsColors.accent.withValues(alpha: 0.22),
      );
      // Bound labels
      final labelStyle =
          const TextStyle(fontSize: 9, color: GsColors.text3);
      if (low != null) {
        _text(canvas, _fmtNum(low!), labelStyle,
            Offset(bandL, trackY + trackH + 3), size.width, center: true);
      }
      if (high != null) {
        _text(canvas, _fmtNum(high!), labelStyle,
            Offset(bandR, trackY + trackH + 3), size.width, center: true);
      }
    }

    // Value dot: white ring + status-colored core.
    final dotX = x(value).clamp(5.0, size.width - 5.0);
    final dotY = trackY + trackH / 2;
    canvas.drawCircle(Offset(dotX, dotY), 6.5, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(dotX, dotY), 5, Paint()..color = labStatusColor(status));
  }

  void _text(Canvas canvas, String s, TextStyle style, Offset at,
      double maxWidth,
      {bool center = false}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr)
      ..layout();
    var dx = center ? at.dx - tp.width / 2 : at.dx;
    dx = dx.clamp(0.0, maxWidth - tp.width);
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(covariant _RangeBarPainter old) =>
      old.value != value || old.low != low || old.high != high;
}

String _fmtNum(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(v.abs() < 10 ? 1 : 0);

// ── Trend sparkline ────────────────────────────────────────────────

/// Serial values for one analyte, oldest → newest, drawn over the
/// shaded reference band (from the newest entry's printed interval —
/// pediatric intervals move with age, so the most recent is the most
/// age-appropriate). Line in measured blue (confirmed data), per-point
/// dots colored by each entry's own status, endpoint emphasized.
class LabSparkline extends StatelessWidget {
  const LabSparkline({super.key, required this.points, this.project = true});

  /// (value, low, high) tuples oldest → newest.
  final List<({double value, double? low, double? high})> points;

  /// Draw a subtle dotted projection of the recent trend (≥3 points).
  /// A visual direction cue only — never a numeric prediction.
  final bool project;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(points, project)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.points, this.project);
  final List<({double value, double? low, double? high})> points;
  final bool project;

  /// Projected next value from the slope of the last (up to 3) points.
  double? _projValue() {
    if (!project || points.length < 3) return null;
    final n = points.length;
    // Slope over the last two intervals, then extend one interval.
    final slope = (points[n - 1].value - points[n - 3].value) / 2;
    return points[n - 1].value + slope;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final latest = points.last;
    final projValue = _projValue();

    // Y domain: values plus the band plus any projection, padded.
    var lo = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    var hi = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    if (latest.low != null && latest.low! < lo) lo = latest.low!;
    if (latest.high != null && latest.high! > hi) hi = latest.high!;
    if (projValue != null) {
      if (projValue < lo) lo = projValue;
      if (projValue > hi) hi = projValue;
    }
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    lo -= span * 0.18;
    hi += span * 0.18;

    // When projecting, reserve one extra x-slot for the projected point.
    final slots = (projValue != null ? points.length + 1 : points.length);
    const padX = 6.0;
    double x(int i) => slots == 1
        ? size.width / 2
        : padX + i / (slots - 1) * (size.width - padX * 2);
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    // Reference band behind everything.
    if (latest.low != null || latest.high != null) {
      final top = latest.high != null ? y(latest.high!) : 0.0;
      final bottom = latest.low != null ? y(latest.low!) : size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(0, top, size.width, bottom),
            const Radius.circular(4)),
        Paint()..color = GsColors.accent.withValues(alpha: 0.10),
      );
    }

    // Data line.
    if (points.length > 1) {
      final path = Path()..moveTo(x(0), y(points[0].value));
      for (var i = 1; i < points.length; i++) {
        path.lineTo(x(i), y(points[i].value));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = GsColors.measured
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }

    // Projection: dotted continuation of the recent trend, hollow
    // endpoint. Purely a direction cue — no number is shown.
    if (projValue != null) {
      final from = Offset(x(points.length - 1), y(points.last.value));
      final to = Offset(x(points.length), y(projValue));
      final paint = Paint()
        ..color = GsColors.text3.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      final total = (to - from).distance;
      final unit = (to - from) / total;
      var d = 0.0;
      while (d < total) {
        final s = from + unit * d;
        final e = from + unit * math.min(d + 2.5, total);
        canvas.drawLine(s, e, paint);
        d += 5.0;
      }
      canvas.drawCircle(to, 2.6, Paint()..color = GsColors.bg);
      canvas.drawCircle(
          to,
          2.6,
          Paint()
            ..color = GsColors.text3
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }

    // Dots: each point in its own status color, endpoint emphasized.
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final c = labStatusColor(labStatusOf(p.value, p.low, p.high));
      final isLast = i == points.length - 1;
      if (isLast) {
        canvas.drawCircle(
            Offset(x(i), y(p.value)), 5.5, Paint()..color = Colors.white);
      }
      canvas.drawCircle(
          Offset(x(i), y(p.value)), isLast ? 4.0 : 2.6, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.points != points || old.project != project;
}
