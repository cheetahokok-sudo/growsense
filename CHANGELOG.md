# Changelog

All notable changes to GrowSense are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and versions follow
[Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

- **MAJOR** — a breaking change to data or core flows.
- **MINOR** — a new, backwards-compatible user-facing feature.
- **PATCH** — bug fixes and small refinements.

On every release, bump `kAppVersion` / `kAppBuild` / `kBuildDate` in
`flutter_app/lib/app_meta.dart`, add the highlights to
`flutter_app/assets/release_notes.json` (what users see in "What's
new"), and add the full entry here.

## [1.5.0] — 2026-07-30 · build 27

_Premium, purchasable in the app. v1.0 shipped to the App Store with every
paid surface hidden on iPhone and iPad (Guideline 3.1.1 — a paid feature may
not be sold outside the App Store). This release brings them back through
In-App Purchase._

### Added
- **Premium, buyable on iPhone and iPad.** A monthly and an annual
  subscription through the App Store, with Restore Purchases, and a
  full-screen paywall carrying the subscription terms Apple requires.
  Prices always come from the store, never from our own code, so every
  storefront shows its own currency. Web and Android are unchanged.
- **Insight Windows.** Analytics cards can be read over 90 days or six
  months on premium; the free tier shows the last 30 days. Height velocity
  keeps a three-month clinical floor — a shorter window cannot produce a
  meaningful cm/year figure — and a chip appears when a window holds too
  few measurements to trust.
- **Annotate a bone-age X-ray.** The annotation overlay from the web app is
  now in the phone app: mark the carpals and the growth plates on the image
  you filed, so a serial history stays readable years later.
- **Export on the phone.** The visit-summary PDF and CSV export now save
  and share from the device instead of only working in the web app.
- **Confirmation before deleting clinical records** — labs, measurements,
  puberty entries, illness records and family heights. The measurement
  dialog says plainly that deleting does not return a free slot. Today's
  food, activity and nap logs deliberately still delete in one tap.

### Changed
- **Free tier defined.** Daily logging — food, activity, sleep — stays
  unlimited and always will. What premium buys is the longitudinal record:
  measurements are capped at five for the lifetime of a free account, and
  analytics are windowed to 30 days. Nothing is deleted; locked history is
  counted and shown, and the most recent point always renders, so a blank
  chart can never be mistaken for lost data.
- **The iOS paid surface is back**: subscription card, bone-age AI second
  opinion, lab interpretation and the visit-summary PDF. Activation codes
  remain web and Android only — redeeming a code for digital content is
  exactly what Guideline 3.1.1 forbids, and the platform gates now assert
  that codes and In-App Purchase are never both offered.
- The growth chart's Focus / All-years control is a segmented control
  rather than a button; as a button it read as an action, not as state.
- iOS deployment target 13.0 → 15.0 (StoreKit 2).

### Fixed
- **Bone-age assessments failed to save.** The app sent `greulich_pyle` /
  `tw3` where the database expects `GP` / `TW3`. Fixed, and a test now
  parses the web app's own `<select>` so the two vocabularies cannot drift
  apart again.
- **The paywall's buy button could not be tapped** and the price wrapped
  vertically — the theme's minimum button height made an infinitely wide
  button that starved the layout.
- **Tab-bar icons were crushed against the top border** on phones with a
  home indicator: the bar's fixed height sat outside the safe area, so the
  inset ate the content space.
- The visit-summary PDF printed ⊠ boxes for dashes and bullets; it now
  stays within the glyphs the built-in font actually has.
- The visit-summary PDF ignored the subscription expiry date, so a lapsed
  subscriber could still generate one.
- Korean, Vietnamese, Chinese and Arabic no longer tell you to go to the
  web app to add your first child, add parent heights, or connect a
  wearable — those screens had kept the pre-app wording.
- The padlock emoji is replaced by a drawn lock glyph, so a paid feature
  never renders as a system emoji that differs per platform.

### Security
- Client write access revoked on the privileged `user_accounts` columns and
  on `live_ai_usage_monthly`, and privileged columns are clamped on insert.
  An account could otherwise grant itself premium or the system-admin role.

### Internal
- Subscription state is server-owned. `recompute_user_entitlement` is the
  only writer of a tier, fed by an Apple notification receiver and a
  purchase-verification function; Apple's own servers are re-queried rather
  than trusted from the device, and one Apple subscription maps to exactly
  one GrowSense account.
- Version numbers unified. The store binary reported `1.0.0` while the
  app reported `1.4.1`, because `codemagic.yaml` overrides only the build
  number. Both are now `1.5.0`. Note 1.1.0 was already released on
  2026-07-12, so the next free number above the in-app history is 1.5.0.
- The Flutter locale files are generated; several past fixes had been made
  to the generated output and would have been silently reverted by the next
  regeneration. The source file is `tool/flutter_extra_keys.json`, and a
  test now scans every locale for web-steering copy and key parity.
- Removed `bone-age-ai-index.ts` / `lab-ai-index.ts`, duplicate copies of
  two edge functions that sat at the repo root.

## [1.4.1] — 2026-07-24 · build 25

### Added
- **Medical citations, easy to find.** Inline "Sources" links next to the
  key results (height/weight percentile, genetic target & adult-height
  range, bone-age reading, nutrition targets) open a sheet with the exact
  published sources — WHO Child Growth Standards, NASEM/IOM Dietary
  Reference Intakes, AASM sleep consensus, Greulich–Pyle, NCD-RisC
  (eLife 2016). A central **Medical information & sources** screen lives
  under Account → Support & legal with the educational-use limitations.
  All sources are real and verified — nothing is generated. (App Store
  Guideline 1.4.1.)

### Changed
- **iOS ships as a free build.** On iPhone/iPad the subscription card,
  activation codes, the visit-summary PDF and the AI features (bone-age
  second opinion, lab interpretation) are not shown, and the free-tier
  caps are lifted so no "upgrade on the web" prompt can appear. Web and
  Android are unchanged. Paid features return via In-App Purchase in a
  later version. (App Store Guideline 3.1.1.)
- **Clearer Sign in with Apple failure message** with an internal
  diagnostic code, instead of a raw server string. (Guideline 2.1a.)

## [1.4.0] — 2026-07-16 · build 7

### Added
- **Lab intelligence.** The lab-values screen is rebuilt: a swipe row of
  per-analyte cards (latest value, reference range, status, trend with a
  dotted projection, and a plain-language line), each opening a detail
  card with a range bar, 12-month trend, "What it means", and
  **Evidence & References** (curated, PubMed-verified). Scope is the five
  labs parents recognise: IGF-1, vitamin D, ferritin, TSH, hemoglobin.
- **Lab SDS (z-score).** Optional SDS captured from the lab report and
  shown on a −3…+3 age/sex-adjusted bar (never computed by the app — a
  correct SDS is assay/age/sex-specific).
- **Premium — AI Growth-Systems interpretation.** A cross-lab reading
  (overview, patterns, questions for the doctor) from the `lab-ai-analysis`
  Edge Function, gated server-side on subscription tier. Citations are
  curated app-side, never AI-generated. Also folded into the visit PDF.
- **Premium — bone-age AI second opinion** is now gated client- and
  server-side; storing X-rays and the maturation timeline stay free.
- **Onboarding gate** — accounts with no children are routed to a
  create-first-child screen instead of an empty Today page.
- **Native Sign in with Apple** on iOS (web keeps the OAuth redirect).

### Changed
- Visit-summary PDF now carries a richer growth-labs summary (per-analyte
  value, range, status, SDS, plus the AI synthesis when present).

## [1.3.1] — 2026-07-13 · build 6

### Added
- **Remove a child profile** in the app (Account → Children profiles →
  tap a child → Remove profile). It archives rather than deletes — the
  profile is hidden but recoverable for the retention window (a year on
  the free plan, longer on Pro) and all logged data is kept during that
  time. You can't remove your last active profile. Brings the app to
  parity with the web app.

## [1.3.0] — 2026-07-13 · build 5

### Added
- **Iron and vitamin D as minor co-factors** — every food you log now
  quietly captures its iron and vitamin D (from USDA-verified food data),
  and Analytics gains a co-factor card: a 30-day average versus the
  age-based target, with an on-track / below read. These stay off the
  Today page and the readiness score on purpose — they're secondary, and
  parents don't need more daily dials.
- Vitamin D from food reads low by design (food rarely covers it), so the
  card surfaces your child's outdoor-activity days as the bigger source
  rather than raising a false alarm.

### Fixed
- The one food preset missing zinc and calcium (chicken nuggets) is now
  filled in; all presets carry zinc and calcium.

## [1.2.0] — 2026-07-12 · build 4

### Added
- **Deli & processed meats** — 6 new USDA-cited presets (ham, turkey
  breast, pork bologna at CP-pack piece size, dry salami, beef hot dog,
  Vienna sausage) in a new Deli category, each carrying real sodium data.
- **"Salty" flag** — foods ≥500 mg sodium/100 g show a gold ⚠ chip on
  their card, so the trade-off is visible at the moment of logging
  (bacon included). Gold, never the clinical red.
- **Custom foods in the app** — add your own food (label values for one
  serving), edit or remove it by tapping its ⭐ card; removal keeps all
  previously-logged days intact. Capped at 5 (free) / 50 (paid) per
  child. A "⭐ Mine" tab next to All makes the feature discoverable.
- **"Why we track protein" explainer** — one-time dismissible card on
  the Food tab linking the protein article, so new parents know not to
  log every potato and fruit.
- **The list learns you** — foods logged often in the last 60 days
  float to the top of the browse list, recomputed at most once a day so
  the order never jumps mid-session.
- **Activity search** — search box over the 33-activity browser
  (name, category, and note), with an empty state.
- PWA parity: Deli tab, Salty chip, explainer card, and the custom-food
  cap in the web app.

### Changed
- Three activity notes (box jumps, jump rope, sprint) rewritten to the
  honest GS-041 voice — bone loading and short-term markers, not height
  promises; both cited papers verified on PubMed.

### Fixed
- Rep-based activities (box jumps, vertical jumps, hopscotch) failed to
  save at 10/30/50 reps — duration_min was an integer column rejecting
  half-minute values; it now accepts fractional minutes.

## [1.1.0] — 2026-07-12 · build 3

### Added
- **Logging calendar (trust calendar v2)** — tap the date on Today to open
  a month view of all three levers at once: each day shows nutrition,
  activity and sleep as a trust-coloured dot plus a bar filled to % of that
  day's target. Past days with anything missing get a soft gold outline
  (red stays reserved for clinical flags), an attention counter with
  "Fill next" walks the backlog oldest-first, and an enlarged sample cell
  explains the rows so parents never guess. Sunday-first weeks per Thai
  convention. Analytics rings open the same unified view.
- **Unified day sheet** — all three levers together with provenance and
  trust pills; one "✓ Looks right" confirms every estimated lever that
  day; "Log / Correct this day" lands back on Today at that date.
- **Trust calendar fully localized** — the whole flutter.trust.* string
  set plus weekday and month names in all six languages (it previously ran
  on English fallbacks).

### Fixed
- GitHub Pages deploys had been failing silently since 2026-07-11 — Jekyll
  tried to parse Astro components' JS frontmatter as YAML and aborted the
  whole site build. Added `.nojekyll` so Pages serves the repo verbatim.

## [1.0.1] — 2026-07-11 · build 2

### Added
- Account now shows your **sign-in method** (Google / Apple / email) under
  your address — so it's clear which one you used to register.
- Admin dashboard: a **Bug reports** triage view (list, filter, and mark
  triaged / fixed / won't-fix) reading the `bug_reports` table.

### Fixed
- Escaped user-submitted text in the admin bug view (stored-XSS hardening).

## [1.0.0] — 2026-07-11 · build 1

First production release on **growsense.life**.

### Added
- **Nutrition Recall Engine** — one-tap "vs yesterday" recall, typical-day
  fill with a less/more adjustment, and activity routine recognition
  ("tennis most Fridays") plus typical-night sleep fill. Estimated days
  are always shown in gold, never mixed with measured data.
- **Trust calendar** — a month view of every day's data provenance
  (measured / recalled / estimated / missing), reachable from each
  Analytics ring, with confirm-or-correct on any estimated day.
- **Analytics insights** — week-over-week ring deltas, trend direction on
  the bar cards, a cross-lever smart-insight card, and a growth summary
  strip that opens the WHO percentile chart with a habit-scenario band.
- **Evidence-weighted readiness score** — nutrition rebalanced to
  protein 40 / calcium 30 / zinc 15 / water 15 with a bounded balance
  penalty; all targets (protein, calcium, zinc, water, sleep) personalized
  to the child's age, sex, and weight.
- **Pediatric visit summary (PDF)** — a branded, clinician-ready dossier
  (Premium), beside CSV export in Account.
- **Google / Apple sign-in** and password reset.

### Changed
- The website login now opens the Flutter app; landing, privacy, terms,
  and support pages live on growsense.life.

### Fixed
- Age-banded nutrition and sleep targets (were fixed adult figures).
