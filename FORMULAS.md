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

## 5l. AI coach now actually works — Edge Function proxy (2026-06-26)

**Where:** `supabase_setup/edge_functions/ai-coach-proxy/index.ts`
(new Supabase Edge Function), `askClaude()` in `app.js`.

**The real bug, found after a user report of "Unable to connect to
AI":** the AI coach had never been able to work at all, on any network.
`askClaude()` called `https://api.anthropic.com/v1/messages` directly
from the browser, with no API key attached anywhere in the request.
Even with a key, this could never have worked: GrowSense is a static
site (GitHub Pages) with no backend, so there was nowhere safe to hold
a real Anthropic API key — putting one directly in client-side JS would
expose it to anyone opening dev tools on the public site, and
Anthropic's API blocks direct cross-origin browser calls (CORS) for
exactly that reason regardless. This wasn't a connectivity problem the
error message suggested; it was a missing piece of architecture.

**The fix:** a new Supabase Edge Function, `ai-coach-proxy`, sits
between the browser and Anthropic. It holds the real API key as a
server-side secret (set via `supabase secrets set`, never committed to
the repo or visible in any client file), accepts only `system`,
`messages`, and `max_tokens` from the caller (not a raw passthrough, so
the function fully controls what reaches Anthropic regardless of what a
caller sends), enforces a hard cap on `max_tokens` server-side
regardless of what the client requests, and handles CORS preflight
correctly. The client (`askClaude()` in `app.js`) now calls
`${SUPABASE_URL}/functions/v1/ai-coach-proxy` instead of Anthropic
directly, authenticating with the same publishable/anon key already
used for every other Supabase call in this app (that key is meant to be
public — unlike the Anthropic key, which is the actual secret this fix
protects).

**Deployment required, not just a file replace:** unlike every other
fix in this project, this one needs a real deploy step beyond uploading
files — the Edge Function itself must be deployed via the Supabase CLI
(`supabase functions deploy ai-coach-proxy`) and the `ANTHROPIC_API_KEY`
secret must be set (`supabase secrets set ANTHROPIC_API_KEY=...`)
before the AI coach will work. Until that's done, the proxy will
correctly return a "not configured" error rather than crash — verified
directly by simulating that exact response and confirming the client
shows a sensible message rather than failing silently.

**Verified directly:** the client now calls the Supabase Edge Function
URL (not `api.anthropic.com`), sends the correct `Authorization: Bearer
<publishable key>` header and request body shape (system prompt +
message history, no `model` field — the proxy decides that
server-side), and correctly surfaces the proxy's own error responses
(e.g. the "AI service is not configured" case, which is exactly what
you'd see if the secret hasn't been set yet).

---

## 5m. Two AI coach modes: template (free) vs live AI (real cost) — 2026-06-26

**Where:** `migration_ai_coach_mode_toggle.sql`,
`seed_ai_coach_answer_templates.sql`, `routeAICoachMessage()`,
`findBestMatchingQuestion()`, `fillAnswerTemplate()`, the admin panel
functions in `app.js`.

**Why this exists:** the live-AI coach needs Anthropic API billing to
work at all (see §5l) — real, ongoing per-question cost. Rather than
require that before the AI coach can do anything, this adds a default,
zero-cost mode that answers from the pre-written question library
(§5j) by matching the user's input to the closest library question and
filling in that child's real data into a template. A `system_admin`
account can flip a single project-wide switch to enable live AI when
ready, rather than it being on by default and accumulating cost before
billing is even confirmed working.

**Mode 1 — Template (default).** `findBestMatchingQuestion()` does
real text-similarity matching, not "AI" — normalized word-overlap
scoring against the question library, after stripping common stopwords
(`what`, `the`, `does`, etc.). **A real bug was caught and fixed during
testing, not just assumed away:** the first version had no stopword
filtering, which caused "what is the capital of France" to falsely
match a BMI question (both shared only "what" and "the" — common words
were inflating the overlap score for any two unrelated questions).
Verified directly: the same input that previously triggered a
confident, fabricated-context wrong answer about the test child's BMI
now correctly returns an honest "I couldn't match that" response.
Matched questions are filled via `fillAnswerTemplate()` using
`{{placeholder}}` tokens substituted from the exact same context object
the live-AI system prompt uses — verified that a real percentile number
and the child's actual name appear in the filled answer, not a literal
unfilled `{{heightPercentile}}` string. If a question matches but has
no template written yet, or nothing matches well enough (50% minimum
word-overlap threshold), the response says so honestly rather than
fabricating an answer — there's no language model in this mode to fall
back on.

**Mode 2 — Live AI.** Unchanged from §5k/§5l — routes through
`askClaude()` and the Edge Function proxy, with full conversation
history and real Anthropic cost per call.

**The toggle itself:** `system_settings.ai_coach_mode`, a single
project-wide row, readable by any authenticated user (the client needs
to know which mode to use) but writable only by `system_admin` accounts
— enforced by RLS at the database level, not just hidden in the UI, so
even a direct API call from a non-admin account would be rejected.
`getAICoachMode()` caches the value for the session after first load.
The admin panel (visible only in the setup modal for `system_admin`
accounts) lets an admin flip this with one tap; verified directly that
switching it mid-session immediately changes which path the very next
message takes, with no page reload needed.

**Usage tracking:** `ai_usage_log` records each live-AI call (rough
token estimates, not billing-exact) so cost is visible over time to an
admin rather than only discoverable after a surprise invoice — not yet
wired into the client in this pass; the table exists, logging calls
from `askClaude()` is the next piece if this is extended further.

**Answer template authoring status:** 23 of 151 library questions have
a written template so far — the highest-priority ones across most
categories (growth trend, BMI, target height, SGA, labs, puberty). The
rest will return the honest "no template yet" message in template mode
until more are written — same quality-over-coverage tradeoff already
applied to the question library itself in §5j.

---

## 5n. Follow-up question suggestions (2026-06-26)

**Where:** `CURATED_FOLLOWUPS`, `suggestFollowUps()`,
`renderFollowUpSuggestions()` in `app.js`.

**What it does:** after a successfully answered question in template
mode, 2-3 "you might also ask" buttons appear beneath the answer.
Two sources, in priority order: (1) a small hand-picked set of 15
cross-category "leads to" chains (e.g. a height percentile question
naturally leading to a velocity question, or a target-height
question) — every entry validated at authoring time against the real
question library, so no chain can silently reference a question that
doesn't exist; (2) same-category questions, ordered by the library's
own `display_priority`, filling out up to 3 total suggestions if the
curated chain doesn't have enough (or any).

**The safety property that actually matters here, verified directly:**
every suggested follow-up is filtered through the exact same
data-availability check used for the main question list
(`questionIsAnswerable()`) — a follow-up is never shown for a question
the active child doesn't have the data to answer. Verified by testing
the same curated chain (percentile → target height) twice: once with
parent heights on file (target-height suggestion correctly appears),
once without (target-height suggestion correctly disappears, leaving
only the still-answerable velocity suggestion). A follow-up button is
never a dead end.

**Scope, deliberately:** this only applies to template mode. Live AI
mode already has real conversational memory (§5k) and doesn't need
scripted suggestions the same way. Also deliberately NOT built: the
AI asking the parent a clarifying question back — that would need real
conversational reasoning template mode doesn't have, versus this
feature, which only needed matching + a static lookup table.

---

## 5o. Citation verification finding + 14 newly verified questions (2026-06-26)

**Where:** `migration_citation_tracking.sql`,
`seed_verified_questions_batch1.sql`, citation display in
`routeAICoachMessage()` in `app.js`.

**What happened, stated plainly because it matters:** a file of 466
candidate questions ("Optimized_Growth_Auditor_600.csv") was supplied
with citations claimed to be NCBI/PubMed-sourced. They were checked
directly, not assumed — and they were fabricated. The decisive finding:
**the same PMID was attached to completely different, unrelated
fabricated titles in different rows** (e.g. PMID 31084227 was cited as
both "Optimizing Clinical Ingestion Workflows in Pediatric Auxology"
and, elsewhere in the same file, "Correlating Odontoblast Enamel Faults
with Skeletal Mineralization Anomalies"). A single PMID cannot be two
different papers — this is structurally impossible for real citations,
not a sourcing-quality issue. Only 24 unique PMIDs were reused 357
times across the file. The one PMID that did trace to a real paper (the
real idiopathic short stature consensus statement) had the wrong number
attached — its real PMID is 18782877, not the 18948124 written in the
file. None of that file's citations were used anywhere in this app.

**The same file also contained the "Phenotypic Masking" / "Expanded
Ancestral Phenomic Model" / 4-generation pedigree framing already
reviewed and explicitly rejected earlier in this project (see the
target-height feature's design notes) — reappearing here dressed up
with a fabricated Nature Reviews Endocrinology citation to look more
credible. Not used, for the same reasons as before.

**What WAS extracted and used:** underneath the padding (hundreds of
near-duplicate questions generated by chaining invented jargon —
"Skeletal Strain Hysteresis Envelope," "Skeletal Strain Hysteresis
Envelope Curve," etc. — these are not real clinical terms) were ~65
genuinely distinct, real concepts. After removing ones already covered
in the existing 151-question library and ones with risky framing, 16
were selected for real research; 14 were written up with answers after
independent verification — each citation actually fetched and read, not
just pattern-matched, confirming it says what's claimed. Sources used:
real PubMed entries (verified via direct PubMed fetch where possible),
PMC, NCBI Bookshelf/StatPearls/GeneReviews, and Nature.

**One real finding worth flagging on its own:** the sleep-fragmentation
question turned up genuinely conflicting evidence, which is reported
honestly rather than smoothed over — a 2022 controlled study in
pubertal children (PMC9562791) found that acutely disrupting deep sleep
did NOT reduce growth hormone pulses, directly contradicting the
popular "broken sleep blocks growth hormone" claim for single nights.
What IS well-supported is that chronic, severe sleep disruption (like
untreated sleep apnea) correlates with lower IGF-1 and slower growth
over time. The answer reflects both findings rather than picking the
more dramatic-sounding one.

**New schema, new UI:** `citation_source` and `citation_verified_date`
columns added to `ai_coach_questions` — this is the first batch to use
them. The chat UI now shows a small, distinctly-styled citation line
under any answer that has a verified source attached (verified directly
that it renders correctly when present and is absent when not). Answers
without a verified citation show none — no placeholder, no fabricated
source, just nothing, consistent with this project's standing rule of
never presenting unverified sourcing as real.

---

## 5p. Second verified question batch — 17 more, library now at 182 (2026-06-26)

**Where:** `seed_verified_questions_batch2.sql`.

**Source material this time was a genuine improvement over the earlier
466-question file:** a new 50-question candidate list was supplied,
honestly marking 43 of its 50 citations as "PMID: TBD" rather than
inventing numbers — a real, credit-worthy difference from the prior
fabricated-citation batch. The 4 questions that DID claim a specific
PMID (sleep/GH, two zinc claims, vitamin D) were checked the same way
as everything else in this project: searched directly, including a
direct PubMed URL fetch attempt. **None of the 4 specific PMIDs could
be confirmed** — the underlying claims were all real and well-supported
by genuine literature, just not by the exact numbers given. None of
those 4 numbers were used; where the claim itself was solid, real
replacement citations were found independently (e.g. the zinc/DNA-
synthesis claim is real and well-supported — PMID 9283119 and others
confirm it directly — just not under the number originally given).

**Of the 50 candidate questions, ~33 were already covered** in the
existing 165-question library under similar wording (height velocity,
zinc, vitamin D, CDGP, bone age basics, etc.) — checked by hand, not
just keyword-matched, since a crude keyword check kept false-flagging
unrelated questions as "covered" just for sharing a single common word.
**17 were genuinely new and got the full research treatment**: growth
plate biology and whether they can reopen (no — confirmed via PMC5798587,
a real synchrotron microtomography study), catch-down growth (the real,
distinct mirror-image of catch-up growth, confirmed via PMC3474389),
Tanner staging's actual definition and origin (PMID 29262142), GnRH as
the literal trigger for puberty (NBK534827), testosterone/estrogen's
growth-plate mechanisms, all four bone-age basics questions (definition,
why ordered, delayed vs. advanced — PMC4266871 and PMC4628949), four
nutrition questions (milk/dairy — a real, citable effect via IGF-1 from
a 5,101-girl cohort; ultra-processed foods — directly linked to lower
height-for-age and 3x higher stunting odds in a real Ecuador study;
sugary drinks; breakfast skipping — a 1,200-child Tunisian study), and
two sleep-tracking basics (wearable accuracy — a real 75-participant,
543-hour polysomnography validation study showing real, substantial
accuracy variation between devices; sleep efficiency's actual
definition).

**Verified directly, not just generated:** all 17 pass the same
placeholder/category/requires_data validation as every prior batch
(zero errors), checked for exact-text duplicates against the existing
165-question library (zero found), and confirmed working end-to-end
against the full reconstructed 182-question library — including a
citation rendering correctly for a new question, fuzzy matching working
on new content, and the pre-existing 165 questions completely
unaffected.

---

## 5q. Illness events replace the mislabeled "illness days this month" field (2026-06-26)

**Where:** `migration_illness_events.sql`, the redesigned "Development
interference log" card, `addIllnessEvent()` and related functions in
`app.js`.

**The real problem, reported directly by the user:** the Medical
screen's "Illness days this month" field showed a number that appeared
to persist after refresh — investigated and confirmed this wasn't a
bug. The field correctly saved/loaded one number tied to one specific
`log_date`, exactly like every other medical_logs field — the label
just claimed something the data model never actually did (there was no
monthly aggregation anywhere in the codebase, confirmed by checking
every usage of `illness_days`). There's no natural moment a parent
would think "let me update my running monthly tally typed into one box
on one arbitrary day" — illness happens as discrete episodes with a
real start and end, not a number you accumulate mentally and type in
once.

**The fix — event-based logging, matching the pattern already trusted
for `lab_results` and `puberty_events`:** a new `illness_events` table
(`start_date`, optional `end_date` for ongoing illnesses, a broad
`illness_type` bucket — fever, cold/respiratory, ear infection,
stomach/GI, flu, skin/rash, injury, hospitalization, other — plus free-
text notes for real specifics). A parent can log the start immediately
and fill in the end date once it resolves, rather than waiting until an
illness is over to log anything. A database constraint
(`illness_end_after_start`) prevents an end date earlier than the start
date from ever being saved, enforced at the database level, not just in
the UI.

**The old field is genuinely gone from the UI, but the old data isn't
lost:** `medical_logs.illness_days` is left untouched in the database —
not migrated, not dropped — so any historical data saved under the old
design still exists if needed later; the screen just no longer reads or
writes it. `saveMedical()` and `loadMedicalLogForDate()` were both
updated to drop their references to the removed `medIllness` element.

**Verified directly:** the full add → render → delete cycle, the
ongoing-illness case (no end date, displays "ongoing"), and both
validation guards (missing start date, end date before start date) all
tested and confirmed working; confirmed the old `medIllness` DOM
element is genuinely gone with no dangling references left anywhere in
either file.

---

## 5r. Customizable food cards — favorites + custom foods (2026-06-26)

**Where:** `migration_custom_foods_favorites.sql`, the "Food library"
modal in `index.html`, `resolveFavoriteFoods()` and related functions
in `app.js`. Two new verified preset foods also added to
`food-reference-data.js`.

**The request:** the original 10 food cards were a fixed list, same
for every user. Wanted: a way to browse beyond that fixed set, add a
custom food with manually-entered protein/zinc (no auto-lookup yet —
explicitly deferred to "find a way to do this later"), and let each
child have their own chosen set of active cards. Decided together: per-
child scoping (not shared across siblings) and a modal/popup for
browsing, rather than an inline expand.

**Two new verified preset foods added first:** peanut butter and tofu,
both real USDA FoodData Central entries (FDC 174294, FDC 174290),
values fetched directly from the source page and converted from the
stated serving size to per-100g — same verification standard as every
other preset already in the library, not estimated.

**Schema:** `custom_foods` (per-child, parent-named, manually entered
protein/zinc/calcium for a stated serving — NOT claimed as USDA-sourced
anywhere, matching the existing "Protein Boost" honesty-labeling
pattern) and `food_favorites` (per-child, points at either a preset
food's string ID or a custom food's UUID via a `food_source` +
`food_ref_id` pair, so one table handles both cases rather than two
parallel ones).

**UI:** a new "Food library" modal (Browse all / My foods / Add new
tabs) reachable from a button below the main grid. Browsing shows every
preset and custom food with a star toggle; favorited items sort to the
top. The main grid (`buildFoodCardGrid()`) now renders from
`resolveFavoriteFoods()` instead of the fixed array directly — falls
back to the original default 9 presets (explicitly excluding the 2 new
ones) if a child has no favorites configured yet, so an existing user's
grid looks unchanged until they actively choose to customize it.

**A real bug caught during testing, not assumed away:** the first
version of `addCustomFood()` and `toggleFoodFavorite()` mutated
`APP.customFoods`/`APP.foodFavorites` in place (`.unshift()`/`.push()`)
after an insert. Testing surfaced a duplicate-row case — traced
precisely to the array-mutation pattern being unsafe if the data layer
ever returns a reference to the same underlying array rather than a
fresh one (confirmed happening in the test harness; unlikely but not
guaranteed impossible with a real client either). Fixed by reassigning
new arrays instead of mutating in place in both functions — strictly
safer regardless of what the data layer returns, not a workaround
specific to the test environment. Re-ran the full suite after the fix:
every case passed, including the full add → favorite → tap-to-log →
delete cycle, with correct cleanup of a custom food's favorite entry on
delete (no dangling reference) and confirmed unrelated favorites stay
untouched.

**Deferred, as discussed:** automatic nutrition lookup for custom foods
(the request explicitly named this as a later improvement, not part of
this pass) — for now, every custom food's values are the parent's own
estimate, clearly labeled as such everywhere it appears (modal warning
text, card styling, list metadata).

---

## 5s. Nine new verified foods + shrimp portion fix (2026-06-26)

**Where:** `food-reference-data.js` (now 20 entries, up from 11).

**Shrimp fix, reported directly by the user:** the existing shrimp card
tapped 85g (~3 medium shrimp) per tap — too large a jump for one tap
compared to every other card's matchbox-sized (~28-30g) convention.
Fixed by recomputing from the SAME already-verified USDA per-100g
source (FDC 175180), just at a corrected 28g serving (1 medium shrimp,
consistent with the original 85g/3-shrimp figure and with industry
sizing references for "medium" shrimp running ~31-40 per pound) — no
new sourcing needed, purely a portion-math correction, and the
underlying nutrient data is untouched.

**Nine new foods, each independently verified the same way as every
other entry in this file** — real USDA page fetched, exact serving-size
values read directly (not estimated), converted to per-100g, then
scaled to a kid-sized matchbox tap (28-30g) to match the established
convention exactly, per direct instruction: pork loin (FDC 168233),
bacon (FDC 168322), raw salmon (FDC 173686, matched to the existing
cooked salmon's "wild Atlantic" species for consistency), squid (FNNDS
782749, steamed/boiled — the common Thai/Japanese preparation, not raw
sashimi-style), crab (FDC 172007, Dungeness, fresh-cooked rather than
canned to avoid an unrepresentative sodium spike), tuna (FDC 172006,
yellowfin), tilapia (FDC 175177, as the white-fish entry), and duck (FDC
172411, roasted meat+skin — the common roast/Peking-duck preparation).

**Miso deliberately breaks the matchbox convention, and this was a
considered decision, not an oversight:** every other new entry uses the
same 28-30g matchbox-sized tap as the existing library. Miso doesn't fit
that pattern — it's a concentrated condiment eaten by the tablespoon in
soup, not a piece of protein eaten in a matchbox-sized portion — so it
uses a 17g (1 tbsp) serving instead. Both miso and bacon carry a real,
loud sodium caveat directly in their `source` field, not just a number
buried in the data: miso's single tablespoon already supplies roughly
28% of a child's full daily recommended sodium intake; bacon's
matchbox-sized tap supplies roughly 9%. Both figures were calculated
directly from the same verified USDA records, not estimated.

**A real bug caught during this addition, not assumed safe:** the
initial edit introduced a double-backslash escaping error in two of the
new `source` strings (an artifact of how the replacement was
constructed), which broke the file's JavaScript syntax outright —
caught immediately by running `node --check` before considering the
work done, not discovered later by a user. Fixed directly, then
re-verified with the same check plus a full value dump confirming every
one of the 20 entries' per-tap protein/zinc/calcium figures are
internally consistent and sensible relative to the existing library
(all land in the same 6-9.6g protein per tap range as the original 11
matchbox-style cards).

**Verified end-to-end, not just at the data-file level:** confirmed all
20 foods load without error, appear correctly in the "Browse all" food
library modal, can be favorited and immediately show on the main grid
with the exact correct per-tap protein value, and that tapping a new
food's card logs the exact right amount into the day's totals — the
same full pipeline test used for the favorites/custom-foods system
itself in the prior session.

---

## 5t. Three UI fixes — hydration tap targets, readiness ring overlap, calcium step (2026-06-26)

**Where:** `style.css` (water grid, GRS score/label), `index.html`
(calcium stepper buttons).

**Hydration tap targets — measured, not just eyeballed.** The 8 water-
drop buttons sat in one `display: flex` row (`.water-grid`). Height was
already a correct 44px, but width was `flex: 1` across 8 items — on a
320px-wide screen, that works out to roughly 32px per button, measurably
below the 44px minimum tap-target guideline (Apple HIG and Material
Design both use 44px as the floor). Fixed by switching to a 4-column
grid (2 rows of 4) instead of forcing all 8 into one row — recalculated
the same way: roughly 68px per button on the same 320px screen, more
than double the previous width and comfortably above the minimum on any
realistic screen size.

**Readiness ring overlap — traced to a specific, real geometry
conflict, not a vague "feels cramped."** The innermost ring has `r=25`
in a 110×110 SVG, meaning the circle the score sits inside is only 50px
across. The score text was 32px font — for the genuinely reachable
value of 100 (confirmed directly from `updateHUD()`'s scoring math: all
three category ratios cap at 1, and `35+35+30=100` is a real achievable
score, not theoretical), the rendered text width comes out to roughly
58px — wider than the 50px circle it's sitting in, which is exactly the
overlap reported. Fixed by reducing to 21px with tightened letter-
spacing, recalculated to leave roughly 15px of real margin even at the
3-digit worst case, while staying clearly legible. The "of 100" label
below it was tightened correspondingly so the two-line stack has room
to breathe rather than just barely fitting.

**Calcium stepper increment.** Changed from ±50mg to ±100mg per direct
request. Confirmed before changing: the calcium range (0-3000mg) and
target (1300mg) both divide cleanly by 100 with no awkward remainder,
so this isn't just a rounder number — it actually halves the number of
taps needed to reach a typical day's target (13 taps instead of 26)
without overshooting past any meaningful threshold.

**Verified directly:** confirmed via functional test that calcium
increments by exactly 100 per tap and updates the display correctly;
that the water grid builds without error with all 8 drops present under
the new layout; and that the readiness score updates without error
under the new font sizing. CSS values were also double-checked directly
against the final file to confirm the exact intended numbers landed,
rather than just trusting the edit call succeeded.

---

## 5u. Collapsible food note + hydration grid reverted on better data (2026-06-27)

**Where:** `style.css` (water grid, info-icon-btn), `index.html`
(food note panel, info button), `toggleFoodNote()` in `app.js`.

**Food sourcing note collapsed behind an (i) button.** The USDA-
sourcing explanation paragraph under the Nutrition grid was always
visible, taking up real vertical space on a phone screen for text most
people only need once. Moved behind a small round (i) button next to
the existing "USDA sourced" badge — same collapse/expand pattern
already used for the SGA birth-details toggle, hidden by default.
Verified directly: hidden on load, toggles open and closed correctly
both directions.

**Hydration grid reverted from 2 rows back to 1 row — and this was a
genuine correction, not just a preference reversal.** The prior
session's 2-row fix was justified using a 320px reference screen width,
which is an old/small Android reference point, not representative of
any current iPhone — this app's actual target. Recalculated against
real iPhone widths (iPhone SE/mini 375px through Pro Max 430px): a
single row of 8 buttons actually lands at roughly 38-45px per button on
real hardware, much closer to the 44px tap-target guideline than the
~32px the 320px calculation implied. Given that, and the real, reported
cost of 2 rows (visible empty space, an objectively worse use of
screen), reverted to 1 row with a slightly tightened gap (5px → 4px) as
a small partial recovery, rather than keep a fix justified by a
miscalibrated reference width.

---

## 5v. Delete confirmations — sorted by real stakes, not applied uniformly (2026-06-27)

**Where:** `deleteLabResult()`, `deletePubertyEvent()`,
`deleteIllnessEvent()`, `deleteFamilyHeightRecord()` in `app.js`.
`removeChild()` already had this pattern from an earlier session and
was the template followed here.

**The actual rule applied, per direct instruction:** confirm before
deleting anything that's either catastrophic (a whole child profile) or
genuinely hard to recreate (clinical/developmental records — illness
episodes, lab results, puberty milestones). Don't confirm same-day
nutrition log taps or custom food cards — both are cheap to fix by just
tapping again, and a confirm dialog there would be pure friction with
no real safety benefit, exactly as specified directly.

**Family height records were a deliberate judgment call, asked and
answered explicitly rather than assumed:** these aren't clinical data
and are never used in any calculation (purely reference), so they
technically belong in the "low stakes" bucket by the same logic applied
elsewhere — but confirmation was requested anyway, since re-entering a
relative's height after a misclick is still real tedium even if it's
not consequential the way a lab result is. Honored as asked rather than
overridden with the "technically low-stakes" argument.

**Final split across all 7 delete buttons in the app:**
- **Confirms:** `removeChild`, `deleteIllnessEvent`, `deleteLabResult`,
  `deletePubertyEvent`, `deleteFamilyHeightRecord`
- **No confirm:** `deleteNutritionLogItem`, `deleteCustomFood`

All five confirms use native `confirm()` with specific, plain wording
naming exactly what's being removed — matching the pattern
`removeChild()` already established, not a generic "Are you sure?"
across all five.

**Verified directly, not assumed from reading the code:** simulated
both cancelling and accepting the browser confirm dialog for all four
newly-guarded functions — confirmed cancelling reaches zero database
delete calls across all four, confirming lets all four proceed exactly
once each, and confirmed by inspecting the actual function source that
the two intentionally-unguarded functions contain no `confirm()` call
at all.

---

## 5w. Real bug: child-delete button silently failed due to a native DOM API name collision (2026-06-27)

**Where:** `app.js` — `removeChild()` renamed to `deleteChildProfile()`.

**The bug, reported as "the × button does nothing":** the actual
browser console (obtained directly from the user, not assumed) showed:
`Uncaught TypeError: Failed to execute 'removeChild' on 'Node':
parameter 1 is not of type 'Node'`. The cause: every DOM `Node` has a
native built-in method called `removeChild()`
(`parentNode.removeChild(childNode)`), and this app's own global
function was named exactly the same thing. The inline
`onclick="removeChild('${childId}')"` attribute was resolving to the
native DOM method instead of the app's function in this execution
context, which then tried to call native `removeChild` with a string
child_id instead of an actual DOM node — hence the exact error shown.
This is a real, classic JavaScript naming-collision class of bug, not a
logic error in the function's own body, which is why the function
looked completely correct on inspection and the click appeared to "do
nothing" rather than visibly error in a casual look.

**Fixed by renaming to `deleteChildProfile`** — a name that can't
collide with any native DOM/JS API. Proactively checked every other
function name in the app against a list of common native DOM/JS method
names (`appendChild`, `insertBefore`, `cloneNode`, `submit`, `reset`,
`close`, `focus`, etc.) to confirm this was an isolated case, not a
systemic pattern — confirmed clean, no other collisions found.

**Verified directly, reproducing the actual failure mode, not just
checking the rename:** wrote a test that renders the real child list
HTML, gets the actual rendered button element, and calls `.click()` on
it exactly the way a real tap would — confirmed this no longer throws
the `Node.removeChild` error and the delete call correctly reaches the
database. Checking only that the function was renamed wouldn't have
caught a possible re-introduction of the same collision; checking the
actual click path does.

## 5x. Custom food deletion now requires confirmation (2026-06-27)

**Where:** `deleteCustomFood()` in `app.js`.

Per direct request: a custom food's protein/zinc/calcium values often
represent real effort — figuring out the actual nutrition for a child's
specific favorite homemade or specialty food — so accidental deletion
costs more than the "quick to redo" framing applied to nutrition-log
taps. Added a `confirm()` gate with wording naming the actual cost
(re-entering the values), not a generic "are you sure." This is a
deliberate exception to the earlier "custom foods are low-stakes, no
confirm needed" decision (§5v) — revised directly based on the user's
own account of how much thought goes into these entries, not assumed
from outside.

---

## 5y. Archive/soft-delete lifecycle + subscription tiers (2026-06-29)

**Where:** `migration_archive_and_subscriptions.sql`,
`migration_archive_sweep_cron.sql`, `deleteChildProfile()`,
`requestAccountDeletion()`, `getAccountArchiveRetentionDays()`,
`loadAndRenderAdminArchivePanel()` + restore functions in `app.js`,
`index.html` (admin archive panel, Delete account button).

**The core guarantee, stated plainly:** nothing a parent removes from
GrowSense vanishes immediately. Tapping "remove" on a child profile or
"Delete account" flips a status flag, hides the data from the parent's
view, and starts a countdown — 1 year on Free and Premium, 3 years on
Pro. Every measurement, lab result, puberty milestone, illness episode,
and log tied to that child stays completely intact in the database
during that window. Only after the countdown expires does the automated
daily sweep (`run_archive_permanent_delete_sweep()`, pg_cron at 03:00
UTC) perform the real, irreversible delete. A system_admin can restore
any archived child or account at any point before that sweep runs — the
admin panel under Account & Settings shows the archived list with a
days-remaining countdown and a Restore button for each.

**Account deletion is a single unit operation, not per-child.** Calling
`requestAccountDeletion()` archives every active child under the account
in one update (`.eq('parent_id', userId).eq('status', 'active')`), then
archives the account itself — so a parent doesn't need to delete each
child separately first, and nothing is left dangling as "active but
orphaned" after the account-level archive.

**Subscription tiers are stored as data, not hardcoded.** The
`subscription_tier_limits` table holds the actual limit values, so a
tier's cap can be changed (a promotion, a pricing correction) without a
code deploy. Limits: Free — 1 child, 30-day rolling retention on daily
logs only (measurements/labs/puberty events never pruned on any tier),
2 custom foods, no live AI; Premium — 2 children, 3-year log retention,
unlimited custom foods, 50 live AI calls/month, doctor sharing, PDF
export; Pro — unlimited children, unlimited log retention, 200 live AI
calls/month, 3-year archive window.

**What's NOT yet wired in the application code** (schema built, UI
labels work, but server-side enforcement isn't done yet): the actual
child-count limit check before `addChild()`, the daily-log pruning job,
and the live-AI monthly cap enforcement in the Edge Function proxy. These
are the next tier-enforcement tasks.

**pg_cron note:** the automated sweep requires the `pg_cron` extension
enabled in the Supabase dashboard (Database → Extensions → pg_cron) —
this is a one-click toggle, but it can't be done from a SQL file in the
standard Editor role. `migration_archive_sweep_cron.sql` documents this
and must be run AFTER enabling the extension.

**Business logic verified directly** via isolated unit tests (not JSDOM
— the Supabase multi-eq chain stub pattern is reliably difficult to
simulate correctly in a string-injected inline script context): all 5
core lifecycle paths confirmed correct — archive-not-delete, active-
filter hides archived data, restore clears timestamps correctly, account
deletion archives all children as one unit, Pro tier's 3-year window is
genuinely longer than Free/Premium's 1-year window.

---

## 5z. Tier enforcement wired into app code (2026-06-30)

**Where:** `addChild()`, `pruneStaleLogItemsIfNeeded()`,
`checkAndIncrementLiveAIUsage()`, `askClaude()` in `app.js`.

**The three enforcement tasks from §5y, now wired:**

**1. Max-children check in `addChild()`.** Reads
`subscription_tier_limits.max_children` for this account's actual
tier before every insert — `NULL` means unlimited (Pro), so Pro users
are never blocked. The check counts only `status !== 'archived'`
children, so an archived child (hidden from the parent's view) doesn't
count against the limit. The user sees a plain message naming their
tier and telling them to upgrade, not a generic error. Verified: Free
blocked at 1/1, allowed at 0/1; Premium allowed at 1/2; Pro (null)
always allowed.

**2. Daily-log pruning in `pruneStaleLogItemsIfNeeded()`.** Runs once
per child per browser session (session-level Set guards re-entry) as a
fire-and-forget background call from `loadDayIntoState()` — the parent
never waits for it. On Premium/Pro, reads the retention limit (`NULL`),
finds it unlimited, exits without touching anything. On Free (30-day
rolling window), issues a single DELETE per table
(`nutrition_log_items`, `sleep_logs`, `activity_logs`) for rows older
than the cutoff date — all using `log_date < cutoffStr` where
`cutoffStr` is a plain `YYYY-MM-DD` string matching the `log_date`
column type, avoiding timezone-sensitive timestamp comparisons that
could silently prune the wrong day. Errors are swallowed silently since
this is background maintenance. Measurements, lab results, puberty
events, and illness events are deliberately NOT included — those are
never pruned regardless of tier, per the original tier design decision.

**3. Monthly live-AI cap in `checkAndIncrementLiveAIUsage()`.** Called
at the top of `askClaude()` before any network call. Reads the tier's
`live_ai_monthly_cap`, then reads and upserts the
`live_ai_usage_monthly` row for this user and the current local
calendar month (YYYY-MM, in local time not UTC — a user making a call
just before midnight UTC shouldn't see it counted in the "wrong"
month). Free gets a clear message that live AI isn't included in their
plan. Premium/Pro users who've hit their monthly cap see a plain
message naming the cap, the current count, and when it resets. The
counter increments only if the call will actually proceed — cap-
exceeded calls don't increment the counter. Returns `true` (blocked)
or `false` (proceed) so `askClaude()` can return early cleanly without
the caller needing to re-check state. Verified: cap=0 always blocks,
49/50 allows and increments, 50/50 blocks, 199/200 Pro allows, YYYY-MM
format correct.

**What's still deferred:** the Edge Function proxy doesn't yet enforce
the cap server-side — this client-side check is the UX layer, and a
determined user could bypass it via dev tools. Server-side enforcement
in the Edge Function is the next step for this feature.

---

## 6a. Admin dashboard, phase 1 — audit log + user list (2026-06-30)

**Where:** `migration_admin_audit_and_users.sql`, new "Admin" tab
(`screenAdmin`) in `index.html`, `loadAdminUsersAndAuditLog()` and
related functions in `app.js`.

**Context — what existed before this:** there was no admin table, no
user list, no way to see who's on what tier short of querying Supabase
directly, and no way to change a tier except a manual SQL UPDATE. "Admin"
was just one value of `account_role` with two narrow capabilities
(toggle AI mode, restore archived data) buried inside Account &
Settings. Admin accounts can only be created by directly editing a row
in Supabase — there's no self-service signup path, which is the
correct security posture and is documented here rather than built as
an in-app flow.

**Decision: this needed to be a dedicated dashboard screen, not an
expanded modal section.** Confirmed directly — the full requested scope
(user list/search, tier management, billing status, usage metrics,
audit log) is too much for a settings modal. Added as a 5th tab,
hidden by default in the HTML (`class="tab hidden"`) and only revealed
after `isSystemAdmin()` is confirmed from the real database row at
login — never assumed or shown speculatively.

**Build order, agreed directly:** audit log + user list first (this
session), then tier-change UI (built together with the audit log since
the two are inseparable — a tier change without an audit record isn't
safe to ship), then usage metrics next. Billing *management* is
explicitly deferred — there's no payment provider integrated yet, so
there's nothing real to manage; the tier-status view doubles as the
billing status view for now.

**The audit log is the safety backbone, built first on purpose.**
`admin_audit_log` records every admin action: who (`admin_user_id` +
a denormalized `admin_email` snapshot, so the log stays readable even
if that admin's email later changes), what (`action_type`), to whom
(`target_user_id`/`target_child_id`/`target_email`), and the
before/after values. Critically, the table has no INSERT policy for
any role — the ONLY way to write to it is through
`log_admin_action()` or `change_user_subscription_tier()`, both
`SECURITY DEFINER` functions that re-check the caller is actually a
system_admin internally (not just trusted because the app called
them correctly) before writing anything. This means even a
system_admin querying the table directly through the normal client
cannot insert a forged entry — only the function path can write,
which is what makes the trail trustworthy rather than just a
convention the app happens to follow.

**`get_all_users_for_admin()`** is a second `SECURITY DEFINER`
function, needed because normal RLS only ever lets a user read their
own `user_accounts` row — an admin dashboard listing everyone
requires a deliberate, explicit bypass, gated the same way (raises an
exception, not just an empty result, if the caller isn't
system_admin).

**`change_user_subscription_tier()`** performs the tier UPDATE and the
audit log INSERT as one atomic function call — there's no code path
where the app could call the update and then fail to log it
separately, because they're not two separate calls from the client at
all.

**UI:** the All Users card shows every account (email, role, child
count, archived status) with a live email search, and an inline
tier dropdown + Apply button per row — applying re-confirms via a
native `confirm()` naming the exact change before calling the RPC.
The Recent Admin Actions card shows the last 30 audit entries with
who/what/when, refreshed immediately after any action so an admin sees
their own change land without needing to reload.

**Verified directly, all 7 scenarios:** tab visibility correctly gated
by real role (not assumed); the user list loads and renders correctly;
search filters correctly and updates the result count; applying a tier
change calls the RPC function with the exact correct parameters (not a
raw table update that would bypass the audit requirement); the
in-memory list updates immediately; the audit log entry is created
with the correct before/after values and renders in the UI; and
selecting the already-current tier correctly skips the RPC call
entirely rather than logging a no-op change.

**Deferred to the next phase:** usage metrics (active users, AI call
volume, signups over time) and the billing status/management view —
both explicitly next, not abandoned.

---

## 6b. Admin dashboard redesign — sidebar shell + overview (2026-06-30)

**Where:** `screenAdmin` in `index.html` (full restructure), new CSS
block in `style.css` (`.admin-shell`, `.admin-nav`, `.admin-stat-*`),
`initAdminDashboard()`, `setAdminSection()`, `setAdminGreeting()`,
`renderAdminOverviewStats()` in `app.js`.

**The ask:** turn the flat admin tab (two stacked cards) into a real
console-style dashboard — minimal, clean, modern, and structured to
make adding future management features easy, modeled loosely on the
Claude Console layout (sidebar nav, greeting, stat cards).

**A real layout decision made explicitly, not silently:** this app is
otherwise tuned specifically for iPhone widths (a recurring theme in
this project — the hydration grid and readiness ring both got fixed
after being calibrated to the wrong reference width). Admin management
work is a different context — checked confirmed there's no app-wide
width constraint (`.app` just stretches to fill the viewport), so the
existing screens already look stretched on a wide desktop browser. The
admin dashboard is deliberately built desktop-shaped (a persistent left
sidebar) rather than forced into the same narrow mobile pattern, with a
CSS breakpoint at 880px collapsing the sidebar into a horizontal
scrollable pill row for the rare case an admin checks in from a phone.

**No new color palette — reused the app's existing tokens
deliberately**, per the frontend-design skill's guidance to ground
choices in the real subject rather than invent a separate identity:
the same `--accent`/`--surface`/`--text` variables, with `IBM Plex Mono`
(already used elsewhere for data values like the readiness score)
applied specifically to the new stat-strip numbers to give the overview
a console/data-forward feel without introducing new type pairings.

**Five sections behind a sidebar nav:** Overview (new — a 4-stat strip:
total users, Free/Premium/Pro counts, computed entirely client-side
from the already-loaded user list with zero extra queries, plus a
5-item audit log preview), Users (the existing list/search/tier-change,
relocated as-is), Archived data (moved OUT of the Account & Settings
modal — this is an admin management function, not a personal account
setting, so it belongs in the dashboard, not buried in a settings
sheet), Audit log (the existing full list, also given its own section),
Settings (the AI coach mode toggle, also relocated out of Account &
Settings for the same reasoning). A sixth nav item, "Billing," is shown
disabled with a "Soon" tag — visible placeholder for a feature that
genuinely has nothing to manage yet (no payment provider integrated),
rather than hidden entirely, so the dashboard's eventual shape is
visible now per the "flexible to extend" requirement.

**Relocating the AI-mode and archive panels required real cleanup, not
just a copy-paste:** both panels previously lived inside the Account &
Settings modal (`adminAIModePanel`, `adminArchivePanel`), loaded by
`openSetup()`. Moving them meant: removing their old IDs and the
`hidden` class toggle logic entirely (visibility is now owned by
`setAdminSection()`, not a per-panel reveal), removing their load calls
from `openSetup()`, and folding their loading into the new
`initAdminDashboard()` instead. Verified directly that zero references
to the old panel IDs remain anywhere in either file — a stale reference
here would have silently broken the relocated panels.

**A small UX touch, not load-bearing but intentional:** the dashboard
greets the admin by name (parsed from their email) and time of day —
"Good evening, cheetah_ok" — a deliberate small personal moment
matching the reference's tone, kept restrained rather than expanded
into anything more elaborate, per the design skill's "spend your
boldness in one place" guidance.

**Verified directly, all 6 scenarios:** the dashboard loads every
section's data in one pass with a working greeting; the overview stats
compute correctly from already-loaded data with confirmed zero extra
aggregate queries; section switching correctly shows exactly one
section and marks the right nav item active; the overview's audit
preview and the full audit list are genuinely independent elements;
applying a tier change correctly cascades to update the overview counts
in real time, not just the user list; and the relocated archive/AI-mode
panels load and render correctly from their new home.

---

## 6c. Codebase separation, phase 1 — shared design tokens + client (2026-06-30, corrected)

**CORRECTION, same day:** the first version of this entry put the two
new files in a `shared/` subfolder, referenced as `shared/design-
tokens.css` and `shared/supabase-client.js`. This broke the live site
— every other file in this project has always lived flat in the repo
root (`food-reference-data.js`, `who-reference-data.js`, etc.), and the
user's GitHub upload workflow matches that: files go straight into the
repo root, no subfolder. Uploading the two new files the same way they
always upload files meant they landed flat, not inside an actual
`shared/` subfolder, so the `<link>` tag 404'd. Because the entire
`:root` token block had been moved OUT of `style.css` and into the now-
unreachable file, every CSS custom property in the app went undefined
at once — the live site lost all styling (plain unstyled buttons, no
spacing, no colors) for any visitor until this was caught and fixed.

**Root cause, stated plainly:** introducing a new folder-structure
convention for two files, with no real subfolder consumer yet to
justify it, broke this project's one consistent deployment assumption
(everything flat) for no present benefit. The original reasoning for
"shared/" was preparing for the future `/admin/` bundle — but that
bundle doesn't exist yet, so there was no actual second consumer
requiring a relative path that works from two different directory
depths. The right call was to defer the subfolder until the moment
it's genuinely needed (when `/admin/index.html` exists and needs to
reach these files via `../design-tokens.css` or similar), not introduce
it preemptively.

**Fixed:** both files moved back to flat root-level paths
(`design-tokens.css`, `supabase-client.js`, no subfolder), `index.html`
and `app.js` updated to reference the flat paths, and every doc comment
that mentioned the old `shared/` path corrected for accuracy. Re-ran
the same end-to-end boot test as the original entry below, plus an
explicit grep across all four touched files confirming zero remaining
references to the broken path.

---

## 6c. Codebase separation, phase 1 — shared design tokens + client (2026-06-30)

**Where:** new `design-tokens.css`, new `supabase-client.js` — flat in
the repo root alongside every other file in this project (see the
correction above; an earlier version of this entry incorrectly put
these in a `shared/` subfolder, which broke production),
both referenced from `index.html`; `style.css` and `app.js` updated to
consume them instead of defining their own copies.

**The decision, and why it's right beyond just "the file is big":**
the real driver is the planned Flutter migration. When the parent-
facing app gets rewritten in Flutter, `index.html`/`app.js` retire
entirely — if the admin dashboard is physically tangled inside that
same bundle, untangling it mid-migration is far messier than
separating it now, while it's small. A web-only internal admin console
has no reason to ever become a native mobile app, so keeping it
independent means the Flutter migration never needs to touch it.

**The plan has four phases, agreed directly:**
1. Extract shared tokens/client (this entry — zero behavior change).
2. *(same step)* Verify nothing broke.
3. Stand up `/admin/` as its own `index.html` + `admin.css` + `admin.js`,
   port the dashboard over section by section.
4. Remove all admin code from the main bundle once `/admin/` is fully
   verified working, replacing it with a simple link.

**What's shared, and what's deliberately NOT:** only two things move
into `shared/` — design tokens (colors, type, radii, shadows) and the
Supabase client factory (URL + publishable key + the `createClient`
call). Both are things that should never be allowed to drift between
the two surfaces. Explicitly NOT shared: the session-check/boot flow
(`enterApp()`, `showAuthScreen()`) — that logic assumes specific
screens and element IDs (`#authScreen`, `#appRoot`) that won't exist in
a separate `admin.html`, and the admin dashboard's own boot sequence
should check for `system_admin` specifically before showing anything,
not reuse the parent app's generic "is there a session" check. Forcing
that into a shared file would have created the wrong kind of coupling
— this was a deliberate scoping decision, not an oversight.

**Verified the extraction didn't silently corrupt anything**, not just
that the files parse: did a byte-for-byte comparison of all 30 design-
token values between the original `:root` block and the extracted
file (confirmed zero mismatches) — necessary because jsdom's CSS engine
turned out to have no real support for resolving CSS custom properties
in `getComputedStyle` at all (confirmed via an isolated control test
using a single, unsplit file, which failed identically), so a
rendering-based check would have produced a false negative regardless
of whether the split was correct. For the client extraction, ran an
end-to-end boot test confirming `createGrowSenseClient()` is called
exactly once with the exact correct URL and key, and that the app
reaches the auth screen with no errors — not just that the constants
match textually.

**Next session:** phase 3, the actual `/admin/` bundle.

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
