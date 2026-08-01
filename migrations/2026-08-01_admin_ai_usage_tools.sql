-- ════════════════════════════════════════════════════════════════
-- Admin tools for per-family AI usage: a monitoring list and a
-- manual monthly reset (support gesture for a specific request —
-- e.g. a parent burned their bone-age reads on failed uploads).
--
-- ⚠️ DEPENDS ON migrations/2026-08-01_ai_feature_monthly_caps.sql
--    (ai_feature_usage_monthly + the cap columns). Apply that first.
-- ⚠️ SQL editor trap: these bodies are dollar-quoted — the Supabase
--    SQL editor silently drops statements from multi-statement
--    scripts with dollar-quoted bodies. RUN ONE FUNCTION PER
--    EXECUTION, then verify:
--      select proname from pg_proc
--       where proname like 'admin%ai_usage%';
--
-- Both functions follow change_user_subscription_tier's pattern:
-- SECURITY DEFINER + an in-body system_admin check on auth.uid(),
-- and every reset writes admin_audit_log.
-- Applied to production: 2026-08-01 — but statement 1 failed at runtime
-- with 42804 (user_accounts.email is text, return column declared varchar);
-- statement 2 is fine. Fixed statement 1 (email cast) re-apply: PENDING
-- ════════════════════════════════════════════════════════════════

-- ── Statement 1: the monitoring list ────────────────────────────
create or replace function public.admin_list_ai_usage()
returns table (
  user_id    uuid,
  email      varchar,
  tier       varchar,
  coach_used integer,
  coach_cap  integer,
  bone_used  integer,
  bone_cap   integer,
  lab_used   integer,
  lab_cap    integer
)
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_admin varchar;
  v_ym text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  select ua.email into v_admin from user_accounts ua
   where ua.user_id = auth.uid()
     and ua.account_role = 'system_admin';
  if v_admin is null then
    raise exception 'Only system_admin accounts can view AI usage';
  end if;

  return query
  select ua.user_id,
         ua.email::varchar,  -- live column is text; RETURN QUERY is strict about varchar vs text (42804)
         coalesce(ua.subscription_tier, 'free')::varchar,
         coalesce(l.call_count, 0),
         stl.live_ai_monthly_cap,
         coalesce(b.call_count, 0),
         stl.bone_age_monthly_cap,
         coalesce(la.call_count, 0),
         stl.lab_ai_monthly_cap
    from user_accounts ua
    left join subscription_tier_limits stl
      on stl.tier = coalesce(ua.subscription_tier, 'free')
    left join live_ai_usage_monthly l
      on l.user_id = ua.user_id and l.year_month = v_ym
    left join ai_feature_usage_monthly b
      on b.user_id = ua.user_id and b.year_month = v_ym
     and b.feature = 'bone_age'
    left join ai_feature_usage_monthly la
      on la.user_id = ua.user_id and la.year_month = v_ym
     and la.feature = 'lab_ai'
   order by coalesce(l.call_count, 0) + coalesce(b.call_count, 0)
          + coalesce(la.call_count, 0) desc,
            ua.email;
end;
$fn$;

-- ── Statement 2: the manual reset (run as its own execution) ────
create or replace function public.admin_reset_ai_usage(
    p_target_user_id uuid,
    p_feature        text,
    p_notes          text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_admin_email  varchar;
  v_target_email varchar;
  v_ym text := to_char(now() at time zone 'utc', 'YYYY-MM');
  v_before text;
begin
  select ua.email into v_admin_email from user_accounts ua
   where ua.user_id = auth.uid()
     and ua.account_role = 'system_admin';
  if v_admin_email is null then
    raise exception 'Only system_admin accounts can reset AI usage';
  end if;

  if p_feature not in ('coach', 'bone_age', 'lab_ai', 'all') then
    raise exception 'Invalid feature: %', p_feature;
  end if;

  select ua.email into v_target_email from user_accounts ua
   where ua.user_id = p_target_user_id;
  if v_target_email is null then
    raise exception 'Target user not found';
  end if;

  select concat(
    'coach=',    coalesce((select call_count from live_ai_usage_monthly
                            where live_ai_usage_monthly.user_id = p_target_user_id
                              and year_month = v_ym), 0),
    ' bone_age=', coalesce((select call_count from ai_feature_usage_monthly
                            where ai_feature_usage_monthly.user_id = p_target_user_id
                              and year_month = v_ym and feature = 'bone_age'), 0),
    ' lab_ai=',   coalesce((select call_count from ai_feature_usage_monthly
                            where ai_feature_usage_monthly.user_id = p_target_user_id
                              and year_month = v_ym and feature = 'lab_ai'), 0)
  ) into v_before;

  if p_feature in ('coach', 'all') then
    delete from live_ai_usage_monthly
     where live_ai_usage_monthly.user_id = p_target_user_id
       and year_month = v_ym;
  end if;
  if p_feature in ('bone_age', 'all') then
    delete from ai_feature_usage_monthly
     where ai_feature_usage_monthly.user_id = p_target_user_id
       and year_month = v_ym and feature = 'bone_age';
  end if;
  if p_feature in ('lab_ai', 'all') then
    delete from ai_feature_usage_monthly
     where ai_feature_usage_monthly.user_id = p_target_user_id
       and year_month = v_ym and feature = 'lab_ai';
  end if;

  insert into admin_audit_log (
      admin_user_id, admin_email, action_type,
      target_user_id, target_email, before_value, after_value, notes
  ) values (
      auth.uid(), v_admin_email, 'ai_usage_reset',
      p_target_user_id, v_target_email, v_before,
      p_feature || ' reset for ' || v_ym, p_notes
  );

  return true;
end;
$fn$;

-- Verify (after BOTH executions):
--   select proname from pg_proc where proname like 'admin%ai_usage%';
--   -- expect: admin_list_ai_usage, admin_reset_ai_usage
