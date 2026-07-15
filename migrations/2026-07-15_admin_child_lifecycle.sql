-- ==========================================
-- Admin child lifecycle: restore / hard-delete / purge (2026-07-15).
-- Run in Supabase SQL editor. Requested by owner: "manage child
-- deletion and recovery" from admin.html.
--
-- WHY RPCs and not policies: children RLS grants parent / assigned
-- doctor / scientist — no admin arm, so admin.js's direct
-- children UPDATE in restoreArchivedChild was a silent no-op (0 rows).
-- Rather than widening children RLS for admins (broad read access to
-- all child health data), these narrow SECURITY DEFINER functions do
-- exactly three lifecycle actions and write admin_audit_log rows —
-- same pattern as change_user_subscription_tier / get_archived_children.
--
-- Safety model (industry standard soft-delete → grace → purge):
--   restore     archived → active, clears countdown.
--   delete now  HARD delete, allowed ONLY on already-archived children
--               (two-step: can never destroy an active profile).
--   purge       hard-deletes archived children whose
--               permanent_delete_after has passed — the countdown the
--               UI promises but nothing enforced until now.
-- Every action logs admin, target child, parent email, and a snapshot.
-- ==========================================

CREATE OR REPLACE FUNCTION public.admin_restore_child(p_child_id uuid)
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

  SELECT * INTO v_child FROM children WHERE child_id = p_child_id AND status = 'archived';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'child not found or not archived';
  END IF;
  SELECT email INTO v_parent_email FROM user_accounts WHERE user_id = v_child.parent_id;

  UPDATE children
     SET status = 'active', archived_at = NULL, archived_by = NULL,
         permanent_delete_after = NULL
   WHERE child_id = p_child_id;

  INSERT INTO admin_audit_log
    (admin_user_id, admin_email, action_type, target_user_id,
     target_child_id, target_email, before_value, after_value, notes)
  VALUES
    (auth.uid(),
     (SELECT email FROM user_accounts WHERE user_id = auth.uid()),
     'child_restored', v_child.parent_id, p_child_id, v_parent_email,
     'archived', 'active', v_child.name);
END;
$fn$;

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

  -- FK cascades wipe all dependent rows (nutrition, activity, sleep,
  -- measurements, medical events, ...).
  DELETE FROM children WHERE child_id = p_child_id;

  INSERT INTO admin_audit_log
    (admin_user_id, admin_email, action_type, target_user_id,
     target_child_id, target_email, before_value, after_value, notes)
  VALUES
    (auth.uid(),
     (SELECT email FROM user_accounts WHERE user_id = auth.uid()),
     'child_permanently_deleted', v_child.parent_id, p_child_id,
     v_parent_email, 'archived', 'deleted', v_child.name);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_purge_overdue_children()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_row record;
  v_count integer := 0;
BEGIN
  IF NOT public.is_system_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  FOR v_row IN
    SELECT c.child_id FROM children c
    WHERE c.status = 'archived'
      AND c.permanent_delete_after IS NOT NULL
      AND c.permanent_delete_after < now()
  LOOP
    PERFORM public.admin_delete_child_permanently(v_row.child_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.admin_restore_child(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_child_permanently(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_purge_overdue_children() TO authenticated;
