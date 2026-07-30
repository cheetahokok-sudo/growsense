// ══════════════════════════════════════════════════════════════════
// GrowSense Height Scan — ARKit two-point height measurement.
//
// Flow (driven from Dart over the per-view MethodChannel):
//   1. ARKit finds the floor (horizontal plane detection).
//   2. Parent aims the screen-centre crosshair at the child's FEET and
//      calls markPoint → we anchor the floor Y there.
//   3. Aims at the TOP OF THE HEAD and calls markPoint → height is the
//      vertical delta between that hit and the floor Y. The child
//      stands against a wall, so even if the hair itself yields no
//      feature points, the wall plane just behind the head is hit at
//      the same height — the Y is all we use.
//   4. Dart repeats for 3 readings and takes the median.
//
// On LiDAR devices scene reconstruction is enabled, which makes the
// head raycast hit the actual mesh instead of estimated planes —
// this is the "phase 1.5" accuracy boost, free on Pro phones.
//
// Channel: growsense/height_scan_<viewId>
//   Dart → native: markPoint, reset, dispose
//   native → Dart: onState {state, guidance}, onReading {heightCm}
// ══════════════════════════════════════════════════════════════════

import ARKit
import Flutter
import SceneKit
import UIKit

// ── Factory, registered in AppDelegate ────────────────────────────
class HeightScanViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return HeightScanPlatformView(frame: frame, viewId: viewId, messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  /// Dart-side availability probe (static channel, no view needed).
  static func registerAvailabilityChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "growsense/height_scan", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        result(ARWorldTrackingConfiguration.isSupported)
      case "hasLidar":
        result(ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// ── The platform view ─────────────────────────────────────────────
class HeightScanPlatformView: NSObject, FlutterPlatformView, ARSCNViewDelegate {
  private let arView: ARSCNView
  private let channel: FlutterMethodChannel

  private var floorY: Float?        // world-space Y of the floor at the feet mark
  private var hasFloorPlane = false // any horizontal plane detected yet

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    arView = ARSCNView(frame: frame)
    channel = FlutterMethodChannel(name: "growsense/height_scan_\(viewId)", binaryMessenger: messenger)
    super.init()

    arView.delegate = self
    arView.automaticallyUpdatesLighting = true

    let config = ARWorldTrackingConfiguration()
    config.planeDetection = [.horizontal, .vertical]
    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
      config.sceneReconstruction = .mesh // LiDAR: raycast against real geometry
    }
    arView.session.run(config)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "markPoint": result(self.markPoint())
      case "reset":     self.resetScan(); result(nil)
      case "dispose":   self.arView.session.pause(); result(nil)
      default:          result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { arView }

  // ── Screen-centre raycast, best available accuracy first ────────
  private func centerRaycast() -> simd_float4x4? {
    let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
    // Existing plane geometry (or LiDAR mesh) is the most stable…
    if let q = arView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .any),
       let hit = arView.session.raycast(q).first {
      return hit.worldTransform
    }
    // …fall back to estimated planes (non-LiDAR head shots often land here).
    if let q = arView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any),
       let hit = arView.session.raycast(q).first {
      return hit.worldTransform
    }
    return nil
  }

  /// Two-step mark. Returns a map the Dart side switches on rather
  /// than throwing — "no surface" mid-scan is normal, not an error.
  private func markPoint() -> [String: Any] {
    guard let transform = centerRaycast() else {
      return ["ok": false, "reason": "no_surface"]
    }
    let y = transform.columns.3.y

    if floorY == nil {
      floorY = y
      return ["ok": true, "step": "feet"]
    }

    let heightM = y - floorY!
    // Outside 0.4–2.2 m the parent almost certainly mis-aimed
    // (marked a table edge, the wall skirting, a sibling…).
    guard heightM > 0.4 && heightM < 2.2 else {
      return ["ok": false, "reason": "implausible", "heightCm": Double(heightM * 100)]
    }
    let cm = Double(heightM * 100)
    floorY = nil // ready for the next reading
    return ["ok": true, "step": "head", "heightCm": cm]
  }

  private func resetScan() { floorY = nil }

  // ── Surface feedback so Dart can gate the Mark button ───────────
  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal, !hasFloorPlane else { return }
    hasFloorPlane = true
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("onState", arguments: ["state": "floor_found"])
    }
  }

  func session(_ session: ARSession, didFailWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("onState", arguments: ["state": "error", "message": error.localizedDescription])
    }
  }
}
