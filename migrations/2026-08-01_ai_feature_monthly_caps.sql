-- ════════════════════════════════════════════════════════════════
-- Per-feature monthly AI caps: bone-age (Sonnet+vision, the pricey
-- one) and lab AI (Haiku). Abuse bounds, not pricing — normal use
-- never touches them. Deliberately separate caps, NOT a shared pool
-- with the coach's 50: a parent must never spend scarce coach
-- questions on a clinically important X-ray read.
--
-- Budget math (2026-08-01, Anthropic pricing Haiku $1/$5, Sonnet
-- $3/$15 per MTok; net revenue ≈ $4.24/mo after Apple 15%):
--   coach   50/mo × ~$0.0065 = $0.33   (existing cap)
--   bone     8/mo × ~$0.03   = $0.24   (owner's call: hammering
--                                       protection; a larger history
--                                       backfill spreads over months)
--   lab     16/mo × ~$0.01   = $0.16
--   worst case ≈ $0.73/user-month — hit only by deliberate maxing;
--   expected blended usage ≈ $0.07/user-month (~1.6% of net).
--
-- Cap semantics: 0 = not in plan, NULL = unlimited, N = N/UTC-month.
-- The edge functions read the columns defensively (select *), so
-- this migration can be applied before or after their deploy.
--
-- ⚠️ Supabase SQL editor: run this file as-is (no dollar-quoted
-- bodies, so the silent-drop trap does not apply), then run the
-- verification query at the bottom.
-- Applied to production: PENDING
-- ════════════════════════════════════════════════════════════════

ALTER TABLE subscription_tier_limits
  ADD COLUMN IF NOT EXISTS bone_age_monthly_cap integer,
  ADD COLUMN IF NOT EXISTS lab_ai_monthly_cap integer;

COMMENT ON COLUMN subscription_tier_limits.bone_age_monthly_cap IS
  'Monthly bone-age AI analyses. 0 = not in plan, NULL = unlimited.';
COMMENT ON COLUMN subscription_tier_limits.lab_ai_monthly_cap IS
  'Monthly lab AI interpretations. 0 = not in plan, NULL = unlimited.';

UPDATE subscription_tier_limits
   SET bone_age_monthly_cap = 8, lab_ai_monthly_cap = 16
 WHERE tier <> 'free';

UPDATE subscription_tier_limits
   SET bone_age_monthly_cap = 0, lab_ai_monthly_cap = 0
 WHERE tier = 'free';

CREATE TABLE IF NOT EXISTS ai_feature_usage_monthly (
  user_id    uuid        NOT NULL,
  year_month text        NOT NULL,
  feature    text        NOT NULL CHECK (feature IN ('bone_age', 'lab_ai')),
  call_count integer     NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, year_month, feature)
);

ALTER TABLE ai_feature_usage_monthly ENABLE ROW LEVEL SECURITY;

-- Reads: a user may see their own counters (future "N left" UI).
-- Writes: none for authenticated — only the service role (edge
-- functions) writes, same posture as live_ai_usage_monthly.
CREATE POLICY ai_feature_usage_read_own
  ON ai_feature_usage_monthly FOR SELECT
  USING (user_id = auth.uid());

-- Verify:
--   SELECT tier, live_ai_monthly_cap, bone_age_monthly_cap,
--          lab_ai_monthly_cap
--     FROM subscription_tier_limits ORDER BY tier;
--   SELECT relrowsecurity FROM pg_class
--    WHERE relname = 'ai_feature_usage_monthly';
