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
      final light = color.withValues(alpha: 0.55);
      final head = Color.lerp(light, color, pct)!;
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
            ..strokeWidth = 9 * scale
            ..strokeCap = StrokeCap.butt);
      final end = start + sweep;
      final startTip =
          center + Offset(math.cos(start) * r, math.sin(start) * r);
      final endTip = center + Offset(math.cos(end) * r, math.sin(end) * r);
      canvas.drawCircle(startTip, 4.5 * scale, Paint()..color = light);
      canvas.drawCircle(endTip, 4.5 * scale, Paint()..color = head);
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

/// Stylized hand radiograph — glowing bones on film-dark ground, with
/// the amber carpal-analysis ellipse echoing the real AI overlay.
class _BoneAgeDemoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const boneCol = Color(0xFFD6E6F5); // radiograph white-blue
    const amber = Color(0xFFE0BD75); // AI annotation accent

    // Film-dark vignette so the card interior reads as an X-ray plate
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.06, 0, w * 0.88, h), const Radius.circular(12)),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.1,
          colors: [
            const Color(0xFF07140E).withValues(alpha: 0.55),
            const Color(0xFF020805).withValues(alpha: 0.85),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Bone segment helper: blurred glow underlay + capsule stroke
    void bone(Offset a, Offset b, double width) {
      final glow = Paint()
        ..color = boneCol.withValues(alpha: 0.35)
        ..strokeWidth = width + 3
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final core = Paint()
        ..color = boneCol.withValues(alpha: 0.85)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, b, glow);
      canvas.drawLine(a, b, core);
    }

    // Layout: left-hand PA, wrist at bottom center, fingers fanning up.
    final cx = w * 0.5;
    final wristY = h * 0.97;

    // Radius + ulna stubs entering from below
    bone(Offset(cx - 7, h * 1.05), Offset(cx - 6, wristY - 4), 7);
    bone(Offset(cx + 8, h * 1.06), Offset(cx + 7, wristY - 2), 6);

    // Carpal cluster — small ossified circles (the AI's primary anchor)
    final carpals = [
      Offset(cx - 10, h * 0.86),
      Offset(cx + 2, h * 0.84),
      Offset(cx + 13, h * 0.86),
      Offset(cx - 4, h * 0.90),
      Offset(cx + 8, h * 0.91),
    ];
    for (final c in carpals) {
      canvas.drawCircle(
          c,
          4.2,
          Paint()
            ..color = boneCol.withValues(alpha: 0.30)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
      canvas.drawCircle(
          c, 3.2, Paint()..color = boneCol.withValues(alpha: 0.8));
    }

    // Metacarpals fanning from the carpals to the knuckle row, then
    // three phalanx segments per finger with joint gaps.
    // (dx of knuckle, finger length factor, base width)
    final fingers = [
      (-0.30, 0.72, 4.4), // index... actually little→index left to right
      (-0.15, 0.88, 4.8),
      (0.00, 1.00, 5.0), // middle — tallest
      (0.15, 0.90, 4.8),
    ];
    for (final f in fingers) {
      final kx = cx + w * f.$1;
      final knuckle = Offset(kx, h * 0.56);
      // metacarpal
      bone(Offset(cx + w * f.$1 * 0.35, h * 0.82), knuckle, f.$3 + 1);
      // phalanges: proximal, middle, distal with 3px gaps
      final tipY = h * (0.56 - 0.40 * f.$2);
      final seg = (knuckle.dy - tipY) / 3;
      for (var i = 0; i < 3; i++) {
        final yA = knuckle.dy - seg * i - 2.5;
        final yB = knuckle.dy - seg * (i + 1) + 2.5;
        bone(Offset(kx, yA), Offset(kx, yB), f.$3 - i * 0.9);
      }
    }
    // Thumb — two segments angled out to the right
    bone(Offset(cx + 16, h * 0.84), Offset(cx + w * 0.26, h * 0.66), 5.2);
    bone(Offset(cx + w * 0.26, h * 0.64), Offset(cx + w * 0.34, h * 0.50), 4.4);
    bone(Offset(cx + w * 0.34, h * 0.48), Offset(cx + w * 0.385, h * 0.38), 3.6);

    // AI carpal-analysis ellipse — dashed amber, like the real overlay
    final carpalRect = Rect.fromCenter(
        center: Offset(cx + 1, h * 0.875), width: w * 0.30, height: h * 0.16);
    final dashPaint = Paint()
      ..color = amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final ellipse = Path()..addOval(carpalRect);
    for (final metric in ellipse.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + 5, metric.length);
        canvas.drawPath(metric.extractPath(d, end), dashPaint);
        d = end + 4;
      }
    }
    // "5/8" carpal count chip beside the ellipse
    final tp = TextPainter(
        text: const TextSpan(
            text: '5/8',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: amber)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(cx + w * 0.19, h * 0.80));

    // Diagonal scan sheen — the AI "reading" the film
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.06, 0, w * 0.88, h), const Radius.circular(12)));
    canvas.rotate(-0.5);
    canvas.drawRect(
      Rect.fromLTWH(-w * 0.2, h * 0.72, w * 1.6, 14),
      Paint()
        ..shader = LinearGradient(colors: [
          amber.withValues(alpha: 0),
          amber.withValues(alpha: 0.20),
          amber.withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(-w * 0.2, 0, w * 1.6, 14)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
