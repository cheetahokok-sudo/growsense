-- ==========================================
-- Nutrition Recall Engine: estimation provenance on daily_nutrition
-- Run in the Supabase SQL editor (ogpkmcqaulohexanucng).
--
-- Every daily_nutrition row now says HOW it came to exist and how
-- much to trust it. Existing rows were all logged by hand on the
-- day, so the defaults ('measured', 1.00) are correct for them.
--
-- estimation_method values (the estimation ladder):
--   measured        1.00  logged on the day (or backfilled <=2 days)
--   recalled_manual 0.85/0.70  parent item-level backfill 3-7d / >7d
--   relative_recall 0.70  one-tap "vs yesterday" multiplier
--   weekly_survey   0.50  Sunday micro-survey adjustment (future)
--   pattern_fill    0.30  typical-day median fill
--
-- Downstream rules (enforced in app code, recorded here for the
-- record): estimates render gold, never blue; smart insights and
-- red clinical flags compute from measured rows only; estimates
-- never overwrite a measured row.
-- ==========================================

ALTER TABLE daily_nutrition
    ADD COLUMN IF NOT EXISTS estimation_method TEXT NOT NULL DEFAULT 'measured'
        CHECK (estimation_method IN
            ('measured', 'recalled_manual', 'relative_recall',
             'weekly_survey', 'pattern_fill')),
    ADD COLUMN IF NOT EXISTS confidence NUMERIC(3,2) NOT NULL DEFAULT 1.00
        CHECK (confidence > 0 AND confidence <= 1);

COMMENT ON COLUMN daily_nutrition.estimation_method IS
    'How this row was produced: measured | recalled_manual | relative_recall | weekly_survey | pattern_fill';
COMMENT ON COLUMN daily_nutrition.confidence IS
    'Trust weight 0-1 inferred from method + elapsed time; 1.00 = same-day log';
