// ══════════════════════════════════════════════════════════════════
// Welcome / About carousel — pre-login guide and "About GrowSense".
//
// Liquid-glass treatment (frosted translucent cards, soft ambient
// light blobs, specular top edge) over the deep-green brand hero.
// Deliberately self-contained: the demo visuals are lightweight
// painters with hardcoded sample values, NOT the live widgets — this
// screen must never touch core app state or core chart code. Glass is
// confined here (static page, few layers) so the BackdropFilter cost
// never lands inside the scrolling app.
// ══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen(
      {super.key, required this.i18n, this.aboutMode = false, this.onDone});
  final I18n i18n;

  /// true when opened from Account → "About GrowSense": back-button
  /// instead of skip, "Done" pops instead of continuing to login.
  final bool aboutMode;
  final VoidCallback? onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (widget.aboutMode) {
      Navigator.of(context).pop();
    } else {
      widget.onDone?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final slides = _slides(t);
    final isLast = _page == slides.length - 1;

    return Scaffold(
      backgroundColor: GsColors.deepGreen,
      body: Stack(
        children: [
          // Ambient light blobs — the "Illuminar" layer the glass
          // cards refract. Static, cheap, no animation cost.
          const Positioned(
              top: -60, left: -70, child: _GlowBlob(GsColors.accent, 260)),
          const Positioned(
              bottom: 120,
              right: -90,
              child: _GlowBlob(GsColors.measured, 300)),
          const Positioned(
              bottom: -80,
              left: -40,
              child: _GlowBlob(GsColors.estimated, 220)),

          SafeArea(
            child: Column(
              children: [
                // Top bar: back (about) or skip (pre-login)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(
                    children: [
                      if (widget.aboutMode)
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 20),
                        ),
                      const Spacer(),
                      if (!widget.aboutMode)
                        TextButton(
                          onPressed: _finish,
                          child: Text(t('flutter.welcome.skip', 'Skip'),
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Colors.white.withValues(alpha: 0.7))),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => slides[i],
                  ),
                ),

                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: i == _page ? 22 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withValues(alpha: i == _page ? 0.95 : 0.35),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // Primary button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: GsColors.deepGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26)),
                      ),
                      onPressed: () {
                        if (isLast) {
                          _finish();
                        } else {
                          _controller.nextPage(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic);
                        }
                      },
                      child: Text(
                        isLast
                            ? (widget.aboutMode
                                ? t('flutter.welcome.done', 'Done')
                                : t('flutter.welcome.start', 'Get started'))
                            : t('flutter.welcome.next', 'Next'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _slides(
      String Function(String, [String?, Map<String, String>?]) t) {
    return [
      _Slide(
        visual: const _BrandVisual(),
        title: t('flutter.welcome.s1_title', 'Grow with confidence'),
        body: t(
            'flutter.welcome.s1_body',
            'GrowSense turns everyday meals, play and sleep into a clear '
                'picture of your child’s growth — built with WHO '
                'standards and pediatric research.'),
      ),
      _Slide(
        visual: const _GlassCard(child: _RingDemo()),
        title: t('flutter.welcome.s2_title', 'One reading, three levers'),
        body: t(
            'flutter.welcome.s2_body',
            'Nutrition, activity and sleep wrap into one readiness score. '
                'The ring’s color deepens as each intake fills — '
                'and a daily insight tells you which lever to pull.'),
      ),
      _Slide(
        visual: const _GlassCard(child: _GrowthDemo()),
        title: t('flutter.welcome.s3_title', 'See the trajectory'),
        body: t(
            'flutter.welcome.s3_body',
            'WHO percentile channels, measured points, and a projection '
                'blended from genetics and daily habits — not just '
                'dots on a chart.'),
      ),
      _Slide(
        visual: const _GlassCard(child: _BoneAgeDemo()),
        title: t('flutter.welcome.s4_title',
            'The history no single clinic keeps'),
        body: t(
            'flutter.welcome.s4_body',
            'Every bone age X-ray from every hospital in one timeline, '
                'with an AI second opinion — bring the full story to '
                'your next consult.'),
      ),
    ];
  }
}

// ── Slide layout ────────────────────────────────────────────────────

class _Slide extends StatelessWidget {
  const _Slide({required this.visual, required this.title, required this.body});
  final Widget visual;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          visual,
          const SizedBox(height: 30),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.25)),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.55)),
        ],
      ),
    );
  }
}

/// Frosted liquid-glass card: backdrop blur over the ambient blobs,
/// low-alpha fill, hairline border, and a specular top edge highlight.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 280,
          height: 230,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.22)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Specular top-edge highlight
              Positioned(
                top: 0,
                left: 30,
                right: 30,
                child: Container(
                  height: 1.2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.55),
                      Colors.white.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
              Center(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft radial light blob behind the glass.
class _GlowBlob extends StatelessWidget {
  const _GlowBlob(this.color, this.size);
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            color.withValues(alpha: 0.32),
            color.withValues(alpha: 0.0),
          ]),
        ),
      ),
    );
  }
}

// ── Demo visuals (sample data, isolated from core widgets) ──────────

class _BrandVisual extends StatelessWidget {
  const _BrandVisual();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: GsColors.accent,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                  color: GsColors.accent.withValues(alpha: 0.45),
                  blurRadius: 40,
                  spreadRadius: 4),
            ],
          ),
          child:
              const Icon(Icons.trending_up, color: Colors.white, size: 42),
        ),
        const SizedBox(height: 18),
        const Text('GrowSense',
            style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5)),
      ],
    );
  }
}

class _RingDemo extends StatelessWidget {
  const _RingDemo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: CustomPaint(
        painter: _RingDemoPainter(),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('76',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      color: Colors.white)),
              Text('of 100',
                  style: TextStyle(fontSize: 9, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingDemoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 150;

    void ring(double radius, double pct, Color color) {
      final r = radius * scale;
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawCircle(
          center,
          r,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.14)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9 * scale);
      const start = -math.pi / 2;
      final sweep = 2 * math.pi * pct;
      final head =
          Color.lerp(color.withValues(alpha: 0.65), color, pct)!;
      canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..shader = SweepGradient(
              colors: [color.withValues(alpha: 0.55), head],
              transform: const GradientRotation(-math.pi / 2),
            ).createShader(rect)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9 * scale
            ..strokeCap = StrokeCap.round);
      final end = start + sweep;
      final tip = center + Offset(math.cos(end) * r, math.sin(end) * r);
      canvas.drawCircle(tip, 5.4 * scale, Paint()..color = head);
      canvas.drawCircle(tip, 2.2 * scale, Paint()..color = Colors.white);
    }

    // Brighter shades of the brand tokens so arcs pop on dark glass
    ring(60, 0.72, const Color(0xFF6FBF92));
    ring(46, 0.55, const Color(0xFF6FA4D8));
    ring(32, 0.90, const Color(0xFFD9B36A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _GrowthDemo extends StatelessWidget {
  const _GrowthDemo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 165,
      child: CustomPaint(painter: _GrowthDemoPainter()),
    );
  }
}

class _GrowthDemoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    Path channel(double topFrac, double botFrac) => Path()
      ..moveTo(0, h * (1 - topFrac * 0.35))
      ..quadraticBezierTo(
          w * 0.5, h * (0.72 - topFrac * 0.42), w, h * (0.5 - topFrac * 0.4))
      ..lineTo(w, h * (0.5 + botFrac * 0.12))
      ..quadraticBezierTo(w * 0.5, h * (0.72 + botFrac * 0.14), 0,
          h * (1 - topFrac * 0.35) + h * botFrac * 0.16)
      ..close();

    // WHO channels — two nested translucent bands
    canvas.drawPath(channel(1.0, 1.0),
        Paint()..color = Colors.white.withValues(alpha: 0.08));
    canvas.drawPath(channel(0.55, 0.55),
        Paint()..color = Colors.white.withValues(alpha: 0.10));

    // Measured points + line (measured-blue, brightened for dark bg)
    const blue = Color(0xFF7FB2E5);
    final pts = [
      Offset(w * 0.12, h * 0.82),
      Offset(w * 0.32, h * 0.72),
      Offset(w * 0.50, h * 0.60),
    ];
    final line = Paint()
      ..color = blue
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
    for (final p in pts) {
      canvas.drawCircle(p, 4.4, Paint()..color = blue);
      canvas.drawCircle(
          p,
          4.4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
    }

    // Estimated projection — dashed gold
    const gold = Color(0xFFE0BD75);
    final dash = Paint()
      ..color = gold
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    var x = w * 0.52;
    var y = h * 0.59;
    final dx = (w * 0.92 - x) / 8;
    final dy = (h * 0.38 - y) / 8;
    for (var i = 0; i < 8; i += 2) {
      canvas.drawLine(Offset(x + dx * i, y + dy * i),
          Offset(x + dx * (i + 1), y + dy * (i + 1)), dash);
    }
    canvas.drawCircle(Offset(w * 0.92, h * 0.38), 4.4,
        Paint()..color = gold.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _BoneAgeDemo extends StatelessWidget {
  const _BoneAgeDemo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: 165,
      child: CustomPaint(painter: _BoneAgeDemoPainter()),
    );
  }
}

class _BoneAgeDemoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // ±band around the identity diagonal
    final band = Path()
      ..moveTo(0, h * 0.80)
      ..lineTo(w, h * 0.05)
      ..lineTo(w, h * 0.35)
      ..lineTo(0, h * 1.0)
      ..close();
    canvas.drawPath(band, Paint()..color = Colors.white.withValues(alpha: 0.08));

    // Identity diagonal — dashed
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.6;
    final a = Offset(0, h * 0.9);
    final b = Offset(w, h * 0.2);
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + 6, total);
      canvas.drawLine(a + dir * d, a + dir * end, dash);
      d = end + 5;
    }

    // Serial studies below the line (delayed) with trajectory
    const blue = Color(0xFF7FB2E5);
    final pts = [
      Offset(w * 0.22, h * 0.86),
      Offset(w * 0.52, h * 0.66),
      Offset(w * 0.80, h * 0.44),
    ];
    final line = Paint()
      ..color = blue.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final tr = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      tr.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(tr, line);
    for (var i = 0; i < pts.length; i++) {
      if (i == pts.length - 1) {
        canvas.drawCircle(
            pts[i], 9, Paint()..color = blue.withValues(alpha: 0.25));
      }
      canvas.drawCircle(pts[i], 4.6, Paint()..color = blue);
      canvas.drawCircle(
          pts[i],
          4.6,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4);
    }

    // 🦴 marker chip near latest point
    final tp = TextPainter(
        text: const TextSpan(text: '🦴', style: TextStyle(fontSize: 15)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(w * 0.80 - 8, h * 0.44 - 30));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
