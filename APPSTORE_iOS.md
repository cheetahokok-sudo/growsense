# GrowSense — iOS App Store prep

## Step 2 — code blockers fixed (2026-07-11)

These are the rejection/crash blockers found in the iOS project and now
resolved in code. Each has a **paired manual step** you must complete.

| Fix | File(s) | Manual step you still need to do |
|---|---|---|
| Photo/camera usage strings (image_picker → crash + ITMS-90683) | `ios/Runner/Info.plist` | none (wording is final; edit if you prefer) |
| In-app account deletion (Guideline 5.1.1(v); mailto no longer accepted) | `lib/screens/account_screen.dart`, `supabase/functions/delete-account/index.ts` | **Deploy the Edge Function** (below) |
| iOS/Android OAuth deep-link redirect (login dead-ended after Apple/Google) | `lib/screens/auth_screen.dart`, `ios/Runner/Info.plist`, `android/.../AndroidManifest.xml` | **Add the redirect to Supabase allowlist** (below) |
| Version sync (pubspec was 1.0.0+1, app_meta 1.0.1+2) | `pubspec.yaml` → `1.0.1+2` | bump both together on each release |

### A. Deploy the account-deletion function
```bash
supabase functions deploy delete-account
```
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are injected
automatically. The function deletes the caller's children + per-child data +
account rows, then the auth user (schema-matched: children.parent_id,
data.child_id, user_accounts.user_id). **Test it on a throwaway account** —
if it returns a `warnings` array or a foreign-key error naming a table, add
that table to `CHILD_TABLES`/`USER_TABLES` in the function.

### B. Add the native OAuth redirect to Supabase
Supabase Dashboard → **Authentication → URL Configuration → Redirect URLs**,
add:
```
com.growsense.growsense://login-callback/
```
(Google/Apple provider consoles still point at the Supabase callback — no change
there. This deep link is what re-opens the app after the provider screen.)

## Still ahead (not code — see the full review)
- Apple Developer Program enrolment (+ D-U-N-S if Organization) — slowest step.
- ⚠️ **BLOCKER — app icon is still the DEFAULT FLUTTER LOGO** (verified 2026-07-14:
  `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` is the
  blue Flutter chevron). Apple auto-rejects placeholder/template icons
  (Guideline 2.3.7 / 4.0). A branded 1024×1024 icon (no alpha, no rounded corners)
  must replace the whole appiconset before submission. Same for Android
  `mipmap-*/ic_launcher`.
- Codemagic (or a Mac) to build/sign/submit — cannot be done from Windows.
- Native Sign in with Apple polish, App Privacy nutrition label, reviewer demo
  account, screenshots, age rating.

## Step 3 — re-applied to current `main` + CI & privacy manifest (2026-07-14)

The original Step-2 work lived on the stale `ios-appstore-prep` branch (64 commits
behind `main` — unmergeable). It was **re-applied onto a fresh branch off current
`main` (`ios-appstore-prep-v2`)**, with the `delete-account` function updated for
tables added since (adds `sleep_naps`, `google_health_connections`), plus:

| Added | File | Manual step |
|---|---|---|
| Apple **privacy manifest** (required since 2024) | `ios/Runner/PrivacyInfo.xcprivacy` | **In Xcode: drag it into the Runner group and tick Runner target membership** (not wired into `project.pbxproj` here, to avoid risking the build). |
| **Codemagic** workflow (build → sign → TestFlight) | `codemagic.yaml` (repo root, `working_directory: flutter_app`) | In Codemagic UI: connect repo; add an **App Store Connect API key** integration named `GrowSense ASC Key`; set `APP_STORE_APPLE_ID`. |
| i18n for the delete dialog | `flutter_app/tool/flutter_extra_keys.json` (6 langs) | none (regenerated) |

Version note: `pubspec.yaml` is `1.0.0+1` on this branch (fine for a first
1.0.0 submission). `codemagic.yaml` auto-increments the **build number** from the
latest TestFlight build; bump the **version** (`1.0.0` → `1.0.1`…) per release.

## Step 4 — Apple account set up (2026-07-14)

Done in the Apple portals (account: Aimvalee Chanphen, **Team ID `D5D3MX2XMH`**):
- ✅ **Apple Developer Program** enrolment active.
- ✅ **App ID registered**: `com.growsense.growsense` (explicit) with **Sign in with
  Apple** capability enabled (primary App ID).
- ✅ **App record created** in App Store Connect.
  - **App Store title:** `GrowSense Life` (the plain "GrowSense" was already taken;
    this is only the store listing name — the home-screen name stays "GrowSense"
    via `CFBundleDisplayName`).
  - **Apple ID (numeric):** `6790710624` → already written into `codemagic.yaml`
    `APP_STORE_APPLE_ID`.
  - SKU `growsense-ios`, Primary language English (U.S.), iOS only.

Next: create the **App Store Connect API key** (Users and Access → Integrations →
App Store Connect API), name it `GrowSense ASC Key` in Codemagic, then run the
Codemagic workflow. Deploy `delete-account` + add the Supabase redirect URL.

### External gates still to do (not code)
- **App Store Connect API key**: Users and Access → Integrations → App Store Connect
  API → Team Keys → App Manager role; download the `.p8` (once) + Issuer ID + Key ID.
- **Privacy policy URL** (mandatory — child health data) + **App Privacy nutrition
  labels** in ASC (declare health data, contact info, identifiers).
- App icon = GrowSense brand icon (not the default Flutter logo).
- Screenshots (6.7"/6.5"/iPad), description, category, age rating, reviewer demo account.

## Test checklist on the first TestFlight build
- [ ] Google login completes and returns to the app (not stuck on the web page)
- [ ] Apple login completes and returns to the app
- [ ] Password-reset email link re-opens the app
- [ ] Bone-age screen: tapping to add a photo shows the OS permission prompt (no crash)
- [ ] Account → Delete account: confirm dialog → account gone → back to sign-in →
      cannot sign back in with the same credentials
- [ ] PDF export / CSV export still work on device
