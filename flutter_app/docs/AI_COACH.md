# AI Coach — library answers + live AI

The coach answers a parent's question about their own child. There are
two answer sources, and the difference is deliberate.

## Library first, model second

1. **Answer library** — `ai_coach_questions` (Supabase, source of truth)
   merged with two bundled asset batches. Each entry is a human-written
   template filled with this child's real data, and carries a
   `citation_source` **only** where the citation was web-verified.
2. **Live AI** — a model answer via the `ai-coach-proxy` Edge Function,
   used **only when the library has no match**.

Library answers are human-verified and carry real sources, so
re-answering them with a model would spend a credit to get a worse
answer. Credits go exactly where the library falls short.

> This differs from the PWA (`app.js`), which routes *every* question to
> the model when live mode is on. The Flutter behaviour is intentional;
> if the two are ever reconciled, reconcile toward this one.

Live answers render with a **"Live AI" chip and never a citation** — the
library's rule is that an unverified answer shows no source rather than
a fabricated one, and a generated answer is held to the same standard.

## Three conditions for a live answer

All must hold, or the parent gets the library's no-match message:

| Condition | Where |
|---|---|
| `system_settings.ai_coach_mode == 'live_ai'` | project-wide admin toggle (control tower) |
| Account is premium | `AppState.isPremium` |
| Tier cap is not 0 | `subscription_tier_limits.live_ai_monthly_cap` |

`aiCoachMode()` caches the mode per session, so an admin toggling it
takes effect on the next app start. Unlike the PWA — whose lookup
collapses RLS denial, a missing row, duplicate rows and a network error
into a silent `'template'` — the Flutter reader **logs which failure it
hit**. That silence cost a full debugging session; don't reintroduce it.

## The cap is enforced on the server

`supabase/functions/ai-coach-proxy/index.ts` is the real gate. It
verifies the session JWT, reads the tier's cap, and **increments
`live_ai_usage_monthly` before calling Anthropic**, so an abandoned
request still counts and the cap can't be gamed by opening and closing
requests. Clients may `SELECT` the usage tables but the 2026-07-28
migration revoked `INSERT/UPDATE/DELETE`, so the counter has exactly one
writer.

The Flutter side is the UX layer only: it shows the remaining count and
translates refusals. It is not a security boundary.

### Error contract

| Function response | Dart `reason` | What the parent sees |
|---|---|---|
| 403 `LIVE_AI_NOT_IN_PLAN` | `not_in_plan` | Live AI is part of Premium; library is free |
| 429 `MONTHLY_CAP_EXCEEDED` | `cap_exceeded` | Allowance used up, resets on the 1st |
| 401 | `session_expired` | Sign out and back in |
| anything else | `failed` | Couldn't reach the AI; library still works |

A refusal **never silently falls back to a template answer** — each case
tells the parent something they can act on.

## Model choice: Haiku, and why

The proxy calls `claude-haiku-4-5`. This is a cost decision, and the
arithmetic decides it. Assuming ~2,000 input tokens (system prompt plus
child context) and ~800 output:

| Model | $/MTok in | $/MTok out | Per question | × 50/month |
|---|---|---|---|---|
| `claude-sonnet-4-6` (previous) | $3.00 | $15.00 | ~$0.018 | ~$0.90 |
| `claude-haiku-4-5` (current) | $1.00 | $5.00 | ~$0.006 | ~$0.30 |

Premium is $5/month with roughly a $0.30 per-user AI ceiling, so Sonnet
put the 50-call allowance at about triple budget. A coach answer is a
short, grounded, single-turn reply — Haiku's job. Sonnet-tier stays
where the reasoning earns it: bone-age analysis and lab interpretation.

Re-check this table before raising the allowance or widening the prompt;
the success payload carries `growsense_model` so usage can be costed
without guessing what was deployed at the time.

## Grounding and rails

`coachSystemPrompt()` in `lib/coach_library.dart` builds the system
prompt from the **same** `buildCoachContext()` map the templates use, so
a generated answer can't contradict the rest of the app. The rails are
part of the prompt, not an afterthought:

- Use only the supplied facts; never invent a measurement, percentile or
  trend. If asked about data not supplied, say so and point at where it
  lives in the app.
- Never diagnose; never name a medication or dose.
- **Never cite** — no sources were supplied, and an invented citation is
  worse than none.
- Never say a child is "getting shorter"; children don't lose height.
  Slower growth is "growing more slowly".

## Deploying

```bash
supabase functions deploy ai-coach-proxy
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase secrets set ALLOWED_ORIGIN=https://www.growsense.life,https://cheetahokok-sudo.github.io
```

`ALLOWED_ORIGIN` is a **comma-separated allowlist** and must include
`https://www.growsense.life`, or the Flutter web build at `/app/` is
blocked by CORS — a failure that appears only in the browser console.
The native iOS app sends no `Origin` header and is unaffected either
way, so this breaks web while iOS looks fine.

## Known gap

Live answers are not yet grounded in food or activity history, so a
question like *"how much beef did he eat last month?"* gets an honest
"I can't see that" rather than an answer. Closing it means adding a
nutrition-history summariser to `buildCoachContext()` — the highest-value
next step for this feature.
