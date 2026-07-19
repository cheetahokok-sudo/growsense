# Health Story — Phase 0 Clinical Design Spec

**Feature (parent-facing):** Health Story
**Engine (internal):** Pattern Engine  · working codename *the Long Listen*
**Prevention/education strand:** Resilience
**Status:** Phase 0 — design only. No app code, no migration, no flag. This document is the deliverable of the crystallisation phase; it is meant to be handed to a paediatrician for review and iterated over weeks.
**Owner:** founder · **Last updated:** 2026-07-19

---

## 0. The one hard rule (claim boundary)

> **Health Story records patterns and hands them to a doctor. It never diagnoses, and it never claims to treat, prevent, or "boost" anything.**

Two words are banned from the product, the code, and the copy:

- **"Diagnosis" / naming a disease as fact** ("your child has asthma"). That is practising medicine and pushes us into Software-as-a-Medical-Device (SaMD) regulation. Every pattern output is framed as **"this is worth discussing with your doctor,"** never as a conclusion.
- **"Immune booster" / "boost immunity."** Unsubstantiated health-intervention claim, and the exact supplement-industry language our evidence-based brand exists to counter. The Resilience strand *educates* (sleep, nutrition, recovery), it does not intervene.

Two failure modes are equally forbidden:

1. **False verdict** — outputting a diagnosis.
2. **False reassurance** — the *absence* of a flag must never read as "all clear." Silence means "no recognised pattern in what was logged," nothing more.

Everything below serves these boundaries.

---

## 1. Why this feature is architecturally different

Every other GrowSense feature is a **transaction** (log a meal → see a chart). Health Story is an **accumulation** feature: its value is ~0 on day one and compounds over months. That single property drives three design decisions:

1. **Ship capture first, intelligence later.** The data clock only starts when logging ships. The slow, hard intelligence work must not block the capture layer. (See §7.)
2. **Know-normal-first.** Same principle as growth: establish the age-expected range *before* flagging anything. A frequency counter with no reference range is an anxiety machine — healthy young children get **6–8 viral colds a year, more in the first year and in daycare** [R5][R6].
3. **Config-as-data, not logic-in-code.** Pattern rules live in a reviewable config file (like `growth_evidence.json`, `who-reference-data.js`), so a clinician can audit them and thresholds can change without redeploying logic.

---

## 2. Data model

### 2.1 Core object: the **illness episode**

Log **episodes, not days.** An episode is a bounded illness event with a lifecycle: `suspected → active → resolved` (or `abandoned` if it fizzles). Days-based logging fragments the story; episode-based logging matches how a clinician thinks.

**`illness_episodes`**

| field | type | notes |
|---|---|---|
| `id` | uuid | pk |
| `child_id` | uuid | fk → children |
| `status` | enum | `suspected` \| `active` \| `resolved` \| `abandoned` |
| `onset_date` | date | first symptom (parent's best estimate) |
| `onset_precision` | enum | `exact` \| `approx_day` \| `approx_week` — recall honesty |
| `resolved_date` | date? | null while active |
| `primary_system` | enum | `respiratory` \| `ent` \| `gi` \| `febrile` \| `skin` \| `other` |
| `label_parent` | text? | parent's own words ("bad cold") — free text, never parsed as truth |
| `daycare_school_exposure` | bool? | context for frequency norms |
| `suspected_trigger` | enum[]? | `cold_air` \| `exercise` \| `pollen` \| `food` \| `contact_sick` \| `unknown` |
| `care_sought` | enum | `none` \| `pharmacy` \| `gp` \| `er` \| `admitted` |
| `source` | enum | `recorded` \| `recalled` — reuse recall-engine labels |
| `confidence` | enum | `high` \| `medium` \| `low` — reuse recall-engine labels |
| `created_at` / `updated_at` | timestamptz | |

### 2.2 Symptom sub-records (one episode → many)

**`episode_symptoms`**

| field | type | notes |
|---|---|---|
| `id` | uuid | pk |
| `episode_id` | uuid | fk |
| `symptom` | enum | see symptom vocabulary below |
| `severity` | enum? | `mild` \| `moderate` \| `severe` |
| `started_on` / `ended_on` | date? | within-episode timing |
| `detail` | jsonb | structured, symptom-specific (see §3) |

**`episode_temperatures`** (fevers are the highest-value, most-quantifiable signal — give them their own table)

| field | type | notes |
|---|---|---|
| `episode_id` | uuid | fk |
| `measured_at` | timestamptz | |
| `temp_c` | numeric | |
| `route` | enum | `axillary` \| `oral` \| `tympanic` \| `rectal` \| `forehead` — route changes interpretation |

**`episode_medications`** (what was given, how much, and whether it helped — the response is clinically meaningful, and the *cumulative* record is a distinct value in its own right, see §2.5)

| field | type | notes |
|---|---|---|
| `episode_id` | uuid | fk |
| `medication` | text | free or picklist (e.g. "Meiact", "Bilaxten", "Zyrtec") |
| `class` | enum? | `antipyretic` \| `antibiotic` \| `bronchodilator` \| `antihistamine` \| `steroid` \| `other` |
| `dose_amount` | numeric? | **recorded exactly as entered by the parent — the app never suggests or computes a dose** |
| `dose_unit` | enum? | `mg` \| `ml` \| `drops` \| `puffs` \| `sachet` \| `other` |
| `frequency` | text? | e.g. "twice daily", "as needed" — free/picklist |
| `duration_days` | int? | intended or actual length of the course |
| `doses_given` | int? | running count for an in-progress course ("3 doses so far") |
| `prescribed_by` | enum? | `doctor` \| `pharmacy` \| `self` \| `unknown` |
| `started_on` / `ended_on` | date? | anchors the exposure timeline |
| `response` | enum? | `resolved` \| `improved` \| `no_change` \| `worsened` — with `response_day` int? for *when*. Wheeze improving after a bronchodilator is a pattern input; an antibiotic course with `no_change` is often *more* informative to a clinician than one that "worked" |

> **Framing rule — "improved after ≠ improved because of."** `response` records a temporal association only. The engine and all copy must present it as **"improved _after_ X,"** never **"improved _because of_ X"** or **"X works for your child."** Most childhood infections are viral and self-resolve, so post-medication improvement is confounded by natural recovery — the same post-hoc trap the blog covers for supplements and seasonal growth. For any `antibiotic` response, attach the standing note: *"most childhood infections clear on their own; whether an antibiotic changed the course is a question for your doctor."* This guards the parent against reading "got better on the antibiotic" as proof it was needed — a real driver of antibiotic overuse in the target markets.

### 2.3 Symptom vocabulary (controlled enum — extend deliberately)

`fever, cough, wheeze, breathing_difficulty, runny_nose, congestion, sore_throat, ear_pain, mouth_ulcers, swollen_glands, rash, eczema_flare, hives, vomiting, diarrhoea, abdominal_pain, poor_feeding, lethargy, other`

### 2.4 Reuse, don't reinvent

- **Source/confidence labels** come straight from the `[[nutrition-recall-engine]]` — recorded vs recalled, high/medium/low. Missingness is data; a transparent gap beats false precision.
- Episodes render on the existing **trust-calendar timeline**.
- Episodes overlay on the existing **growth curve** (the differentiator — see rule P6).
- The output surfaces through the existing **Visit PDF**.

### 2.5 Cumulative medication exposure (a derived rollup, not a table)

Individual medicine records are one value; the **multi-year sum across episodes** is a second, distinct one — the thing no parent can hold in their head and no 3-minute appointment reconstructs. Computed on the fly from `episode_medications` grouped by `class`, e.g.:

- **Antibiotics:** number of *courses* and total *days on antibiotics* per rolling 12 months and since birth (course count, not pill count, is the clinically meaningful unit).
- **Antihistamines / steroids / others:** total days of exposure and recurrence pattern (e.g. "needed every rainy season for 3 years").

**Claim boundary — total and surface, never adjudicate harm.** This rollup is arithmetic on logged data; it is honest to *count* and to say "worth reviewing with your doctor." It must **never** state or imply that a cumulative dose *caused* harm — that is a diagnosis. For allergy medicines the useful signal is usually the **recurring need** (a persistent allergy worth managing properly), not the tally; for antibiotics it is **course frequency** for stewardship review [R2][R8]. Chronic doctor-guided use of a second-generation antihistamine for a genuine allergy is common and is *not* something the app should alarm about — it should surface the *pattern*, and let the clinician judge the exposure.

---

## 3. Guided-questionnaire flow

The engine's job at capture time is to **take a structured history the way a good triage nurse would** — adaptive, minimal free-text, asked while it's fresh. This is what fights recall bias: parents cannot reliably reconstruct "how many fevers, how high, how often" months later at a 3-minute appointment [R4].

### 3.1 Principles

- **Adaptive branching:** only ask what's relevant to the chosen `primary_system`. Never a 40-question wall.
- **Structured over free-text:** pickers, ranges, counts — free text is captured but never parsed as clinical truth.
- **Log-at-the-moment > retrospective:** push a gentle "how is [child] today?" follow-up while an episode is `active`; retrospective entries get `confidence: low`.
- **Two entry points:** (a) start a new episode; (b) add to the active episode.

### 3.2 Intake trees (per system)

**Febrile**
1. Highest temperature? (value + `route`) → 2. How measured? → 3. How many days has fever come and gone? → 4. Any fevers in the last 6 weeks? *(periodicity probe — feeds P4)* → 5. Well between fevers? → 6. Mouth ulcers / sore throat / swollen glands with it? *(PFAPA cluster)*

**Respiratory**
1. Cough: wet / dry? day / night / both? → 2. Any wheeze (whistling)? → 3. Fast or laboured breathing? *(→ if yes, safety interstitial: "breathing difficulty needs same-day medical attention")* → 4. Triggered by cold air / exercise / a cold? *(feeds P2)* → 5. Given an inhaler/bronchodilator — did it help? *(→ `episode_medications.response`)*

**ENT** — ear pain? which side? discharge? hearing change? *(feeds ear-infection frequency, P5)*

**GI** — vomiting/diarrhoea frequency; blood; hydration (wet nappies / urination); feeding.

**Skin** — eczema flare? hives? location; relation to a food or contact. *(feeds atopic-march, P3)*

**Triggers & context** (all systems) — daycare/school exposure, known sick contacts, suspected food, season.

### 3.3 Safety interstitials (hard-coded, not rules)

Certain answers **short-circuit to "seek care now"** regardless of pattern logic: laboured/fast breathing, blue lips, stiff neck, non-blanching rash, severe dehydration, seizure, infant < 3 months with any fever. These are red-flag safety-netting, shown immediately, never deferred to the engine.

---

## 4. Pattern-flag rules (config-as-data)

Rules live in `health_patterns.json` (Phase 2). Each rule is **deterministic, windowed, cited, and humble.** The engine only *reads* episodes; it never writes conclusions into the record.

### 4.1 Rule schema

```json
{
  "id": "P2_recurrent_wheeze",
  "title": "Recurrent wheeze pattern",
  "inputs": ["wheeze episodes", "triggers", "bronchodilator response", "eczema history"],
  "window_months": 12,
  "threshold": "≥3 wheeze episodes, or wheeze with consistent cold-air/exercise trigger",
  "flag_text": "Your child has had several wheezing episodes, often with {triggers}. This pattern is worth discussing with your doctor.",
  "action": "discuss",
  "never": "Do not state or imply asthma.",
  "references": ["R1"],
  "limitations": "Mirrors the *inputs* of the Asthma Predictive Index, not its verdict. The API predicts risk with modest positive predictive value and was built for research cohorts; many wheezy toddlers never develop asthma."
}
```

Every rule carries `action: "discuss"`, a `never:` guard, `references[]`, and an explicit `limitations` string. **A rule without a limitations field does not ship.**

### 4.2 The rules

**P0 — Frequency context (runs first, gates the others).**
Before any flag, compare infection count to the age- and exposure-expected range. Young children average **6–8 colds/year (more in infancy and daycare)** [R5][R6]. Output is *reassuring context by default* ("this is within the usual range for a [age] in daycare"), and only escalates when genuinely above range. *Limitation:* counts depend on parent logging completeness; under-logging hides burden, over-logging inflates it.

**P1 — Periodic fever / PFAPA pattern.**
Trigger: ≥3 fevers at **regular intervals (~every 3–6 weeks)**, child well between, often with pharyngitis / aphthous ulcers / adenitis, normal growth. The *clockwork periodicity* is the diary-only signal — the single best showcase for "the log caught what memory couldn't." Flag: "worth discussing periodic fever." [R7] *Limitation:* PFAPA is a diagnosis of exclusion; periodicity has other causes; interval regularity is often imperfect. Clinician required.

**P2 — Recurrent wheeze.** (schema example above) [R1]

**P3 — Atopic co-occurrence (atopic march).**
Trigger: infantile eczema + later recurrent wheeze and/or persistent rhinitis. Flag: "these often travel together (the 'atopic march') — worth discussing with your doctor." [R3] *Limitation:* a risk association, not deterministic; many children with eczema never progress.

**P4 — Frequency above expected range.**
Trigger (adapted from published immunodeficiency warning signs): e.g. **≥4 new ear infections in 1 year; ≥2 serious sinus infections in 1 year; ≥2 pneumonias in 1 year; ≥2 months of antibiotics with little effect; recurrent deep abscesses; persistent thrush after age 1; failure to thrive alongside infections; need for IV antibiotics/hospitalisation to clear infections; family history of primary immunodeficiency.** Flag: "the *number/type* of infections is above what's usual — worth mentioning to your doctor." [R2] *Limitation (must be shown):* the "ten warning signs" have **limited sensitivity and specificity** — they miss cases (especially antibody deficiencies) and over-flag ordinary daycare children; the most discriminating signals are **family history, failure to thrive, and need for IV antibiotics/sepsis** [R2]. Never reassure on their absence.

**P5 — Recurrent ENT infections.** Subset of P4, surfaced for the ear/sinus cluster with the same limitation.

**P6 — Illness burden × growth (the differentiator).**
Trigger: clusters of illness episodes coinciding with a low six-to-twelve-month height-velocity window (from existing WHO growth data). Flag: "these illnesses clustered around a slower-growth stretch — worth discussing whether illness burden is affecting growth." This is the honest, on-mission link (infection competes with growth; already taught in the blood-test and seasonal articles). *Limitation:* coincidence ≠ causation; correlation over one window is weak; needs clinical read alongside velocity and nutrition.

**P7 — Recurrent medication need / cumulative exposure (from §2.5 rollup).**
Two sub-triggers, both framed as review prompts, never harm claims:
- *Recurrent allergy-medicine need:* repeated antihistamine/steroid courses for rash/rhinitis across seasons or years. Flag: "your child has needed allergy medicines repeatedly over [period] — worth discussing whether there's an underlying allergy to manage, rather than treating each flare." (Links to P3 atopic march.)
- *Frequent antibiotic courses:* course count above the usual for age over a rolling window / since birth. Flag: "your child has had [N] antibiotic courses in [period] — worth reviewing with your doctor, both for whether each was needed and for antibiotic stewardship." [R2][R8]
*Limitation (must be shown):* this counts exposure, it does not judge it. Chronic doctor-guided antihistamine use for a real allergy is normal and not a concern in itself; "improved after" an antibiotic never proves it was needed (see the §2 framing rule). Course/exposure norms vary by condition and region — the flag is a prompt for a clinician, never a verdict that the child was over-medicated or harmed.

### 4.3 Output ordering

`P0 context → safety interstitials (already shown at capture) → any P1–P7 flags → visit summary`. Reassuring context leads; flags follow; nothing is a verdict.

---

## 5. Output contract

1. **Visit-ready summary** (Visit PDF): "N months of structured illness history for your appointment" — episode timeline, fever log, frequency vs age norm, medications + responses. *This alone justifies the feature.*
2. **Flags as questions**, never answers. Copy is always "worth discussing," with the plain-language pattern and the trigger data behind it.
3. **Frequency context** against age/exposure norms — reassurance is a first-class output, not just alarms.
4. **Illness-on-growth overlay** — episodes rendered against the growth curve.
5. **Medication-response line** — per-episode, "improved *after* X" phrasing only (never "because of"); antibiotic responses carry the standing viral-illness note from §2. This is the medical-memory the doctor most values.
6. **Cumulative-exposure line** (from §2.5) — e.g. "antibiotics: N courses / ~N days since birth (M in the last 12 months); antihistamines: recurring each rainy season for 3 years." Framed as "worth reviewing," with counts only — never a harm claim.

**Non-negotiables:** no diagnosis; no "boost"; absence-of-flag ≠ all-clear; sparse/low-confidence data is shown as such (never smoothed into false precision); AI (existing Haiku/Sonnet) may **summarise and cite only** — it may not generate a pattern conclusion outside the deterministic config.

---

## 6. Data quality & honesty

- **Recall bias is the core problem this feature fights** — and is also its own risk. Parent recall of symptom counts degrades over weeks [R4]. Mitigations: episode-based capture, active-episode nudges, `source`/`confidence` labels, `onset_precision`.
- The summary must **show its own completeness** ("logged 6 of an estimated ~8 episodes") rather than imply totality.
- Under-logging is the default failure; the engine should never treat "few episodes logged" as "few episodes occurred."

---

## 7. Architecture & sequencing

**The `illness_episodes` table is the seam** that decouples two layers moving at different speeds:

| Layer | Contents | Risk | Cadence | Maps to existing |
|---|---|---|---|---|
| **Capture** | tables §2 + questionnaire §3 + logging UI | low, additive | ship early behind a flag | migration + Flutter screens |
| **Intelligence** | rules §4 + outputs §5 | the months-long work | read-only; iterate forever | edge function, like `lab-ai-analysis` / `bone-age-analysis` |

Because intelligence only **reads** episodes, it can be rewritten indefinitely without touching capture or destabilising the app. No long-lived feature branch: small PRs to `main` behind a feature flag; this design doc needs no branch at all.

**Phase plan**
- **Phase 0 (this doc):** clinical spec + draft `health_patterns.json`. Ships nothing. Hand to a paediatrician.
- **Phase 1 — Capture (flagged):** migration + questionnaire + logging. Starts the data clock.
- **Phase 2 — Intelligence (read-only edge fn):** rules config + visit summary + flags + growth overlay.
- **Phase 3 — Beta + clinician review:** enable for a few families; refine `health_patterns.json` against real (anonymised) episodes.

---

## 8. Open questions / hypotheses to test (before any flag ships)

- **H-A (capture viability):** will parents actually log episodes with enough completeness for P0 frequency context to be trustworthy? *Test in Phase 1 with real logging rates.*
- **H-B (periodicity detectability):** does episode logging capture fever intervals cleanly enough to surface a PFAPA-like pattern? *Simulate against known-periodicity test data.*
- **H-C (growth link, P6):** do logged illness clusters actually co-locate with low-velocity windows in our own data? *Retrospective check before enabling the flag.*
- **H-D (clinician trust):** would a paediatrician accept the visit summary and the flag wording as helpful rather than noise? *Direct review, Phase 0/3.*
- **Regulatory:** confirm the "record + flag, never diagnose" framing keeps us in general-wellness scope in target markets; legal review before Phase 3. Children's-data consent flow required.

---

## 9. References (verified against PubMed, 2026-07-19)

- **[R1]** Castro-Rodríguez JA, Holberg CJ, Wright AL, Martinez FD. A clinical index to define risk of asthma in young children with recurrent wheezing. *Am J Respir Crit Care Med.* 2000;162(4 Pt 1):1403–1406. PMID: 11029352.
- **[R2]** Arkwright PD, Gennery AR. Ten warning signs of primary immunodeficiency: a new paradigm is needed for the 21st century. *Ann N Y Acad Sci.* 2011;1238:7–14. PMID: 22129048. *(source of the warning signs AND their limited sensitivity/specificity)*
- **[R3]** Schneider L, Hanifin J, Boguniewicz M, et al. Study of the Atopic March: Development of Atopic Comorbidities. *Pediatr Dermatol.* 2016;33(4):388–398. PMID: 27273433.
- **[R4]** Heyer GL, Merison K, Rose SC, et al. Comparing patient and parent recall of 90-day and 30-day migraine disability. *Cephalalgia.* 2014;34(4):298–306. PMID: 24126944. *(parent recall of symptom frequency degrades over time)*
- **[R5]** Heikkinen T, Järvinen A. The common cold. *Lancet.* 2003;361(9351):51–59. PMID: 12517470. *(normal cold frequency in children)*
- **[R6]** Chonmaitree T, Revai K, Grady JJ, et al. Viral upper respiratory tract infection and otitis media complication in young children. *Clin Infect Dis.* 2008;46(6):815–823. PMID: 18279042. *(URI frequency cohort, infancy/daycare)*
- **[R7]** Marshall GS. Prolonged and recurrent fevers in children. *J Infect.* 2014;68 Suppl 1:S83–S93. PMID: 24120354. *(periodic fever / PFAPA pattern and its differential)*
- **[R8]** Aversa Z, et al. Association of Infant Antibiotic Exposure With Childhood Health Outcomes. *Mayo Clin Proc.* 2021;96(1):66–77. PMID: 33208243. *(rationale for surfacing cumulative early-life antibiotic exposure — association only, not causation)*

> All PMIDs confirmed via PubMed eutils on 2026-07-19. The Jeffrey Modell Foundation "10 Warning Signs" is a clinical screening tool, not a single indexed trial; it is represented here via its scholarly reappraisal [R2], which is also the source for its documented limitations. No citation in this document is unverified.
