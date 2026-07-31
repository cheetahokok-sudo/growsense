# Height Scan — AR height measurement (iOS)

User-facing name: **Height Scan** (สแกนส่วนสูง). Saves to `measurements`
with `data_source: 'camera_ar'`.

## Measurement algorithm (v4 — stationary markers, closest-point solve)

Field test against a known 197 cm door (2026-07-31): v3 read
192.8 / 188.8 / 188.2 — 4–9 cm short, 4.5 cm spread. Three causes:

1. **Reticle mis-centring.** The drawn reticle sat in a Column between
   two Spacers whose surrounding cards had different heights, so it was
   drawn *above* the true view centre where the raycast fired — the user
   aligned the line, the phone measured a point below it.
2. **Move-the-phone flow.** Sweeping from feet to head added tracking
   drift and re-aim error between marks; every mark was one jittery
   single-frame raycast.
3. **Grazing feet ray.** ~1° of feet-aim error moves the floor hit
   6–8 cm horizontally, and that distance error scales into height
   error by tan(head-ray pitch).

v4 discards aim-and-mark entirely. The phone stays STILL with the whole
child in frame; the parent taps a FEET marker (wall-floor junction
between the heels) and a HEAD marker (the crown) on screen, fine-tunes
them by dragging (1:3 reduced gain), then Measure runs a native burst:

- `worldAlignment = .gravity` → world Y is true vertical.
- Per frame (~15 frames over ~1 s via CADisplayLink, 30 fps):
  1. Gate: `trackingState == .normal`.
  2. **Feet**: raycast the feet marker onto `.existingPlaneGeometry`
     (horizontal), preferring a `.floor`-classified plane; Y snapped to
     the tracked floor anchor when within 10 cm. → `F`
  3. **Head**: unproject the head marker into a world ray `C + s·D`
     (never raycast the head onto environment geometry — the wall
     behind the child must not determine the head depth).
  4. **Closest approach** of that ray to the vertical line
     `L(h) = F + h·(0,1,0)`. `h` is the height; the miss distance
     (residual) is the frame's quality signal.
  5. Per-sample gates: `s > 0`, `0.4 < h < 2.2` m, residual < 5 cm,
     denominator guard against near-vertical rays.
- Burst verdict: `no_floor` if the feet marker never hit detected
  floor; `hold_still` if < 6 clean samples; else median `h` with MAD
  outlier rejection; `unstable` if stddev > 1.5 cm. Success returns
  `heightCm` + `stddevCm` + `distanceM` (horizontal camera→feet) +
  `pitchDeg` (head-ray elevation) for the Dart honesty hints
  (pitch > 25° or distance < 1.5 m → step-back tip, never blocking).
- Three bursts (markers persist, nudge between), median of medians,
  spread > 2 cm → estimated-gold warning.

Note: v3's "theodolite" pull-back was the same geometry as the
closest-point solve (direction-only head, depth discarded) — v4 keeps
that insight but gains the residual gate, multi-frame medians, the
floor lock, and removes the mis-centred reticle by construction (the
ray goes through the marker the user placed, not the screen centre).

Residual error sources: floor-anchor estimate (~sub-cm, refined live),
marker placement (~1 px ≈ 1–2 mm at 2 m), hair compression (true of
stadiometers too), diurnal 1–2 cm.

## UX (v4)

- **Setup illustration** on the intro (`_SetupScenePainter`): child
  against the wall, parent 2–2.5 m back, phone still at chest height.
- **Markers**: dot + full-width hairline (no circle — field feedback),
  mint for feet, white for head, label chips, drag handles with 1:3
  reduced-gain vertical drag. Tap to place, drag to fine-tune.
- **Burst chips** ① ② ③ above the buttons (current bold, done ✓).
- **AR furniture** per successful burst: numbered dashed level lines at
  feet + head and a vertical measure labelled with cm. Latest bright
  mint, history fades to 30%. A provisional feet line (55% opacity,
  estimated-plane allowed) previews where the feet tap landed.
- **Refusals, not bad numbers**: no_floor / hold_still / unstable map
  to plain-language hints; Measure shows a spinner + "Hold the phone
  still…" during the burst.
- **Single-line buttons**: labels FittedBox-shrink instead of wrapping
  (the "Can cel" / "Red o" fix).
- **No emoji** — `hscan_*` glyphs in `widgets/gs_icons.dart`.

## Code map

| Piece | File |
| --- | --- |
| ARKit platform view + channel | `ios/Runner/HeightScanView.swift` |
| Registration | `ios/Runner/AppDelegate.swift` |
| Dart channel wrapper + median | `lib/height_scan.dart` |
| Guided flow screen | `lib/screens/height_scan_screen.dart` |
| Entry point + provenance save | `lib/screens/medical_screen.dart` (`_EntryCard`) |
| Strings | `flutter.hscan.*` in all six `assets/locales/*.json` |

Channel contract:
- `growsense/height_scan` (static): `isSupported`, `hasLidar`
- `growsense/height_scan_<viewId>` (per view):
  - `setMarkers {feetX, feetY, headX, headY}` — normalized 0–1 view
    coords; either pair may be absent while placing.
  - `measure` → `{ok: true, heightCm, stddevCm, distanceM, pitchDeg}`
    or `{ok: false, reason: no_floor|hold_still|unstable|no_markers|busy|cancelled}`.
    Async on the native side (~1 s burst); the pending FlutterResult is
    always completed, including on reset/dispose (`cancelled`).
  - `reset`; `dispose`. Native → Dart: `onState {state: floor_found|error}`.

Provenance rules (the honest-data part):
- The scan median lands in the normal entry card with a 📷 suffix; weight,
  date, and the free-tier cap all behave exactly as a typed entry.
- Save passes the **exact AR median** (not the re-parsed display text) with
  `data_source: 'camera_ar'`.
- Hand-editing the prefilled height drops provenance back to `'manual'` —
  a typed number is never labelled as a scan.
- The Scan button renders only when the availability probe succeeds, so
  web/Android/old-binary builds are untouched.

## Building (Codemagic — no Mac in the loop)

1. `HeightScanView.swift` is **already hand-wired into
   `project.pbxproj`** (UUIDs `A1B2C3D4…0003/0004`, same convention as
   PrivacyInfo.xcprivacy) — no Xcode step needed.
2. Build via Codemagic as usual (TestFlight workflow, branch `main`).
   No new pods, no new permissions — `NSCameraUsageDescription`
   already exists (X-ray flow).
3. Do **not** add `arkit` to `UIRequiredDeviceCapabilities` — the app
   must keep installing on devices without ARKit; the feature hides
   itself via `isSupported`.
4. ARKit does **not** run in the iOS Simulator — a physical device via
   TestFlight is the only way to exercise the feature.

Strings live in `tool/flutter_extra_keys.json` (the SOURCE —
`assets/locales/` is generated by `node tool/sync_locales.js`).

## Acceptance test (real phone)

1. **Door regression**: the 197 cm door, ~2.5 m back, phone ~1.2–1.4 m
   high. Feet line at the wall-floor joint, head line at the door's top
   edge, 3 bursts. Pass: median 197 ± 1.5 cm, spread < 2 cm
   (v3 baseline: 188.8, spread 4.5).
2. **Marker precision**: slow drag lands the head line on the door's
   top edge; chips don't occlude the line.
3. **Gates**: sweep the phone during Measure → unstable/hold-still hint,
   never a silently bad number; feet marker on a wall → no_floor.
4. **Hints**: measure from ~1 m → steep-pitch hint.
5. **Buttons**: Cancel / Measure / Scan again / Use this height all
   single-line in EN and TH.
6. **Human check**: known-height adult, hair flattened — median within
   ~1.5 cm, spread < 2 cm; save lands `data_source = 'camera_ar'`;
   hand-edit drops to `'manual'`.
7. **Regressions**: cancel mid-scan, Scan again (markers clear, AR
   furniture clears), re-entering the screen.
8. **Product validation (later)**: versus a stadiometer at
   1.5 / 2.0 / 2.5 m across rooms and hair styles — target bias
   < 0.5 cm, MAE < 1 cm, repeats within 1 cm.

## Phase 2 (not built)

Person-segmentation auto-crown (find the head silhouette top from the
ARKit person mask, median over frames — no manual head marker) and raw
`sceneDepth` as a secondary validation source on LiDAR phones;
Android/ARCore twin of the platform view if the Android build ships.
