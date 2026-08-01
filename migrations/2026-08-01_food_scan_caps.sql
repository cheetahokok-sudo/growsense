-- ════════════════════════════════════════════════════════════════
-- Food Lens (meal photo + label scan AI) plumbing:
--   1. widen the ai_feature_usage_monthly feature CHECK to accept
--      'food_scan' — REQUIRED BEFORE the food-scan edge function
--      sees real traffic. usage_caps.ts swallows counter-write
--      errors (by design), so an unwidened CHECK means the counter
--      silently never increments = an uncapped feature that LOOKS
--      capped.
--   2. subscription_tier_limits.food_scan_monthly_cap
--      (meal + label scans share one bucket).
--   3. nutrition_log_items.log_method — provenance for photo-logged
--      rows ('manual' | 'photo_ai'); analytics confidence tiers later.
--   4. energy_kcal on nutrition_log_items + custom_foods — energy
--      enters the data model ("collect quietly, surface later", same
--      as iron/vit-D; future illness recovery mode surfaces it).
--
-- Budget math (Haiku 4.5 vision ≈ $0.01–0.03/call):
--   food_scan 30/mo × ~$0.02 ≈ $0.60 worst case, abuse bound only;
--   expected blended usage well under $0.10/user-month.
--
-- Cap semantics: 0 = not in plan, NULL = unlimited, N = N/UTC-month.
--
-- ⚠️ Constraint name: 'ai_feature_usage_monthly_feature_check' was
-- confirmed against the live schema dump 2026-08-01. If the DROP
-- fails with "constraint does not exist", find the real name first:
--   SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conrelid = 'ai_feature_usage_monthly'::regclass
--      AND contype = 'c';
--
-- ⚠️ Supabase SQL editor: plain DDL, no dollar-quoted bodies — run
-- this file as one execution, then the verification queries below.
-- Applied to production: 2026-08-01 ✅ (verified via schema dump: CHECK
-- includes food_scan; all 4 columns + comments present. food-scan edge
-- function deployed the same day.)
-- ════════════════════════════════════════════════════════════════

ALTER TABLE ai_feature_usage_monthly
  DROP CONSTRAINT ai_feature_usage_monthly_feature_check;
ALTER TABLE ai_feature_usage_monthly
  ADD CONSTRAINT ai_feature_usage_monthly_feature_check
  CHECK (feature IN ('bone_age', 'lab_ai', 'food_scan'));

ALTER TABLE subscription_tier_limits
  ADD COLUMN IF NOT EXISTS food_scan_monthly_cap integer;

COMMENT ON COLUMN subscription_tier_limits.food_scan_monthly_cap IS
  'Monthly Food Lens AI scans (meal photos + label scans combined). 0 = not in plan, NULL = unlimited.';

UPDATE subscription_tier_limits
   SET food_scan_monthly_cap = 30
 WHERE tier <> 'free';

UPDATE subscription_tier_limits
   SET food_scan_monthly_cap = 0
 WHERE tier = 'free';

ALTER TABLE nutrition_log_items
  ADD COLUMN IF NOT EXISTS log_method text NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS energy_kcal numeric;

COMMENT ON COLUMN nutrition_log_items.log_method IS
  'How the row was created: manual (typed/tapped) or photo_ai (Food Lens, parent-confirmed).';
COMMENT ON COLUMN nutrition_log_items.energy_kcal IS
  'Energy for the logged serving. Collected quietly since 2026-08; no UI surfaces it yet.';

ALTER TABLE custom_foods
  ADD COLUMN IF NOT EXISTS energy_kcal numeric;

COMMENT ON COLUMN custom_foods.energy_kcal IS
  'Energy per serving as read from the packaging label (Food Lens label scan). No UI yet.';

-- Verify:
--   SELECT tier, food_scan_monthly_cap
--     FROM subscription_tier_limits ORDER BY tier;
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conrelid = 'ai_feature_usage_monthly'::regclass
--      AND contype = 'c';
--   -- expect: CHECK (feature IN ('bone_age','lab_ai','food_scan'))
