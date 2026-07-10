-- ==========================================
-- Recall Engine phase 2: estimation provenance on activity + sleep.
-- Run in the Supabase SQL editor (ogpkmcqaulohexanucng) AFTER
-- 2026-07-10_nutrition_estimation_columns.sql.
--
-- Same estimation ladder as daily_nutrition, plus one method unique
-- to activity:
--   pattern_suggest 0.75  AI mined the child's routine ("tennis most
--                         Fridays"), parent confirmed each item by
--                         recognition. Occurrence is parent-verified;
--                         the duration is the routine's median, so it
--                         sits between relative_recall and
--                         recalled_manual.
--
-- Sleep notes: wearable-synced rows (data_source = 'fitbit' etc.)
-- stay 'measured' — the device measured them. Sleep estimates use
-- gentler multipliers than food (a night varies ±10-20%, not ±35%).
-- ==========================================

ALTER TABLE daily_activity_items
    ADD COLUMN IF NOT EXISTS estimation_method TEXT NOT NULL DEFAULT 'measured'
        CHECK (estimation_method IN
            ('measured', 'recalled_manual', 'relative_recall',
             'weekly_survey', 'pattern_fill', 'pattern_suggest')),
    ADD COLUMN IF NOT EXISTS confidence NUMERIC(3,2) NOT NULL DEFAULT 1.00
        CHECK (confidence > 0 AND confidence <= 1);

ALTER TABLE daily_sleep
    ADD COLUMN IF NOT EXISTS estimation_method TEXT NOT NULL DEFAULT 'measured'
        CHECK (estimation_method IN
            ('measured', 'recalled_manual', 'relative_recall',
             'weekly_survey', 'pattern_fill', 'pattern_suggest')),
    ADD COLUMN IF NOT EXISTS confidence NUMERIC(3,2) NOT NULL DEFAULT 1.00
        CHECK (confidence > 0 AND confidence <= 1);

COMMENT ON COLUMN daily_activity_items.estimation_method IS
    'How this item was produced: measured | recalled_manual | pattern_suggest (routine confirmed by parent) | ...';
COMMENT ON COLUMN daily_sleep.estimation_method IS
    'How this night was produced: measured (incl. wearable) | recalled_manual | pattern_fill | ...';
