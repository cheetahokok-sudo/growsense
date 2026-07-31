// ══════════════════════════════════════════════════════════════════
// Height Scan — camera/AR height measurement (iOS-only).
//
// Thin Dart wrapper over the native ARKit module in
// ios/Runner/HeightScanView.swift. v4.2 flow: the phone stays STILL
// with the whole child in frame; two measuring lines are pre-placed
// (presetHead gives the head line a real-world starting position) and
// the parent drags them onto the feet and the crown (setMarkers,
// normalized coords). measure() then samples up to 10 unique frames
// natively and returns the median with quality gates — a bad burst is
// refused with a reason code instead of returning a wrong number. The
// guided flow (height_scan_screen.dart) takes 2 bursts, and a 3rd
// only when the first two disagree.
//
// Honesty contract: results save with data_source 'camera_ar', NOT
// 'manual' — a scan is a real measurement but a different instrument,
// and analytics must be able to tell them apart later.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart';

import 'platform.dart' show kIsApplePhone;

/// Static availability probe — safe to call on any platform; only
/// actually talks to native on an Apple phone.
class HeightScan {
  static const _channel = MethodChannel('growsense/height_scan');

  /// Whether the device can run an AR height scan at all.
  static Future<bool> isSupported() async {
    if (!kIsApplePhone) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false; // channel not registered (old binary) — hide the feature
    } on MissingPluginException {
      return false;
    }
  }

  /// LiDAR present → raycasts hit real mesh, accuracy tier improves.
  static Future<bool> hasLidar() async {
    if (!kIsApplePhone) return false;
    try {
      return await _channel.invokeMethod<bool>('hasLidar') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Talks to one live AR view (created by the UiKitView in the scan
/// screen). One instance per platform-view id.
class HeightScanController {
  HeightScanController(int viewId, {this.onFloorFound, this.onError})
      : _channel = MethodChannel('growsense/height_scan_$viewId') {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  final MethodChannel _channel;
  final void Function()? onFloorFound;
  final void Function(String message)? onError;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'onState') return null;
    final args = (call.arguments as Map?) ?? {};
    switch (args['state']) {
      case 'floor_found':
        onFloorFound?.call();
      case 'error':
        onError?.call(args['message'] as String? ?? 'AR session failed');
    }
    return null;
  }

  /// Push the current marker positions (normalized 0–1 view coords) to
  /// the native side. Either marker may be null while the parent is
  /// still placing them; the native side draws a provisional feet
  /// line as guidance.
  Future<void> setMarkers({Offset? feet, Offset? head}) {
    return _channel.invokeMethod('setMarkers', {
      if (feet != null) 'feetX': feet.dx,
      if (feet != null) 'feetY': feet.dy,
      if (head != null) 'headX': head.dx,
      if (head != null) 'headY': head.dy,
    });
  }

  /// Where the crown of a [heightCm]-tall child standing at the feet
  /// marker would appear on screen, in normalized view coords. Pure
  /// guidance — it never feeds a saved number, it just gives the head
  /// line a starting position that means something in the room.
  /// ok=false reasons: no_floor | behind | invalid | implausible |
  /// not_ready. [offScreen] means the child can't fit in frame from
  /// here (same condition as the too-close hint).
  Future<
      ({
        bool ok,
        String? reason,
        double? headX,
        double? headY,
        bool offScreen,
        double? distanceM,
      })> presetHead({required Offset feet, double heightCm = 150}) async {
    try {
      final res = await _channel.invokeMethod<Map>('presetHead', {
        'feetX': feet.dx,
        'feetY': feet.dy,
        'heightCm': heightCm,
      });
      return (
        ok: res?['ok'] == true,
        reason: res?['reason'] as String?,
        headX: (res?['headX'] as num?)?.toDouble(),
        headY: (res?['headY'] as num?)?.toDouble(),
        offScreen: res?['offScreen'] == true,
        distanceM: (res?['distanceM'] as num?)?.toDouble(),
      );
    } catch (_) {
      // Older native binary: fall back to the fixed screen fraction
      // rather than breaking the screen.
      return (
        ok: false,
        reason: 'not_ready',
        headX: null,
        headY: null,
        offScreen: false,
        distanceM: null
      );
    }
  }

  /// One measurement burst: the native side samples up to 10 unique
  /// frames (hold the phone still) and returns the median height with
  /// quality gates. ok=false reasons:
  ///   'no_floor'     — feet marker isn't over detected floor at all
  ///   'floor_patchy' — some floor, but the ray keeps missing it
  ///   'hold_still'   — too few clean frames (movement / bad tracking)
  ///   'unstable'     — frames disagree by > 1.5 cm, or camera moved
  ///   'no_markers'   — markers not set yet
  ///   'busy'         — a burst is already running
  ///   'cancelled'    — view reset/disposed mid-burst
  /// distanceM = horizontal camera→feet distance, pitchDeg = head-ray
  /// elevation — both feed the honesty hints.
  Future<
      ({
        bool ok,
        String? reason,
        double? heightCm,
        double? stddevCm,
        double? distanceM,
        double? pitchDeg,
      })> measure() async {
    final res = await _channel.invokeMethod<Map>('measure');
    return (
      ok: res?['ok'] == true,
      reason: res?['reason'] as String?,
      heightCm: (res?['heightCm'] as num?)?.toDouble(),
      stddevCm: (res?['stddevCm'] as num?)?.toDouble(),
      distanceM: (res?['distanceM'] as num?)?.toDouble(),
      pitchDeg: (res?['pitchDeg'] as num?)?.toDouble(),
    );
  }

  Future<void> reset() => _channel.invokeMethod('reset');

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
    } catch (_) {
      // View already gone — nothing to release.
    }
    _channel.setMethodCallHandler(null);
  }
}

/// Median of the collected readings — the value that gets saved.
double heightScanMedian(List<double> readings) {
  final sorted = [...readings]..sort();
  final n = sorted.length;
  return n.isOdd
      ? sorted[n ~/ 2]
      : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}
