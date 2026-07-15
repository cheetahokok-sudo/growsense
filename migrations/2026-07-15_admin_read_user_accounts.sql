-- ==========================================
-- Admin visibility on user_accounts (2026-07-15). Run in Supabase SQL editor.
--
-- ROOT CAUSE: user_accounts had exactly ONE policy — own-row, FOR ALL
-- ("Allow individual account data reading", auth.uid() = user_id).
-- Consequences discovered while wiring reporter emails into the bug
-- queue ("by unknown user"):
--   * admin.html could not resolve reporter emails (bug_reports join),
--   * the admin Users list / tier management silently saw & updated
--     ONLY the admin's own row this whole time.
-- bug_reports' own admin policies worked because they live on
-- bug_reports and only EXISTS-check the admin's OWN user_accounts row.
--
-- FIX: is_system_admin() as SECURITY DEFINER (a user_accounts policy
-- cannot subquery user_accounts itself — infinite recursion; the
-- definer function bypasses RLS internally, standard Supabase pattern)
-- + permissive admin SELECT/UPDATE policies alongside the own-row one.
-- Parents' privacy is unchanged: non-admin users still see only
-- themselves; the function leaks nothing (boolean about the caller).
-- ==========================================

CREATE OR REPLACE FUNCTION public.is_system_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_accounts
    WHERE user_id = auth.uid() AND account_role = 'system_admin'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_system_admin() TO authenticated;

DROP POLICY IF EXISTS "admins read all accounts" ON user_accounts;
CREATE POLICY "admins read all accounts" ON user_accounts
    FOR SELECT USING (public.is_system_admin());

-- Tier management from admin.html updates other users' rows — that
-- write path was a silent no-op before this policy existed.
DROP POLICY IF EXISTS "admins update accounts" ON user_accounts;
CREATE POLICY "admins update accounts" ON user_accounts
    FOR UPDATE USING (public.is_system_admin());
