-- ═══════════════════════════════════════════════════════════════════
-- SECURITY Part 2: clamp privileged columns on client INSERT
--
-- APPLIED TO PRODUCTION 2026-07-28 via the Supabase SQL editor.
-- Part 1 is migrations/2026-07-28_user_accounts_column_grants.sql.
--
-- Part 1 closed the UPDATE vector with column-level grants. The same
-- escalation remained reachable at signup, because the initial insert
-- accepted client-supplied values for the privilege and entitlement
-- columns. (Described by category rather than as a runnable request —
-- this repository is public and the path is now closed.)
--
-- Why a trigger and not a REVOKE
-- ------------------------------
-- account_role cannot simply be revoked from clients:
--   * app.js:2236 sets it at signup (clinician onboarding uses it), and
--   * app_state.dart:131 self-heals a missing row with it — and that
--     code is in the LIVE iOS build, so revoking the column would break
--     new signups on a shipped app we cannot hot-fix.
--
-- Scope of the clamp
-- ------------------
-- Only 'system_admin' is actually dangerous. Verified by query: NO RLS
-- policy anywhere references account_role, and no function other than
-- is_system_admin() reads it — so doctor/scientist grant no database
-- privilege at all and only branch UI. They are deliberately left
-- assignable so clinician onboarding keeps working.
--
-- Trust model: clamp only requests arriving through PostgREST as
-- anon/authenticated. service_role (redeem-code, the admin RPC, and
-- Apple IAP from v1.1) and non-PostgREST contexts (SQL editor,
-- migrations, psql) carry no such claim and pass through untouched.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.clamp_user_account_privileges()
returns trigger
language plpgsql
as $fn$
declare
  v_role text := current_setting('request.jwt.claims', true)::json ->> 'role';
begin
  if v_role is null or v_role not in ('anon', 'authenticated') then
    return new;
  end if;

  if new.account_role is null or new.account_role::text = 'system_admin' then
    new.account_role := 'parent_subscriber';
  end if;

  new.subscription_tier := 'free';
  new.tier_expires_at := null;
  new.total_measurements_logged := 0;

  return new;
end;
$fn$;

create trigger trg_clamp_user_account_privileges
before insert on public.user_accounts
for each row execute function public.clamp_user_account_privileges();

-- ═══════════════════════════════════════════════════════════════════
-- Verification, run on production 2026-07-28. Exercises the function
-- against a temp table so no real row is touched, and rolls back.
--
--   begin;
--   create temp table probe (user_id uuid, email text, account_role text,
--     subscription_tier text, tier_expires_at timestamptz,
--     total_measurements_logged int) on commit drop;
--   create trigger t before insert on probe for each row
--     execute function public.clamp_user_account_privileges();
--
--   set local request.jwt.claims = '{"role":"authenticated"}';
--   insert into probe values (gen_random_uuid(),'1_attacker','system_admin','pro','2099-01-01',9999);
--   insert into probe values (gen_random_uuid(),'2_clinician','doctor','free',null,0);
--   insert into probe values (gen_random_uuid(),'3_normal','parent_subscriber','free',null,0);
--   set local request.jwt.claims = '{"role":"service_role"}';
--   insert into probe values (gen_random_uuid(),'4_serviceRole','system_admin','pro','2099-01-01',9999);
--   select * from probe order by email;
--   rollback;
--
-- Observed result — all four correct:
--   1_attacker      role=parent_subscriber  tier=free  exp=null  meas=0   <- blocked
--   2_clinician     role=doctor             tier=free  exp=null  meas=0   <- unbroken
--   3_normal        role=parent_subscriber  tier=free  exp=null  meas=0   <- unaffected
--   4_serviceRole   role=system_admin       tier=pro   exp=2099   meas=9999 <- bypass works
-- ═══════════════════════════════════════════════════════════════════
