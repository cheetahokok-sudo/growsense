# Height Scan — AR height measurement (iOS)

User-facing name: **Height Scan** (สแกนส่วนสูง). Saves to `measurements`
with `data_source: 'camera_ar'`.

## Measurement algorithm (v3 — the theodolite correction)

Device testing (2026-07-31, iPhone 15 Pro) showed v1/v2 readings running
**4–10 cm short**. Two systematic mechanisms, both geometric:

1. **Head-ray wall overshoot.** A ray aimed at the crown grazes the hair
   and lands on the wall 10–15 cm behind — a detected plane the raycast
   prefers (dark hair is near-invisible to LiDAR, making wall hits the
   norm). The phone is held above a child's crown, so the ray descends;
   by the wall it is below true crown height:
   `error ≈ (camY − crownY)/distance × head-to-wall gap`.
   Worse close up, worse for small children.
2. **Foot-top feet marks.** With mesh reconstruction an `.any` raycast at
   the feet can hit the top of the foot (3–8 cm above floor), raising the
   floor reference.

Fix (in `markPoint`):

- **Feet raycast restricted to `.horizontal`** — it can only land on the
  floor plane, which is at true floor height wherever the ray touches it.
- **Head hit depth is discarded; only the ray direction is used.** The
  feet mark fixed the child's horizontal distance `d_child`, so the crown
  height is the ray evaluated at the child's plane:

  ```
  dir     = hit − cam            (direction; the hit may be the wall)
  t       = d_child / ‖dir_xz‖
  crownY  = camY + dirY · t
  height  = crownY − floorY
  ```

  If the ray hit the head itself the result is unchanged; if it overshot
  to the wall, the overshoot term cancels exactly. The measurement is
  purely angular — a theodolite, not a rangefinder — so head-depth error
  (LiDAR-through-hair, wall planes, estimated-plane noise) drops out.
  Guard: near-vertical rays (‖dir_xz‖ < 0.05) keep the raw hit.
- **Crosshair carries a horizontal bar** (stadiometer headboard): the
  parent rests the *line* on the crown / at the floor contact, rather
  than centring a circle on the head — which read a few cm low.

Residual error sources: floor-plane estimate (~sub-cm), aim (~the bar
width), hair compression (true of stadiometers too), diurnal 1–2 cm.

## How it works

Two-point AR raycast, no LiDAR required (LiDAR sharpens it for free):

1. ARKit detects the floor plane.
2. Parent aims the crosshair at the child's **feet** → tap Mark (anchors floor Y).
3. Aims at the **top of the head** → tap Mark. Height = vertical delta.
   The child stands against a wall, so even when hair gives no feature
   points, the wall plane behind the head is hit *at the same Y* — which
   is the only coordinate used.
4. Three readings → **median** is offered as the result.

Expected accuracy: ~1 cm tier on non-LiDAR phones, better on Pro (LiDAR
mesh raycasts). Diurnal height variation is 1–2 cm, hence the intro tip
to scan at a consistent time of day.

## v2 UX (designed in the approved user-journey artifact)

- **Setup illustration** on the intro (CustomPainter `_SetupScenePainter`):
  child against the wall, parent 2–3 steps back, gold sight-lines.
- **Six-mark sequence strip** — ①feet ①head ②feet ②head ③feet ③head —
  static on the intro, live above the Mark button (current bold, done ✓).
- **Numbered AR level lines**: every mark pins a dashed line with number
  badges at both ends into the room; a completed pair is joined by a
  **vertical measure** labelled with that reading's cm. Current reading
  bright mint, history fades to 30%. All SceneKit, in the platform view.
- **Redo** (`undoMark`): one mark back — pending feet unmarks, or the
  last pair reopens (head line + measure removed, feet line restored).
- **Honesty hints**: both marks < 1.5 m → "step back" tip; readings
  spread > 2 cm → estimated-gold warning on the result, never blocking.
- **No emoji** — `hscan_*` glyphs in `widgets/gs_icons.dart` (house
  duotone grammar: #153a2b stroke, #cfe3d5 plane, teal/gold accents).

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
- `growsense/height_scan_<viewId>` (per view): `markPoint` → `{ok, step: feet|head, heightCm?}` or `{ok: false, reason: no_surface|implausible}`; `reset`; `dispose`. Native → Dart: `onState {state: floor_found|error}`.

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
   PrivacyInfo.xcprivacy) — no Xcode step needed. The first Codemagic
   build after this lands validates the pbxproj parse.
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

## Acceptance test (the spike, on a real phone)

1. Medical tab → Log measurement → **Scan height** appears (iPhone only).
2. Scan a cooperative adult 3× against a wall; compare the median to a
   tape measure. Pass: within ~1.5 cm on a non-LiDAR phone, ~0.5 cm on
   a Pro. If it's wildly off, check the floor: reflective/patterned
   floors defeat plane detection.
3. Save with a weight → row in `measurements` has `data_source = 'camera_ar'`.
4. Edit the height field by hand → 📷 suffix disappears → save →
   `data_source = 'manual'`.

## Phase 2 (not built)

LiDAR auto-detect (Vision person segmentation + `sceneDepth`, no aiming)
as an upgrade path inside the same Swift module; Android/ARCore twin of
the platform view if the Android build ships.
