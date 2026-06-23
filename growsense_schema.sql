-- ==========================================
-- GrowSense — Full Production Schema
-- Run this once in Supabase SQL Editor (Dashboard → SQL Editor → New query)
--
-- This is the user-proposed schema with one fix applied: the RLS policies
-- on daily_nutrition, daily_sleep, measurements, and daily_activity have
-- been corrected to actually check identity (auth.uid()) against the
-- parent/doctor/scientist relationship, matching the children policy.
-- As originally written, those four policies only checked that the
-- child_id existed *somewhere* in the children table — meaning any
-- authenticated user could read/write any child's health data. That gap
-- is closed below.
--
-- NOT included, by design:
--  - Pubertal/Tanner-stage photography. Bone-age X-rays (a real, standard
--    skeletal-maturity assessment method) are supported via
--    bone_age_assessments below; images of a minor's pubertal physical
--    development are a hard line and are not part of this schema.
--  - EEG. Left out until there's a specific device/use case — consumer
--    EEG wearables don't have established pediatric growth correlations
--    worth encoding as structured data yet, and clinical EEG belongs in
--    a doctor's own clinical-record system, not a parent-facing app.
-- ==========================================

-- ==========================================
-- 1. SECURITY, EXTENSIONS & TYPES SETUP
-- ==========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE app_role AS ENUM ('parent_subscriber', 'doctor', 'scientist', 'system_admin');
CREATE TYPE subscription_tier AS ENUM ('free', 'premium_growth_tier', 'clinical_tier');

-- ==========================================
-- 2. INFRASTRUCTURE & IDENTITY RECORDS
-- ==========================================
CREATE TABLE user_accounts (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    account_role app_role NOT NULL DEFAULT 'parent_subscriber',
    tier subscription_tier NOT NULL DEFAULT 'free',
    subscription_status VARCHAR(20) DEFAULT 'active', -- 'active', 'past_due', 'canceled'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE children (
    child_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID NOT NULL REFERENCES user_accounts(user_id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    biological_sex VARCHAR(10) CHECK (biological_sex IN ('male', 'female')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE doctor_patient_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID NOT NULL REFERENCES user_accounts(user_id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE(doctor_id, child_id)
);

CREATE TABLE wearable_sync_credentials (
    sync_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_accounts(user_id) ON DELETE CASCADE,
    provider_platform VARCHAR(30) NOT NULL, -- 'fitbit', 'whoop', 'apple_health'
    encrypted_access_token TEXT NOT NULL,
    encrypted_refresh_token TEXT NOT NULL,
    token_expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_successful_sync_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(user_id, provider_platform)
);

-- ==========================================
-- 3. CORE TELEMETRICS & NUTRITION LEDGERS
-- ==========================================
CREATE TABLE daily_nutrition (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    log_date DATE NOT NULL,
    protein_breakfast_g NUMERIC(4,1) DEFAULT 0.0,
    protein_lunch_g NUMERIC(4,1) DEFAULT 0.0,
    protein_dinner_g NUMERIC(4,1) DEFAULT 0.0,
    total_protein_g NUMERIC(5,1) GENERATED ALWAYS AS (protein_breakfast_g + protein_lunch_g + protein_dinner_g) STORED,
    calcium_mg NUMERIC(6,1) DEFAULT 0.0,
    zinc_mg NUMERIC(4,2) DEFAULT 0.00,
    fluids_ml NUMERIC(6,1) DEFAULT 0.0,
    UNIQUE(child_id, log_date)
);

CREATE TABLE daily_sleep (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    log_date DATE NOT NULL,
    total_sleep_min INT NOT NULL,
    deep_sleep_min INT,
    rem_sleep_min INT,
    sleep_efficiency_score INT,
    hrv_ms NUMERIC(5,2),
    data_source VARCHAR(30) NOT NULL, -- 'fitbit', 'whoop', 'apple'
    UNIQUE(child_id, log_date)
);

-- ==========================================
-- 4. SMART SCALE COMPOSITION & BIOMETRICS
-- ==========================================
CREATE TABLE measurements (
    measurement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    recorded_date DATE NOT NULL,

    stature_height_cm NUMERIC(4,1) NOT NULL,
    mass_weight_kg NUMERIC(4,1) NOT NULL,
    calculated_bmi NUMERIC(3,1) GENERATED ALWAYS AS (ROUND(mass_weight_kg / ((stature_height_cm / 100.0) * (stature_height_cm / 100.0)), 1)) STORED,

    body_fat_percentage NUMERIC(4,1) DEFAULT NULL,
    muscle_mass_kg NUMERIC(4,1) DEFAULT NULL,
    body_water_percentage NUMERIC(4,1) DEFAULT NULL,
    bone_mass_kg NUMERIC(3,1) DEFAULT NULL,
    visceral_fat_rating INT DEFAULT NULL,

    data_source VARCHAR(30) NOT NULL DEFAULT 'manual', -- 'smart_scale_ble', 'apple_health', 'google_health', 'manual'
    device_hardware_model TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(child_id, recorded_date)
);

CREATE TABLE daily_activity (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    log_date DATE NOT NULL,

    step_count INT DEFAULT 0,
    active_calories_kcal INT DEFAULT 0,

    hanging_decompression_sec INT DEFAULT 0,
    box_jumps_reps INT DEFAULT 0,
    stretching_yoga_duration_min INT DEFAULT 0,

    data_source VARCHAR(30) NOT NULL, -- 'fitbit', 'whoop', 'apple', 'manual'
    UNIQUE(child_id, log_date)
);

-- ==========================================
-- 5. CLINICAL IMAGING — BONE AGE ONLY
-- Skeletal-maturity X-ray assessment is a standard, well-established
-- clinical method (comparing hand/wrist radiographs against atlases such
-- as Greulich-Pyle or Tanner-Whitehouse) read and entered by a radiologist
-- or pediatrician — not a parent-facing upload of physical/pubertal photos.
-- ==========================================
CREATE TABLE bone_age_assessments (
    assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
    assessed_by UUID REFERENCES user_accounts(user_id),  -- the doctor/radiologist who entered this
    xray_date DATE NOT NULL,
    chronological_age_months INT NOT NULL,
    assessed_bone_age_months INT NOT NULL,
    assessment_method VARCHAR(40) DEFAULT 'greulich_pyle', -- or 'tanner_whitehouse'
    image_storage_path TEXT,  -- path into Supabase Storage, not the image itself
    radiologist_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ==========================================
-- 6. ROW-LEVEL SECURITY (RLS) POLICIES
-- ==========================================
ALTER TABLE user_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE children ENABLE ROW LEVEL SECURITY;
ALTER TABLE doctor_patient_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE wearable_sync_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_nutrition ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_sleep ENABLE ROW LEVEL SECURITY;
ALTER TABLE measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE bone_age_assessments ENABLE ROW LEVEL SECURITY;

-- Accounts viewable by respective authenticated users
CREATE POLICY "Allow individual account data reading" ON user_accounts
    FOR ALL USING (auth.uid() = user_id);

-- Children visible to: their parent, an assigned active doctor, or any scientist role
CREATE POLICY "Children identity isolation filter" ON children
    FOR ALL USING (
        parent_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM doctor_patient_assignments
            WHERE doctor_id = auth.uid() AND child_id = children.child_id AND is_active = TRUE
        )
        OR EXISTS (
            SELECT 1 FROM user_accounts WHERE user_id = auth.uid() AND account_role = 'scientist'
        )
    );

-- FIXED: each metrics table now checks the same parent/doctor/scientist
-- relationship as the children policy, instead of merely checking that
-- child_id exists somewhere in the children table.
CREATE POLICY "Nutrition data cascading context rule" ON daily_nutrition FOR ALL USING (
    EXISTS (
        SELECT 1 FROM children
        WHERE children.child_id = daily_nutrition.child_id
        AND (
            children.parent_id = auth.uid()
            OR EXISTS (SELECT 1 FROM doctor_patient_assignments
                       WHERE doctor_id = auth.uid() AND child_id = children.child_id AND is_active = TRUE)
            OR EXISTS (SELECT 1 FROM user_accounts WHERE user_id = auth.uid() AND account_role = 'scientist')
        )
    )
);

CREATE POLICY "Sleep metrics data cascading context rule" ON daily_sleep FOR ALL USING (
    EXISTS (
        SELECT 1 FROM children
        WHERE children.child_id = daily_sleep.child_id
        AND (
            children.parent_id = auth.uid()
            OR EXISTS (SELECT 1 FROM doctor_patient_assignments
                       WHERE doctor_id = auth.uid() AND child_id = children.child_id AND is_active = TRUE)
            OR EXISTS (SELECT 1 FROM user_accounts WHERE user_id = auth.uid() AND account_role = 'scientist')
        )
    )
);

CREATE POLICY "Smart scale composition cascading context rule" ON measurements FOR ALL USING (
    EXISTS (
        SELECT 1 FROM children
        WHERE children.child_id = measurements.child_id
        AND (
            children.parent_id = auth.uid()
            OR EXISTS (SELECT 1 FROM doctor_patient_assignments
                       WHERE doctor_id = auth.uid() AND child_id = children.child_id AND is_active = TRUE)
            OR EXISTS (SELECT 1 FROM user_accounts WHERE user_id = auth.uid() AND account_role = 'scientist')
        )
    )
);

CREATE POLICY "Activity tracking cascading context rule" ON daily_activity FOR ALL USING (
    EXISTS (
        SELECT 1 FROM children
        WHERE children.child_id = daily_activity.child_id
        AND (
            children.parent_id = auth.uid()
            OR EXISTS (SELECT 1 FROM doctor_patient_assignments
                       WHERE doctor_id = auth.uid() AND child_id = children.child_id AND is_active = TRUE)
            OR EXISTS (SELECT 1 FROM user_accounts WHERE user_id = auth.uid() AND account_role = 'scientist')
        )
    )
);

-- Bone age assessments: same relationship check, plus only a doctor/admin
-- (never a bare parent_subscriber) may INSERT/UPDATE — parents can view
-- their own child's results but assessments are entered by clinicians.
CREATE POLICY "Bone age visible to parent, assigned doctor, or scientist" ON bone_age_assessments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM children
            WHERE children.child_id = bone_age_assessments.child_id
            AND (
                children.parent_id = auth.uid()
                OR EXISTS (SELECT 1 FROM doctor_patient_assignments
                           WHERE doctor_id = auth.uid() AND child_id = children.child_id AND is_active = TRUE)
                OR EXISTS (SELECT 1 FROM user_accounts WHERE user_id = auth.uid() AND account_role = 'scientist')
            )
        )
    );

CREATE POLICY "Bone age entered only by assigned doctor or admin" ON bone_age_assessments
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM user_accounts
            WHERE user_id = auth.uid() AND account_role IN ('doctor', 'system_admin')
        )
        AND EXISTS (
            SELECT 1 FROM doctor_patient_assignments
            WHERE doctor_id = auth.uid() AND child_id = bone_age_assessments.child_id AND is_active = TRUE
        )
    );

CREATE POLICY "Bone age updated only by assigned doctor or admin" ON bone_age_assessments
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM user_accounts
            WHERE user_id = auth.uid() AND account_role IN ('doctor', 'system_admin')
        )
        AND EXISTS (
            SELECT 1 FROM doctor_patient_assignments
            WHERE doctor_id = auth.uid() AND child_id = bone_age_assessments.child_id AND is_active = TRUE
        )
    );

-- ==========================================
-- 7. PEDIATRIC GROWTH VELOCITY ENGINE (VIEW)
-- ==========================================
CREATE OR REPLACE VIEW child_growth_analytics_ledger AS
SELECT
    measurement_id,
    child_id,
    recorded_date,
    stature_height_cm,
    mass_weight_kg,
    calculated_bmi,
    body_fat_percentage,
    muscle_mass_kg,
    body_water_percentage,
    ROUND(
        (stature_height_cm - LAG(stature_height_cm, 1) OVER (PARTITION BY child_id ORDER BY recorded_date ASC)), 2
    ) AS height_delta_cm,
    -- date - date returns an integer day count directly in Postgres,
    -- not an interval, so EXTRACT(DAY FROM ...) doesn't apply here.
    (recorded_date - LAG(recorded_date, 1) OVER (PARTITION BY child_id ORDER BY recorded_date ASC)) AS days_between_measurements
FROM measurements;
