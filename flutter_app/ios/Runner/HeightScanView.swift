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
// v2 (UX): every mark drops a numbered LEVEL LINE into the room at the
// hit position, and a completed pair is joined by a VERTICAL MEASURE
// line labelled with that reading's cm value — so a mark that landed
// on the skirting board is visible immediately. Current reading is
// bright mint; finished readings fade. undoMark steps one mark back.
//
// On LiDAR devices scene reconstruction is enabled, which makes the
// head raycast hit the actual mesh instead of estimated planes —
// this is the "phase 1.5" accuracy boost, free on Pro phones.
//
// Channel: growsense/height_scan_<viewId>
//   Dart → native: markPoint, undoMark, reset, dispose
//   native → Dart: onState {state, message?}
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

// One completed reading's scene furniture, kept for undo + fading.
private struct ReadingNodes {
  let number: Int
  let feetPos: simd_float3
  let headPos: simd_float3
  let feetNode: SCNNode
  let headNode: SCNNode
  let measureNode: SCNNode
}

// ── The platform view ─────────────────────────────────────────────
class HeightScanPlatformView: NSObject, FlutterPlatformView, ARSCNViewDelegate {
  private let arView: ARSCNView
  private let channel: FlutterMethodChannel

  // GrowSense mint — the "current" colour; faded readings drop opacity.
  private static let mint = UIColor(red: 0x78/255.0, green: 0xD6/255.0, blue: 0xA0/255.0, alpha: 1)
  private static let fadedOpacity: CGFloat = 0.3

  private var hasFloorPlane = false            // any horizontal plane yet
  private var pendingFeet: (pos: simd_float3, node: SCNNode)? // feet marked, head next
  private var completed: [ReadingNodes] = []

  private var nextNumber: Int { completed.count + 1 }

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
      case "undoMark":  result(self.undoMark())
      case "reset":     self.resetScan(); result(nil)
      case "dispose":   self.arView.session.pause(); result(nil)
      default:          result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { arView }

  // ── Screen-centre raycast, best available accuracy first ────────
  // The feet mark restricts to HORIZONTAL surfaces: the floor plane is
  // at true floor height wherever the ray lands, whereas an .any hit
  // on the LiDAR mesh can land on the top of the foot (3–8 cm high) —
  // one of the systematic shorteners found in device testing.
  private func centerRaycast(alignment: ARRaycastQuery.TargetAlignment) -> simd_float4x4? {
    let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
    // Existing plane geometry (or LiDAR mesh) is the most stable…
    if let q = arView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: alignment),
       let hit = arView.session.raycast(q).first {
      return hit.worldTransform
    }
    // …fall back to estimated planes (non-LiDAR head shots often land here).
    if let q = arView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: alignment),
       let hit = arView.session.raycast(q).first {
      return hit.worldTransform
    }
    return nil
  }

  private func cameraDistance(to pos: simd_float3) -> Double {
    guard let cam = arView.pointOfView?.simdWorldPosition else { return 0 }
    return Double(simd_length(pos - cam))
  }

  /// Two-step mark. Returns a map the Dart side switches on rather
  /// than throwing — "no surface" mid-scan is normal, not an error.
  /// distanceM lets Dart show a "step back a little" hint when the
  /// parent is too close for clean raycast angles.
  ///
  /// HEAD GEOMETRY (the 4–10 cm-short fix from device testing): a ray
  /// aimed at the crown grazes the hair and lands on the WALL behind —
  /// a detected plane the raycast prefers, 10–15 cm past the child.
  /// The phone is usually held ABOVE a child's crown, so the ray is
  /// descending, and by the wall it sits below the true crown height:
  ///   error ≈ (camY − crownY)/distance × head-to-wall gap
  /// (worse close-up, worse for small children, worse for dark hair
  /// that LiDAR sees straight through). The fix: never trust the head
  /// hit's DEPTH — only its DIRECTION. The feet mark already fixed the
  /// child's distance, so evaluate the ray AT the child's plane:
  ///   t = dist_xz(cam → feet) / ‖dir_xz‖ ;  crownY = camY + dirY·t
  /// If the ray hit the head itself this is unchanged; if it overshot
  /// to the wall the overshoot term vanishes entirely. The measurement
  /// becomes purely angular — a theodolite, not a rangefinder.
  private func markPoint() -> [String: Any] {
    let isFeet = pendingFeet == nil
    guard let transform = centerRaycast(alignment: isFeet ? .horizontal : .any) else {
      return ["ok": false, "reason": "no_surface"]
    }
    var pos = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

    if isFeet {
      let node = addLevelLine(at: pos, number: nextNumber)
      pendingFeet = (pos, node)
      updateOpacities() // a new reading began — everything finished fades
      return ["ok": true, "step": "feet", "distanceM": cameraDistance(to: pos)]
    }

    let feet = pendingFeet!

    // Pull the head point back from wherever the ray landed to the
    // child's plane (the feet mark's horizontal distance from camera).
    var dist = cameraDistance(to: pos)
    if let cam = arView.pointOfView?.simdWorldPosition {
      let dir = pos - cam
      let dirXZ = simd_length(simd_float2(dir.x, dir.z))
      let dChild = simd_length(simd_float2(feet.pos.x - cam.x, feet.pos.z - cam.z))
      if dirXZ > 0.05 { // aiming near-vertical would blow up t; keep raw hit
        let t = dChild / dirXZ
        pos = cam + dir * t
        dist = Double(dChild)
      }
    }

    let heightM = pos.y - feet.pos.y
    // Outside 0.4–2.2 m the parent almost certainly mis-aimed
    // (marked a table edge, the wall skirting, a sibling…).
    guard heightM > 0.4 && heightM < 2.2 else {
      return ["ok": false, "reason": "implausible", "heightCm": Double(heightM * 100)]
    }
    let cm = Double(heightM * 100)

    let headNode = addLevelLine(at: pos, number: nextNumber)
    let measure = addVerticalMeasure(feet: feet.pos, head: pos, labelCm: cm)
    completed.append(ReadingNodes(
      number: nextNumber, feetPos: feet.pos, headPos: pos,
      feetNode: feet.node, headNode: headNode, measureNode: measure))
    pendingFeet = nil
    updateOpacities() // the pair just finished — it stays bright for now
    return ["ok": true, "step": "head", "heightCm": cm, "distanceM": dist]
  }

  /// One mark back. Feet pending → unmark the feet. Otherwise reopen
  /// the last completed pair: its head line + measure go, its feet
  /// line comes back as the pending mark. Dart mirrors this state.
  private func undoMark() -> [String: Any] {
    if let feet = pendingFeet {
      feet.node.removeFromParentNode()
      pendingFeet = nil
      return ["undone": "feet"]
    }
    guard let last = completed.popLast() else { return ["undone": "none"] }
    last.headNode.removeFromParentNode()
    last.measureNode.removeFromParentNode()
    last.feetNode.opacity = 1
    pendingFeet = (last.feetPos, last.feetNode)
    updateOpacities()
    return ["undone": "head"]
  }

  private func resetScan() {
    pendingFeet?.node.removeFromParentNode()
    pendingFeet = nil
    for r in completed {
      r.feetNode.removeFromParentNode()
      r.headNode.removeFromParentNode()
      r.measureNode.removeFromParentNode()
    }
    completed.removeAll()
  }

  // ── Scene furniture ─────────────────────────────────────────────

  /// Current work is bright, history fades. Mid-reading (feet pending)
  /// every finished pair is history; between readings the pair that
  /// just completed keeps full brightness so the parent can check
  /// where its lines landed before moving on.
  private func updateOpacities() {
    for (i, r) in completed.enumerated() {
      let bright = pendingFeet == nil && i == completed.count - 1
      let opacity: CGFloat = bright ? 1 : Self.fadedOpacity
      r.feetNode.opacity = opacity
      r.headNode.opacity = opacity
      r.measureNode.opacity = opacity
    }
  }

  /// A horizontal level line pinned at [pos], numbered at both ends —
  /// the AR "1———1". Y-billboarded so it always spans across the view.
  private func addLevelLine(at pos: simd_float3, number: Int) -> SCNNode {
    let parent = SCNNode()
    parent.simdPosition = pos
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .Y
    parent.constraints = [billboard]

    parent.addChildNode(dashSegmentsNode(width: 0.7))

    for x: Float in [-0.38, 0.38] {
      let badge = numberBadge("\(number)")
      badge.position = SCNVector3(x, 0, 0)
      parent.addChildNode(badge)
    }

    arView.scene.rootNode.addChildNode(parent)
    return parent
  }

  /// The vertical measure joining a finished pair, labelled with cm —
  /// the tape-measure element. Placed at the pair's x/z (head hit).
  private func addVerticalMeasure(feet: simd_float3, head: simd_float3, labelCm: Double) -> SCNNode {
    let h = CGFloat(head.y - feet.y)
    let parent = SCNNode()
    // Anchor at the head's x/z, vertically centred between the levels.
    parent.simdPosition = simd_float3(head.x, (head.y + feet.y) / 2, head.z)
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .Y
    parent.constraints = [billboard]

    let rail = SCNBox(width: 0.006, height: h, length: 0.006, chamferRadius: 0.003)
    rail.firstMaterial = mintMaterial()
    let railNode = SCNNode(geometry: rail)
    // Nudge sideways so it hangs beside the child, not through them —
    // 0.25 m keeps it inside a portrait frame at 2 m (0.35 clipped).
    railNode.position = SCNVector3(0.25, 0, 0)
    parent.addChildNode(railNode)

    let label = numberBadge(String(format: "%.1f", labelCm))
    label.position = SCNVector3(0.25, 0, 0.02)
    parent.addChildNode(label)

    arView.scene.rootNode.addChildNode(parent)
    return parent
  }

  /// Dashed bar built from short segments (SceneKit has no line dash).
  private func dashSegmentsNode(width: CGFloat) -> SCNNode {
    let node = SCNNode()
    let dash: CGFloat = 0.05, gap: CGFloat = 0.035
    var x = -width / 2
    while x < width / 2 {
      let w = Swift.min(dash, width / 2 - x)
      let seg = SCNBox(width: w, height: 0.005, length: 0.005, chamferRadius: 0.002)
      seg.firstMaterial = mintMaterial()
      let n = SCNNode(geometry: seg)
      n.position = SCNVector3(Float(x + w / 2), 0, 0)
      node.addChildNode(n)
      x += dash + gap
    }
    return node
  }

  private func mintMaterial() -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = Self.mint
    m.emission.contents = Self.mint.withAlphaComponent(0.85)
    m.lightingModel = .constant
    return m
  }

  /// Billboarded number/value badge, always facing the camera.
  private func numberBadge(_ text: String) -> SCNNode {
    let t = SCNText(string: text, extrusionDepth: 0.4)
    t.font = UIFont.systemFont(ofSize: 9, weight: .bold)
    t.flatness = 0.15
    t.firstMaterial = mintMaterial()
    let node = SCNNode(geometry: t)
    node.scale = SCNVector3(0.006, 0.006, 0.006)
    // Centre the text on its position.
    let (min, max) = node.boundingBox
    node.pivot = SCNMatrix4MakeTranslation((min.x + max.x) / 2, (min.y + max.y) / 2, 0)
    return node
  }

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
