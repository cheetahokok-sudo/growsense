-- ==========================================
-- Fix: admin child hard-delete blocked by the audit table's own FK
-- (2026-07-15, applied live same day). Found in owner testing:
-- Restore worked, Delete-now failed.
--
-- CAUSE (two-part, both from admin_audit_log.target_child_id):
--   1. The FK was NO ACTION, so any audit row referencing the child
--      (e.g. the one written by the successful Restore test!) blocked
--      DELETE FROM children.
--   2. admin_delete_child_permanently inserted its audit row AFTER the
--      delete, violating the same FK even with no prior rows.
--
-- FIX: FK -> ON DELETE SET NULL (audit rows must outlive the child;
-- name was already snapshotted in notes), and the function now writes
-- the audit row BEFORE the delete (atomic — rolls back together), with
-- the child uuid appended to notes since target_child_id nulls out.
-- (ai_usage_log.child_id was checked too: already SET NULL + nullable,
-- not a blocker.)
-- ==========================================

ALTER TABLE admin_audit_log DROP CONSTRAINT admin_audit_log_target_child_id_fkey;
ALTER TABLE admin_audit_log ADD CONSTRAINT admin_audit_log_target_child_id_fkey
  FOREIGN KEY (target_child_id) REFERENCES children(child_id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.admin_delete_child_permanently(p_child_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_child record;
  v_parent_email text;
BEGIN
  IF NOT public.is_system_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  -- Two-step safety: only an ALREADY-ARCHIVED child can be hard-deleted.
  SELECT * INTO v_child FROM children WHERE child_id = p_child_id AND status = 'archived';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'child not found or not archived — archive first';
  END IF;
  SELECT email INTO v_parent_email FROM user_accounts WHERE user_id = v_child.parent_id;

  -- Audit FIRST (atomic with the delete; rolls back together on error).
  -- target_child_id SET-NULLs when the child row goes, so the uuid is
  -- also snapshotted in notes for forensics.
  INSERT INTO admin_audit_log
    (admin_user_id, admin_email, action_type, target_user_id,
     target_child_id, target_email, before_value, after_value, notes)
  VALUES
    (auth.uid(),
     (SELECT email FROM user_accounts WHERE user_id = auth.uid()),
     'child_permanently_deleted', v_child.parent_id, p_child_id,
     v_parent_email, 'archived', 'deleted',
     v_child.name || ' (' || p_child_id || ')');

  -- FK cascades wipe all dependent child-data rows.
  DELETE FROM children WHERE child_id = p_child_id;
END;
$fn$;
