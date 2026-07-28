-- ═══════════════════════════════════════════════════════════════════
-- Rewire the manual entitlement writers onto the new model
--
-- APPLIED TO PRODUCTION 2026-07-28.
-- Companion to 2026-07-28_iap_entitlement_foundation.sql — that file
-- created the split, this one moves the existing writers onto it.
--
-- Both writers of manual entitlement must stop touching
-- subscription_tier / tier_expires_at, which are now owned exclusively
-- by recompute_user_entitlement(). Until they do, a redemption or an
-- admin grant writes the effective columns directly and the next
-- recompute overwrites it — the exact clobbering the split exists to
-- prevent.
--
--   1. redeem-code edge function — see supabase/functions/redeem-code/
--      index.ts (deployed separately; it also had to be renamed from
--      redeem-code.ts, since the CLI requires <name>/index.ts and this
--      was the one function still being dashboard-pasted).
--   2. change_user_subscription_tier — below.
-- ═══════════════════════════════════════════════════════════════════

-- ⚠️ Deliberately CREATE OR REPLACE on the EXISTING 3-argument
-- signature rather than adding a p_expires_at parameter.
--
-- Adding a defaulted 4th argument would have created a second overload,
-- and admin.js calls with 3 arguments — which would have resolved to the
-- OLD, still-broken body. Replacing in place avoids that entirely and
-- needs no client change. (Dropping the old signature was the
-- alternative; it was not available here.)
--
-- Consequence: an admin grant is now a LIFETIME grant
-- (manual_tier_expires_at = null). That is still strictly better than
-- the behaviour it replaces — the old body set subscription_tier and
-- NEVER touched tier_expires_at, so promoting a user whose expiry was
-- already in the past did nothing at all: isPremium kept returning
-- false and the admin had no way to tell. If dated admin grants are
-- wanted later, add a separately-named function rather than an overload.
--
-- Downgrading to 'free' CLEARS the manual grant instead of storing
-- 'free', so an admin demotion cannot mask an active Apple subscription
-- — recompute then reports whatever Apple actually says.

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
declare
    v_admin_email  varchar;
    v_old_tier     varchar;
    v_target_email varchar;
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

    select subscription_tier, email into v_old_tier, v_target_email
      from user_accounts where user_accounts.user_id = p_target_user_id;

    if v_target_email is null then
        raise exception 'Target user not found';
    end if;

    update user_accounts
       set manual_tier            = case when p_new_tier = 'free' then null else p_new_tier end,
           manual_tier_expires_at = null,
           manual_tier_source     = case when p_new_tier = 'free' then null else 'admin' end
     where user_accounts.user_id = p_target_user_id;

    perform recompute_user_entitlement(p_target_user_id);

    insert into admin_audit_log (
        admin_user_id, admin_email, action_type,
        target_user_id, target_email, before_value, after_value, notes
    ) values (
        auth.uid(), v_admin_email, 'tier_change',
        p_target_user_id, v_target_email, v_old_tier,
        p_new_tier || case when p_new_tier = 'free'
                           then ' (manual grant cleared)' else ' (lifetime)' end,
        p_notes
    );

    return true;
end;
$fn$;

-- Verified on production 2026-07-28:
--   writes manual_tier = true
--   calls recompute_user_entitlement = true
--   still writes subscription_tier directly = false
--   overloads = 1   (no stale 3-arg version left behind)


-- ═══════════════════════════════════════════════════════════════════
-- END-TO-END TEST OF THE ENTITLEMENT MODEL, run on production
-- 2026-07-28 against a free account, then fully cleaned up.
--
--   1. Simulated a code grant (manual_tier='premium', now+30d) and
--      called recompute
--        -> free account became premium, exp 2026-08-27, src=code   ✅
--
--   2. Inserted an Apple subscription expiring 200 days out, WITHOUT
--      calling recompute — to prove the AFTER trigger fires
--        -> exp moved to 2027-02-13, src=apple                      ✅
--
--   3. Set revocation_date on that subscription (the refund case)
--        -> fell back to the code grant, exp 2026-08-27, src=code,
--           even though the Apple row still said exp 2027-02-13.
--           revocation beats a future expiry, which is what stops
--           buy -> run one AI analysis -> refund.                   ✅
--
--   4. Deleted the test row, cleared the manual grant, recomputed all
--        -> baseline restored exactly: 2 paid with original expiries
--           (2027-07-04, 2026-08-14), 5 free, 0 apple rows.         ✅
--
-- NOTE FOR LATER: the recompute trigger covers INSERT and UPDATE but
-- NOT DELETE, so removing an apple_subscriptions row by hand leaves the
-- entitlement stale. Nothing in the app deletes them (revocation is an
-- UPDATE), but call recompute manually if you ever do.
-- ═══════════════════════════════════════════════════════════════════
