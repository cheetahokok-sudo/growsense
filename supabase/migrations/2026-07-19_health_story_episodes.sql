-- ==========================================
-- Health Story — illness episodes (beta, Gate 1 capture)
-- Run in the Supabase SQL editor (project ogpkmcqaulohexanucng).
--
-- Episode-based illness record (NOT the legacy single-row illness_events):
-- one bounded illness with a lifecycle, plus child rows for symptoms,
-- temperatures and medications. This is the capture layer for the
-- Health Story feature — a record for the parent + doctor, never a
-- diagnosis. Pattern flags (Gate 2) are computed read-only later and
-- are NOT part of this schema.
--
-- RLS mirrors the existing clinical cascading-context rule
-- (parent_id = auth.uid() OR assigned doctor OR scientist). The three
-- child tables cascade through illness_episodes -> children.
-- See content/specs/health-story-pattern-engine.md
-- ==========================================

CREATE TABLE IF NOT EXISTS illness_episodes (
    episode_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id                UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    created_by              UUID,
    status                  VARCHAR(12) NOT NULL DEFAULT 'active',   -- suspected | active | resolved | abandoned
    onset_date              DATE NOT NULL,
    onset_precision         VARCHAR(12) DEFAULT 'exact',             -- exact | approx_day | approx_week
    resolved_date           DATE,
    primary_system          VARCHAR(12),                             -- respiratory | ent | gi | febrile | skin | other
    label_parent            TEXT,
    daycare_school_exposure BOOLEAN,
    suspected_trigger       TEXT[],                                  -- cold_air | exercise | pollen | food | contact_sick | unknown
    care_sought             VARCHAR(12) NOT NULL DEFAULT 'none',     -- none | pharmacy | gp | er | admitted
    diagnosis               TEXT,                                    -- entered by the parent FROM their doctor; app never generates
    source                  VARCHAR(10) NOT NULL DEFAULT 'recorded', -- recorded | recalled
    confidence              VARCHAR(6)  NOT NULL DEFAULT 'high',     -- high | medium | low
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_illness_episodes_child ON illness_episodes(child_id, onset_date DESC);

CREATE TABLE IF NOT EXISTS episode_symptoms (
    symptom_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    episode_id  UUID NOT NULL REFERENCES illness_episodes(episode_id) ON DELETE CASCADE,
    symptom     VARCHAR(30) NOT NULL,
    severity    VARCHAR(10),                                         -- mild | moderate | severe
    started_on  DATE,
    ended_on    DATE,
    detail      JSONB,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_episode_symptoms_ep ON episode_symptoms(episode_id);

CREATE TABLE IF NOT EXISTS episode_temperatures (
    temp_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    episode_id  UUID NOT NULL REFERENCES illness_episodes(episode_id) ON DELETE CASCADE,
    measured_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    temp_c      NUMERIC(4,1) NOT NULL,
    route       VARCHAR(10),                                         -- axillary | oral | tympanic | rectal | forehead
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_episode_temps_ep ON episode_temperatures(episode_id);

CREATE TABLE IF NOT EXISTS episode_medications (
    med_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    episode_id    UUID NOT NULL REFERENCES illness_episodes(episode_id) ON DELETE CASCADE,
    medication    TEXT NOT NULL,
    med_class     VARCHAR(16),                                       -- antipyretic | antibiotic | bronchodilator | antihistamine | steroid | other
    dose_amount   NUMERIC,                                           -- recorded as entered; the app never suggests a dose
    dose_unit     VARCHAR(10),                                       -- mg | ml | drops | puffs | sachet | other
    frequency     TEXT,
    duration_days INT,
    doses_given   INT,
    prescribed_by VARCHAR(10),                                       -- doctor | pharmacy | self | unknown
    started_on    DATE,
    ended_on      DATE,
    response      VARCHAR(10),                                       -- resolved | improved | no_change | worsened  ("improved AFTER", not "because of")
    response_day  INT,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_episode_meds_ep ON episode_medications(episode_id);

-- ── Row-level security ───────────────────────────────────────────────
ALTER TABLE illness_episodes    ENABLE ROW LEVEL SECURITY;
ALTER TABLE episode_symptoms    ENABLE ROW LEVEL SECURITY;
ALTER TABLE episode_temperatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE episode_medications ENABLE ROW LEVEL SECURITY;

-- Episodes: same cascading-context rule as measurements/daily_sleep.
CREATE POLICY "Illness episodes cascading context rule" ON illness_episodes FOR ALL USING (
    EXISTS (
        SELECT 1 FROM children
        WHERE children.child_id = illness_episodes.child_id
        AND (
            children.parent_id = auth.uid()
            OR EXISTS (SELECT 1 FROM doctor_patient_assignments
                       WHERE doctor_id = auth.uid() AND child_id = children.child_id AND is_active = TRUE)
            OR EXISTS (SELECT 1 FROM user_accounts WHERE user_id = auth.uid() AND account_role = 'scientist')
        )
    )
);

-- Child tables: cascade access through the parent episode.
CREATE POLICY "Episode symptoms via episode" ON episode_symptoms FOR ALL USING (
    EXISTS (SELECT 1 FROM illness_episodes e WHERE e.episode_id = episode_symptoms.episode_id)
);
CREATE POLICY "Episode temperatures via episode" ON episode_temperatures FOR ALL USING (
    EXISTS (SELECT 1 FROM illness_episodes e WHERE e.episode_id = episode_temperatures.episode_id)
);
CREATE POLICY "Episode medications via episode" ON episode_medications FOR ALL USING (
    EXISTS (SELECT 1 FROM illness_episodes e WHERE e.episode_id = episode_medications.episode_id)
);
-- NOTE: the child-table policies rely on illness_episodes' own RLS to
-- gate the EXISTS subquery (RLS applies to the subquery too), so a user
-- only "sees" an episode_id they are allowed to see. Verify in the
-- Supabase policy simulator before opening the beta beyond one account.
