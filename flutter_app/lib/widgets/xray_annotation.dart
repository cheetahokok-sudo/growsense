// ══════════════════════════════════════════════════════════════════
// Annotated X-ray overlay — Flutter port of the PWA's
// buildAnnotationOverlaySVG (app.js:6491).
//
// The AI returns findings as text; this draws them back onto the film
// so a parent can see WHERE each finding is. That translation from
// "7/8 carpals identified" to a labelled region on their child's own
// X-ray is the part that makes the second opinion legible to someone
// who is not a radiologist.
//
// Geometry is ported coordinate-for-coordinate from the SVG, which was
// tuned over several passes against real films. The source viewBox is
// 0–100 with preserveAspectRatio="xMidYMid meet" inside a 832:888 box,
// which resolves to a CENTRED SQUARE of side min(w, h) — replicated
// exactly in _map() below, so the two platforms line up pixel for
// pixel on the same image.
//
// ⚠️ These are approximate anatomical positions, not per-image
// detections: the AI reports appearance per bone group, not
// coordinates. Nothing here is calibrated to the individual film, and
// the caption says so. If DICOM ingest ever lands (real mm/pixel), the
// coordinates become measured rather than assumed — until then, do not
// present this as measurement.
//
// Anatomical labels stay in English: they are standard terms, they sit
// at fixed coordinates with no room to reflow, and they match the PWA
// so a parent comparing the two sees the same thing. Only the caption
// and legend heading are translated.
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

/// The PWA container's aspect ratio (.xray-annotated-container).
const double _kFilmAspect = 832 / 888;

/// Appearance → colour, same mapping as the PWA. absent is muted,
/// then blue → green → gold → red as maturation advances, which is the
/// brand's measured/estimated/flag ramp rather than an invented scale.
Color _appearanceColor(String? appearance) => switch (appearance) {
  'barely_visible' => GsColors.measured,
  'small_clear' => GsColors.accent,
  'well_formed' => GsColors.estimated,
  'wide_capping' => GsColors.flag,
  _ => GsColors.text3, // absent / unknown
};

class XrayAnnotationOverlay extends StatelessWidget {
  const XrayAnnotationOverlay({
    super.key,
    required this.appState,
    required this.xrayPath,
    required this.result,
    required this.i18n,
  });

  final AppState appState;
  final String xrayPath;
  final Map<String, dynamic> result;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return FutureBuilder<String?>(
      future: appState.xraySignedUrl(xrayPath),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) {
          return AspectRatio(
            aspectRatio: _kFilmAspect,
            child: Container(
              decoration: BoxDecoration(
                color: GsColors.deepGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: snap.connectionState == ConnectionState.waiting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: GsColors.text3,
                    ),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: _kFilmAspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                Image.network(url, fit: BoxFit.contain),
                CustomPaint(painter: _AnnotationPainter(result)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        t(
                          'flutter.ba.overlay_caption',
                          'AI annotation overlay · Regions are approximate anatomical positions',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 9,
                          height: 1.3,
                          color: GsColors.text3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Painter ─────────────────────────────────────────────────────────

enum _Anchor { start, middle, end }

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter(this.result);
  final Map<String, dynamic> result;

  // Set by paint() before any drawing helper runs.
  late double _scale;
  late Offset _origin;

  /// Source viewBox (0–100) → canvas, replicating SVG
  /// preserveAspectRatio="xMidYMid meet": a centred square of side
  /// min(w, h).
  Offset _map(double x, double y) =>
      Offset(_origin.dx + x * _scale, _origin.dy + y * _scale);

  double _s(double v) => v * _scale;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return; // laid out at zero — nothing to draw on
    _scale = side / 100;
    _origin = Offset((size.width - side) / 2, (size.height - side) / 2);

    // Everything below is defensive on purpose. This JSON comes from a
    // language model, so a wrong type or a null inside a list is a
    // question of when, not if — and an exception here would black out
    // the whole record screen, not just the overlay. `as Map?` would
    // THROW on a String; `is Map` degrades to an empty overlay instead.
    final carpals =
        result['carpal_analysis'] is Map ? result['carpal_analysis'] as Map : const {};
    final obs = result['epiphyseal_observations'] is List
        ? result['epiphyseal_observations'] as List
        : const [];

    String? appearanceOf(String group) {
      for (final o in obs) {
        if (o is Map && o['bone_group'] == group) {
          final a = o['appearance'];
          return a is String ? a : null;
        }
      }
      return null;
    }

    Color colorOf(String group) => _appearanceColor(appearanceOf(group));
    String labelOf(String group) =>
        (appearanceOf(group) ?? '').replaceAll('_', ' ');

    final rawIds = carpals['bones_identified'];
    final ids = [
      if (rawIds is List)
        for (final b in rawIds)
          if (b != null) b.toString().toLowerCase(),
    ];
    bool has(String name) => ids.any((b) => b.contains(name));

    // ── Distal radius band ──
    final rC = colorOf('distal_radius');
    _dashedRRect(canvas, 33, 79, 23, 5, 1, rC);
    _text(canvas, 'Radius', 32, 81, 3.2, rC, anchor: _Anchor.end, bold: true);
    _text(
      canvas,
      labelOf('distal_radius'),
      32,
      84.5,
      2.5,
      rC.withValues(alpha: 0.85),
      anchor: _Anchor.end,
    );
    _line(canvas, 32.5, 81.5, 33, 81.5, rC, 0.4);

    // ── Carpal region ──
    const carpalColor = GsColors.estimated;
    _dashedEllipse(
      canvas,
      46,
      73,
      16,
      7.5,
      carpalColor,
      strokeWidth: 0.7,
      dash: 2.5,
      gap: 2,
      fillAlpha: 0.063,
    );
    _text(canvas, 'Carpals', 64, 70, 3.2, carpalColor, bold: true);
    _text(
      canvas,
      '${carpals['count_visible'] ?? 0}/8 found',
      64,
      73.5,
      2.5,
      carpalColor.withValues(alpha: 0.85),
    );
    _line(canvas, 62, 72, 63.5, 71.5, carpalColor, 0.4);

    // ── Individual carpal bones, drawn only when the AI named them ──
    if (has('capitate')) _carpal(canvas, 51, 72, 2.8, 'Cap', 77.5, 0.8);
    if (has('hamate')) _carpal(canvas, 43, 74.5, 2.3, 'Ham', 79.5, 0.8);
    if (has('triquetrum')) {
      _carpal(canvas, 36, 76.5, 2, 'Triq', 81, 0.7, dashed: true);
    }
    if (has('lunate')) _carpal(canvas, 58, 71, 2, 'Lun', 75.5, 0.7);
    if (has('scaphoid')) _carpal(canvas, 55, 68, 2, 'Scap', 72.5, 0.7);

    // ── Epiphyseal groups, distal → proximal ──
    _group(
      canvas,
      44,
      57,
      20,
      5.5,
      66,
      54.5,
      58.5,
      64,
      57,
      65.5,
      56.5,
      'Metacarpals',
      labelOf('metacarpals'),
      colorOf('metacarpals'),
    );
    _group(
      canvas,
      43,
      43,
      19,
      5,
      64,
      40.5,
      44.5,
      62,
      43,
      63.5,
      42.5,
      'Prox. phalan.',
      labelOf('proximal_phalanges'),
      colorOf('proximal_phalanges'),
    );
    _group(
      canvas,
      43,
      31,
      17,
      4.5,
      62,
      28.5,
      32.5,
      60,
      31,
      61.5,
      30.5,
      'Mid. phalan.',
      labelOf('middle_phalanges'),
      colorOf('middle_phalanges'),
    );
    _group(
      canvas,
      43,
      18,
      14,
      4,
      59,
      15.5,
      19.5,
      57,
      18,
      58.5,
      17.5,
      'Dist. phalan.',
      labelOf('distal_phalanges'),
      colorOf('distal_phalanges'),
    );

    _legend(canvas);
  }

  void _group(
    Canvas canvas,
    double cx,
    double cy,
    double rx,
    double ry,
    double tx,
    double ty1,
    double ty2,
    double lx1,
    double ly1,
    double lx2,
    double ly2,
    String title,
    String sub,
    Color c,
  ) {
    _dashedEllipse(
      canvas,
      cx,
      cy,
      rx,
      ry,
      c,
      strokeWidth: 0.6,
      dash: 2,
      gap: 1.5,
      fillAlpha: 0.094,
    );
    _text(canvas, title, tx, ty1, 3.2, c, bold: true);
    _text(canvas, sub, tx, ty2, 2.5, c.withValues(alpha: 0.85));
    _line(canvas, lx1, ly1, lx2, ly2, c, 0.4);
  }

  void _carpal(
    Canvas canvas,
    double cx,
    double cy,
    double r,
    String label,
    double labelY,
    double strokeWidth, {
    bool dashed = false,
  }) {
    const c = GsColors.estimated;
    final centre = _map(cx, cy);
    canvas.drawCircle(
      centre,
      _s(r),
      Paint()..color = c.withValues(alpha: 0.157),
    );
    final stroke = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = _s(strokeWidth);
    if (dashed) {
      final p = Path()..addOval(Rect.fromCircle(center: centre, radius: _s(r)));
      canvas.drawPath(_dash(p, _s(1.5), _s(1)), stroke);
    } else {
      canvas.drawCircle(centre, _s(r), stroke);
    }
    _text(canvas, label, cx, labelY, 2.3, c, anchor: _Anchor.middle);
  }

  void _legend(Canvas canvas) {
    // Panel sits bottom-left, over the film's dark border area.
    final rect = RRect.fromRectAndRadius(
      Rect.fromPoints(_map(1, 88), _map(41, 99)),
      Radius.circular(_s(1.5)),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = const Color(0xFF1F2B22).withValues(alpha: 0.6),
    );
    _text(
      canvas,
      'APPEARANCE SCALE',
      2.5,
      91.5,
      2.4,
      GsColors.text3,
      bold: true,
    );
    void entry(double cx, double cy, Color c, String label) {
      canvas.drawCircle(_map(cx, cy), _s(1.2), Paint()..color = c);
      _text(canvas, label, cx + 2.5, cy + 1, 2.2, const Color(0xFFEEF0EC));
    }

    entry(4, 94.5, GsColors.measured, 'barely visible');
    entry(21, 94.5, GsColors.accent, 'small, clear');
    entry(4, 98, GsColors.estimated, 'well formed');
    entry(21, 98, GsColors.flag, 'wide/capping');
  }

  // ── Primitives ──

  void _line(
    Canvas canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    Color c,
    double w,
  ) => canvas.drawLine(
    _map(x1, y1),
    _map(x2, y2),
    Paint()
      ..color = c
      ..strokeWidth = _s(w),
  );

  void _dashedRRect(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
    double r,
    Color c,
  ) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromPoints(_map(x, y), _map(x + w, y + h)),
      Radius.circular(_s(r)),
    );
    canvas.drawRRect(rr, Paint()..color = c.withValues(alpha: 0.094));
    canvas.drawPath(
      _dash(Path()..addRRect(rr), _s(2), _s(1.5)),
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = _s(0.6),
    );
  }

  void _dashedEllipse(
    Canvas canvas,
    double cx,
    double cy,
    double rx,
    double ry,
    Color c, {
    required double strokeWidth,
    required double dash,
    required double gap,
    required double fillAlpha,
  }) {
    final rect = Rect.fromCenter(
      center: _map(cx, cy),
      width: _s(rx * 2),
      height: _s(ry * 2),
    );
    canvas.drawOval(rect, Paint()..color = c.withValues(alpha: fillAlpha));
    canvas.drawPath(
      _dash(Path()..addOval(rect), _s(dash), _s(gap)),
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = _s(strokeWidth),
    );
  }

  /// SVG stroke-dasharray has no Flutter equivalent; walk the path and
  /// emit alternating segments.
  Path _dash(Path source, double dashLen, double gapLen) {
    final out = Path();
    if (dashLen <= 0 || gapLen <= 0) return source;
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLen, metric.length);
        out.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gapLen;
      }
    }
    return out;
  }

  /// SVG `y` is the text BASELINE; Flutter positions from the top, so
  /// measure the real ascent rather than guessing a factor.
  void _text(
    Canvas canvas,
    String text,
    double x,
    double baselineY,
    double fontSize,
    Color color, {
    _Anchor anchor = _Anchor.start,
    bool bold = false,
  }) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: _s(fontSize),
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontFamily: 'monospace',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final p = _map(x, baselineY);
    final dx = switch (anchor) {
      _Anchor.start => 0.0,
      _Anchor.middle => -tp.width / 2,
      _Anchor.end => -tp.width,
    };
    tp.paint(canvas, Offset(p.dx + dx, p.dy - ascent));
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter old) =>
      !identical(old.result, result);
}

// ── Test hooks ──────────────────────────────────────────────────────
// The painter is private so nothing outside this file can depend on
// its geometry, but paint() is exactly what needs exercising: it runs
// against model-authored JSON and must never throw. These give the
// tests a way in without widening the real API.

@visibleForTesting
void debugPaintXrayAnnotations(
        Canvas canvas, Size size, Map<String, dynamic> result) =>
    _AnnotationPainter(result).paint(canvas, size);

@visibleForTesting
Color xrayAppearanceColorForTest(String? appearance) =>
    _appearanceColor(appearance);
