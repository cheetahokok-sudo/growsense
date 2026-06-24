# GrowSense — Formulas & Calculations Reference

This documents every calculation currently implemented in `app.js` and in the
Supabase schema (`growsense_schema.sql`). It exists so the math is easy to
review and audit without reading through application code, and so future
changes can be checked against what's written here.

**Status of this document:** describes what is *actually deployed today*,
not an aspirational spec. Where something is a known placeholder rather than
a validated clinical calculation, that's called out explicitly.

---

## 1. BMI (Body Mass Index) and BMI-for-age percentile (implemented 2026-06-23)

**Raw BMI — where:** Postgres generated column, `measurements.calculated_bmi`
(computed by the database itself, not by client code)

```
calculated_bmi = ROUND( mass_weight_kg / (stature_height_cm / 100)², 1 )
```

Standard BMI formula. Generated columns mean this can never drift out of
sync with the underlying height/weight values — there's exactly one place
this is computed.

**Why a raw BMI number alone is misleading for a child:** adult BMI has
fixed cutoffs (18.5/25/30) that don't apply to growing children — a BMI
of 17 means something different for a 5-year-old than a 15-year-old,
because body composition changes substantially through childhood. The
correct approach is BMI-*for-age* percentile against a reference
population, the same way height-for-age works (see §5).

**BMI-for-age — where:** `who-bmi-reference-data.js`, `bmi-percentile.js`,
consumed by `updateStats()` (the Analytics BMI card) and
`refreshActiveChildHistory()` (the growth history table's "Channel"
column).

**Data source:** the WHO 2007 Growth Reference, BMI-for-age, 5–19 years —
the **full monthly L/M/S table** (not the coarser band-interpolation
approach used for height-for-age in §5), transcribed directly from the
official WHO PDFs at `cdn.who.int` (boys and girls, 168 rows each,
months 61–228).

**Why full monthly LMS instead of the height-for-age band-interpolation
shortcut:** BMI-for-age has a genuinely skewed distribution — the L
(Box-Cox power) parameter ranges from about -1.8 to -0.7 across this age
span, rather than staying near 1 the way height-for-age's does. That
skew is large enough that the full Box-Cox transform matters, so this
implementation uses real L/M/S triplets and the actual formula:

```
Z = ((BMI/M)^L − 1) / (L·S)        when L ≠ 0
Z = ln(BMI/M) / S                   when L = 0 (limiting case)
```

rather than interpolating between five fixed percentile points.

**Verification performed before trusting this data** (168 rows × 2 sexes,
transcribed by hand from PDF text — a meaningfully larger and more
error-prone transcription task than height-for-age's percentile bands,
so it got a correspondingly higher verification bar):
1. **Structural validation** — every row checked programmatically for:
   sequential months 61–228 with no gaps or duplicates; percentiles
   monotonically increasing within every row (3rd < 15th < 50th < ... is
   a structural property any genuine LMS table must have); no
   implausible jumps in the median curve month-to-month.
2. **External cross-check against an independent source** — recomputing
   +1SD/+2SD BMI from the transcribed L/M/S at age 19 reproduced
   25.45/29.72 kg/m² (boys) and 24.97/29.67 kg/m² (girls), matching a
   *separately found* PMC paper on the WHO reference's construction,
   which stated 25.4/29.7 and 25.0/29.7 — independent confirmation, not
   just internal consistency.
3. **Internal formula consistency** — recomputing all 11 published
   percentile columns from the transcribed L/M/S via the actual Box-Cox
   formula reproduced WHO's own listed values to within 0.05 kg/m² at
   every checked point, both sexes.

This is the same verify-before-trust standard adopted after the
fabricated-citation incident in §7 — checked against independent
sources, not just internally self-consistent.

**Clinical classification thresholds** — WHO's own stated cutoffs for
this exact reference (not invented categories):

```
Z > +2        → obesity
+1 < Z ≤ +2   → overweight
-2 ≤ Z ≤ +1   → healthy range
-3 ≤ Z < -2   → thinness
Z < -3        → severe thinness
```

**Known limitation:** BMI-for-age is a screening signal, not a
diagnosis — it can't distinguish muscle mass from fat mass, which
matters for an athletic child. The UI states this directly next to the
BMI card rather than only in this file.

**Not yet implemented:** weight-for-age (WHO publishes this 5–10 years
only) and the under-5 BMI/weight standards, which use a different
underlying sample than the 5–19y reference — same limitation already
noted for height-for-age in §5.

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

## 5b. Growth standards 0–5 years + SGA catch-up growth tracking (implemented 2026-06-24)

**Where:** `who-reference-data-0-5.js`, `growth-percentile-0-5.js`,
`migration_sga_tracking.sql`, consumed by `updateStats()`'s SGA card and
(future work) a dedicated 0-5y chart.

**Data source:** the WHO Child Growth Standards (2006) — a different
dataset from the WHO 2007 Reference used for 5-19y (§5), with a
different underlying sample and methodology, reflecting that postnatal
growth in early childhood is biologically distinct from later
childhood/adolescence. Two age bands per indicator, each its own table,
transcribed directly from official WHO PDFs:
- Length-for-age, 0–2 years (recumbent) — boys/girls
- Height-for-age, 2–5 years (standing) — boys/girls
- BMI-for-age, 0–2 years and 2–5 years — boys/girls

**The measurement-method switch — read this before changing the related
code:** WHO's own documentation states the conversion constant directly:
standing height = recumbent length − 0.7cm. This isn't just a data
artifact — it's why this dataset is split into two tables per indicator
rather than one continuous one. `growth-percentile-0-5.js` requires the
caller to specify which measurement type was actually taken
(`'recumbent'` or `'standing'`) and converts automatically if it doesn't
match what that age band's table expects; if omitted, no conversion is
applied (the value is assumed to already match the conventional method
for that age).

**Verification performed** (8 tables this time — boys/girls × 2
indicators × 2 age bands — same standard as the 5-19y BMI dataset):
1. **Structural** — all 8 tables checked for sequential months, no
   gaps/duplicates, monotonically increasing percentiles within every
   row. (Large month-to-month jumps in the median height curve during
   months 0-4 were flagged by the automated check and confirmed as real
   biology, not transcription errors — early infancy growth genuinely is
   that fast, several cm/month.)
2. **Internal LMS consistency** — recomputing all 11 percentile columns
   from transcribed L/M/S, across all 8 tables and every row, reproduced
   WHO's own published percentile values to within 0.05 units at every
   checked point.
3. **Independent fact check** — median length at birth recovered as
   49.88cm (boys) / 49.15cm (girls), matching the widely-cited WHO
   reference figures of 49.9cm / 49.1cm.
4. **Cross-table continuity** — the two independently-transcribed height
   tables (0-2y vs 2-5y) showed *exactly* a 0.700cm gap at their
   24-month overlap point, matching WHO's separately-documented
   recumbent/standing conversion constant precisely. This is meaningful
   evidence both tables are correct and mutually consistent, since this
   number wasn't assumed going in — it fell out of two independently
   transcribed sources agreeing with a third, separate piece of WHO
   documentation.

### SGA (small-for-gestational-age) catch-up growth tracking

**Why this exists:** per the International Consensus Guideline on SGA
(a pediatric endocrine consensus document), SGA is defined as birth
weight and/or length below −2 SDS for gestational age. Catch-up growth
is specifically defined as height velocity **>0 SDS** — i.e. growing
*faster than the population median* for age and sex, not just growing
in absolute cm. About 10% of SGA children fail to show catch-up growth
and may remain short-statured into adulthood. The same guideline
recommends growth-hormone-therapy referral evaluation by ages 2-4 if
catch-up hasn't occurred — but real-world referral commonly happens much
later (ages 7-9), which is part of the clinical case for consistent
early tracking rather than infrequent checkups.

**What this app does:** `is_sga` is a parent/clinician-confirmed flag on
the child profile (see `migration_sga_tracking.sql`), **not** something
this app computes automatically. This is a deliberate choice, not a
missing feature: determining SGA status from birth weight/length
requires a *gestational-age-specific* birth-weight reference chart
(e.g. Fenton 2013 or INTERGROWTH-21st) — a completely different dataset
from the WHO *postnatal* growth standards used everywhere else in this
app. These two reference standards are not just "different versions of
the same thing" — published comparisons find they meaningfully disagree
on SGA classification rates in the same cohorts (one comparison found
INTERGROWTH-21st and Fenton classified 11.5% vs 9.5% of the same infants
as SGA respectively; another found the gap as wide as 19% vs 14.7%), and
which standard is most appropriate varies by population with no single
settled answer in the literature. Auto-computing this inside GrowSense
would mean silently picking a side in a genuine, ongoing clinical
disagreement — the same category of mistake flagged in §7's review of
the external "v2.0" document. A clinician-confirmed flag, entered after
an actual gestational-age-appropriate assessment, avoids that.

**Catch-up velocity calculation:** uses the *change in height Z-score*
between two measurements, divided by the time elapsed in years — not raw
cm/year. This matters: a child growing at exactly the population-median
rate has a *flat* Z-score over time (same percentile, just bigger) — that's
not catch-up, it's tracking. Catch-up means gaining SDS, i.e. moving
up through the percentile bands over time. Classification:
- `> +0.1 SDS/year` → "catching up"
- `< -0.1 SDS/year` → "falling further behind"
- in between → "tracking, not catching up" (flat, deliberately not
  alarming language for small/noise-level changes near zero)

**Monitoring cadence reminder**, shown directly in the UI, per the same
consensus guideline: every 3 months in year 1, every 6 months in year 2,
yearly after.

**Scope boundary, stated plainly:** this card only appears for children
flagged `is_sga` AND currently under age 5 — both the clinical catch-up-
growth literature and this app's available reference data are scoped to
that age range. A flagged SGA child who ages past 5 stops seeing this
card; their growth is then tracked the same way as any other child via
§5's 5-19y reference (catch-up growth, in the specific clinical sense
used here, is a 0-5y phenomenon — by school age, the relevant question
shifts to general growth-faltering screening, which the standard
percentile/velocity tracking already covers).

---

## 5c. Age-aware chart rendering + BMI chart (implemented 2026-06-24)

**Where:** `drawGrowthChart()` (height) and `drawBMIChart()` (new), both
in `app.js`, sharing extracted helpers (`setupChartCanvas`,
`drawChartGridAndAxis`, `fillChartBand`, `drawChartBandLine`,
`drawEmptyChartMessage`).

**What changed:** both charts now branch on the active child's current
age. Under 5, they use the WHO Child Growth Standards (§5b) via a new
`deriveBandsFromLMS()` helper in `growth-percentile-0-5.js`, which
computes the same 5 percentile bands (3rd/15th/50th/85th/97th) the
chart's existing rendering code already knows how to draw — derived
directly from real L/M/S via the inverse Box-Cox transform, not a
separate approximation. 5 and over, both charts use the existing 5-19y
references (§1, §5) exactly as before.

**Curve shape — verified, not assumed:** the 0-5y chart samples at 48
points across the window (vs 24 for 5-19y) specifically because early
growth changes shape fast enough that fewer samples would visibly facet
what should be a smooth curve. The deceleration itself is real WHO data,
not a rendering trick — checked directly: median height gain per ~6-week
sample interval is ~3.3cm near birth vs ~0.7cm near age 5, a 4.85×
difference, confirming the curve the chart draws reflects genuine early-
childhood growth biology rather than a stretched straight line.

**Measurement-method consistency:** the 0-5y height chart applies the
exact same recumbent/standing 0.7cm conversion (per §5b) to a child's
actual logged measurements before plotting them, using the same
`resolveHeightTableAndValue()` function the numeric percentile
calculation uses — so the chart and the printed percentile reading can
never disagree with each other about which measurement basis was used.

**The BMI/obesity chart** is new (previously only a single-point card on
Analytics, with no trend view at all). It adds dashed reference lines at
WHO's own +1SD (overweight) and +2SD (obesity) cutoffs, computed at
every sampled age the same way the single-point classification in §1
already does — so a parent can see at a glance whether a trend is
approaching either threshold, not just whether the most recent point is
past it.

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
