import 'package:flutter/material.dart';

import '../height_scan.dart';
import '../i18n.dart';
import '../theme.dart';

/// Height Scan — guided AR height measurement (iOS-only).
///
/// The camera view is the native ARKit platform view; this screen is
/// the overlay that walks the parent through it: find the floor → aim
/// at the feet → aim at the top of the head → repeat for 3 readings →
/// median. Pops with the median height in cm (double), or null if
/// cancelled — the measurement entry card prefills from it and owns
/// the actual save (weight, date, free-tier cap all live there).
///
/// Discipline notes shown in the intro matter more than the sensor:
/// barefoot, against a wall, and the same time of day (children are
/// 1–2 cm taller in the morning than the evening).
class HeightScanScreen extends StatefulWidget {
  const HeightScanScreen({super.key, required this.i18n});
  final I18n i18n;

  static const readingsNeeded = 3;

  @override
  State<HeightScanScreen> createState() => _HeightScanScreenState();
}

enum _Phase { intro, findingFloor, aimFeet, aimHead, done }

class _HeightScanScreenState extends State<HeightScanScreen> {
  HeightScanController? _controller;
  _Phase _phase = _Phase.intro;
  final List<double> _readings = [];
  String? _hint; // transient guidance (no surface, implausible…)
  bool _marking = false;

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
    final (step, heightCm) = await c.markPoint();
    if (!mounted) return;
    setState(() {
      _marking = false;
      switch (step) {
        case 'feet':
          _phase = _Phase.aimHead;
        case 'head':
          _readings.add(heightCm!);
          _phase = _readings.length >= HeightScanScreen.readingsNeeded
              ? _Phase.done
              : _Phase.aimFeet;
        case 'implausible':
          _phase = _Phase.aimFeet;
          _hint = t('flutter.hscan.implausible',
              'That doesn\'t look right — starting this reading over');
        default: // no_surface
          _hint = t('flutter.hscan.no_surface',
              'Couldn\'t find a surface there — steady the phone and try again');
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

  // ── Intro card: the measurement discipline ──────────────────────
  Widget _intro(String Function(String, [String?, Map<String, String>?]) t) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('📷 ${t('flutter.hscan.title', 'Height Scan')}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 24),
            _introStep('🦶',
                t('flutter.hscan.intro_1', 'Barefoot, standing tall against a wall')),
            _introStep('📏',
                t('flutter.hscan.intro_2', 'Stand 2–3 steps back and hold the phone steady')),
            _introStep('🎯',
                t('flutter.hscan.intro_3', 'Mark the feet, then the top of the head — 3 times')),
            _introStep('🌅',
                t('flutter.hscan.intro_4', 'Scan at the same time of day — kids are taller in the morning')),
            const SizedBox(height: 28),
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

  Widget _introStep(String emoji, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 15))),
        ]),
      );

  // ── Live overlay: crosshair + guidance + mark button ────────────
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

    return SafeArea(
      child: Column(
        children: [
          // Top: guidance card
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
          // Centre: crosshair
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
          // Bottom: readings + actions
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(14)),
            child: done ? _result(t) : _controls(t),
          ),
        ],
      ),
    );
  }

  Widget _controls(String Function(String, [String?, Map<String, String>?]) t) {
    final canMark = _phase == _Phase.aimFeet || _phase == _Phase.aimHead;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(
          t('flutter.hscan.reading_n', 'Reading {n} of {total}', {
            'n': '${_readings.length + 1}',
            'total': '${HeightScanScreen.readingsNeeded}',
          }),
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GsColors.accent),
            onPressed: canMark && !_marking ? _mark : null,
            child: Text(_marking
                ? '…'
                : t('flutter.hscan.mark', 'Mark')),
          ),
        ),
      ]),
    ]);
  }

  Widget _result(String Function(String, [String?, Map<String, String>?]) t) {
    final median = heightScanMedian(_readings);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${median.toStringAsFixed(1)} cm',
          style: const TextStyle(
              color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(_readings.map((r) => r.toStringAsFixed(1)).join(' · '),
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _readings.clear();
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
