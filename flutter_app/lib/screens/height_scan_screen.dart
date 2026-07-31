import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../height_scan.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/gs_icons.dart';

/// Height Scan — guided AR height measurement (iOS-only).
///
/// The camera view is the native ARKit platform view; this screen is
/// the overlay that walks the parent through it. v4.2 flow: the phone
/// stays STILL with the whole child in frame, and the two measuring
/// lines are ALREADY on screen when the camera opens — the head line
/// at a real-world 150 cm above the floor once ARKit can work it out.
/// The parent drags them onto the feet and the crown (slow drags move
/// precisely, fast flicks travel), then Measure runs a ~0.5 s native
/// sampling burst. Two bursts normally; a third only when they
/// disagree. Pops with the median height in cm (double), or null if
/// cancelled — the measurement entry card prefills from it and owns
/// the actual save (weight, date, cap).
class HeightScanScreen extends StatefulWidget {
  const HeightScanScreen({super.key, required this.i18n});
  final I18n i18n;

  /// Upper bound. Two bursts that agree finish early — see [agreeCm].
  static const readingsNeeded = 3;

  /// Two readings this close mean a third would tell us nothing.
  static const agreeCm = 0.5;

  /// Readings further apart than this get the "scan again" nudge.
  static const spreadWarnCm = 2.0;

  /// Feet closer than this suggests the parent can't frame the whole
  /// child — shallow angles hurt accuracy.
  static const tooCloseM = 1.5;

  /// Head-ray elevation above this means the parent is aiming steeply
  /// upward — the step-back hint fires.
  static const maxHeadPitchDeg = 25.0;

  /// Where the lines sit before ARKit has anything to say. Feet clears
  /// the bottom controls card (its top edge lands near 0.82 on both
  /// tall and small phones); the head fallback is deliberately
  /// conservative — it lands on the chest, never off the top.
  static const defaultFeetY = 0.72;
  static const fallbackHeadY = 0.35;

  /// A generic starting guess, NOT the child's last height — see
  /// docs/HEIGHT_SCAN.md for why that would corrupt the data.
  static const presetHeightCm = 150.0;

  /// Markers stay clear of the two overlay cards, and can't cross.
  static const markerMinY = 0.20;
  static const markerMaxY = 0.80;
  static const markerMinGap = 0.05;

  /// Finger-to-line gain. Slow drags stay at 1:3 — that precision is
  /// what produced the validated sub-centimetre accuracy — while fast
  /// flicks ramp to 1:1 so crossing the screen costs one gesture.
  static const dragGainFine = 1 / 3;
  static const dragSlowPxPerSec = 250.0;
  static const dragFastPxPerSec = 900.0;

  @override
  State<HeightScanScreen> createState() => _HeightScanScreenState();
}

enum _Phase { intro, adjust, sampling, done }

class _HeightScanScreenState extends State<HeightScanScreen> {
  HeightScanController? _controller;
  _Phase _phase = _Phase.intro;
  final List<double> _readings = [];
  String? _hint; // transient guidance (no floor, hold still, too close…)

  bool _floorFound = false;

  // Marker positions, normalized 0–1 against the full-screen camera.
  // Never null: both lines exist before the camera renders a frame.
  Offset _feetMarker = const Offset(0.5, HeightScanScreen.defaultFeetY);
  Offset _headMarker = const Offset(0.5, HeightScanScreen.fallbackHeadY);

  // Preset: applied at most once, and never after the parent touches
  // a line — a line that moves under their finger reads as a bug.
  bool _presetPristine = true;
  bool _presetApplied = false;
  bool _animateHead = false;
  Timer? _presetTimer;

  /// Last line the parent touched — drives the contextual aim detail,
  /// and deliberately PERSISTS after the drag so the instruction is
  /// readable when they look up to press Measure.
  String? _activeLine;
  Duration? _lastDragTs;

  @override
  void dispose() {
    _presetTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _onViewCreated(int viewId) {
    _controller = HeightScanController(
      viewId,
      onFloorFound: () {
        if (!mounted || _floorFound) return;
        setState(() => _floorFound = true);
        _pushMarkers();
        _armPreset();
      },
      onError: (msg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: GsColors.flag, content: Text(msg)));
        Navigator.of(context).pop();
      },
    );
  }

  // ── Markers ─────────────────────────────────────────────────────

  Offset _clampMarker(Offset o, {required bool isFeet}) {
    var dy = o.dy.clamp(HeightScanScreen.markerMinY, HeightScanScreen.markerMaxY);
    if (isFeet) {
      dy = math.max(dy, _headMarker.dy + HeightScanScreen.markerMinGap);
    } else {
      dy = math.min(dy, _feetMarker.dy - HeightScanScreen.markerMinGap);
    }
    dy = dy.clamp(HeightScanScreen.markerMinY, HeightScanScreen.markerMaxY);
    return Offset(o.dx.clamp(0.02, 0.98), dy);
  }

  Future<void> _pushMarkers() async {
    await _controller?.setMarkers(feet: _feetMarker, head: _headMarker);
  }

  /// Ask the native side where a 150 cm child's crown would appear.
  /// Retried while untouched because floor_found fires on the first
  /// small plane patch, when the raycast usually still misses.
  void _armPreset() {
    _presetTimer?.cancel();
    if (!_presetPristine || _presetApplied) return;
    _tryPreset();
    var waited = Duration.zero;
    _presetTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      waited += const Duration(milliseconds: 500);
      if (waited > const Duration(seconds: 6) ||
          !_presetPristine ||
          _presetApplied) {
        t.cancel();
        return;
      }
      _tryPreset();
    });
  }

  Future<void> _tryPreset() async {
    final t = widget.i18n.t;
    final c = _controller;
    if (c == null) return;
    final r = await c.presetHead(
        feet: _feetMarker, heightCm: HeightScanScreen.presetHeightCm);
    if (!mounted || !_presetPristine || _presetApplied) return;
    if (!r.ok) return;
    setState(() {
      _presetApplied = true;
      _animateHead = true;
      _headMarker = _clampMarker(Offset(r.headX!, r.headY!), isFeet: false);
      // Framing check BEFORE a burst is wasted: a crown that lands off
      // the top, or feet nearer than 1.5 m, means the child won't fit.
      if (r.offScreen || (r.distanceM ?? 99) < HeightScanScreen.tooCloseM) {
        _hint = t('flutter.hscan.too_close',
            'Step back until the whole child fits on screen — about 2–2.5 m');
      }
    });
    _presetTimer?.cancel();
    await _pushMarkers();
    // The settle is a one-off; every later move must track the finger.
    if (mounted) setState(() => _animateHead = false);
  }

  void _onDragStart(String line) {
    _presetPristine = false;
    _presetTimer?.cancel();
    _lastDragTs = null;
    setState(() {
      _activeLine = line;
      _hint = null;
    });
  }

  /// Gain ramps with drag speed: precise when slow, quick when fast.
  double _gainFor(double dyPx, Duration? ts) {
    final double speed;
    if (ts != null && _lastDragTs != null) {
      final dt = (ts - _lastDragTs!).inMicroseconds / 1e6;
      speed = dt > 0 ? dyPx.abs() / dt : dyPx.abs() * 60;
    } else {
      speed = dyPx.abs() * 60; // no timestamp — assume a 60 Hz frame
    }
    _lastDragTs = ts;
    final f = ((speed - HeightScanScreen.dragSlowPxPerSec) /
            (HeightScanScreen.dragFastPxPerSec - HeightScanScreen.dragSlowPxPerSec))
        .clamp(0.0, 1.0);
    return HeightScanScreen.dragGainFine +
        (1 - HeightScanScreen.dragGainFine) * f;
  }

  void _dragMarker(bool isFeet, DragUpdateDetails d, Size screen) {
    final t = widget.i18n.t;
    final current = isFeet ? _feetMarker : _headMarker;
    final gain = _gainFor(d.delta.dy, d.sourceTimeStamp);
    final wanted = Offset(current.dx, current.dy + d.delta.dy * gain / screen.height);
    final moved = _clampMarker(wanted, isFeet: isFeet);
    setState(() {
      if (isFeet) {
        _feetMarker = moved;
      } else {
        _headMarker = moved;
      }
      // A clamp that silently swallows the drag is worse than the bug
      // it prevents — say what's actually wrong.
      if ((wanted.dy - moved.dy).abs() > 0.002 &&
          (moved.dy <= HeightScanScreen.markerMinY + 0.001 ||
              moved.dy >= HeightScanScreen.markerMaxY - 0.001)) {
        _hint = t('flutter.hscan.too_close',
            'Step back until the whole child fits on screen — about 2–2.5 m');
      }
    });
  }

  // ── Measuring ───────────────────────────────────────────────────

  /// Two agreeing readings are enough; a third only earns its time
  /// when they disagree.
  bool get _haveEnough {
    if (_readings.length >= HeightScanScreen.readingsNeeded) return true;
    return _readings.length == 2 &&
        (_readings[0] - _readings[1]).abs() <= HeightScanScreen.agreeCm;
  }

  Future<void> _measure() async {
    final t = widget.i18n.t;
    final c = _controller;
    if (c == null || _phase != _Phase.adjust || !_floorFound) return;
    _presetTimer?.cancel();
    _presetPristine = false;
    setState(() {
      _phase = _Phase.sampling;
      _hint = null;
    });
    await _pushMarkers();
    var res = await c.measure();
    // One silent retry: most refusals are transient, and a retry the
    // parent never sees beats an error message they have to act on.
    if (!res.ok &&
        res.reason != 'no_markers' &&
        res.reason != 'busy' &&
        res.reason != 'cancelled') {
      res = await c.measure();
    }
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
        _phase = _haveEnough ? _Phase.done : _Phase.adjust;
      } else {
        _phase = _Phase.adjust;
        _hint = switch (res.reason) {
          'no_floor' => t('flutter.hscan.no_floor',
              'Can\'t find the floor there — aim the feet line at clear floor between the feet'),
          'floor_patchy' => t('flutter.hscan.floor_patchy',
              'Move the mint line onto clearer floor — it needs an open patch between the feet'),
          'unstable' => t('flutter.hscan.unstable',
              'Too much movement — hold the phone still and measure again'),
          _ => t('flutter.hscan.hold_still_retry',
              'Couldn\'t get a steady reading — hold the phone still and try again'),
        };
      }
    });
  }

  Future<void> _rescan() async {
    _presetTimer?.cancel();
    setState(() {
      _readings.clear();
      _hint = null;
      _activeLine = null;
      _presetPristine = true;
      _presetApplied = false;
      _feetMarker = const Offset(0.5, HeightScanScreen.defaultFeetY);
      _headMarker = const Offset(0.5, HeightScanScreen.fallbackHeadY);
      _phase = _Phase.adjust;
    });
    await _controller?.reset();
    await _pushMarkers();
    _armPreset();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final screen = MediaQuery.of(context).size;
    final showLines = _phase != _Phase.intro && _phase != _Phase.done;
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
          if (showLines) ...[
            _MarkerLine(
              yNorm: _feetMarker.dy,
              color: const Color(0xFF78D6A0),
              label: t('flutter.hscan.feet', 'feet'),
              active: _activeLine == 'feet',
              draggable: _phase == _Phase.adjust,
              animate: false,
              onDragStart: () => _onDragStart('feet'),
              onDrag: (d) => _dragMarker(true, d, screen),
              onDragEnd: _pushMarkers,
            ),
            _MarkerLine(
              yNorm: _headMarker.dy,
              color: Colors.white,
              label: t('flutter.hscan.head', 'head'),
              active: _activeLine == 'head',
              draggable: _phase == _Phase.adjust,
              animate: _animateHead,
              onDragStart: () => _onDragStart('head'),
              onDrag: (d) => _dragMarker(false, d, screen),
              onDragEnd: _pushMarkers,
            ),
          ],
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
                    'Adjust the lines to the feet and the head — the app measures 2–3 quick bursts')),
            _introStep('hscan_morning',
                t('flutter.hscan.intro_4', 'Scan at the same time of day — kids are taller in the morning')),
            const SizedBox(height: 14),
            _burstStrip(active: -1),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: GsColors.accent),
              onPressed: () => setState(() {
                _phase = _Phase.adjust;
                _hint = t('flutter.hscan.preset_hint',
                    'These lines are a starting guess, not a measurement — move them onto your child');
              }),
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

  /// Burst rhythm ① ② ③ — the third is dimmed until the first two
  /// actually disagree, so the usual scan reads as two.
  Widget _burstStrip({required int active}) {
    final children = <Widget>[];
    for (var i = 0; i < HeightScanScreen.readingsNeeded; i++) {
      final done = active >= 0 && i < active;
      final current = i == active;
      final optional = i == HeightScanScreen.readingsNeeded - 1 && !current && !done;
      children.add(Opacity(
        opacity: optional ? 0.45 : 1,
        child: Container(
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
    // The aim detail follows the line the parent last touched, so it
    // is on screen when they look up — not only while their finger
    // covers it.
    final guidance = switch (_phase) {
      _Phase.adjust => switch (_activeLine) {
          'feet' => t('flutter.hscan.drag_feet',
              'Line this up with the floor between the feet, right at the ankles — not the wall edge, not the toes'),
          'head' => t('flutter.hscan.drag_head',
              'Line this up with the very top of the head — the crown, not the forehead. Flatten the hair'),
          _ => _readings.isEmpty
              ? t('flutter.hscan.adjust',
                  'Adjust the lines to the feet and the head — slow drags move precisely. Then tap Measure')
              : t('flutter.hscan.between_bursts',
                  'Check the lines still sit right, then measure again'),
        },
      _Phase.sampling => t('flutter.hscan.hold_still', 'Hold the phone still…'),
      _ => '',
    };
    // Floor status is subordinate: it gates Measure, it isn't the
    // headline instruction.
    final subHint = !_floorFound && !done
        ? t('flutter.hscan.finding_floor',
            'Move the phone slowly so it can find the floor…')
        : _hint;

    return SafeArea(
      child: Column(
        children: [
          _card(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 150),
              child: Column(children: [
                Text(
                    done
                        ? t('flutter.hscan.result_title', 'Scan complete')
                        : guidance,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                if (subHint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(subHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFFFC978), fontSize: 13)),
                  ),
              ]),
            ),
          ),
          const Spacer(),
          _card(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            child: done ? _result(t) : _controls(t),
          ),
        ],
      ),
    );
  }

  /// Overlay cards swallow pointers — Container/Column/Text don't
  /// hit-test themselves, so without this a tap on the guidance text
  /// falls through and drags a measuring line. Buttons inside still
  /// win, since descendants are hit-tested first.
  Widget _card({
    required EdgeInsets margin,
    required EdgeInsets padding,
    required Widget child,
  }) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onVerticalDragUpdate: (_) {},
        child: Container(
          margin: margin,
          padding: padding,
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14)),
          child: child,
        ),
      );

  /// Single-line button label — long i18n strings shrink instead of
  /// wrapping ("Can cel" / "Red o" were real field complaints).
  static Widget _label(String text, {Color? color}) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text,
            maxLines: 1, style: color == null ? null : TextStyle(color: color)),
      );

  Widget _controls(String Function(String, [String?, Map<String, String>?]) t) {
    final sampling = _phase == _Phase.sampling;
    final canMeasure = _phase == _Phase.adjust && _floorFound;
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
/// per field feedback, a line and a dot, nothing circular. The
/// generous vertical hit area keeps the thin line grabbable.
class _MarkerLine extends StatelessWidget {
  const _MarkerLine({
    required this.yNorm,
    required this.color,
    required this.label,
    required this.active,
    required this.draggable,
    required this.animate,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
  });

  final double yNorm;
  final Color color;
  final String label;
  final bool active;
  final bool draggable;

  /// Only true for the one-off preset settle — a drag must track the
  /// finger exactly.
  final bool animate;
  final VoidCallback onDragStart;
  final void Function(DragUpdateDetails d) onDrag;
  final Future<void> Function() onDragEnd;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    const hitHeight = 44.0;
    return AnimatedPositioned(
      duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
      curve: Curves.easeOut,
      left: 0,
      right: 0,
      top: yNorm * h - hitHeight / 2,
      height: hitHeight,
      child: GestureDetector(
        behavior: draggable ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onVerticalDragStart: draggable ? (_) => onDragStart() : null,
        onVerticalDragUpdate: draggable ? onDrag : null,
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
                color: Colors.black.withValues(alpha: active ? 0.85 : 0.55),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
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
/// back holding the phone still at the child's head height, gold
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

    // Distance bracket: the rule breaks around the label rather than
    // striking through it.
    final tp = TextPainter(
      text: TextSpan(
          text: distLabel,
          style: TextStyle(
              color: const Color(0xFFB9C4BB),
              fontSize: 9 * sx,
              fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    const cx = 124.0, ruleY = 122.0, x0 = 66.0, x1 = 182.0;
    final halfGap = (tp.width / 2) / sx + 4; // tp is in device px
    final gapL = cx - halfGap, gapR = cx + halfGap;
    if (gapL > x0 + 6 && gapR < x1 - 6) {
      canvas.drawLine(p(x0, ruleY), p(gapL, ruleY), bracket);
      canvas.drawLine(p(gapR, ruleY), p(x1, ruleY), bracket);
    } // else the label is wider than the bracket — draw the caps only
    canvas.drawLine(p(x0, 118), p(x0, 126), bracket);
    canvas.drawLine(p(x1, 118), p(x1, 126), bracket);
    tp.paint(canvas, p(cx, ruleY) - Offset(tp.width / 2, tp.height / 2));
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
