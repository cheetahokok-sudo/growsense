-- ==========================================
-- Lab-value AI interpretation reports (2026-07-15). Run in Supabase SQL editor.
--
-- Stores the structured AI reading of a child's lab panel produced by the
-- lab-ai-analysis Edge Function (Haiku 4.5). One row per run; history kept
-- so the family can see how interpretations evolve. The Edge Function
-- writes with the service role; parents read their own children's reports.
--
-- Premium feature (gated server-side in the function on subscription_tier),
-- but the TABLE is readable by the owning parent regardless of tier so a
-- lapsed subscriber can still see reports they already generated.
-- ==========================================

CREATE TABLE IF NOT EXISTS public.lab_ai_reports (
  report_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id       uuid NOT NULL REFERENCES public.children(child_id) ON DELETE CASCADE,
  created_by     uuid REFERENCES public.user_accounts(user_id) ON DELETE SET NULL,
  report         jsonb NOT NULL,
  model          text,
  analyte_count  integer,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS lab_ai_reports_child_idx
  ON public.lab_ai_reports (child_id, created_at DESC);

ALTER TABLE public.lab_ai_reports ENABLE ROW LEVEL SECURITY;

-- Parents read reports for their own children. Writes come only from the
-- Edge Function (service role bypasses RLS) — no client insert/update path.
DROP POLICY IF EXISTS lab_ai_reports_select_own ON public.lab_ai_reports;
CREATE POLICY lab_ai_reports_select_own ON public.lab_ai_reports
  FOR SELECT TO authenticated
  USING (
    child_id IN (
      SELECT child_id FROM public.children WHERE parent_id = auth.uid()
    )
  );

-- Owning parent may delete a stored report (housekeeping); still no
-- insert/update by clients.
DROP POLICY IF EXISTS lab_ai_reports_delete_own ON public.lab_ai_reports;
CREATE POLICY lab_ai_reports_delete_own ON public.lab_ai_reports
  FOR DELETE TO authenticated
  USING (
    child_id IN (
      SELECT child_id FROM public.children WHERE parent_id = auth.uid()
    )
  );
