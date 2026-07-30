# Supabase Edge Functions

Source of truth for every Edge Function running on the GrowSense project
(`ogpkmcqaulohexanucng`). These were **downloaded from the live project** and
committed so they have version history, review and rollback — previously they
existed only in the Supabase dashboard.

> **Committing this source does NOT deploy it.** The live functions are
> unchanged. Deploy is a separate, deliberate step (below).

## Functions

| Function | Model | Purpose | Sensitivity |
| --- | --- | --- | --- |
| `bone-age-analysis` | `claude-sonnet-4-6` | AI second opinion on a hand X-ray; returns a bone-age assessment. Body: `{ assessment_id, … }`. | **YMYL / medical** |
| `lab-ai-analysis` | `claude-haiku-4-5-20251001` | Cross-lab interpretation for parents. Body: `{ child_id }`. | **YMYL / medical** |
| `ai-coach-proxy` | `claude-sonnet-4-6` | Proxies the AI coach Q&A. | AI, non-diagnostic |
| `redeem-code` | — | Redeems an activation code; billing/entitlement logic. | Billing |
| `google-health-auth` | — | Google Health OAuth start/callback. | Auth |
| `google-health-sync` | — | Pulls wearable data from Google Health. | Data |
| `delete-account` | — | GDPR account + data deletion. | Destructive |

The two **medical** prompts (`bone-age-analysis`, `lab-ai-analysis`) generate
text a parent may act on. Treat every change to their prompt as a clinical
review, not a code tweak: diff it, and never let the model be silently
downgraded.

## Secrets — never commit these

All functions read secrets from `Deno.env`; nothing is hardcoded (verified).
They are set in the dashboard / CLI, not in this repo:

```
ANTHROPIC_API_KEY
SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
GOOGLE_HEALTH_CLIENT_ID, GOOGLE_HEALTH_CLIENT_SECRET, GOOGLE_HEALTH_REDIRECT_URI
ALLOWED_ORIGIN
```

## Working with these

Every function's entrypoint **must** be `supabase/functions/<name>/index.ts` —
that is the only path the CLI looks for. A differently-named file deploys as
`400 Entrypoint path does not exist`. Run these from the **repo root**, not
your home directory; the CLI resolves `supabase/functions/…` relative to the
working directory.

```bash
# Pull the current live source back down (overwrites local — commit first):
supabase functions download <name> --project-ref ogpkmcqaulohexanucng

# Deploy local source to live (deliberate; changes production):
supabase functions deploy <name> --project-ref ogpkmcqaulohexanucng
```

If a live function is ever edited in the dashboard, `download` it and commit so
this folder never drifts from production.
