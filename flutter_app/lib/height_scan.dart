// ══════════════════════════════════════════════════════════════════
// Height Scan — camera/AR height measurement (iOS-only, MVP).
//
// Thin Dart wrapper over the native ARKit module in
// ios/Runner/HeightScanView.swift. The measurement itself is a
// two-point raycast: mark the child's feet, mark the top of the head,
// height = vertical delta. The guided flow (height_scan_screen.dart)
// collects THREE readings and saves the median — single AR readings
// carry ~1 cm noise on non-LiDAR phones, and the median of three is
// the cheapest way to shave the tails.
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

  /// First call marks the feet, second returns the reading. The native
  /// side also drops the numbered AR level line at each mark, and joins
  /// a finished pair with the vertical measure.
  /// step values:
  ///   'feet'        — feet anchored, now aim at the head
  ///   'head'        — one full reading captured (heightCm set)
  ///   'no_surface'  — nothing under the crosshair, try again
  ///   'implausible' — mark landed somewhere absurd; scan reset
  /// distanceM = camera→mark distance, for the "step back" hint.
  Future<({String step, double? heightCm, double? distanceM})>
      markPoint() async {
    final res = await _channel.invokeMethod<Map>('markPoint');
    if (res == null) return (step: 'no_surface', heightCm: null, distanceM: null);
    if (res['ok'] == true) {
      return (
        step: res['step'] as String,
        heightCm: (res['heightCm'] as num?)?.toDouble(),
        distanceM: (res['distanceM'] as num?)?.toDouble(),
      );
    }
    if (res['reason'] == 'implausible') {
      await reset();
      return (step: 'implausible', heightCm: null, distanceM: null);
    }
    return (step: 'no_surface', heightCm: null, distanceM: null);
  }

  /// One mark back (removes its AR line too).
  /// 'feet' — pending feet unmarked → aim at feet again.
  /// 'head' — last pair reopened → drop its reading, aim at head.
  /// 'none' — nothing to undo.
  Future<String> undoMark() async {
    final res = await _channel.invokeMethod<Map>('undoMark');
    return (res?['undone'] as String?) ?? 'none';
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
