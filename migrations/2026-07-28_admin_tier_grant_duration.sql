-- ═══════════════════════════════════════════════════════════════════
-- Admin tier grants get an explicit duration
--
-- APPLIED TO PRODUCTION 2026-07-28.
--
-- 2026-07-28_rewire_manual_tier_writers.sql made admin grants LIFETIME,
-- because a p_expires_at parameter would have created a second overload
-- that admin.js (calling with 3 args) would not have hit.
--
-- That was the wrong default. An admin picking "premium" from a dropdown
-- silently granted access forever, with nothing to expire and nothing to
-- review. Manual grants should follow the same shape as the real
-- subscriptions they stand in for: 1 month or 1 year.
--
-- Solved with a NEW, differently-named function rather than an overload,
-- so no DROP is needed and admin.js moves over explicitly.
-- change_user_subscription_tier now DELEGATES here, so there is exactly
-- one implementation to keep correct; grants made through that older
-- path remain lifetime.
--
-- Semantics worth knowing:
--   · The grant REPLACES any existing manual grant rather than extending
--     it — picking "1 month" for someone already on a year shortens
--     them. The admin UI shows the resulting end date in its
--     confirmation for exactly that reason.
--   · 'free' CLEARS the manual grant instead of storing 'free', so an
--     admin demotion cannot mask an active Apple subscription; recompute
--     then reports whatever Apple actually says.
--   · Returns the resulting expiry (NULL = lifetime) so the caller can
--     show it without a second round trip.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.admin_set_manual_tier(
    p_target_user_id uuid,
    p_new_tier       character varying,
    p_duration       character varying default 'month',
    p_notes          text default null::text
)
returns timestamptz
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
    v_admin_email  varchar;
    v_old_tier     varchar;
    v_target_email varchar;
    v_expires      timestamptz;
begin
    select email into v_admin_email from user_accounts
     where user_accounts.user_id = auth.uid()
       and user_accounts.account_role = 'system_admin';
    if v_admin_email is null then
        raise exception 'Only system_admin accounts can change subscription tiers';
    end if;

    if p_new_tier not in ('free', 'premium', 'pro') then
        raise exception 'Invalid tier: %', p_new_tier;
    end if;
    if p_duration not in ('month', 'year', 'lifetime') then
        raise exception 'Invalid duration: % (expected month, year or lifetime)', p_duration;
    end if;

    select subscription_tier, email into v_old_tier, v_target_email
      from user_accounts where user_accounts.user_id = p_target_user_id;
    if v_target_email is null then
        raise exception 'Target user not found';
    end if;

    v_expires := case
        when p_new_tier = 'free'   then null
        when p_duration = 'month'  then now() + interval '1 month'
        when p_duration = 'year'   then now() + interval '1 year'
        else null   -- lifetime
    end;

    update user_accounts
       set manual_tier            = case when p_new_tier = 'free' then null else p_new_tier end,
           manual_tier_expires_at = v_expires,
           manual_tier_source     = case when p_new_tier = 'free' then null else 'admin' end
     where user_accounts.user_id = p_target_user_id;

    perform recompute_user_entitlement(p_target_user_id);

    insert into admin_audit_log (
        admin_user_id, admin_email, action_type,
        target_user_id, target_email, before_value, after_value, notes
    ) values (
        auth.uid(), v_admin_email, 'tier_change',
        p_target_user_id, v_target_email, v_old_tier,
        case when p_new_tier = 'free' then 'free (manual grant cleared)'
             when v_expires is null then p_new_tier || ' (lifetime)'
             else p_new_tier || ' until ' || to_char(v_expires, 'YYYY-MM-DD') end,
        p_notes
    );

    return v_expires;
end;
$fn$;


-- Superseded, kept for any caller not migrated. Delegates so there is
-- only one implementation; grants through this path are lifetime.
create or replace function public.change_user_subscription_tier(
    p_target_user_id uuid,
    p_new_tier       character varying,
    p_notes          text default null::text
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
    perform admin_set_manual_tier(p_target_user_id, p_new_tier, 'lifetime', p_notes);
    return true;
end;
$fn$;

-- ═══════════════════════════════════════════════════════════════════
-- Verified on production 2026-07-28, with a simulated admin JWT
-- (set request.jwt.claims -> auth.uid()), then cleaned up:
--
--   admin_set_manual_tier(<free user>, 'premium', 'month')
--     -> tier=premium  exp=2026-08-28 (today + 1 month)  src=admin
--        manual=premium  msrc=admin                              ✅
--   admin_set_manual_tier(<same user>, 'free', ...)
--     -> grant cleared; baseline restored: 2 paid with original
--        expiries, 5 free, 0 stray admin grants                  ✅
--
-- The audit row is written for both directions.
-- ═══════════════════════════════════════════════════════════════════
