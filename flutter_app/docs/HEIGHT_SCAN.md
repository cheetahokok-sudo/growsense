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
- Both markers are **snapshotted at measure()** — a mid-burst drag
  cannot mix geometries.
- Per unique camera frame (~15 over ~1 s via CADisplayLink; duplicate
  `ARFrame.timestamp`s are skipped so 15 samples are 15 real frames):
  1. Gate: `trackingState == .normal`; camera travel tracked against
     the first frame.
  2. **Feet**: raycast the feet marker onto `.existingPlaneGeometry`
     (horizontal), preferring a `.floor`-classified plane. The burst
     **locks to the first hit's anchor identifier** — one burst never
     blends two floor datums, and there is deliberately NO cross-anchor
     Y correction (a plane-geometry hit already lies on its plane's
     refined surface).
  3. **Head**: unproject the head marker into a world ray from the AR
     camera origin (never raycast the head onto environment geometry —
     the wall behind the child must not determine the head depth).
- Burst verdict: `no_floor` if the feet marker never hit detected
  floor; `hold_still` if < 6 clean frames; `unstable` if the camera
  travelled > 3 cm. Then the floor point is **frozen**: `F*` =
  component-wise median of the same-anchor hits, and every frame's ray
  is solved against `F*` — **closest approach** to the vertical line
  `L(h) = F* + h·(0,1,0)`, gated per frame (`s > 0`,
  `0.4 < h < 2.2` m, residual < 5 cm, near-vertical guard). Median `h`
  with MAD outlier rejection; `unstable` if stddev > 1.5 cm. Success
  returns `heightCm` + `stddevCm` + `distanceM` (horizontal
  camera→feet) + `pitchDeg` (head-ray elevation) for the Dart honesty
  hints (pitch > 25° or distance < 1.5 m → step-back tip, never
  blocking).
- Three bursts (markers persist, nudge between), median of medians,
  spread > 2 cm → estimated-gold warning.
- **Feet marker definition matters**: the vertical line must rise from
  under the crown axis, so the instruction is the floor between the
  feet AT THE ANKLES — not the wall-floor seam (behind the body axis)
  and not the toes (in front). Marking the wall seam reads short by
  `(camY − crownY) × gap / distance`. The stronger mitigation is in
  the intro: hold the phone level with the child's head — when camera
  height ≈ crown height that error term vanishes entirely.

Note: v3's "theodolite" pull-back was the same geometry as the
closest-point solve (direction-only head, depth discarded) — v4 keeps
that insight but gains the residual gate, multi-frame medians, the
floor lock, and removes the mis-centred reticle by construction (the
ray goes through the marker the user placed, not the screen centre).

Residual error sources: floor-anchor estimate (~sub-cm, refined live),
marker placement (~1 px ≈ 1–2 mm at 2 m), hair compression (true of
stadiometers too), diurnal 1–2 cm.

## v4.2 — reliability and pre-placed lines

v4.1 measured **0.2–0.5 cm** against a known reference on device, so
the engine above is correct and the door test guards it. v4.2 fixes
what surrounded it.

**Bursts kept refusing honest attempts** ("hold the phone still" with a
steady hand). Two starvation causes, both in the feet raycast:

- `raycastFloor` only tried `.existingPlaneGeometry`, so the ray had to
  land inside the detected plane's *polygon* — clutter, rug edges and
  low-texture patches leave holes. It now falls back to
  `.existingPlaneInfinite`: the same detected plane extended, so the Y
  datum is identical on a flat floor, but the hit rate jumps.
- The per-burst lock compared plane **anchor identity**. ARKit merges
  plane anchors mid-burst, and after a merge every later frame was
  rejected. The lock is now on floor **height** (±5 cm), which survives
  merges and still refuses a table — the datum-blending this guard
  exists to prevent.

Window widened to 10 wanted / 4 minimum / 2.5 s deadline, camera-travel
gate 3 → 5 cm. A clean burst finishes *sooner* (it stops at 10 samples);
only a starving one runs long. The accuracy gates — residual, stddev,
MAD rejection — are untouched, because those are what protect the
number; sample count never did.

**Refusals name the real cause.** New `floor_patchy` fires when the ray
found *some* floor but missed more often than it hit: the feet line is
over bad floor, not the parent's hands. Telling someone to hold still
when the floor was the problem is what made this feel broken.

**Measuring is adaptive**: two bursts finish the scan when they agree
within 0.5 cm (`agreeCm`); the third runs only on disagreement, and its
chip stays dimmed until needed. A failed burst retries once silently
before any hint appears.

### Why 150 cm, and not the child's last height

The head line is pre-placed at a **generic** 150 cm above the floor —
never at the child's previous measurement, and the preset height is
never displayed as a number. Presetting the last value would let a
parent press Measure without adjusting and record the previous number
again, which reads as "no growth" and is indistinguishable from a real
flat period. The generic guess is visibly wrong for most children, so
it forces a real adjustment, and `preset_hint` says so out loud: these
lines are a starting guess, not a measurement. **Do not "improve" this
by remembering the child's height.**

## UX (v4.2)

- **Both lines exist before the camera renders a frame** — no bare-camera
  moment. Feet starts at `defaultFeetY = 0.72` (clear of the bottom
  card, whose top edge lands near 0.82 on both tall and small phones),
  head at `fallbackHeadY = 0.35` (conservative: lands on the chest,
  never off the top).
- **`presetHead`** then settles the head line once onto a true 150 cm
  above the floor. Retried every 500 ms for up to 6 s while untouched,
  because `floor_found` fires on the first small plane patch when the
  raycast usually still misses; any drag cancels it permanently.
  If the crown projects off-screen or the feet are nearer than 1.5 m,
  the too-close hint fires *before* a burst is wasted.
- **Velocity-adaptive drag**: 1:3 gain below ~250 px/s (bit-identical to
  the validated behaviour) ramping to 1:1 above ~900 px/s, so a big move
  is one flick. No tap-to-place — "tap moves the nearest line" would put
  a mode boundary at the middle of the child's body.
- **Markers clamp to 0.20–0.80 and cannot cross** (crossed lines produced
  `h < 0.4`, surfaced as a misleading "hold still"), and a clamp that
  bites explains itself with the framing hint.
- **Overlay cards absorb pointers** — `Container`/`Column`/`Text` don't
  hit-test themselves, so a tap on the guidance text used to fall
  through and move a line.
- **Aim detail follows the last-touched line** and persists after the
  drag, so it's readable when the parent looks up to press Measure.

## UX (v4)

- **Setup illustration** on the intro (`_SetupScenePainter`): child
  against the wall, parent 2–2.5 m back, phone still and level with
  the child's head.
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
  - `presetHead {feetX, feetY, heightCm}` →
    `{ok, headX, headY, offScreen, distanceM}` or
    `{ok: false, reason: no_floor|behind|invalid|implausible|not_ready}`.
    **Pure query — never mutates native marker state**, so a preset can
    never silently revert a parent's drag. Behind-camera is detected in
    camera space (`pCam.z < -0.05`), not from the projected z.
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
8. **Refusal rate (the reason v4.2 exists)**: 10 consecutive bursts on a
   cluttered wooden floor. Pass: ≥ 8 succeed first try, and any failure
   names the right cause (`floor_patchy`, not "hold still").
9. **Speed**: a good scan ends after 2 bursts; the 3rd appears only when
   the first two disagree by > 0.5 cm.
10. **Cold open**: both lines visible in the first rendered frame.
11. **Preset settle**: the head line snaps once within ~2 s, never after
    you touch it; a 150 cm reference at 2.5 m lands within a few cm
    untouched.
12. **Drag**: a fast flick crosses the screen in one gesture; a slow drag
    still moves ~1 px per 3 px of finger.
13. **Hit-testing**: taps and drags starting on either overlay card do
    nothing to the lines; every button still works; lines can't cross.
14. **AR label**: frame the child hard against the right edge — the cm
    label flips to the left instead of clipping.
15. **Product validation (later)**: versus a stadiometer at
    1.5 / 2.0 / 2.5 m across rooms and hair styles — target bias
    < 0.5 cm, MAE < 1 cm, repeats within 1 cm. Method: Bland-Altman
    (bias + limits of agreement), matching Thaventhiran et al. 2023
    (*Mayo Clin Proc Digit Health* 1(4):498–509), whose AR app scored
    0.11 cm bias / −2.21 to +2.42 cm in clinic and 0.44 cm / −5.10 to
    +4.21 cm for parents at home. Note the floor: repeat stadiometer
    measurements themselves carry 0.2–0.3 cm SD (Voss et al. 1990,
    *Arch Dis Child* 65:1340) — no app can beat that, and diurnal
    variation is ~1.9 cm with 54% lost in the first hour after rising
    (Tyrrell et al. 1985, *Spine* 10:161).

## Phase 2 (not built)

Person-segmentation auto-crown (find the head silhouette top from the
ARKit person mask, median over frames — no manual head marker) and raw
`sceneDepth` as a secondary validation source on LiDAR phones;
Android/ARCore twin of the platform view if the Android build ships.
