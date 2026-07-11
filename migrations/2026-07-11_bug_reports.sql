-- ==========================================
-- Bug / feedback collection. Run in the Supabase SQL editor.
--
-- Every in-app "Report a bug" submission lands here with enough
-- structured context to triage without going back to the user:
-- app version + build, channel, locale, and an ANONYMIZED child
-- snapshot (age in years + sex only — never name, never the actual
-- measurements). The reporter's user_id is kept so we can follow up
-- if they ask, but reports are not readable by other users.
-- ==========================================

CREATE TABLE IF NOT EXISTS bug_reports (
    report_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    app_version  TEXT,
    app_build    INT,
    channel      TEXT,                      -- 'web' | 'app'
    locale       TEXT,                      -- 'en' | 'th' | ...
    category     TEXT NOT NULL DEFAULT 'bug'
                 CHECK (category IN ('bug', 'data_wrong', 'confusing', 'idea')),
    severity     TEXT NOT NULL DEFAULT 'medium'
                 CHECK (severity IN ('low', 'medium', 'high')),
    description  TEXT NOT NULL,
    child_age_years NUMERIC(4,1),           -- anonymized, nullable
    child_sex    TEXT,                       -- anonymized, nullable
    context      JSONB DEFAULT '{}'::jsonb,  -- active screen, UA, etc.
    status       TEXT NOT NULL DEFAULT 'new'
                 CHECK (status IN ('new', 'triaged', 'fixed', 'wontfix'))
);

CREATE INDEX IF NOT EXISTS bug_reports_created_idx
    ON bug_reports (created_at DESC);
CREATE INDEX IF NOT EXISTS bug_reports_status_idx
    ON bug_reports (status);

ALTER TABLE bug_reports ENABLE ROW LEVEL SECURITY;

-- Any signed-in user may file a report as themselves.
CREATE POLICY "file own bug report" ON bug_reports
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Reports are triage-only: no SELECT/UPDATE policy for normal users,
-- so nobody can read anyone's reports through the anon/auth key.
-- Review them in the dashboard or via the service_role key.
