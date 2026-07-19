# Reel / short-video standard — the brief before any video is produced

**Purpose:** turn a GrowSense blog article into a 30–50s reel (Instagram / YouTube Shorts) WITHOUT losing the credibility that is the brand's whole edge. This doc is the brief that must exist *before* any footage is generated or assembled. Owner: founder. Last updated: 2026-07-19.

## The one rule that keeps us credible: four layers, always separated

Every reel must keep these four things distinct — never blur them into a single overreaching claim:

1. **The guideline** — what an authority actually recommends (quote the wording).
2. **The study** — the exact population, intervention, dose, duration and outcome.
3. **The parent translation** — what families can reasonably do.
4. **The limitation** — what the study did *not* prove.

A hook can be strong; it can never cross into a claim the source doesn't support. If a line can't be traced to one of the four layers, it doesn't ship.

## Accuracy guardrails (learned from real mistakes)

- **Don't imply the opposite of the guideline.** "60 minutes isn't a rigid nightly pass/fail" is right; "kids don't need daily movement" is wrong — WHO still encourages daily activity. State the nuance, not the inversion.
- **Don't invent comparisons the study never made.** The Fuchs jumping trial did *not* compare jumping to "an hour of walking" — so never say "a few minutes of jumping beats an hour of walking." Walking and jumping serve different purposes.
- **Represent the study honestly:** population, dose, duration, the *specific* sites/outcomes, and effect size as measured — not a rounded-up general version.
- **Put the source on screen.** A visible citation line is the differentiator vs. every other parenting reel. Author + journal + year, e.g. "Fuchs RK et al. J Bone Miner Res. 2001."
- **Conservative beats catchy** when they conflict. A slightly smaller true number outlasts a punchy false one.

## Production rules (how we hit house standard, NOT how we lose it)

- **Assemble, don't AI-generate.** Build the reel in a real editor (CapCut / Descript) from real footage + real app-screen recordings + clean text overlays. A text-to-video model (ChatGPT/Sora/Higgsfield) cannot render correct on-screen text, our brand colour, or our actual app — and morphs people. It failed on the first attempt for exactly these reasons.
- **Never AI-generate children or clinical scenes.** For a paediatric health brand this reads as uncanny/misleading and erodes trust. Use real stock (Pexels/Storyblocks) or the real app.
- **Real app footage is the most trust-building shot** — the growth curve, the weekly activity view. Show the actual product.
- **Muted-first:** on-screen text must carry the whole story without sound (majority watch muted). Voiceover (ElevenLabs or a real voice) is a bonus layer.
- **Brand:** GrowSense green `#2F6B4F`; calm, warm, uncluttered; sentence case; no shouty hype.
- AI video (if ever) is a minor abstract accent only — never the substance, never people, never text.

## Prompting an AI video model (Veo / Sora / etc.) — hard rules

Learned from a real Veo attempt (garbled `#2F6B4F` on every chart; a fake app screen full of gibberish):

1. **Strip production notes from any video prompt.** Feed the model ONLY the visual scene + the exact on-screen text you want shown. NEVER put hex codes, pixel safe-zones, or assembly instructions in the prompt — the model renders them literally as garbled on-screen text (it drew "#2F6B4F" as a chart label and "…250 pixel amd 250 pixe safe zone" as a caption). **Describe colour in words** ("deep muted forest-green"), never as a hex code.
2. **Never AI-generate the app screen.** The model invents a fake GrowSense app with nonsense labels (real failure: it rendered "Total cumpol meekly tenst", "Oreents", "Actrooires"). The product beat is ALWAYS a real screen recording. The real app is the single most trust-building shot — AI can only forge a broken imitation.

Corollaries:
- **10-second cap → produce as ~5 clips of ~10s**, then assemble in CapCut. This also gives per-shot re-gen control and lets the app clip be a real recording.
- **Generate vertical (1080×1920) directly** — don't let it export 720p landscape with a pillarboxed insert.
- **Keep on-screen text to one short line per clip** (models garble long text); add precise numbers and the citation as clean CapCut overlays if the model mangles them.
- Assume a watermark; trim/cover it in CapCut.

## Worked reference: "The 60-minute myth" (verified)

- **Guideline (WHO 2020, Bull FC et al. Br J Sports Med. PMID 33239350):** ages 5–17, an *average* of ≥60 min/day of moderate-to-vigorous activity *across the week*, with vigorous + muscle-strengthening + bone-strengthening activity on ≥3 days/week. Nuance: it's a weekly average, not a nightly pass/fail — daily movement is still encouraged.
- **Study (Fuchs RK, Bauer JJ, Snow CM. J Bone Miner Res. 2001. PMID 11149479):** 89 prepubescent children aged 5.9–9.8; jumping group did 100 two-footed jumps off 61-cm boxes, 3×/week, for 7 months. Primary outcome (bone mineral *content*) rose **+4.5% at the femoral neck and +3.1% at the lumbar spine** vs controls (secondary BMD: lumbar spine +2.0%).
- **Parent translation:** build a varied week — move often, work hard sometimes, and include short bouts of jumping / running / multidirectional sport a few times a week to load bone.
- **Limitation:** ~90 prepubescent kids, one 7-month trial, effects at *selected* hip/spine sites; it did not compare jumping with walking, and doesn't generalise to all ages or "stronger bones" overall.

On-screen effect-size line should read **"≈3–4% more bone at the hip and spine (vs. a non-jumping group)"** — the primary outcome, honest and labelled — not a bare "2% stronger bones."
