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

## [Unreleased]

_Work in progress lands here before it's tagged._

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
