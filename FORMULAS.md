# GrowSense — Formulas & Calculations Reference

This documents every calculation currently implemented in `app.js` and in the
Supabase schema (`growsense_schema.sql`). It exists so the math is easy to
review and audit without reading through application code, and so future
changes can be checked against what's written here.

**Status of this document:** describes what is *actually deployed today*,
not an aspirational spec. Where something is a known placeholder rather than
a validated clinical calculation, that's called out explicitly.

---

## 1. BMI (Body Mass Index)

**Where:** Postgres generated column, `measurements.calculated_bmi`
(computed by the database itself, not by client code)

```
calculated_bmi = ROUND( mass_weight_kg / (stature_height_cm / 100)², 1 )
```

Standard BMI formula. Generated columns mean this can never drift out of
sync with the underlying height/weight values — there's exactly one place
this is computed.

---

## 2. Height velocity (cm/year)

**Where:** Postgres view `child_growth_analytics_ledger`, consumed by
`updateStats()` in `app.js`

The view uses a window function to find each measurement's *delta* from
the previous one for the same child:

```sql
height_delta_cm = ROUND(stature_height_cm - LAG(stature_height_cm) OVER (...), 2)
days_between_measurements = recorded_date - LAG(recorded_date) OVER (...)
```

The app then annualizes the most recent pair:

```js
velocity_cm_per_year = (height_delta_cm / days_between_measurements) * 365.25
```

**Why this matters clinically:** a single height reading is a snapshot;
velocity (change over time) is what's actually used to judge whether growth
is tracking normally — multiple measurements across visits reveal trends
that a single data point cannot. This implementation only uses the *most
recent pair* of measurements — it does not yet average across more than two
points, so a single noisy measurement can swing the velocity figure
noticeably. Worth revisiting once there's enough real measurement history
per child to smooth this.

**Trend labeling thresholds** (`app.js`, `updateStats()`):
```
>= 5.3 cm/yr  → "on pace"
4.2–5.3 cm/yr → "stable"
< 4.2 cm/yr   → "below range"
```
These thresholds are rough placeholders, not derived from a specific
reference population table yet, unlike the percentile calculation in §5
which now does use real WHO data — these velocity thresholds (5.3 / 4.2
cm/yr) are still rough cutoffs, not derived from a specific source.

---

## 3. Daily Readiness reading (0–100)

**Where:** `updateHUD()` (today's live reading) and `updateStats()`
(7-day average), both in `app.js`

This is a same-day composite of three sub-scores, each itself a weighted
blend of capped ratios (every input ratio is clamped to a max of 1.0, so
exceeding a target doesn't push the score past 100):

### Nutrition (35% of total)
```
protein_ratio = min(protein_g / 44, 1)
calcium_ratio = min(calcium_mg / 1300, 1)
water_ratio   = min(water_glasses / 8, 1)

nutrition_score = protein_ratio×0.4 + calcium_ratio×0.4 + water_ratio×0.2
```
44g protein / 1300mg calcium are general pediatric daily targets, not
personalized to the individual child's age/weight yet.

### Activity (35% of total)
```
hanging_ratio = min(hanging_sec / 30, 1)
jumps_ratio   = min(jumps_reps / 40, 1)
yoga_ratio    = min(yoga_min / 20, 1)

activity_score = hanging_ratio×0.4 + jumps_ratio×0.4 + yoga_ratio×0.2
```

### Sleep (30% of total)
```
duration_ratio = min(total_sleep_hours / 9.5, 1)

on_time_ratio  = 1                                   if bedtime <= 21:30
               = max(0, 1 - (minutes_late / 120))     if bedtime > 21:30

wake_ratio     = max(0, 1 - night_wakes × 0.25)

sleep_score = duration_ratio×0.35 + on_time_ratio×0.4 + wake_ratio×0.25
```

### Combined
```
readiness = nutrition_score×35 + activity_score×35 + sleep_score×30
```

**Why bedtime is weighted so heavily in the sleep score:** growth hormone
release in children occurs in pulses tied to sleep, with the largest pulse
typically occurring in the first slow-wave-sleep episode, 60–90 minutes
after sleep onset. Going to bed on time is believed to protect that early
window, which is why `on_time_ratio` carries the largest weight (0.4) in
the sleep sub-score rather than `duration_ratio`. **Caveat added after
review (see §7):** the *strength* of the link between disrupting that
specific window and total GH output is less settled than earlier framing
in this file suggested — at least one controlled polysomnography study in
pubertal children found that acutely disrupting slow-wave sleep did not
reduce overall GH pulse amplitude or frequency, suggesting the relationship
between SWS and GH secretion may be associative rather than strictly
causal. The bedtime-weighting choice is kept as a reasonable, conservative
default (early consistent bedtime is uncontroversial pediatric sleep
hygiene advice on its own merits) but should not be read as a tightly
validated dose-response model.

**Known limitation, stated plainly in the app itself:** this is a same-day
input score, not a diagnostic measure. A single day carries very little
signal — clinical growth assessment is about trends over weeks/months, not
daily snapshots. The app's own copy says this explicitly on the Today
screen and in the AI coach's system prompt, to discourage over-reading any
one day's number.

---

## 4. Sleep duration

**Where:** `calcSleep()`, `app.js`

```
total_sleep_hours = (wake_time - bed_time) / 60
```
with simple overnight wraparound handling (`if bed_minutes > wake_minutes,
add 1440 to wake_minutes before subtracting`).

This is wall-clock time in bed, not measured sleep (no wearable integration
yet) — the UI labels this as "estimated" rather than "measured" for that
reason.

---

## 5. Growth percentile / Z-score — real WHO 2007 reference (implemented 2026-06-23)

**Where:** `who-reference-data.js`, `growth-percentile.js`, consumed by
`updateStats()` and `drawGrowthChart()` in `app.js`

This replaces the earlier hardcoded `'32% / 15th percentile (placeholder)'`
with an actual calculation against real population reference data.

**Data source:** the WHO 2007 Growth Reference for school-aged children
and adolescents, height-for-age, 5–19 years, transcribed directly from the
official WHO PDFs at `cdn.who.int` (boys and girls, percentile tables).
This is a different, separate reference from the WHO Child Growth
Standards used for children under 5 — GrowSense currently only implements
the 5–19y table; younger children will show as "out of range" until/unless
the under-5 table is added the same way.

**Method:**
1. WHO publishes five percentile bands (3rd, 15th, 50th, 85th, 97th) at
   each age. `interpolateBands()` linearly interpolates these five values
   to the child's exact age in months, between the two nearest WHO table
   rows (the data file ships at ~6-month resolution rather than WHO's
   full monthly table, to keep file size reasonable — see note in
   `who-reference-data.js` on why this introduces negligible error for
   this purpose).
2. The child's actual height is located between two adjacent bands (or
   extrapolated beyond the 3rd/97th edges using the same local slope,
   rather than just clipping to "below 3rd" with no magnitude).
3. That position is converted to a Z-score using the known standard-normal
   Z-value of each band edge (z = -1.881, -1.036, 0, 1.036, 1.881 for the
   3rd/15th/50th/85th/97th respectively — these are exact values for a
   standard normal distribution, verified against `scipy.stats.norm.ppf`).
4. The Z-score is converted to a percentile via the normal CDF, using the
   Abramowitz & Stegun erf() approximation (the same approximation the
   original PDF correctly used; this part of the prior framing was
   accurate, see §7).

This is mathematically equivalent to the full LMS method for placing a
point on a chart, since WHO's published percentile bands already *are*
the L/M/S curves evaluated at five fixed points — using them directly
avoids re-deriving or re-transcribing L/M/S parameters from scratch.

**Known limitation, stated in code comments and worth restating here:**
linear interpolation between band edges is a reasonable local
approximation but is not exact in the deep tails (true 1st or 99.5th
percentile, etc.) — the real WHO distribution is not perfectly normal
between these five points. Adequate for the screening-level question
"roughly where does this child sit," not for fine clinical distinctions
at the extremes without the full Box-Cox L/M/S parameters.

**Visual overlay:** `drawGrowthChart()` shades the 3rd–97th band (light)
and 15th–85th band (slightly darker) using the same real, sampled WHO
data — not the five hand-picked illustrative numbers the chart used
before. The child's actual measurements are plotted on the identical
age/height scale as the bands, so visual position directly reflects
standing against the real reference curve. The visible age window is
centered on the child's current age (±3 years, clamped to the table's
5–19y coverage) rather than a fixed 6–11y range.

---

## 6. Bone age (schema only, not yet used by any UI)

**Where:** `bone_age_assessments` table

No formula lives in the app for this — bone age (skeletal maturity, read
from a hand/wrist X-ray) is entered directly by a radiologist/clinician via
`chronological_age_months` and `assessed_bone_age_months`, using an
established method (`assessment_method` defaults to `greulich_pyle`, i.e.
Greulich-Pyle atlas comparison; Tanner-Whitehouse is the schema's other
supported option). The app does not compute or estimate bone age itself.

---

## 7. External "v2.0" specification — reviewed, mostly rejected (2026-06-23)

An external document (*"BioGrowth Intelligence OS v2.0 — Revised Technical
Reference"*) and a matching `Code.js` (Google Apps Script) were submitted
for consideration as an upgrade path. They were checked against primary
sources before any of it was adopted. Recording the outcome here so the
decision isn't silently lost or re-litigated from scratch later.

### What checked out and is worth keeping in mind for future work

- **The LMS method itself** (Cole & Green, 1992, *Statistics in Medicine*
  11(10):1305-19, PMID 1518992) is real and is in fact the correct,
  standard method underlying WHO/CDC growth charts — confirmed against
  multiple independent sources. If/when §5's percentile placeholder gets
  built out for real, this is the right method to implement.
- **Real long-acting growth hormone trial data exists** and is more modest
  than the external document's numbers: a phase-2 somapacitan trial in
  diagnosed GH-deficient children showed annualized height velocity of
  8.0–12.9 cm/year across dose groups vs. 11.4 cm/year for daily GH; a
  phase-3 somatrogon trial showed 10.1 cm/yr vs. 9.8 cm/yr for daily GH
  (a 0.33 cm difference) — i.e., these drugs are roughly *equivalent* to
  daily injections for diagnosed deficiency, not a dramatic "catch-up"
  intervention, and were tested only in children with a clinical diagnosis
  of GH deficiency, not general short stature.

### What was rejected, and why

- **Several specific citations could not be verified and appear to be
  fabricated** — e.g. a claimed "St-Onge et al. 2021, Sleep Medicine
  Reviews" paper and a claimed "Ren et al. 2021, Nature Communications"
  paper on hepatic GHR resistance do not turn up under those
  authors/titles/journals in any search. The document's citation list
  has the visual format of a real bibliography (numbered, journal names,
  PMIDs) but several entries do not survive a direct check. Per-citation
  verification was not exhaustive — given multiple early fabrications, the
  whole list is being treated as unreliable rather than item-by-item
  cleared.
- **The "Ranke catch-up model" with coefficients (γ₀, γ₁, γ₂) projecting
  specific outcomes like "+8.0 to +11.5 cm/year" and a "174.5 cm" maximized
  scenario does not match real trial data** (see above) and was not found
  in the literature under that description. Ranke et al. (2003) is a real,
  citable paper, but it's a clinical prediction tool for diagnosed-GHD
  patients on standard daily GH — not a generic simulator for otherwise
  healthy children, and not the source of the specific multiplier
  constants the external document presented.
- **The Apps Script (`Code.js`) bypassed Row Level Security** by design
  (a `getSupabaseServerAuthKey()` function that prefers a service-role key
  over the anon key, intended to be called from a public-facing
  `doGet()` web app) — this would have undone the RLS work in
  `growsense_schema.sql` if connected to the same database. It also
  contained a hardcoded Supabase anon key for a *different* project than
  this one, set diagnostic X-ray uploads to be publicly link-viewable with
  no auth, and hardcoded the same unverified "+8.5cm" LAGH projection
  directly into a function return value.

### Security note — resolved (2026-06-23)

`Code.js` contained an anon-role API key for Supabase project ref
`hrldehehdxdaggqddkno`. This was confirmed to be a **separate project**
from GrowSense (which uses `ogpkmcqaulohexanucng`) — an earlier,
Gemini-assisted prototype, unrelated to this codebase. The project
contained test/empty data only, no real user or health data. The key has
been rotated by the project owner.

**Still true regardless of the outcome here:** `Code.js` should not be
committed to this repo, since it was built against a different
architecture (bypasses RLS via an optional service-role key, sets X-ray
uploads to public-link-viewable, and embeds the unverified LAGH
projection figures rejected above). It's left out of this repository
entirely — kept only as a record in conversation history, not as a file
in version control.

**Net decision:** none of the external document's drug-projection math or
its citation list were adopted. The verified real trial figures above are
worth surfacing to a pediatrician directly if/when that conversation is
relevant, clearly labeled as population averages from diagnosed-GHD
trials — not as a personalized prediction this app can make.

---

## Change log

When a formula above changes, update this file in the same commit as the
code change — that's the whole point of keeping this here rather than only
in code comments.
