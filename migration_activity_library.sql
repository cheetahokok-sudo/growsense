-- ══════════════════════════════════════════════════════════════════
-- GrowSense migration: customisable activity library
-- Run once in Supabase SQL Editor.
--
-- WHAT THIS ADDS:
--
-- 1. daily_activity_items — per-activity log entries (replaces the
--    three fixed columns in daily_activity for new logs). Each tap on
--    an activity card creates one row: activity + duration. Multiple
--    activities per day are stored as separate rows.
--
-- 2. custom_activities — parent-defined activities not in the built-in
--    library, scoped to the parent account.
--
-- 3. favorite_activities — which activities a child's card grid shows.
--    Stars in the library browser write here. Scoped per child so
--    siblings can have different default grids.
--
-- The old daily_activity table is NOT dropped — historical data from
-- the three-stepper era (bar_hanging_sec, box_jumps_reps, yoga_min)
-- is preserved and still contributes to analytics. New logs go into
-- daily_activity_items only.
-- ══════════════════════════════════════════════════════════════════

-- ── 1. daily_activity_items ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS daily_activity_items (
  item_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  child_id    UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
  log_date    DATE NOT NULL,
  activity_id TEXT NOT NULL,          -- library id or 'custom_xxx'
  display_name TEXT NOT NULL,
  category    TEXT,
  tier        TEXT NOT NULL DEFAULT 'weight_bearing'
    CHECK (tier IN ('high_impact','weight_bearing','cardio','flexibility','lifestyle')),
  duration_min INT NOT NULL DEFAULT 30 CHECK (duration_min > 0),
  is_custom   BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dai_child_date
  ON daily_activity_items(child_id, log_date);

ALTER TABLE daily_activity_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Activity items — parent only"
ON daily_activity_items FOR ALL USING (
  is_parent_of_child(child_id, auth.uid())
);

COMMENT ON TABLE daily_activity_items IS
  'One row per logged activity per day. Multiple rows per day are '
  'expected (e.g. basketball + yoga). Tier drives the readiness '
  'score weight: high_impact=1.0, weight_bearing=0.65, '
  'cardio=0.35, flexibility=0.15.';

-- ── 2. custom_activities ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS custom_activities (
  activity_id  TEXT PRIMARY KEY,      -- format: 'custom_<uuid_short>'
  parent_id    UUID NOT NULL REFERENCES user_accounts(user_id),
  display_name TEXT NOT NULL,
  category     TEXT DEFAULT 'custom',
  tier         TEXT NOT NULL DEFAULT 'weight_bearing'
    CHECK (tier IN ('high_impact','weight_bearing','cardio','flexibility','lifestyle')),
  emoji        TEXT DEFAULT '⭐',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE custom_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Custom activities — parent only"
ON custom_activities FOR ALL USING (parent_id = auth.uid());

-- ── 3. favorite_activities ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS favorite_activities (
  child_id    UUID NOT NULL REFERENCES children(child_id) ON DELETE CASCADE,
  activity_id TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (child_id, activity_id)
);

ALTER TABLE favorite_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Favorite activities — parent only"
ON favorite_activities FOR ALL USING (
  is_parent_of_child(child_id, auth.uid())
);

COMMENT ON TABLE favorite_activities IS
  'Which activity cards are pinned to the Today tab card grid for '
  'each child. Empty = show built-in defaults.';
