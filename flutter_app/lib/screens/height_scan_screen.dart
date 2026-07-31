import 'package:flutter/material.dart';

import '../height_scan.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/gs_icons.dart';

/// Height Scan — guided AR height measurement (iOS-only).
///
/// The camera view is the native ARKit platform view; this screen is
/// the overlay that walks the parent through it. v2 of the flow:
/// illustrated setup scene, an explicit six-mark sequence
/// (①feet ①head ②feet ②head ③feet ③head) echoed as a live progress
/// row, numbered AR level lines + a vertical measure drawn by the
/// native side, redo of a single mark, and two honesty hints
/// (too-close, readings-disagree). Pops with the median height in cm
/// (double), or null if cancelled — the measurement entry card
/// prefills from it and owns the actual save (weight, date, cap).
class HeightScanScreen extends StatefulWidget {
  const HeightScanScreen({super.key, required this.i18n});
  final I18n i18n;

  static const readingsNeeded = 3;

  /// Readings further apart than this get the "scan again" nudge.
  static const spreadWarnCm = 2.0;

  /// Marks closer than this (both in a pair) suggest the parent is too
  /// close for clean raycast angles.
  static const tooCloseM = 1.5;

  @override
  State<HeightScanScreen> createState() => _HeightScanScreenState();
}

enum _Phase { intro, findingFloor, aimFeet, aimHead, done }

class _HeightScanScreenState extends State<HeightScanScreen> {
  HeightScanController? _controller;
  _Phase _phase = _Phase.intro;
  final List<double> _readings = [];
  String? _hint; // transient guidance (no surface, implausible, too close…)
  bool _marking = false;
  double? _feetDistanceM; // current pair's feet mark distance

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onViewCreated(int viewId) {
    _controller = HeightScanController(
      viewId,
      onFloorFound: () {
        if (!mounted || _phase != _Phase.findingFloor) return;
        setState(() => _phase = _Phase.aimFeet);
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: GsColors.flag, content: Text(msg)));
        Navigator.of(context).pop();
      },
    );
  }

  Future<void> _mark() async {
    final t = widget.i18n.t;
    final c = _controller;
    if (c == null || _marking) return;
    setState(() {
      _marking = true;
      _hint = null;
    });
    final res = await c.markPoint();
    if (!mounted) return;
    setState(() {
      _marking = false;
      switch (res.step) {
        case 'feet':
          _feetDistanceM = res.distanceM;
          _phase = _Phase.aimHead;
        case 'head':
          _readings.add(res.heightCm!);
          // Both marks of this pair very close to the phone → shallow
          // raycast angles. Say so, but never block.
          final feetClose = (_feetDistanceM ?? 99) < HeightScanScreen.tooCloseM;
          final headClose = (res.distanceM ?? 99) < HeightScanScreen.tooCloseM;
          if (feetClose && headClose) {
            _hint = t('flutter.hscan.too_close',
                'A little far back helps accuracy — try 2–3 steps away');
          }
          _feetDistanceM = null;
          _phase = _readings.length >= HeightScanScreen.readingsNeeded
              ? _Phase.done
              : _Phase.aimFeet;
        case 'implausible':
          _feetDistanceM = null;
          _phase = _Phase.aimFeet;
          _hint = t('flutter.hscan.implausible',
              'That doesn\'t look right — starting this reading over');
        default: // no_surface
          _hint = t('flutter.hscan.no_surface',
              'Couldn\'t find a surface there — steady the phone and try again');
      }
    });
  }

  Future<void> _undo() async {
    final c = _controller;
    if (c == null || _marking) return;
    final undone = await c.undoMark();
    if (!mounted) return;
    setState(() {
      _hint = null;
      switch (undone) {
        case 'feet':
          _feetDistanceM = null;
          _phase = _Phase.aimFeet;
        case 'head':
          if (_readings.isNotEmpty) _readings.removeLast();
          _phase = _Phase.aimHead;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera only spins up once the parent has read the intro.
          if (_phase != _Phase.intro)
            UiKitView(
              viewType: 'growsense/height_scan_view',
              onPlatformViewCreated: _onViewCreated,
            ),
          if (_phase == _Phase.intro) _intro(t) else _overlay(t),
        ],
      ),
    );
  }

  // ── Intro: illustration + the measurement discipline + sequence ──
  Widget _intro(String Function(String, [String?, Map<String, String>?]) t) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const GsIcon('hscan_cam', size: 22),
                const SizedBox(width: 8),
                Text(t('flutter.hscan.title', 'Height Scan'),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ],
            ),
            const SizedBox(height: 18),
            // Setup scene: who stands where, what gets aimed at.
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(10),
              child: AspectRatio(
                aspectRatio: 240 / 128,
                child: CustomPaint(painter: _SetupScenePainter()),
              ),
            ),
            const SizedBox(height: 16),
            _introStep('hscan_wall',
                t('flutter.hscan.intro_1', 'Barefoot, standing tall against a wall')),
            _introStep('hscan_distance',
                t('flutter.hscan.intro_2', 'Stand 2–3 steps back and hold the phone steady')),
            _introStep('hscan_reticle',
                t('flutter.hscan.intro_3', 'Mark the feet, then the top of the head — 3 times')),
            _introStep('hscan_morning',
                t('flutter.hscan.intro_4', 'Scan at the same time of day — kids are taller in the morning')),
            const SizedBox(height: 14),
            _sequenceStrip(t, active: -1),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: GsColors.accent),
              onPressed: () => setState(() => _phase = _Phase.findingFloor),
              child: Text(t('flutter.hscan.start', 'Start scanning')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('flutter.cancel', 'Cancel'),
                  style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _introStep(String icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: GsIcon(icon, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 14.5))),
        ]),
      );

  /// The six-mark rhythm: ①feet ①head ②feet ②head ③feet ③head.
  /// [active] = 0-based index of the CURRENT mark (bold), earlier ones
  /// tick; -1 shows the strip neutrally (intro).
  Widget _sequenceStrip(
      String Function(String, [String?, Map<String, String>?]) t,
      {required int active}) {
    final feet = t('flutter.hscan.feet', 'feet');
    final head = t('flutter.hscan.head', 'head');
    final children = <Widget>[];
    for (var i = 0; i < HeightScanScreen.readingsNeeded * 2; i++) {
      final reading = i ~/ 2 + 1;
      final label = i.isEven ? feet : head;
      final done = active >= 0 && i < active;
      final current = i == active;
      children.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: current
              ? GsColors.accent
              : Colors.white.withValues(alpha: done ? 0.28 : 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          done ? '$reading $label ✓' : '$reading $label',
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.white.withValues(alpha: current || done ? 1 : 0.65),
            fontWeight: current ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ));
    }
    return Wrap(
        spacing: 5, runSpacing: 5, alignment: WrapAlignment.center,
        children: children);
  }

  // ── Live overlay: guidance + crosshair + progress + controls ─────
  Widget _overlay(String Function(String, [String?, Map<String, String>?]) t) {
    final done = _phase == _Phase.done;
    final guidance = switch (_phase) {
      _Phase.findingFloor => t('flutter.hscan.finding_floor',
          'Move the phone slowly so it can find the floor…'),
      _Phase.aimFeet => t('flutter.hscan.aim_feet',
          'Aim the circle at your child\'s feet, then tap Mark'),
      _Phase.aimHead => t('flutter.hscan.aim_head',
          'Now aim at the top of their head and tap Mark'),
      _ => '',
    };
    // Current mark index for the strip: two per finished reading, +1
    // if the feet of the current pair is already placed.
    final activeMark =
        _readings.length * 2 + (_phase == _Phase.aimHead ? 1 : 0);

    return SafeArea(
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text(
                  done
                      ? t('flutter.hscan.result_title', 'Scan complete')
                      : guidance,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              if (_hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_hint!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFFFFC978), fontSize: 13)),
                ),
            ]),
          ),
          const Spacer(),
          if (!done)
            IgnorePointer(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Center(
                    child: Icon(Icons.add, color: Colors.white, size: 20)),
              ),
            ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(14)),
            child: done ? _result(t) : _controls(t, activeMark),
          ),
        ],
      ),
    );
  }

  Widget _controls(
      String Function(String, [String?, Map<String, String>?]) t,
      int activeMark) {
    final canMark = _phase == _Phase.aimFeet || _phase == _Phase.aimHead;
    final canUndo = canMark &&
        (_phase == _Phase.aimHead || _readings.isNotEmpty) &&
        !_marking;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _sequenceStrip(t, active: activeMark),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white38)),
            child: Text(t('flutter.cancel', 'Cancel'),
                style: const TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: canUndo ? _undo : null,
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white38)),
            child: Text(t('flutter.hscan.redo', 'Redo'),
                style: TextStyle(
                    color: canUndo ? Colors.white : Colors.white38)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GsColors.accent),
            onPressed: canMark && !_marking ? _mark : null,
            child: Text(_marking ? '…' : t('flutter.hscan.mark', 'Mark')),
          ),
        ),
      ]),
    ]);
  }

  Widget _result(String Function(String, [String?, Map<String, String>?]) t) {
    final median = heightScanMedian(_readings);
    final sorted = [..._readings]..sort();
    final spread = sorted.last - sorted.first;
    final disagree = spread > HeightScanScreen.spreadWarnCm;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${median.toStringAsFixed(1)} cm',
          style: const TextStyle(
              color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(_readings.map((r) => r.toStringAsFixed(1)).join(' · '),
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      if (disagree)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              t(
                  'flutter.hscan.spread_warn',
                  'The readings disagree by {cm} cm — a fresh scan may be more accurate',
                  {'cm': spread.toStringAsFixed(1)}),
              textAlign: TextAlign.center,
              // Estimated-gold: honest caution, never a blocker.
              style: const TextStyle(color: Color(0xFFD9B36A), fontSize: 12.5)),
        ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _readings.clear();
                _feetDistanceM = null;
                _hint = null;
                _phase = _Phase.aimFeet;
                _controller?.reset();
              });
            },
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white38)),
            child: Text(t('flutter.hscan.rescan', 'Scan again'),
                style: const TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GsColors.accent),
            onPressed: () => Navigator.of(context).pop(median),
            child: Text(t('flutter.hscan.use', 'Use this height')),
          ),
        ),
      ]),
    ]);
  }
}

/// The intro setup scene: child against the wall, parent 2–3 steps
/// back holding the phone upright, gold sight-lines to feet and
/// head-top, distance bracket. Deliberately simple geometric figures —
/// round head, capsule body — nothing anatomical to get wrong.
class _SetupScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Design space 240x128, scaled to fit.
    final sx = size.width / 240.0;
    final sy = size.height / 128.0;
    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final wallFloor = Paint()
      ..color = GsColors.accent
      ..strokeWidth = 3.5 * sx
      ..strokeCap = StrokeCap.round;
    final parent = Paint()..color = const Color(0xFF9AA79D);
    final child = Paint()..color = GsColors.accent;
    final mint = Paint()
      ..color = const Color(0xFF78D6A0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * sx;
    final phoneFill = Paint()..color = GsColors.deepGreen;
    final sight = Paint()
      ..color = GsColors.estimated
      ..strokeWidth = 1.7 * sx
      ..strokeCap = StrokeCap.round;
    final bracket = Paint()
      ..color = const Color(0xFFB9C4BB)
      ..strokeWidth = 1.4 * sx;

    // Wall + floor
    canvas.drawLine(p(210, 6), p(210, 112), wallFloor);
    canvas.drawLine(p(12, 112), p(228, 112), wallFloor);

    // Parent: head, body, legs, arm
    canvas.drawCircle(p(52, 30), 10 * sx, parent);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(44 * sx, 42 * sy, 17 * sx, 44 * sy),
            Radius.circular(7 * sx)),
        parent);
    for (final x in [47.0, 54.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x * sx, 87 * sy, 5 * sx, 24 * sy),
              Radius.circular(2 * sx)),
          parent);
    }
    canvas.drawLine(p(60, 52), p(82, 58),
        Paint()
          ..color = const Color(0xFF9AA79D)
          ..strokeWidth = 5 * sx
          ..strokeCap = StrokeCap.round);

    // Phone (upright, mint edge)
    final phoneRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(80 * sx, 46 * sy, 13 * sx, 24 * sy),
        Radius.circular(3 * sx));
    canvas.drawRRect(phoneRect, phoneFill);
    canvas.drawRRect(phoneRect, mint);

    // Child against the wall
    canvas.drawCircle(p(194, 36), 9 * sx, child);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(187 * sx, 47 * sy, 14 * sx, 38 * sy),
            Radius.circular(6 * sx)),
        child);
    for (final x in [189.0, 195.5]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x * sx, 86 * sy, 4.5 * sx, 25 * sy),
              Radius.circular(2 * sx)),
          child);
    }

    // Dashed sight-lines: phone → head-top, phone → feet
    _dashedLine(canvas, p(93, 52), p(190, 28), sight, 4.5 * sx, 3.5 * sx);
    _dashedLine(canvas, p(93, 64), p(191, 110), sight, 4.5 * sx, 3.5 * sx);

    // Distance bracket + label
    canvas.drawLine(p(66, 122), p(182, 122), bracket);
    canvas.drawLine(p(66, 118), p(66, 126), bracket);
    canvas.drawLine(p(182, 118), p(182, 126), bracket);
    final tp = TextPainter(
      text: TextSpan(
          text: '2–3',
          style: TextStyle(
              color: const Color(0xFFB9C4BB),
              fontSize: 9 * sx,
              fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p(124, 121) - Offset(tp.width / 2, tp.height / 2));
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      double dash, double gap) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = (d + dash).clamp(0.0, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
