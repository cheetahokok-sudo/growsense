// ══════════════════════════════════════════════════════════════════
// The original GrowSense logo, exactly as the PWA renders it:
// an accent-green rounded square with the white trend-line + dot
// (SVG path "M3 17l5-5 4 4 8-9", dot at 20,7), and the two-tone
// "Grow"+"Sense" wordmark (text / text3).
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../theme.dart';

class GsLogoMark extends StatelessWidget {
  const GsLogoMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: GsColors.accent,
        // PWA: 7px radius at 28px, 11px at 40px — scale linearly.
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: CustomPaint(painter: _TrendlinePainter()),
    );
  }
}

class _TrendlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // The glyph occupies ~54% of the mark, centered (15px in a 28px
    // box), in the SVG's 24-unit coordinate space.
    final glyph = size.width * 0.54;
    final offset = (size.width - glyph) / 2;
    final u = glyph / 24;
    Offset p(double x, double y) => Offset(offset + x * u, offset + y * u);

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(p(3, 17).dx, p(3, 17).dy)
      ..lineTo(p(8, 12).dx, p(8, 12).dy)
      ..lineTo(p(12, 16).dx, p(12, 16).dy)
      ..lineTo(p(20, 7).dx, p(20, 7).dy);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(p(20, 7), 1.2 * u, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class GsWordmark extends StatelessWidget {
  const GsWordmark(
      {super.key,
      this.fontSize = 14.5,
      this.growColor = GsColors.text,
      this.senseColor = GsColors.text3});
  final double fontSize;
  final Color growColor;
  final Color senseColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: 'Grow',
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: growColor)),
        TextSpan(
            text: 'Sense',
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
                color: senseColor)),
      ]),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Mark + wordmark side by side — the PWA's .topbar-logo.
class GsLogo extends StatelessWidget {
  const GsLogo(
      {super.key,
      this.markSize = 28,
      this.fontSize = 15.5,
      this.growColor = GsColors.text,
      this.senseColor = GsColors.text3});
  final double markSize;
  final double fontSize;
  final Color growColor;
  final Color senseColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GsLogoMark(size: markSize),
        const SizedBox(width: 9),
        Flexible(
          child: GsWordmark(
              fontSize: fontSize,
              growColor: growColor,
              senseColor: senseColor),
        ),
      ],
    );
  }
}
