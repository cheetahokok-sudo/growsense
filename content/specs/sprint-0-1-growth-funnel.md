# Growth Funnel — Build Spec (two-track, reality-matched)

The executable version of the GTM proposal's first sprints. Goal: wire the funnel that
already half-exists — great content + great product, nothing connecting them.

> **Honest framing.** The proposal says "days." That is true for the **web/blog half** and
> false for the **app half**. So this spec runs **two tracks on two clocks**. Track A ships
> on a days clock and does not depend on the app. Track B is real feature work across two
> codebases and gets its own honest window. The funnel is only as real as its slower half —
> don't let "days" morale-language hide Track B.

---

## Track A — Web / Blog  ·  days clock  ·  ships independently

No app dependency. Every item here is shippable now and earns value even before Track B lands.

### A1 · Free tools (the lead magnets) — Days 1–8
Standalone Astro pages under `web/src/pages/*.astro` → `/blog/*.html`, reusing the app's own
verified math so tool = app.

- [x] **Height percentile calculator (EN)** — `web/src/pages/height-percentile-calculator.astro`.
      Reuses `who-reference-data.js` + `growth-percentile.js`. Verified: Boy 8yr 127.3 cm → 50th, z 0.
- [ ] **Mid-parental height predictor (EN)** — `web/src/pages/mid-parental-height-predictor.astro`.
      mid-parental = (mother+father)/2; boys **+6.5 cm**, girls **−6.5 cm**; target range ≈ ±8.5 cm.
      Honesty: a genetic-potential **range**, not a prediction; bone age, puberty timing, nutrition move it.
- [ ] **Thai + Chinese versions of BOTH tools** — *blocking for the Thailand beachhead.* Driving
      LINE/creator traffic to an English-only tool wastes the beachhead. TH first, ZH next.

Every tool already fires `tool_view` / `tool_result` (band-level only) / `app_link_click` as
**no-ops guarded by `window.posthog`** — they light up automatically the moment Track B adds the key.

### A2 · The blog routes, not just informs — Days 3–6
- [ ] Upgrade the article `cta` in `ArticleLayout.astro` to deep-link the **module the article is about**,
      with UTMs (see convention). Map per cluster: bone-age→`open=boneage`, sleep/growth→`open=measure`,
      labs→`open=labs`.
- [ ] Soft mid-article inline prompt component (not only the footer CTA).
- [ ] Blog analytics: PostHog snippet in `ArticleLayout.astro` + tool pages (autocapture + `article_view`).
      *(Web-only capture works before Track B — you'll see traffic and outbound clicks immediately.)*

### A3 · Content cadence (the fuel — do NOT drop this) — ongoing
Organic compounding **is** content volume; the proposal's 30→120 only happens if production is scheduled.
- [ ] **~2–3 new articles / week**, trilingual, clustered with internal links (target ~120 by month 6).
- [ ] **1 new tool or one tool-localization per sprint.**
- [ ] Prioritize high-intent, low-competition parent queries (per-country norms, "is X cm normal at Y").
Without a cadence the flywheel has no fuel — treat this as a standing commitment, not a phase.

---

## Track B — App instrumentation  ·  weeks clock  ·  the real critical path

This is the honest bottleneck. It is feature work across **PWA (`app.js`) and Flutter**, not Day-1 config.
Budget **~2–4 weeks**, not 3 days.

### B1 · One analytics brain
- [ ] Create ONE PostHog project. *(User step — needs an account; drop the key into config and I wire it.)*
- [ ] Init in PWA + Flutter; `identify(userId)` on login and `alias` anon→known at signup, so a parent is
      ONE profile from first article to first payment.

### B2 · Events (the six that matter)
```
article_view       { slug, lang, cluster }          // Track A, web
tool_view          { tool, lang }                   // Track A, web
tool_result        { tool, sex, age_band, percentile_band }   // bands only — NO exact height/DOB
app_link_click     { source_slug, cta_position, target_module, utm_campaign }  // Track A, web
app_first_open     { utm_source, utm_medium, utm_campaign }    // Track B, app
first_measurement  { }                              // ACTIVATION — the metric that matters early
paywall_view       { feature }
subscribe_success  { plan }
```

### B3 · Inbound deep-links + attribution capture
- [ ] App handles `?open=measure|boneage|labs|today` on launch → routes to that screen.
      *(This is a feature, not a flag — verify the app can even route to a module from a URL today.)*
- [ ] On first load, read UTMs → `localStorage.gs_acq` → on signup write to Supabase `acquisition_source`.
- [ ] Supabase migration:
```sql
alter table public.children add column if not exists acquisition_source jsonb;
-- {"utm_source":"blog","utm_medium":"tool","utm_campaign":"height-percentile-calculator",
--  "self_reported":null,"first_seen":"<iso>"}
```

### B4 · Install prompt
- [ ] PWA `beforeinstallprompt` on the app origin; tools/articles route to it.

---

## iOS / native attribution — the decision (make it now, not in Sprint 3)

**The problem:** `localStorage.gs_acq` only survives when the app is the **same-origin PWA**. The
moment a parent installs the **native / App Store app**, the UTM is lost across the install boundary
(the classic deferred-deep-link problem). If we ignore this, "see reader → install → paid" is only
half-true.

**The decision (chosen): PWA-first measured, self-reported for native. No paid SDK yet.**
- **PWA path** → fully measured end-to-end via UTM + localStorage. This is the primary funnel we optimize.
- **Native / App Store path** → a single, required **"How did you hear about us?"** question at
  onboarding, mapping to the *same* `utm_source` taxonomy (blog / LINE / creator / search / friend…).
  Written to `acquisition_source.self_reported`. Modeled, not measured — and honest about it.
- **Deferred-deep-link SDK (Branch/Adjust)** → **deferred** until native installs clear ~500/mo.
  Below that, the fee and integration cost aren't worth it; the onboarding question is enough signal.

> Consequence for reading the data: PWA channels get exact attribution; native channels get a
> self-reported estimate. Never blend them into one "CAC by channel" number without labelling which
> is measured vs. modeled.

---

## Reading the funnel — staged, honest metrics

Traffic is small today, so the bottom of the funnel is thin. Don't over-read early numbers.

| Stage | The honest KPI **now** | Becomes meaningful when |
| --- | --- | --- |
| Early (Sprints 0–1) | **Install-rate & activation (`first_measurement`) by article/tool** | immediately — decent n at the top |
| Mid (Sprint 2) | Activation + **D7/D30 retention**; free→paid **directional only** | a few hundred activations |
| Late (Sprint 3) | free→paid, LTV:CAC, "kill losers / double winners" | `subscribe` events reach double digits per channel |

North star stays **retained paying families** — but it's a *destination*, not a Sprint-3 readout.
Judge Sprint 3 on whether the **activation** path is healthy, not on tiny subscription counts.

---

## Privacy — PDPA (Thailand), because trust is the whole brand
- Autocapture + `identify` on health-adjacent content about **children**, in a PDPA jurisdiction,
  needs a **consent posture** (analytics consent on the blog; clear purpose; opt-out honored).
- Extend the band-level discipline everywhere: a child's exact measurements stay on-device;
  analytics sees bands and events, never raw values. This is a brand asset, not just compliance.

---

## Honesty rails (carry from the blog)
- Tools are a **screen, not a diagnosis**; one point is a snapshot, growth is the curve over time.
- Below 3rd / above 97th, or a dropping curve → "worth a check with a pediatrician," never alarm.
- Never present a predicted adult height as fact — it's a range shaped by many factors.
- Band-level data only leaves the device; exact measurements never do.

---

## Sequencing at a glance
1. **Now (Track A):** ship tools EN → build predictor → localize TH/ZH; upgrade article CTAs; blog analytics.
2. **Now, in parallel (decision):** lock the iOS attribution answer above.
3. **Weeks 1–4 (Track B):** app instrumentation, deep-link routing, `acquisition_source`, install prompt.
4. **Standing:** content cadence, every week, forever.
5. **Then:** beachhead (LINE + creators to the **localized** tools) → monetize → read **activation** first.
