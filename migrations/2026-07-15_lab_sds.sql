-- ==========================================
-- Optional standard-deviation score (SDS / z-score) on lab results
-- (2026-07-15). Run in Supabase SQL editor.
--
-- Many pediatric lab reports print an age/sex-adjusted SDS next to a
-- value (most importantly IGF-1). GrowSense captures that lab-reported
-- SDS as-is and renders a "-2 … +2 SDS" bar — it never computes its own
-- SDS (a correct one is assay-, age- and sex-specific; inventing one
-- would be misleading). Nullable: values without a printed SDS are fine.
-- ==========================================

ALTER TABLE public.lab_results
  ADD COLUMN IF NOT EXISTS sds numeric;
