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

## 5e. Full-timeline (0–19y) chart view (implemented 2026-06-25)

**Where:** `chartZoomToggle` UI, `setChartZoom()`, and the `isFullTimeline`
branch inside `drawGrowthChart()` in `app.js`.

**What it is:** a second toggle, independent of the WHO/Thai one (§5d),
switching between the existing "zoomed to current age" view (±3y window,
or the full 0-5y window for younger children — unchanged default
behavior) and a new "full timeline" view that always shows the entire
birth-to-19-years span in one chart. Useful for a parent or doctor
reviewing the overall growth trajectory at a glance — from birth through
puberty — rather than the day-to-day working view centered on the
child's current age.

**How the stitching works:** there is no single dataset spanning 0-19
years — WHO publishes the 0-5y Child Growth Standards and the 5-19y 2007
Reference as two separate studies (see §5b), and the Thai approximate
data only covers 2-19y (§5d). The full-timeline view's band-sampling
function switches data source mid-chart at the real boundary: WHO 0-5y
→ WHO 5-19y (when the WHO reference is selected), or WHO 0-2y → Thai
2-19y approximate (when Thai is selected, since Thai has no data below
age 2). This produces one continuous-looking curve, but a **small, real,
visible jump at the seam is expected and intentional** — checked
directly: the WHO-only seam at age 5 is about 0.39cm, consistent with
these being genuinely separate studies rather than one continuous
dataset artificially smoothed together. The chart's note text says this
explicitly when full-timeline mode is active, rather than hiding it.

**Measurement plotting across the seam:** a single full-timeline chart
can show measurements taken before AND after age 5 together. The
recumbent/standing 0.7cm conversion (§5b) is applied **per measurement,
based on that measurement's own age** — not as a single chart-wide
setting — so a measurement taken at 18 months and another taken at age 9
each get the correct treatment on the same chart.

**Resolution:** 76 samples across the full 0-19y span (vs 48 for the
0-5y-only view, 24 for the zoomed 5-19y view) — enough to keep the early,
fast-bending part of the curve visually smooth even though it's now a
small fraction of a much wider chart.

---

## 5d. WHO/Thai reference toggle on the height chart (implemented 2026-06-24)

**Where:** `thai-reference-data-approx.js`, the `referenceToggle` UI on
the Analytics height chart, `setReferenceStandard()` in `app.js`.

**This is the one dataset in GrowSense that is NOT independently
verified, and that's stated deliberately and repeatedly — in the data
file's own header comment, in the chart's note text when Thai is
selected, and here. Read this before extending it.**

**What it is:** approximate 3rd/50th/97th percentile height-for-age
values for ages 2–19, for comparing against the WHO reference — useful
specifically for international-school contexts where a child's peer
group spans both an international/expat population (WHO reference fits
better) and the local Thai population (where a national reference would
fit better, if one were available in verified form).

**Source and why it's only approximate:** read by eye from a printed
chart ("Boys/Girls aged 2-19 years: Height and Weight," Thai Society for
Pediatric Endocrinology, 2022), which itself cites "National Growth
References for children aged 5-19 years, 2020, Bureau of Nutrition,
Department of Health, Ministry of Public Health" as its underlying data.
Multiple targeted searches for an openly-published, structured Thai
national LMS/percentile table came up empty — what exists in the
literature is citations to this chart's existence, not a downloadable
dataset. A real candidate (SEANUTS, a peer-reviewed multi-country study)
was checked and rejected for this purpose: its data is pooled across 4
countries (not Thailand-specific — the paper's own stated conclusion was
to use the pooled values, not country-specific ones), only covers ages
0.5–12y (not 2–19y), and its actual L/M/S values are in a supplementary
file that wasn't accessible to transcribe. Using it under a "Thai" label
would have been inaccurate in a way this project has specifically tried
to avoid (see §7's review of the external "v2.0" document, where exactly
this kind of mislabeling was the core problem).

**What "approximate" means concretely:** values were estimated against
the chart's printed gridlines, not transcribed from a numeric source.
Only 3 of the chart's 7 percentile lines were extracted (3rd/50th/97th,
not P10/P25/P75/P90) to limit how much could be misread. The only
checks performed were basic sanity checks (P3 < P50 < P97 at every age;
no decrease in height as age increases) — there was no independent
secondary source to cross-check against, unlike every other dataset in
this app. One specific finding worth flagging for whoever revisits this:
the eyeballed Thai median came out very close to the verified WHO median
at several test ages (110 vs 110.0 at age 5, 137 vs 137.8 at age 10,
163 vs 163.0 at age 14) — this could mean Thai and WHO medians genuinely
are close while other percentiles diverge more, or it could mean the
eyeballing wasn't precise enough to detect a real difference. This isn't
resolved and shouldn't be treated as a finding either way.

**2026-06-24 update — new source files, one new indicator added, no
change to existing height-for-age numbers:** newer, cleaner vector-PDF
versions of the Thai charts were supplied, plus two chart types not
previously available: 0-2y length/weight (confirmed to cite the same
WHO 2006 standard already verified and built into
`who-reference-data-0-5.js` — nothing new there, no extraction needed)
and weight-for-height (a genuinely new indicator, now added as
`THAI_WFH_BOYS_APPROX`/`THAI_WFH_GIRLS_APPROX`, same eye-read method and
caveats as the height-for-age data). The existing height-for-age numbers
were re-checked against the clearer chart renders and held up — no
revision needed.

**A real attempt was made to extract exact values from the PDF's
embedded vector data** (these PDFs contain genuine curve coordinate
objects, not just flat images) rather than reading by eye. It was
abandoned after producing internally contradictory results — depending
on which curve-to-percentile-label matching heuristic was tried, the
same data alternately implied physically impossible results (height
decreasing with age) or required matches that couldn't be verified with
confidence. Per this project's standing rule of not shipping numbers
that fail their own consistency checks, that path was dropped in favor
of continuing with the eye-read method, which has a known and stated
error profile rather than an unresolved, possibly-larger one. Full
technical note is in `thai-reference-data-approx.js`'s header for
whoever wants to retry the extraction with a more rigorous approach.

**UI behavior:** the toggle only appears for children aged 2+ (the
approximate data's covered range) and never for the 0-5y chart (no Thai
data exists for that range at all). Selecting Thai shows only the outer
3rd-97th band (no inner 15th-85th band, since that data wasn't
extracted) and replaces the chart note with explicit "approximate, read
by eye" language — it should never visually look as confident as the
WHO bands. (Weight-for-height is added to the data file as of this
update but not yet wired into any chart UI — that's a separate piece of
work from today's data session.)

**Independent corroboration check, 2026-06-24:** a third-party Python
script claiming to encode the same TSPE 2022/Thai 2020 reference (via
PCHIP interpolation from height anchor points) was actually run and
checked against this file's data, not just read. Its Z-score constants
are correct, its output passes the same structural checks used
throughout this project, and — most usefully — its age-2 boundary value
matches this app's own independently-verified WHO 2-5y data to within
0.1-0.2cm. Direct comparison against this file's eye-read anchors at 8
ages gave an average absolute difference of 1.09cm. This is treated as
corroborating evidence the values here are in a reasonable range — not
as independent verification, since the script's own anchors have no
stated extraction method or citation trail and could be another
estimate of the same uncertain quantity rather than a true source. No
values in this file were changed as a result. Full detail in
`thai-reference-data-approx.js`'s header.

**If real Thai national LMS data becomes available later:** replace
this file's contents with the real numbers, run it through the same
verification process as every other dataset in this app (structural
checks, independent cross-check if any secondary source exists, internal
LMS-formula consistency if L/M/S parameters are available), and update
both the file header and the chart's note text to drop the "approximate"
language once that's actually true.

---

## 5f. Generic lab results + puberty/Tanner tracking (implemented 2026-06-25)

**Where:** `migration_lab_results_and_puberty.sql`, the "Other lab
results" and "Puberty milestones" cards on the Medical screen, and
`addLabResult()`/`addPubertyEvent()` (+ their load/render/delete
counterparts) in `app.js`.

**Context:** an external "Database Architecture v1.1" review document
proposed a broader schema redesign. After reconciling it against what's
actually live, most of its tables turned out to already exist under
different names (its `sleep_daily_summary` is this project's
`daily_sleep`; its `children` birth-data fields were already added for
SGA tracking — see §5b) or were left as future/aspirational sections
with no concrete design (its "AI Feature Store" heading had no table
under it). Two ideas were judged genuinely new and worth building:

**`lab_results`** — a generic analyte table (`analyte_name`,
`result_value`, `unit`, `reference_low/high`), so adding a new lab
value (TSH, LH, FSH, testosterone, estradiol, IGFBP3, etc.) never again
needs a schema change. **Deliberately does not touch or replace** the 3
existing hardcoded lab columns on `medical_logs` (`igf1_ng_ml`,
`vitamin_d_nmol_l`, `ferritin_ng_ml`) — that UI is live and working, and
per this project's standing rule of not breaking what works, it was left
exactly as-is. `lab_results` is purely additive capacity for everything
else. Unlike the daily_nutrition/sleep/activity/medical_logs tables, this
is **event-based, not date-keyed** — no `UNIQUE(child_id, date)`
constraint, since a single blood draw can produce several results on
the same day, and that's a real, valid case, not a duplicate to prevent.

**`puberty_events`** — Tanner staging (real 1-5 clinical scale, enforced
via a CHECK constraint, not the generic free-text "severity" the source
document left underspecified) plus binary milestone occurrences
(menarche, voice change, etc. — date-only, no stage). This was a
complete gap before: GrowSense had no way to record pubertal timing at
all, despite it being one of the strongest real predictors of remaining
growth window and adult height.

**What was deliberately NOT adopted from the source document, and why:**
- `ethnicity` as a `children` column — sensitive demographic data that
  needs a clear stated purpose (e.g. an intent to apply ethnicity-
  specific growth references) before collection, not added reflexively
  because it's a common epidemiological variable.
- `media_files` for `puberty_photo`/`body_photo` — storing photos of a
  minor's body is a meaningfully higher sensitivity category than
  anything else in this app. Not built without a separate, explicit
  conversation about encryption at rest, RLS/access design, and
  retention policy — this isn't a "just add the table" item.
- The "AI Feature Store" / prediction-model sections — vision statements
  with no actual schema underneath them, not something to implement
  from this document directly.

**Performance, no behavior change:** while building this, an explicit
`DESC`-ordered index was added to `daily_nutrition`, `daily_sleep`,
`daily_activity`, and `measurements` (all using `IF NOT EXISTS`, so
re-running the migration is harmless) — these tables already worked
correctly via their existing unique constraints, but history screens
always query "most recent N entries for this child," and an explicit
index serves that read pattern faster as histories grow. This changes
query speed only, not correctness or any existing behavior.

---

## 5g. Target (mid-parental) height calculator (implemented 2026-06-25)

**Where:** `target-height.js`, the "Target height (mid-parental)" card
on Analytics, `calculateAndShowTargetHeight()` in `app.js`.

**What was proposed first, and rejected:** a "3-generation ancestral
traceback engine" that would convert relatives' heights to Z-scores,
flag any parent more than 1.5 SD from their own family's median height
as having a likely "undiagnosed clinical condition," and silently
substitute their relatives' median height in place of their real
measured height before averaging. This was rejected for two reasons:
(1) height varies within families by this much for entirely ordinary
genetic reasons — treating normal variation as anomalous would
misclassify healthy parents at a real, non-trivial rate; (2) even when
a parent's short stature genuinely does come from childhood illness or
malnutrition, that's real clinical context a doctor needs to see, not
noise to silently overwrite with a different number. Same category of
problem as §7's review of the external "v2.0" document — presenting an
algorithmic guess as more authoritative than the real data it's
replacing.

**What was built instead:** a real, peer-reviewed method — Zeevi D,
Ben Yehuda A, Nathan D, Zangen D, Kruglyak L. "Accurate Prediction of
Children's Target Height from Their Mid-Parental Height." *Children*
2024, 11(8), 916. doi:10.3390/children11080916. Verified directly
(full text fetched and read, not summarized from an abstract), including
reproducing both of the paper's own worked clinical examples through
this app's actual implementation (159.3cm vs the paper's stated ~159cm
for a father 170cm/age 45, mother 157cm/age 50 predicting a daughter;
157.8cm, well above the naive 3rd-percentile expectation, for the
short-father/average-mother example).

**The three real corrections this implements**, none of them in the
traditional Tanner method still recommended in clinical guidelines
today:
1. **Age-shrinkage correction** — adult height loses height starting
   around age 30, accelerating with age, not a one-time event. Modeled
   here as a piecewise-linear approximation of real, independently-
   published data (Sorkin et al. 1999, Baltimore Longitudinal Study of
   Aging: ~3cm cumulative loss by 70/5cm by 80 for men, ~5cm/8cm for
   women) — an approximation of the real shape, not a reproduction of
   the original paper's own unpublished exact nonlinear coefficients
   (not available to verify), stated as such in the code and the UI.
2. **Multiplicative sex correction (×1.08)**, not the traditional flat
   ±13cm. Verified directly: the real male-female height gap at a given
   percentile is NOT constant — 12.2cm at the 3rd percentile vs 14.7cm
   at the 97th, per the paper's CDC growth-chart analysis.
3. **Regression to the mean** — very tall parents have children who
   regress toward the population mean; very short parents have children
   who regress upward. Known since Galton (1886), still not used in
   current clinical practice per the paper's own review of guidelines.
   Implemented using the paper's own fitted equation on standardized
   heights: `Corrected Z = 0.79 × (mid-parental Z) − 0.077`.

**Result spread:** uses the paper's real *measured* residual SD (4.5cm
sons, 4.2cm daughters, from their large-family cohort) instead of
Tanner's original theoretical ±8.5cm guess — while also carrying
forward the paper's own stated caution that this has a ~20% coefficient
of variation and should be used with care.

**Transparency, by design:** the UI always shows the traditional Tanner
result alongside the improved estimate, plus exactly how much
age-correction was added to each parent's entered height — nothing is
computed or substituted without the parent seeing precisely what went
into it. Uses GrowSense's existing WHO adult-height mean/SD (already
in `who-reference-data.js`, age 19y row) rather than introducing a
third population reference for "adult height."

---

## 5h. Extended family heights — reference only (implemented 2026-06-25)

**Where:** `migration_family_height_records.sql`, the "Extended family
heights" section inside the Target Height card, `addFamilyHeightRecord()`
and related functions in `app.js`.

**Why this exists, and why it's structurally isolated from §5g's
calculation:** a parent may know a grandparent's or aunt/uncle's height
even when they don't know all of them — e.g. the grandmother's height
but not the grandfather's. There's a real temptation to fold partial
data like this into the target-height estimate somehow. This app
doesn't, on purpose: the only validated method implemented (Zeevi et
al. 2024, §5g) is parent-to-child; there's no peer-reviewed method here
for weighting incomplete extended-family data, and inventing weights for
missing relatives would repeat the exact mistake the original
"3-generation ancestral traceback" proposal was rejected for.

**What this actually is:** a place to record what's known, for a
parent's own reference or to show a doctor — nothing more.
`family_height_records` is a real, persistent table (relation type,
height, optional age, optional free-text notes), but
`calculateAndShowTargetHeight()` and everything in `target-height.js`
never read from it. Verified directly, not just by code inspection:
added two deliberately extreme family records (195cm grandfather, 140cm
grandmother) around an existing target-height calculation and confirmed
the result (159.3cm) was byte-for-byte identical before and after, then
confirmed it stayed identical after deleting one of those records too.

**If extended-family weighting is ever added properly:** it would need
its own cited, peer-reviewed method (the kind of coefficient-of-
relationship weighting from quantitative genetics is real and exists in
the literature) — not an invented weighting scheme — and should
probably show its own separate, clearly-labeled estimate rather than
quietly blending into the validated parent-only number.

---

## 5i. Target height fixes: persistence, collapse, formula toggle (2026-06-25)

**Where:** `migration_parent_height_persistence.sql`,
`loadTargetHeightForm()`/`toggleCardCollapse()`/`setTargetHeightFormula()`
in `app.js`, the new `calculateExploratoryExtendedTargetHeight()` in
`target-height.js`.

**Bug fixed — parent heights weren't saved.** `calculateAndShowTargetHeight()`
read mother/father height and age straight from form inputs with no
database write at all — every reload or tab switch lost them, forcing
re-entry every time. Fixed by adding `mother_height_cm`,
`mother_current_age`, `father_height_cm`, `father_current_age` directly
on `children` (parallel to the existing SGA birth-data columns), saved
on every successful calculation and restored via `loadTargetHeightForm()`
whenever the Analytics tab opens or the active child changes — verified
directly: calculated once, cleared the form, called the restore
function, confirmed both values came back and the result re-displayed
automatically.

**UI change — the card is now collapsible, default closed.** Feedback
was that the calculator felt like a separate mini-tool dominating the
Analytics page by default. `toggleCardCollapse()` is a small, generic
helper (reusable for any future card) — click the header, body
shows/hides, chevron flips. Defaults closed so a parent who isn't using
this tool today doesn't have to scroll past it.

**New: a formula toggle, with the honesty boundary kept structural, not
just a UI label.** "Parents only" (default) calls the validated
`calculateTargetHeight()` from §5g, unchanged. "+ Extended family" calls
a new, separate function — `calculateExploratoryExtendedTargetHeight()`
— explicitly marked `isExploratory: true` in its return value, which the
UI checks to apply different styling (amber border, an explicit
"⚠️ Exploratory" label, and the parents-only number always shown
alongside for comparison) rather than ever presenting the two results
with equal visual confidence.

**What the exploratory formula actually does, and doesn't:** real,
textbook coefficient-of-relationship weighting (grandparents/aunts/
uncles at r=0.25, siblings at r=0.5 — standard quantitative genetics,
not invented) applied to whatever extended-family heights are on file,
standardized to Z-scores the same way as the main calculation, then
blended with the validated parents-only Z-score at a **fixed 70/30
split that is itself arbitrary and stated as such in the code** — not a
researched constant the way the Zeevi-derived figures are. No
age-shrinkage correction is applied to extended-family entries (that
correction was only validated for parents in the source study).
Verified directly: zero family records produces a result byte-identical
to the parents-only baseline; adding deliberately tall or short
extended-family records measurably shifts the result up or down in the
correct direction; an unrecognized relation type is safely ignored
rather than corrupting the result.

**Follow-up fix, same day — the toggle replaced one result with the
other instead of showing both.** The original implementation had the
formula toggle pick which single calculation ran — meaning the only way
to compare the validated and exploratory numbers was to manually toggle,
recalculate, write down the number, toggle again, recalculate again.
Fixed: `calculateAndShowTargetHeight()` now always computes and shows
the validated parents-only result, and additionally computes and shows
the exploratory result in a second card right below it (clearly marked,
amber border, "Exploratory" badge) whenever extended-family records
exist AND the toggle is set to "extended" — the toggle now controls
whether the second card is eligible to appear at all, not which single
number gets calculated. Verified directly, including catching a real
race condition in the test itself along the way (the toggle handler
calls the now-`async` calculation function without awaiting it, so a
test checking the DOM immediately after toggling needs to wait for that
to settle — same as a real browser's click handler would, this isn't a
bug, just something the verification needed to account for).

---

## 5j. AI coach context fix + question library (implemented 2026-06-26)

**Where:** `buildAICoachContext()`, `loadAICoachQuestions()` and related
functions in `app.js`, `migration_ai_coach_questions.sql`,
`seed_ai_coach_questions.sql`.

**What was actually wrong, found before building anything new:** the AI
coach's system prompt only ever included today's daily log (protein,
sleep, activity) — it had no access to growth percentile, BMI status,
height velocity, target height, SGA catch-up status, lab results, or
puberty milestones, despite all of that being real, already-built data
elsewhere in the app. A parent asking "what does my child's percentile
mean?" would get a generic answer with no actual percentile in it. Fixed
with `buildAICoachContext()`, which recomputes every value fresh from
the same functions the rest of the app uses (not by scraping DOM text,
which can be stale or not yet rendered) — height/BMI percentile, height
velocity, target height (if parent heights are on file), SGA catch-up
velocity (if flagged and under 5), recent labs, recent puberty
milestones. Verified directly: a fully-populated test child produced
correct values for every field, including an exact velocity match
(7.0 cm/yr from a real 7cm-over-365-days case) and a sensible positive
SGA catch-up rate.

**On "embedding an ML module"** — this was explicitly considered and
the honest answer given before building anything: a genuinely trained
ML model needs training data, and this app has WHO's published
reference *curves*, not a dataset of individual children's longitudinal
records to train on. What exists (and what was extended here) is the
same category of thing already in this app — cited statistical formulas
and an LLM call grounded in real data — not a new trained model. Stated
plainly rather than building something that looks like ML but isn't.

**The question library — why a database table, not 500 padded
questions.** Storage was never the real constraint (even 100MB holds
hundreds of thousands of entries at ~300 bytes/question) — the real
constraint is authoring quality, so this shipped with 150 genuinely
distinct, categorized questions rather than 500 stretched out with
near-duplicates. `ai_coach_questions` lives in Supabase (not a static
JS file) specifically so it can be filtered live: each question is
tagged with `requires_data` (e.g. `labs`, `target_height`,
`measurements_2plus`) and an optional age range, and
`getAvailableDataTags()` computes — from the exact same context object
the AI prompt uses — which tags are actually satisfied for the active
child, so a parent never sees a suggested question their child has no
data to answer (e.g. no lab-result questions shown with zero labs
logged, though purely educational lab questions tagged `none` still
show, by design — see code comments). 12 categories, shown as filter
chips that only appear when at least one of their questions is
currently answerable. Falls back to a small hardcoded set if the table
hasn't loaded (migration not yet run, or a network failure) — verified
directly by simulating a failed query and confirming the fallback set
loads correctly.

---

## 5k. AI coach conversation memory + error handling (2026-06-26)

**Where:** `askClaude()`, `resetAIChatForChildSwitch()`,
`clearAIConversation()` in `app.js`.

**Bug fixed — no conversation memory.** Every call to `askClaude()` sent
only `[{ role: 'user', content: userMsg }]` — the current message,
nothing before it. A follow-up like "what about compared to last
month?" had no prior turn to refer to. Fixed: `APP.aiChatHistory` stores
the full exchange, and each API call sends the last 20 messages (10
exchanges) plus the new one — capped to bound token cost and latency,
since the system prompt already re-supplies a fresh data snapshot on
every call regardless of history length. Verified directly: a second
question's request body was confirmed to contain the first question's
text, proving the history is actually transmitted, not just stored
locally and forgotten.

**History resets on child switch**, not just manually — a conversation
about one child's growth data should never silently carry over as
context for a different child. Also added a user-facing "Clear
conversation" button for starting a fresh topic without switching
children. Both call the same `resetAIChatForChildSwitch()`, which also
re-renders the question library's category chips, since which questions
are answerable depends on the active child's data.

**Error handling — failures were previously indistinguishable.** A
network failure, an API error response (rate limit, bad request), and a
malformed/empty success response all produced the same generic "had
trouble responding" text with nothing logged anywhere. Now each case is
handled separately: a real API error object is logged to the console
with its actual content and shown a distinct message; a malformed
response (missing `content`) is also logged and distinguished from a
genuine network failure. None of these failure cases pollute
`aiChatHistory` with a bad exchange — verified directly by simulating
both an error response and a malformed response and confirming history
stayed empty afterward.

**Incidental fix:** `.btn-link` had been used in two places (the SGA
birth-details toggle from an earlier session, and this session's new
"Clear conversation" button) with no actual CSS definition — both had
been rendering as unstyled default browser buttons this whole time.
Added the missing class.

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
