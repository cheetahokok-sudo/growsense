import 'package:flutter/material.dart';

import '../height_scan.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/gs_icons.dart';

/// Height Scan — guided AR height measurement (iOS-only).
///
/// The camera view is the native ARKit platform view; this screen is
/// the overlay that walks the parent through it. v4 flow: the phone
/// stays STILL with the whole child in frame. The parent taps a FEET
/// marker (where the wall meets the floor, between the heels) and a
/// HEAD marker (the crown), fine-tunes them with reduced-gain drags,
/// then Measure runs a ~1 s native sampling burst with quality gates.
/// Three bursts, median of medians. Pops with the median height in cm
/// (double), or null if cancelled — the measurement entry card
/// prefills from it and owns the actual save (weight, date, cap).
class HeightScanScreen extends StatefulWidget {
  const HeightScanScreen({super.key, required this.i18n});
  final I18n i18n;

  static const readingsNeeded = 3;

  /// Readings further apart than this get the "scan again" nudge.
  static const spreadWarnCm = 2.0;

  /// Feet closer than this suggests the parent can't frame the whole
  /// child — shallow angles hurt accuracy.
  static const tooCloseM = 1.5;

  /// Head-ray elevation above this means the parent is aiming steeply
  /// upward — the step-back hint fires.
  static const maxHeadPitchDeg = 25.0;

  /// Finger-to-marker gain while fine-tuning: 3 px of finger movement
  /// moves the line 1 px, so the crown can be hit precisely.
  static const dragGain = 1 / 3;

  @override
  State<HeightScanScreen> createState() => _HeightScanScreenState();
}

enum _Phase { intro, findingFloor, placeFeet, placeHead, ready, sampling, done }

class _HeightScanScreenState extends State<HeightScanScreen> {
  HeightScanController? _controller;
  _Phase _phase = _Phase.intro;
  final List<double> _readings = [];
  String? _hint; // transient guidance (no floor, hold still, too close…)

  // Marker positions, normalized 0–1 against the full-screen camera.
  Offset? _feetMarker;
  Offset? _headMarker;

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
        setState(() => _phase = _Phase.placeFeet);
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: GsColors.flag, content: Text(msg)));
        Navigator.of(context).pop();
      },
    );
  }

  Offset _clampMarker(Offset o) =>
      Offset(o.dx.clamp(0.02, 0.98), o.dy.clamp(0.02, 0.98));

  Future<void> _pushMarkers() async {
    await _controller?.setMarkers(feet: _feetMarker, head: _headMarker);
  }

  void _onTapDown(TapDownDetails d, Size screen) {
    if (_phase != _Phase.placeFeet && _phase != _Phase.placeHead) return;
    // localPosition of the full-Stack detector == position inside the
    // UiKitView — never normalize against global/screen coords, which
    // can drift from the platform view's own bounds.
    final norm = _clampMarker(Offset(
        d.localPosition.dx / screen.width, d.localPosition.dy / screen.height));
    setState(() {
      _hint = null;
      if (_phase == _Phase.placeFeet) {
        _feetMarker = norm;
        _phase = _Phase.placeHead;
      } else {
        _headMarker = norm;
        _phase = _Phase.ready;
      }
    });
    _pushMarkers();
  }

  void _dragMarker(bool isFeet, double dyPx, Size screen) {
    final current = isFeet ? _feetMarker : _headMarker;
    if (current == null) return;
    final moved = _clampMarker(Offset(current.dx,
        current.dy + dyPx * HeightScanScreen.dragGain / screen.height));
    setState(() {
      if (isFeet) {
        _feetMarker = moved;
      } else {
        _headMarker = moved;
      }
    });
  }

  Future<void> _measure() async {
    final t = widget.i18n.t;
    final c = _controller;
    if (c == null || _phase != _Phase.ready) return;
    setState(() {
      _phase = _Phase.sampling;
      _hint = null;
    });
    await _pushMarkers();
    final res = await c.measure();
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _readings.add(res.heightCm!);
        // Honesty hints — advisory only, never blocking.
        if ((res.pitchDeg ?? 0) > HeightScanScreen.maxHeadPitchDeg) {
          _hint = t('flutter.hscan.step_back_pitch',
              'You\'re aiming steeply upward — step back until the whole child fits on screen');
        } else if ((res.distanceM ?? 99) < HeightScanScreen.tooCloseM) {
          _hint = t('flutter.hscan.too_close',
              'Step back until the whole child fits on screen — about 2–2.5 m');
        }
        _phase = _readings.length >= HeightScanScreen.readingsNeeded
            ? _Phase.done
            : _Phase.ready;
      } else {
        _phase = _Phase.ready;
        _hint = switch (res.reason) {
          'no_floor' => t('flutter.hscan.no_floor',
              'Can\'t find the floor there — aim the feet line at clear floor between the feet'),
          'unstable' => t('flutter.hscan.unstable',
              'Too much movement — hold the phone still and measure again'),
          _ => t('flutter.hscan.hold_still_retry',
              'Couldn\'t get a steady reading — hold the phone still and try again'),
        };
      }
    });
  }

  void _rescan() {
    setState(() {
      _readings.clear();
      _feetMarker = null;
      _headMarker = null;
      _hint = null;
      _phase = _Phase.placeFeet;
      _controller?.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final screen = MediaQuery.of(context).size;
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
          // Tap-to-place layer sits under the overlay cards, so buttons
          // still win hit-testing.
          if (_phase == _Phase.placeFeet || _phase == _Phase.placeHead)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _onTapDown(d, screen),
            ),
          if (_feetMarker != null)
            _MarkerLine(
              yNorm: _feetMarker!.dy,
              color: const Color(0xFF78D6A0),
              label: t('flutter.hscan.feet', 'feet'),
              draggable: _phase == _Phase.ready,
              onDrag: (dy) => _dragMarker(true, dy, screen),
              onDragEnd: _pushMarkers,
            ),
          if (_headMarker != null)
            _MarkerLine(
              yNorm: _headMarker!.dy,
              color: Colors.white,
              label: t('flutter.hscan.head', 'head'),
              draggable: _phase == _Phase.ready,
              onDrag: (dy) => _dragMarker(false, dy, screen),
              onDragEnd: _pushMarkers,
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
                child: CustomPaint(
                    painter: _SetupScenePainter(
                        distLabel: t('flutter.hscan.dist_label', '2–2.5 m'))),
              ),
            ),
            const SizedBox(height: 16),
            _introStep('hscan_wall',
                t('flutter.hscan.intro_1',
                    'Barefoot, heels and back touching the wall, standing tall')),
            _introStep('hscan_distance',
                t('flutter.hscan.intro_2',
                    'Step back until the whole child fits on screen (about 2–2.5 m), hold the phone at the child\'s head height, and keep it still')),
            _introStep('hscan_reticle',
                t('flutter.hscan.intro_3',
                    'Tap the feet line, then the top of the head — the app measures 3 quick bursts')),
            _introStep('hscan_morning',
                t('flutter.hscan.intro_4', 'Scan at the same time of day — kids are taller in the morning')),
            const SizedBox(height: 14),
            _burstStrip(active: -1),
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

  /// The three-burst rhythm: chips ① ② ③. [active] = 0-based index of
  /// the burst being worked on; earlier ones tick; -1 = neutral.
  Widget _burstStrip({required int active}) {
    final children = <Widget>[];
    for (var i = 0; i < HeightScanScreen.readingsNeeded; i++) {
      final done = active >= 0 && i < active;
      final current = i == active;
      children.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
        decoration: BoxDecoration(
          color: current
              ? GsColors.accent
              : Colors.white.withValues(alpha: done ? 0.28 : 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          done ? '${i + 1} ✓' : '${i + 1}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: current || done ? 1 : 0.65),
            fontWeight: current ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ));
    }
    return Wrap(
        spacing: 6, runSpacing: 5, alignment: WrapAlignment.center,
        children: children);
  }

  // ── Live overlay: guidance + progress + controls ─────────────────
  Widget _overlay(String Function(String, [String?, Map<String, String>?]) t) {
    final done = _phase == _Phase.done;
    final guidance = switch (_phase) {
      _Phase.findingFloor => t('flutter.hscan.finding_floor',
          'Move the phone slowly so it can find the floor…'),
      _Phase.placeFeet => t('flutter.hscan.place_feet',
          'Tap the floor between the feet, right at the ankles — not the wall edge, not the toes'),
      _Phase.placeHead => t('flutter.hscan.place_head',
          'Tap the very top of the head — the crown, not the forehead. Flatten the hair'),
      _Phase.ready => _readings.isEmpty
          ? t('flutter.hscan.adjust',
              'Drag a line to fine-tune it — slow drags move it precisely. Then tap Measure')
          : t('flutter.hscan.between_bursts',
              'Check the lines still sit right, then measure again'),
      _Phase.sampling => t('flutter.hscan.hold_still', 'Hold the phone still…'),
      _ => '',
    };

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
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(14)),
            child: done ? _result(t) : _controls(t),
          ),
        ],
      ),
    );
  }

  /// Single-line button label — long i18n strings shrink instead of
  /// wrapping ("Can cel" / "Red o" were real field complaints).
  static Widget _label(String text, {Color? color}) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text,
            maxLines: 1, style: color == null ? null : TextStyle(color: color)),
      );

  Widget _controls(String Function(String, [String?, Map<String, String>?]) t) {
    final sampling = _phase == _Phase.sampling;
    final canMeasure = _phase == _Phase.ready;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _burstStrip(active: _readings.length),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: sampling ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                side: const BorderSide(color: Colors.white38)),
            child: _label(t('flutter.cancel', 'Cancel'), color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: GsColors.accent),
            onPressed: canMeasure ? _measure : null,
            child: sampling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : _label(t('flutter.hscan.measure', 'Measure')),
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
            onPressed: _rescan,
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                side: const BorderSide(color: Colors.white38)),
            child:
                _label(t('flutter.hscan.rescan', 'Scan again'), color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: GsColors.accent),
            onPressed: () => Navigator.of(context).pop(median),
            child: _label(t('flutter.hscan.use', 'Use this height')),
          ),
        ),
      ]),
    ]);
  }
}

/// One measuring line: full-width hairline + centre dot + label chip —
/// per field feedback, a line and a dot, nothing circular. Draggable
/// with reduced gain when [draggable]; the generous vertical hit area
/// keeps the thin line grabbable.
class _MarkerLine extends StatelessWidget {
  const _MarkerLine({
    required this.yNorm,
    required this.color,
    required this.label,
    required this.draggable,
    required this.onDrag,
    required this.onDragEnd,
  });

  final double yNorm;
  final Color color;
  final String label;
  final bool draggable;
  final void Function(double dyPx) onDrag;
  final Future<void> Function() onDragEnd;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    const hitHeight = 44.0;
    return Positioned(
      left: 0,
      right: 0,
      top: yNorm * h - hitHeight / 2,
      height: hitHeight,
      child: GestureDetector(
        behavior: draggable ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onVerticalDragUpdate: draggable ? (d) => onDrag(d.delta.dy) : null,
        onVerticalDragEnd: draggable ? (_) => onDragEnd() : null,
        child: Stack(alignment: Alignment.center, children: [
          // Shadow line for contrast on bright scenes, then the line.
          Container(
              height: 2,
              margin: const EdgeInsets.only(top: 2),
              color: Colors.black.withValues(alpha: 0.35)),
          Container(height: 2, color: color.withValues(alpha: 0.95)),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                  color: Colors.black.withValues(alpha: 0.4), width: 1),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(label,
                  style: TextStyle(color: color, fontSize: 11)),
            ),
          ),
          if (draggable)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(Icons.unfold_more,
                    size: 18, color: color.withValues(alpha: 0.85)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The intro setup scene: child against the wall, parent 2–2.5 m
/// back holding the phone still at the child's chest height, gold
/// sight-lines to feet and head-top, distance bracket. Deliberately
/// simple geometric figures — nothing anatomical to get wrong.
class _SetupScenePainter extends CustomPainter {
  _SetupScenePainter({required this.distLabel});
  final String distLabel;

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
    canvas.drawLine(p(60, 48), p(82, 38),
        Paint()
          ..color = const Color(0xFF9AA79D)
          ..strokeWidth = 5 * sx
          ..strokeCap = StrokeCap.round);

    // Phone — held still, LEVEL WITH THE CHILD'S HEAD: when camera
    // height ≈ crown height, feet-marker depth error stops mattering.
    final phoneRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(80 * sx, 26 * sy, 13 * sx, 24 * sy),
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
    _dashedLine(canvas, p(93, 32), p(190, 28), sight, 4.5 * sx, 3.5 * sx);
    _dashedLine(canvas, p(93, 44), p(191, 110), sight, 4.5 * sx, 3.5 * sx);

    // Distance bracket + label
    canvas.drawLine(p(66, 122), p(182, 122), bracket);
    canvas.drawLine(p(66, 118), p(66, 126), bracket);
    canvas.drawLine(p(182, 118), p(182, 126), bracket);
    final tp = TextPainter(
      text: TextSpan(
          text: distLabel,
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
  bool shouldRepaint(covariant _SetupScenePainter oldDelegate) =>
      oldDelegate.distLabel != distLabel;
}
