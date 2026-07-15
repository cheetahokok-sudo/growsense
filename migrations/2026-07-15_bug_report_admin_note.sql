-- ==========================================
-- Bug-report resolution notes (2026-07-15). Run in Supabase SQL editor.
--
-- Industry-standard-lite triage additions:
--   admin_note     what caused it / what fixed it, written at close time.
--                  Hard-capped at 1000 chars IN THE DATABASE (~10 display
--                  lines) so notes stay cheap and disciplined — a fix
--                  note is a summary, not a novel. Longer form belongs
--                  in the git commit the note references.
--   admin_note_by  audit: which admin wrote it.
--   admin_note_at  audit: when.
--
-- Reporter identity needs NO schema change — bug_reports.user_id already
-- exists; admin.js joins it to user_accounts.email client-side under the
-- admin session (same RLS the user list already relies on).
-- Existing "admins triage bug reports" UPDATE policy covers these
-- columns; normal users still have no UPDATE/SELECT path.
-- ==========================================

ALTER TABLE bug_reports
  ADD COLUMN IF NOT EXISTS admin_note TEXT
      CHECK (admin_note IS NULL OR char_length(admin_note) <= 1000),
  ADD COLUMN IF NOT EXISTS admin_note_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS admin_note_at TIMESTAMPTZ;
