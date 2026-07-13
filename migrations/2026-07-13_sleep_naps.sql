-- ==========================================
-- sleep_naps — daytime naps kept SEPARATE from the main night.
-- Run in the Supabase SQL editor (ogpkmcqaulohexanucng).
--
-- Why a separate table (not another daily_sleep row):
--   • daily_sleep is UNIQUE(child_id, log_date) — one consolidated night
--     per day, and it is the ONLY thing that feeds sleep_efficiency_score
--     / readiness. Naps must NOT inflate that score.
--   • For ages 5–19 naps are rare and can be a *signal* (daytime
--     sleepiness → OSA, per the GS-021 evidence), so we record them
--     honestly for future / clinical analysis of frequency + timing —
--     which needs per-nap start/end, not a lumped daily total.
--   • It also lets google-health-sync route a same-day extra sleep
--     session here instead of colliding on daily_sleep's unique key
--     (the PG 21000 "ON CONFLICT … cannot affect row a second time" bug).
--
-- log_date follows the same wake-date convention as daily_sleep.
-- UNIQUE(child_id, log_date, start_time) makes wearable re-syncs
-- idempotent (upsert on that key) without duplicating a nap.
-- ==========================================

CREATE TABLE IF NOT EXISTS sleep_naps (
    nap_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id        UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    log_date        DATE NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    total_sleep_min INT  NOT NULL,
    data_source     VARCHAR(30) NOT NULL DEFAULT 'manual', -- 'manual' | 'fitbit' | ...
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(child_id, log_date, start_time)
);

CREATE INDEX IF NOT EXISTS idx_sleep_naps_child_date
    ON sleep_naps(child_id, log_date);

ALTER TABLE sleep_naps ENABLE ROW LEVEL SECURITY;

-- Same cascading-context rule as daily_sleep: parent, assigned doctor,
-- or a scientist account.
CREATE POLICY "Sleep naps cascading context rule" ON sleep_naps FOR ALL USING (
    EXISTS (
        SELECT 1 FROM children
        WHERE children.child_id = sleep_naps.child_id
        AND (
            children.parent_id = auth.uid()
            OR EXISTS (SELECT 1 FROM doctor_patient_assignments
                       WHERE doctor_id = auth.uid() AND child_id = children.child_id AND is_active = TRUE)
            OR EXISTS (SELECT 1 FROM user_accounts WHERE user_id = auth.uid() AND account_role = 'scientist')
        )
    )
);

COMMENT ON TABLE sleep_naps IS
    'Daytime naps, separate from daily_sleep. Deliberately excluded from sleep_efficiency_score / readiness; retained for honest history + future nap-pattern analysis.';
