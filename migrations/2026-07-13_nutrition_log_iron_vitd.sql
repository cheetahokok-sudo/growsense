-- ==========================================
-- Minor growth co-factors on the per-food log: iron + vitamin D.
-- Run in the Supabase SQL editor (ogpkmcqaulohexanucng).
--
-- These are captured AUTOMATICALLY when a parent logs a food — computed
-- from the food's per-100g value (already in food-reference-data.js),
-- never entered by hand. They are deliberately NOT part of the Today
-- page or the readiness score (too many parameters for parents); they
-- surface only as a quiet monthly co-factor view in Analytics.
--
-- Nullable: custom foods and older log rows simply carry NULL (unknown),
-- and regional composite dishes without an FDC record contribute nothing
-- — same honest "not collected" rule as the food data itself.
-- ==========================================

ALTER TABLE nutrition_log_items
    ADD COLUMN IF NOT EXISTS iron_mg numeric,
    ADD COLUMN IF NOT EXISTS vitamin_d_iu numeric;

COMMENT ON COLUMN nutrition_log_items.iron_mg IS
    'Iron (mg) for this logged serving, auto-captured from the food''s '
    'per-100g value. Minor co-factor — Analytics only, never a Today input.';
COMMENT ON COLUMN nutrition_log_items.vitamin_d_iu IS
    'Vitamin D (IU) for this logged serving, auto-captured from the food''s '
    'per-100g value. Minor co-factor — Analytics only.';
