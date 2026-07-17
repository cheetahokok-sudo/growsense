# Height measurement — data quality spec

**Status:** design notes, not built.
**Origin:** split out of the GS-058 blog draft (`measure-height-accurately-at-home`).

> **This file is internal.** It was drafted inside a public blog article and
> removed before publication. It contains positioning, roadmap and marketing-claim
> boundaries — none of which belong on a page a parent reads. Keep it here.
>
> The published article covers the *protocol* and the *evidence*. This covers what
> the product does with the result.

## Why this exists

Everything downstream — velocity, percentile trends, the bone-age-to-calendar gap
— is arithmetic on a single number a parent typed in. It cannot be more reliable
than that input, and today we store the input as if it were exact.

The evidence the article is built on (all PMIDs verified against PubMed):

| Finding | Source |
| --- | --- |
| Height falls a mean **0.47 cm** morning→afternoon; individuals **+1.8 to −2.7 cm**. Authors recommend recording time of day. | Siklar 2005, PMID 16354217 |
| Stretching does **not** reliably cancel diurnal loss. | Voss 1997, PMID 9389235 |
| Parent vs hospital: mean bias only **−0.30 cm**, but 95% limits **−1.26 to +0.66 cm**. Good average, unreliable single reading. | Remmits 2024, PMID 37843612 |
| Parent accuracy rises with more detailed instruction. | Patel 2024, PMID 37967393 |
| Height **velocity** stays imprecise even when individual heights look fine. | Voss 1991, PMID 1863094 |
| Clinic audit: **none** of 34 staff followed all guidelines; **50%** sometimes enter reported height; **18%** of patients had ≥2 cm swings in 3 months; TEM 1.77 cm; 9% of stadiometers off by >1.5 cm. | Mikula 2016, PMID 27207559 |
| No portable digital device removes the need for controlled positioning/training. | Soller 2023, PMID 37494355 |

**Design consequence:** a height row must carry its own provenance and a confidence
grade, and low-confidence rows must not silently become growth velocities.

## Fields to store per measurement

Beyond the single `height_cm` we store today:

- `reading_1`, `reading_2`, `reading_3` — raw, unaveraged
- `mean_cm` — what we display
- `spread_cm` — max − min across readings (the quality signal)
- `measured_at` — date **and time** (diurnal variation makes time load-bearing)
- `device_id` → device registry (below)
- `measured_by` — different measurers carry different bias
- `barefoot` — bool
- `surface` — hard / carpet / unknown
- `confidence` — high / moderate / low (derived, see below)
- `notes` — posture, hairstyle, cooperation

## Confidence grading

**High** — 3 readings · spread ≤0.2 cm · same device as previous · time within the
family's usual window · barefoot · no positioning warnings.

**Moderate** — spread 0.3–0.5 cm · time differs substantially from usual · different
measurer · device moved or reinstalled.

**Low** — single reading · spread >0.5 cm · shoes on · soft floor · unknown device ·
device changed since last measurement · result implausible vs recent trend.

Low-confidence rows stay **visible** in the record — they are not deleted or hidden.
They simply must not trigger a velocity alert.

## Rules

1. **Three-reading capture.** Prompt for three; compute mean and spread. Never let
   the parent hand-pick one.
2. **Repeatability gate.** Spread >0.2 cm → warn and offer to re-measure; >0.5 cm →
   grade low.
3. **Same-hour reminder.** Learn the family's window; schedule inside it; surface the
   time on the chart.
4. **Device registry.** Brand, model, install date, calibration checks.
5. **Device-change marker.** A visible discontinuity on the chart when the device
   changes — a device switch is a new baseline, never a growth event.
6. **Velocity protection.** Do not compute or highlight velocity from low-confidence
   rows, or across a device change, or over intervals too short to clear the noise.
7. **Clinician export.** Raw readings, mean, spread, times, device, confidence —
   not a smoothed line.
8. **Photo posture check** *(later, consent-gated)*. Side-view frame to flag chin
   tilt / raised heels / non-level headpiece. Evaluates **posture only** — must never
   estimate height from an image.

## Positioning

**Do not say "clinic-grade" or "hospital-level".** Aiming at the clinic is aiming at
the wrong target — Mikula shows routine clinic measurement is itself unreliable, and
the claim is both unverifiable and easy to disprove.

The defensible promise is about *process*:

> A repeatable protocol, honestly graded.

**Defensible:** guided measurement · repeatability and posture checks · same-time
reminders · automatic averaging and outlier detection · measurement-quality scoring ·
records built to hand to a clinician.

**Requires validation we do not have:** "medical-grade accuracy" · "accurate to 1 mm" ·
"equivalent to hospital measurement" · "detects growth disorders" · "predicts final
height" · "replaces paediatric assessment".

Our edge is surfacing uncertainty, not hiding it behind a smooth line.

## Deliberately not in the article

Device brand comparisons (Seca / Charder / Holtain / InBody), supplier-channel
analysis and hospital-service positioning were cut from the public draft. Naming
models with unverified manufacturer specs turns an educational page into a buyer's
guide, invites affiliate suspicion, and undermines the E-E-A-T the library is built
on. The article keeps *categories* only: proper stadiometer / prepared wall station /
not suitable for velocity. If we ever want a device guide, it should be its own page
with specs verified against manufacturer documentation — not folded into this one.
