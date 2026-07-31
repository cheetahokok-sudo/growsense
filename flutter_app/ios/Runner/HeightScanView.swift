// ══════════════════════════════════════════════════════════════════
// GrowSense Height Scan — ARKit stationary-marker height measurement.
//
// v4 flow (driven from Dart over the per-view MethodChannel): the
// phone stays STILL with the whole child in frame. The parent taps a
// FEET marker (where the wall meets the floor, between the heels) and
// a HEAD marker (the crown) on screen; Dart sends both as normalized
// view coordinates via setMarkers. measure() then samples ~15 frames
// over ~1 s and returns the median height with quality gates — the
// phone never sweeps between marks, so no tracking drift or re-aim
// error enters a reading. Dart repeats 3 bursts, median of medians.
//
// GEOMETRY (supersedes the v3 "theodolite" pull-back — same idea,
// cleaner form, and it yields a residual quality signal): never trust
// any raycast DEPTH at the head. Per frame:
//   1. Raycast the FEET marker onto detected horizontal plane
//      geometry (preferring a .floor-classified plane); snap its Y to
//      the tracked floor anchor when they agree within 10 cm. → F
//   2. Unproject the HEAD marker into a world ray C + s·D.
//   3. Intersect (closest approach) that ray with the vertical line
//      F + h·(0,1,0). h IS the height; the miss distance (residual)
//      tells us how trustworthy the frame was.
// The wall behind the child never determines the head depth, and the
// per-frame residual + tracking-state + stddev gates mean an unstable
// burst is refused ("hold still") instead of returning a bad number.
//
// Channel: growsense/height_scan_<viewId>
//   Dart → native: setMarkers, measure, reset, dispose
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

// One completed burst's scene furniture, kept for fading + reset.
private struct ReadingNodes {
  let feetNode: SCNNode
  let headNode: SCNNode
  let measureNode: SCNNode
}

// One accepted frame within a burst.
private struct MeasureSample {
  let h: Float          // height in metres (the quantity of interest)
  let residual: Float   // ray↔vertical-line miss distance
  let feetPos: simd_float3
  let dChild: Float     // horizontal camera→feet distance
  let pitchDeg: Float   // head-ray elevation above horizontal
}

// ── The platform view ─────────────────────────────────────────────
class HeightScanPlatformView: NSObject, FlutterPlatformView, ARSCNViewDelegate {
  private let arView: ARSCNView
  private let channel: FlutterMethodChannel

  // GrowSense mint — the "current" colour; faded readings drop opacity.
  private static let mint = UIColor(red: 0x78/255.0, green: 0xD6/255.0, blue: 0xA0/255.0, alpha: 1)
  private static let fadedOpacity: CGFloat = 0.3

  // Burst tuning. 15 samples at 30 fps is ~0.5 s of stillness; the
  // deadline gives slow frames room without letting a bad burst drag.
  private static let samplesWanted = 15
  private static let samplesMinimum = 6
  private static let burstDeadline: CFTimeInterval = 1.2
  private static let floorSnapTolerance: Float = 0.10
  private static let residualLimit: Float = 0.05
  private static let stddevLimit: Float = 0.015 // metres → 1.5 cm

  private var hasFloorPlane = false      // fires the floor_found event once
  private var floorAnchor: ARPlaneAnchor? // best-known floor plane, refreshed by ARKit
  private var completed: [ReadingNodes] = []
  private var nextNumber: Int { completed.count + 1 }

  // Markers in normalized view coordinates (0–1), set from Dart.
  private var feetMarker: CGPoint?
  private var headMarker: CGPoint?
  private var provisionalFeetNode: SCNNode? // guidance-only line while placing

  // In-flight burst. The FlutterResult MUST always be completed —
  // a leaked result leaves Dart hanging on its await.
  private var burstSamples: [MeasureSample] = []
  private var burstFloorHits = 0
  private var burstTicks = 0
  private var burstStart: CFTimeInterval = 0
  private var burstResult: FlutterResult?
  private var displayLink: CADisplayLink?

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    arView = ARSCNView(frame: frame)
    channel = FlutterMethodChannel(name: "growsense/height_scan_\(viewId)", binaryMessenger: messenger)
    super.init()

    arView.delegate = self
    arView.automaticallyUpdatesLighting = true

    let config = ARWorldTrackingConfiguration()
    config.worldAlignment = .gravity // world Y ∥ gravity — h is true vertical
    config.planeDetection = [.horizontal, .vertical]
    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
      config.sceneReconstruction = .mesh // LiDAR: raycast against real geometry
    }
    arView.session.run(config)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "setMarkers": self.setMarkers(call.arguments); result(nil)
      case "measure":    self.measure(result: result)
      case "reset":      self.resetScan(); result(nil)
      case "dispose":
        self.finishBurst(["ok": false, "reason": "cancelled"])
        self.arView.session.pause()
        result(nil)
      default:           result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { arView }

  // ── Markers ─────────────────────────────────────────────────────

  /// Dart sends both markers (normalized 0–1) on every place/drag-end.
  /// Either may be absent while the parent is still placing them.
  private func setMarkers(_ args: Any?) {
    guard let map = args as? [String: Any] else { return }
    func point(_ xKey: String, _ yKey: String) -> CGPoint? {
      guard let x = map[xKey] as? Double, let y = map[yKey] as? Double else { return nil }
      return CGPoint(x: x, y: y)
    }
    feetMarker = point("feetX", "feetY")
    headMarker = point("headX", "headY")
    updateProvisionalFeetLine()
  }

  /// Guidance only: shows the parent where the feet tap landed in 3D.
  /// May use estimated planes — never feeds the saved number.
  private func updateProvisionalFeetLine() {
    provisionalFeetNode?.removeFromParentNode()
    provisionalFeetNode = nil
    guard let marker = feetMarker else { return }
    let screen = denormalize(marker)
    guard let hit = raycastFloor(from: screen, allowEstimated: true) else { return }
    let pos = simd_float3(hit.worldTransform.columns.3.x,
                          hit.worldTransform.columns.3.y,
                          hit.worldTransform.columns.3.z)
    let node = addLevelLine(at: pos, number: nextNumber)
    node.opacity = 0.55
    provisionalFeetNode = node
  }

  private func denormalize(_ p: CGPoint) -> CGPoint {
    CGPoint(x: p.x * arView.bounds.width, y: p.y * arView.bounds.height)
  }

  // ── Raycast + ray helpers ───────────────────────────────────────

  /// Floor hit for the feet marker. Detected plane geometry only for
  /// the real measurement (estimated is allowed just for guidance);
  /// prefers a hit on a .floor-classified plane when one exists.
  private func raycastFloor(from screen: CGPoint, allowEstimated: Bool) -> ARRaycastResult? {
    if let q = arView.raycastQuery(from: screen, allowing: .existingPlaneGeometry, alignment: .horizontal) {
      let hits = arView.session.raycast(q)
      if let classified = hits.first(where: {
        ($0.anchor as? ARPlaneAnchor)?.classification == .floor
      }) {
        return classified
      }
      if let first = hits.first { return first }
    }
    if allowEstimated,
       let q = arView.raycastQuery(from: screen, allowing: .estimatedPlane, alignment: .horizontal),
       let hit = arView.session.raycast(q).first {
      return hit
    }
    return nil
  }

  /// World-space ray through a screen point (SceneKit's equivalent of
  /// RealityKit's ray(through:)): unproject at the near and far plane.
  private func worldRay(through screen: CGPoint) -> (origin: simd_float3, dir: simd_float3)? {
    let near = arView.unprojectPoint(SCNVector3(Float(screen.x), Float(screen.y), 0))
    let far = arView.unprojectPoint(SCNVector3(Float(screen.x), Float(screen.y), 1))
    let origin = simd_float3(near.x, near.y, near.z)
    let dir = simd_float3(far.x - near.x, far.y - near.y, far.z - near.z)
    let len = simd_length(dir)
    guard len > 0.0001 else { return nil }
    return (origin, dir / len)
  }

  /// World Y of the tracked floor plane (its refined centre, not the
  /// raw anchor origin), read fresh at sample time — never cached.
  private var floorY: Float? {
    guard let a = floorAnchor else { return nil }
    let c = a.transform * simd_float4(a.center.x, a.center.y, a.center.z, 1)
    return c.y
  }

  // ── The burst ───────────────────────────────────────────────────

  private func measure(result: @escaping FlutterResult) {
    guard burstResult == nil else {
      return result(["ok": false, "reason": "busy"])
    }
    guard feetMarker != nil, headMarker != nil else {
      return result(["ok": false, "reason": "no_markers"])
    }
    burstSamples = []
    burstFloorHits = 0
    burstTicks = 0
    burstStart = CACurrentMediaTime()
    burstResult = result
    let link = CADisplayLink(target: self, selector: #selector(burstTick))
    link.preferredFramesPerSecond = 30
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func burstTick() {
    guard burstResult != nil else { return finishBurst(nil) }
    burstTicks += 1
    let expired = CACurrentMediaTime() - burstStart > Self.burstDeadline
    if burstSamples.count >= Self.samplesWanted || expired {
      return finishBurst(burstVerdict())
    }
    guard let feet = feetMarker, let head = headMarker,
          let frame = arView.session.currentFrame,
          case .normal = frame.camera.trackingState else { return }

    // Feet: detected floor geometry only. Y snaps to the tracked floor
    // anchor when they agree — per-ray Y on an estimated-ish hit can
    // float, the refined anchor is the stable truth.
    guard let floorHit = raycastFloor(from: denormalize(feet), allowEstimated: false) else { return }
    burstFloorHits += 1
    var f = simd_float3(floorHit.worldTransform.columns.3.x,
                        floorHit.worldTransform.columns.3.y,
                        floorHit.worldTransform.columns.3.z)
    if let fy = floorY, abs(f.y - fy) <= Self.floorSnapTolerance {
      f.y = fy
    }

    // Head: a pure direction — closest approach of the screen ray to
    // the vertical line rising from the feet point.
    guard let ray = worldRay(through: denormalize(head)) else { return }
    let c = ray.origin
    let d = ray.dir
    let u = simd_float3(0, 1, 0)
    let w = c - f
    let b = simd_dot(d, u)
    let dd = simd_dot(d, w)
    let e = simd_dot(u, w)
    let denom = 1 - b * b
    guard denom > 0.05 else { return } // ray near-vertical → unstable solve
    let s = (b * e - dd) / denom
    let h = (e - b * dd) / denom
    let residual = simd_length((c + s * d) - (f + h * u))

    // Per-sample gates: in front of the camera, plausible child
    // height, ray actually passes near the vertical line.
    guard s > 0, h > 0.4, h < 2.2, residual < Self.residualLimit else { return }

    let dirXZ = simd_length(simd_float2(d.x, d.z))
    burstSamples.append(MeasureSample(
      h: h,
      residual: residual,
      feetPos: f,
      dChild: simd_length(simd_float2(f.x - c.x, f.z - c.z)),
      pitchDeg: atan2(d.y, dirXZ) * 180 / .pi))
  }

  /// Decide the burst outcome from what the ~1 s window collected.
  private func burstVerdict() -> [String: Any] {
    if burstFloorHits == 0 {
      return ["ok": false, "reason": "no_floor"]
    }
    guard burstSamples.count >= Self.samplesMinimum else {
      return ["ok": false, "reason": "hold_still"]
    }

    // Median h with MAD outlier rejection, then the spread gate.
    let heights = burstSamples.map { $0.h }
    let med = Self.median(heights)
    let mad = Self.median(heights.map { abs($0 - med) })
    let tolerance = Swift.max(0.01, 3 * mad)
    let kept = burstSamples.filter { abs($0.h - med) <= tolerance }
    guard kept.count >= Self.samplesMinimum else {
      return ["ok": false, "reason": "hold_still"]
    }
    let keptHeights = kept.map { $0.h }
    let finalH = Self.median(keptHeights)
    let mean = keptHeights.reduce(0, +) / Float(keptHeights.count)
    let variance = keptHeights.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(keptHeights.count)
    let stddev = variance.squareRoot()
    guard stddev <= Self.stddevLimit else {
      return ["ok": false, "reason": "unstable", "stddevCm": Double(stddev * 100)]
    }

    // Draw this burst's furniture at the median-h sample's feet point.
    let anchorSample = kept.min(by: { abs($0.h - finalH) < abs($1.h - finalH) }) ?? kept[0]
    let feetPos = anchorSample.feetPos
    let headPos = simd_float3(feetPos.x, feetPos.y + finalH, feetPos.z)
    let cm = Double(finalH * 100)

    provisionalFeetNode?.removeFromParentNode()
    provisionalFeetNode = nil
    let feetNode = addLevelLine(at: feetPos, number: nextNumber)
    let headNode = addLevelLine(at: headPos, number: nextNumber)
    let measureNode = addVerticalMeasure(feet: feetPos, head: headPos, labelCm: cm)
    completed.append(ReadingNodes(feetNode: feetNode, headNode: headNode, measureNode: measureNode))
    updateOpacities()

    return [
      "ok": true,
      "heightCm": cm,
      "stddevCm": Double(stddev * 100),
      "distanceM": Double(Self.median(kept.map { $0.dChild })),
      "pitchDeg": Double(Self.median(kept.map { $0.pitchDeg })),
    ]
  }

  /// Single exit for a burst: stop the clock and ALWAYS answer Dart.
  private func finishBurst(_ payload: [String: Any]?) {
    displayLink?.invalidate()
    displayLink = nil
    burstSamples = []
    if let result = burstResult {
      burstResult = nil
      result(payload ?? ["ok": false, "reason": "cancelled"])
    }
  }

  private static func median(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let n = sorted.count
    return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
  }

  private func resetScan() {
    finishBurst(["ok": false, "reason": "cancelled"])
    feetMarker = nil
    headMarker = nil
    provisionalFeetNode?.removeFromParentNode()
    provisionalFeetNode = nil
    for r in completed {
      r.feetNode.removeFromParentNode()
      r.headNode.removeFromParentNode()
      r.measureNode.removeFromParentNode()
    }
    completed.removeAll()
  }

  // ── Scene furniture ─────────────────────────────────────────────

  /// Latest burst bright, history fades.
  private func updateOpacities() {
    for (i, r) in completed.enumerated() {
      let opacity: CGFloat = i == completed.count - 1 ? 1 : Self.fadedOpacity
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

  /// The vertical measure joining a finished burst, labelled with cm —
  /// the tape-measure element.
  private func addVerticalMeasure(feet: simd_float3, head: simd_float3, labelCm: Double) -> SCNNode {
    let h = CGFloat(head.y - feet.y)
    let parent = SCNNode()
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

  // ── Floor tracking + surface feedback ───────────────────────────

  /// Adopt the best floor candidate: a .floor-classified plane wins
  /// outright; otherwise the LOWEST horizontal plane (rejects tables
  /// and beds detected before the actual floor).
  private func considerFloorCandidate(_ plane: ARPlaneAnchor) {
    guard plane.alignment == .horizontal else { return }
    if plane.classification == .floor {
      floorAnchor = plane
    } else if let current = floorAnchor {
      if current.classification != .floor {
        let currentY = (current.transform * simd_float4(current.center.x, current.center.y, current.center.z, 1)).y
        let candidateY = (plane.transform * simd_float4(plane.center.x, plane.center.y, plane.center.z, 1)).y
        if candidateY < currentY { floorAnchor = plane }
      }
    } else {
      floorAnchor = plane
    }
  }

  // Delegate callbacks arrive on the render thread; floorAnchor is
  // read by the burst on main, so hop before touching shared state.
  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let plane = anchor as? ARPlaneAnchor else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.considerFloorCandidate(plane)
      guard plane.alignment == .horizontal, !self.hasFloorPlane else { return }
      self.hasFloorPlane = true
      self.channel.invokeMethod("onState", arguments: ["state": "floor_found"])
    }
  }

  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    guard let plane = anchor as? ARPlaneAnchor else { return }
    // ARKit refines planes over time; re-evaluate (classification can
    // arrive late, and the same anchor object updates in place).
    DispatchQueue.main.async { [weak self] in
      self?.considerFloorCandidate(plane)
    }
  }

  func session(_ session: ARSession, didFailWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("onState", arguments: ["state": "error", "message": error.localizedDescription])
    }
  }
}
