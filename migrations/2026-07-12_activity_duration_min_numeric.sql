-- ==========================================
-- Fix: daily_activity_items.duration_min must accept fractional values.
-- Run in the Supabase SQL editor (ogpkmcqaulohexanucng).
--
-- BUG: duration_min was created as an integer. But rep-based activities
-- convert to minutes at 0.25 min/rep, so odd rep counts land on a
-- half-minute (10 reps → 2.5, 30 → 7.5, 50 → 12.5). Postgres rejects
-- those with "invalid input syntax for type integer", so Box Jumps /
-- Vertical Jumps / Hopscotch silently failed to save at 10/30/50 reps
-- while 20/40 (whole minutes) went through. The recall engine's
-- pattern-fill also writes a 1-decimal median duration, so it hit the
-- same wall. duration_min is genuinely continuous — make it numeric.
--
-- Both clients already send the correct fractional values; no app
-- change is needed once this runs. duration_value stays integer (it
-- holds the raw reps/minutes the parent picked).
-- ==========================================

ALTER TABLE daily_activity_items
    ALTER COLUMN duration_min TYPE numeric(6, 2)
    USING duration_min::numeric(6, 2);

COMMENT ON COLUMN daily_activity_items.duration_min IS
    'Minute-equivalent for the readiness score. Continuous: rep-based '
    'activities convert at 0.25 min/rep and recall fills store a median, '
    'so this is numeric, not integer. duration_value holds the raw '
    'reps/minutes the parent entered.';
