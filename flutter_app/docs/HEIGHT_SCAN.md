# Height Scan — AR height measurement (iOS)

User-facing name: **Height Scan** (สแกนส่วนสูง). Saves to `measurements`
with `data_source: 'camera_ar'`.

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

## Building (Mac required — the Swift side cannot compile on Windows)

1. `HeightScanView.swift` must be added to the Runner target: open
   `ios/Runner.xcworkspace` in Xcode → if the file isn't listed under
   Runner, drag it in from Finder with "Add to target: Runner" checked.
   (Files created outside Xcode are NOT picked up automatically —
   the project uses a pbxproj file list, not folder references.)
2. `flutter build ios` / archive as usual. No new pods, no new
   permissions — `NSCameraUsageDescription` already exists (X-ray flow).
3. Do **not** add `arkit` to `UIRequiredDeviceCapabilities` — the app
   must keep installing on devices without ARKit; the feature hides
   itself via `isSupported`.

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
