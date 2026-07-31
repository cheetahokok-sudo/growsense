// ══════════════════════════════════════════════════════════════════
// Height Scan — camera/AR height measurement (iOS-only).
//
// Thin Dart wrapper over the native ARKit module in
// ios/Runner/HeightScanView.swift. v4 flow: the phone stays STILL
// with the whole child in frame; the parent taps a feet marker and a
// head marker on screen (setMarkers, normalized coords), then
// measure() samples ~15 frames over ~1 s natively and returns the
// median with quality gates — an unstable burst is refused with a
// reason code instead of returning a bad number. The guided flow
// (height_scan_screen.dart) collects THREE bursts and saves the
// median of medians.
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

  /// One measurement burst: the native side samples ~15 frames over
  /// ~1 s (hold the phone still) and returns the median height with
  /// quality gates. ok=false reasons:
  ///   'no_floor'   — feet marker isn't over detected floor
  ///   'hold_still' — too few clean frames (movement / bad tracking)
  ///   'unstable'   — frames disagree by > 1.5 cm stddev
  ///   'no_markers' — markers not set yet
  ///   'busy'       — a burst is already running
  ///   'cancelled'  — view reset/disposed mid-burst
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
