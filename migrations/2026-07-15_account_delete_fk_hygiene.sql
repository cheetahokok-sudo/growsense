-- ==========================================
-- Account-deletion FK hygiene + admin permanent account deletion
-- (2026-07-15). Run in Supabase SQL editor.
--
-- WHY: 18 FKs referencing user_accounts/auth.users were NO ACTION.
-- Consequences: (a) admin cannot hard-delete an archived account,
-- (b) the delete-account edge function (Apple 5.1.1(v) — App Review
-- TESTS this) fails for any user with ai_usage_log /
-- live_ai_usage_monthly / custom_activities / google_health_connections
-- rows, because its explicit passes miss those user-keyed tables and
-- the final auth-user delete is then FK-blocked.
--
-- POLICY applied per FK class:
--   OWNED BY the account (their own data)          -> ON DELETE CASCADE
--   HISTORY that must outlive the account          -> ON DELETE SET NULL
--   PROVENANCE stamps on child-owned rows          -> ON DELETE SET NULL
--     (row ownership is child_id; created_by is just attribution)
-- After this, deleting the auth user cascades the whole tree cleanly.
-- ==========================================

-- Account-owned rows: die with the account -------------------------------
ALTER TABLE ai_usage_log DROP CONSTRAINT ai_usage_log_user_id_fkey;
ALTER TABLE ai_usage_log ADD CONSTRAINT ai_usage_log_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES user_accounts(user_id) ON DELETE CASCADE;

ALTER TABLE live_ai_usage_monthly DROP CONSTRAINT live_ai_usage_monthly_user_id_fkey;
ALTER TABLE live_ai_usage_monthly ADD CONSTRAINT live_ai_usage_monthly_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES user_accounts(user_id) ON DELETE CASCADE;

ALTER TABLE custom_activities DROP CONSTRAINT custom_activities_parent_id_fkey;
ALTER TABLE custom_activities ADD CONSTRAINT custom_activities_parent_id_fkey
  FOREIGN KEY (parent_id) REFERENCES user_accounts(user_id) ON DELETE CASCADE;

ALTER TABLE google_health_connections DROP CONSTRAINT google_health_connections_parent_id_fkey;
ALTER TABLE google_health_connections ADD CONSTRAINT google_health_connections_parent_id_fkey
  FOREIGN KEY (parent_id) REFERENCES user_accounts(user_id) ON DELETE CASCADE;

-- History: outlives the account ------------------------------------------
ALTER TABLE admin_audit_log DROP CONSTRAINT admin_audit_log_admin_user_id_fkey;
ALTER TABLE admin_audit_log ADD CONSTRAINT admin_audit_log_admin_user_id_fkey
  FOREIGN KEY (admin_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE admin_audit_log DROP CONSTRAINT admin_audit_log_target_user_id_fkey;
ALTER TABLE admin_audit_log ADD CONSTRAINT admin_audit_log_target_user_id_fkey
  FOREIGN KEY (target_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE activation_codes DROP CONSTRAINT activation_codes_redeemed_by_fkey;
ALTER TABLE activation_codes ADD CONSTRAINT activation_codes_redeemed_by_fkey
  FOREIGN KEY (redeemed_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;

ALTER TABLE system_settings DROP CONSTRAINT system_settings_updated_by_fkey;
ALTER TABLE system_settings ADD CONSTRAINT system_settings_updated_by_fkey
  FOREIGN KEY (updated_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;

-- Provenance stamps on child-owned rows ------------------------------------
ALTER TABLE children DROP CONSTRAINT children_sga_confirmed_by_fkey;
ALTER TABLE children ADD CONSTRAINT children_sga_confirmed_by_fkey
  FOREIGN KEY (sga_confirmed_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
ALTER TABLE children DROP CONSTRAINT children_archived_by_fkey;
ALTER TABLE children ADD CONSTRAINT children_archived_by_fkey
  FOREIGN KEY (archived_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
-- NOTE: this constraint's NAME says assessed_by but the live column is
-- created_by (table was rebuilt at some point; the name is a fossil).
ALTER TABLE bone_age_assessments DROP CONSTRAINT bone_age_assessments_assessed_by_fkey;
ALTER TABLE bone_age_assessments ADD CONSTRAINT bone_age_assessments_assessed_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
ALTER TABLE nutrition_log_items DROP CONSTRAINT nutrition_log_items_created_by_fkey;
ALTER TABLE nutrition_log_items ADD CONSTRAINT nutrition_log_items_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
ALTER TABLE medical_logs DROP CONSTRAINT medical_logs_created_by_fkey;
ALTER TABLE medical_logs ADD CONSTRAINT medical_logs_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
ALTER TABLE lab_results DROP CONSTRAINT lab_results_created_by_fkey;
ALTER TABLE lab_results ADD CONSTRAINT lab_results_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
ALTER TABLE puberty_events DROP CONSTRAINT puberty_events_created_by_fkey;
ALTER TABLE puberty_events ADD CONSTRAINT puberty_events_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
ALTER TABLE family_height_records DROP CONSTRAINT family_height_records_created_by_fkey;
ALTER TABLE family_height_records ADD CONSTRAINT family_height_records_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
ALTER TABLE illness_events DROP CONSTRAINT illness_events_created_by_fkey;
ALTER TABLE illness_events ADD CONSTRAINT illness_events_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;
ALTER TABLE custom_foods DROP CONSTRAINT custom_foods_created_by_fkey;
ALTER TABLE custom_foods ADD CONSTRAINT custom_foods_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES user_accounts(user_id) ON DELETE SET NULL;

-- Admin permanent account deletion ----------------------------------------
-- Two-step (archived only), never deletes admins, audits first, then
-- deletes the auth user — cascades wipe user_accounts -> children ->
-- all child data; SET NULLs preserve audit/code history.
CREATE OR REPLACE FUNCTION public.admin_delete_account_permanently(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_acc record;
BEGIN
  IF NOT public.is_system_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT * INTO v_acc FROM user_accounts
   WHERE user_id = p_user_id AND account_status = 'archived';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account not found or not archived — archive first';
  END IF;
  IF v_acc.account_role = 'system_admin' THEN
    RAISE EXCEPTION 'refusing to delete a system_admin account';
  END IF;

  INSERT INTO admin_audit_log
    (admin_user_id, admin_email, action_type, target_user_id,
     target_email, before_value, after_value, notes)
  VALUES
    (auth.uid(),
     (SELECT email FROM user_accounts WHERE user_id = auth.uid()),
     'account_permanently_deleted', p_user_id, v_acc.email,
     'archived', 'deleted', v_acc.email || ' (' || p_user_id || ')');

  DELETE FROM auth.users WHERE id = p_user_id;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.admin_delete_account_permanently(uuid) TO authenticated;
