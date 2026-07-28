-- ═══════════════════════════════════════════════════════════════════
-- v1.1 IAP — entitlement foundation
--
-- ✅ APPLIED TO PRODUCTION 2026-07-28, verified (see the bottom of this file).
--
-- ⚠️  HOW TO APPLY THIS FILE — do NOT paste it in one go.
-- The Supabase SQL editor SILENTLY DROPS statements from multi-statement
-- scripts containing dollar-quoted function bodies. It reports
-- "Success. No rows returned" while creating nothing. During this apply
-- it swallowed three CREATE FUNCTIONs and both CREATE TRIGGERs, twice,
-- and only a follow-up existence query caught it.
-- Apply section by section, ONE function or ONE trigger per run, and
-- verify each object exists in pg_proc / pg_trigger before moving on.
-- Never trust the editor's success message.
--
-- Creates the Apple-side tables and, more importantly, fixes the fact
-- that user_accounts.subscription_tier / tier_expires_at are about to
-- have THREE writers (activation codes, the admin RPC, and Apple) that
-- would silently clobber each other.
--
-- THE BUG THIS PREVENTS
-- ---------------------
-- redeem-code.ts step 8 EXTENDS FROM the current tier_expires_at. So if
-- Apple wrote 2026-09-01 and the user redeems a 365-day code, they get
-- 2027-09-01 — and then the next DID_RENEW recompute writes Apple's own
-- expiry straight over it and the user silently loses a year they were
-- granted. Conversely an admin lifetime grant (NULL) gets clobbered to a
-- date by any Apple renewal.
--
-- THE SHAPE OF THE FIX
-- --------------------
-- Manual entitlement (codes, admin grants) moves to its own columns.
-- Apple entitlement lives in its own table. A single function decides
-- the winner and writes the two legacy columns.
--
--   manual_tier / manual_tier_expires_at ─┐
--                                          ├─► recompute_user_entitlement()
--   apple_subscriptions ────────────────── ┘        │
--                                                   ▼
--                              user_accounts.subscription_tier
--                                            .tier_expires_at
--                                            .billing_source
--
-- Every existing READER is untouched — app_state.dart:346, app.js:1453,
-- and the service-role checks in bone-age-analysis, lab-ai-analysis and
-- ai-coach-proxy all keep reading subscription_tier exactly as today.
-- That property is what makes this affordable.
--
-- AUDITED STATE THIS IS WRITTEN AGAINST (2026-07-28)
-- --------------------------------------------------
--   * 7 accounts, 2 paid — both 'premium', both billing_source='code',
--     expiring 2027-07-04 and 2026-08-14. The backfill is two rows.
--   * No manual_* columns and no apple_* tables exist yet.
--   * subscription_tier CHECK is (free|premium|pro).
--   * Dead columns present but NOT touched here: tier, subscription_status,
--     subscription_expires_at (0 code references between them).
--
-- ⚠️  DEPLOY ORDER — read before applying
--   1. Apply this migration (the backfill below must run BEFORE any Apple
--      write, or the first recompute wipes the code-granted users).
--   2. Update redeem-code.ts to write manual_* and call recompute.
--      Until that lands, redemptions still write subscription_tier
--      directly. That is harmless ONLY because nothing calls recompute
--      yet — the Apple functions do not exist. Do not build them first.
--   3. Then build apple-verify-purchase / apple-notifications.
-- ═══════════════════════════════════════════════════════════════════


-- ── 1. Tier ranking helper ───────────────────────────────────────────
create or replace function public.tier_rank(p_tier text)
returns int
language sql
immutable
as $$
  select case p_tier when 'pro' then 2 when 'premium' then 1 else 0 end;
$$;


-- ── 2. Manual entitlement columns ────────────────────────────────────
-- Codes and admin grants write HERE, never to subscription_tier.
-- NULL manual_tier_expires_at means a lifetime grant, and that is
-- meaningfully different from an expired one.
alter table public.user_accounts
  add column if not exists manual_tier text
    check (manual_tier is null or manual_tier in ('free','premium','pro')),
  add column if not exists manual_tier_expires_at timestamptz,
  add column if not exists manual_tier_source text
    check (manual_tier_source is null or manual_tier_source in ('code','admin'));

comment on column public.user_accounts.manual_tier is
  'Entitlement granted by activation code or admin. NULL expiry = lifetime. '
  'Never write subscription_tier directly — call recompute_user_entitlement().';

-- ⚠️ These new columns are an ESCALATION VECTOR if left unguarded.
--
-- UPDATE is already safe: 2026-07-28_user_accounts_column_grants.sql
-- revoked table-level UPDATE and granted only three named columns, so a
-- newly added column inherits no update grant at all.
--
-- INSERT is NOT safe. `authenticated` still holds table-level INSERT
-- (all 17 columns), and table-level grants automatically cover columns
-- added later. So without the change below, a client could sign up
-- POSTing manual_tier='pro' — the existing clamp trigger forces
-- subscription_tier='free' but knows nothing about manual_tier, and the
-- first recompute would then hand them Pro.
--
-- Fixed two ways, deliberately belt-and-braces:
--   (a) extend the clamp trigger to null the manual_* columns, and
--   (b) narrow the INSERT grant to the three columns clients actually
--       insert (app.js:2236, app_state.dart:131).
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

  -- NEW: manual entitlement is granted by redeem-code or an admin, never
  -- self-assigned at signup.
  new.manual_tier := null;
  new.manual_tier_expires_at := null;
  new.manual_tier_source := null;

  return new;
end;
$fn$;

revoke insert on public.user_accounts from anon, authenticated;
grant  insert (user_id, email, account_role)
  on public.user_accounts to authenticated;


-- ── 3. Apple subscription state ──────────────────────────────────────
-- Keyed on original_transaction_id: it is the ONLY stable identity of a
-- subscription. transactionId changes on every renewal; this does not.
-- It is also the sole join key back to a GrowSense user when a REFUND
-- notification arrives at 3am carrying no user identity, and as a PRIMARY
-- KEY it structurally enforces one Apple subscription -> one account,
-- which is the usual way self-hosted IAP leaks revenue.
create table if not exists public.apple_subscriptions (
  original_transaction_id  text primary key,

  -- ON DELETE SET NULL, deliberately. If this cascaded, deleting the
  -- account would erase the mapping while Apple keeps charging: refunds
  -- would have nowhere to land and a re-signup could not restore. The row
  -- survives as an orphan keyed by OTI and re-binds on a later restore.
  -- ⚠️ Do NOT add this table to USER_TABLES in delete-account/index.ts.
  user_id                  uuid references auth.users(id) on delete set null,

  product_id               text not null,
  tier                     text not null
    check (tier in ('premium','pro')),
  environment              text not null
    check (environment in ('Sandbox','Production')),

  latest_transaction_id    text,
  purchase_date            timestamptz,
  expires_at               timestamptz,

  -- Apple's status enum: 1 active, 2 expired, 3 billing retry,
  -- 4 grace period, 5 revoked.
  status                   smallint,
  auto_renew_status        boolean,
  auto_renew_product_id    text,
  grace_period_expires_at  timestamptz,

  -- revocation_date always beats a future expires_at. Buy -> run one AI
  -- analysis -> refund is the realistic abuse vector for this product.
  revocation_date          timestamptz,
  revocation_reason        smallint,

  is_upgraded              boolean,
  offer_type               smallint,
  offer_identifier         text,

  -- StoreKit 2 appAccountToken. We pass the Supabase user id as
  -- applicationUserName at purchase, so a notification arriving before
  -- (or instead of) the client's verify call can still be attributed.
  app_account_token        uuid,

  last_notification_type   text,
  last_notification_subtype text,
  last_synced_at           timestamptz,
  raw_status_response      jsonb,

  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index if not exists apple_subscriptions_user_id_idx
  on public.apple_subscriptions (user_id);
-- Drives the reconcile cron that re-resolves subscriptions about to lapse.
create index if not exists apple_subscriptions_expires_at_idx
  on public.apple_subscriptions (expires_at);


-- ── 4. Notification log — this IS the idempotency mechanism ──────────
-- Apple redelivers on any perceived failure, and its retries are not
-- rare. Inserting on the UUID primary key first, and returning 200 on
-- conflict, is what makes the receiver safe to redeliver into.
-- It is also the observability surface: with no Mac and no device
-- console, this table is how the Apple integration gets debugged.
create table if not exists public.apple_notification_log (
  notification_uuid        text primary key,
  notification_type        text,
  subtype                  text,
  original_transaction_id  text,
  environment              text,
  signed_date              timestamptz,
  received_at              timestamptz not null default now(),
  processed                boolean not null default false,
  error                    text,
  payload                  jsonb            -- decoded, not the raw JWS
);

create index if not exists apple_notification_log_oti_idx
  on public.apple_notification_log (original_transaction_id);
create index if not exists apple_notification_log_received_idx
  on public.apple_notification_log (received_at desc);


-- ── 5. Client-verify log ─────────────────────────────────────────────
-- Same reasoning: no device console, so a failed first purchase can only
-- be diagnosed from the server side.
create table if not exists public.iap_verification_log (
  id                       bigint generated always as identity primary key,
  created_at               timestamptz not null default now(),
  user_id                  uuid,
  payload_shape            text,   -- sk2_jws | sk1_receipt | unknown
  original_transaction_id  text,
  product_id               text,
  environment              text,
  app_account_token_present boolean,
  outcome                  text,   -- ok | rejected | error
  error                    text
);

create index if not exists iap_verification_log_user_idx
  on public.iap_verification_log (user_id, created_at desc);


-- ── 6. Lock the new tables down ──────────────────────────────────────
-- RLS on with NO policies = nothing reachable for anon/authenticated;
-- service_role bypasses RLS. The explicit REVOKE is belt-and-braces,
-- because today's audit showed default grants are broad and that is
-- precisely how the user_accounts hole arose.
alter table public.apple_subscriptions    enable row level security;
alter table public.apple_notification_log enable row level security;
alter table public.iap_verification_log   enable row level security;

revoke all on public.apple_subscriptions    from anon, authenticated;
revoke all on public.apple_notification_log from anon, authenticated;
revoke all on public.iap_verification_log   from anon, authenticated;


-- ── 7. The single entitlement writer ─────────────────────────────────
create or replace function public.recompute_user_entitlement(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_manual_tier   text;
  v_manual_exp    timestamptz;
  v_manual_src    text;
  v_manual_active boolean;

  v_apple_tier    text;
  v_apple_exp     timestamptz;
  v_apple_active  boolean;

  v_tier          text := 'free';
  v_exp           timestamptz := null;
  v_source        text := 'none';
begin
  select ua.manual_tier, ua.manual_tier_expires_at, ua.manual_tier_source
    into v_manual_tier, v_manual_exp, v_manual_src
    from user_accounts ua
   where ua.user_id = p_user_id;

  v_manual_active :=
        v_manual_tier is not null
    and v_manual_tier <> 'free'
    and (v_manual_exp is null or v_manual_exp > now());

  -- Best currently-active Apple subscription for this user.
  -- Active = not revoked AND (Apple says active/grace OR not yet expired).
  select s.tier, s.expires_at
    into v_apple_tier, v_apple_exp
    from apple_subscriptions s
   where s.user_id = p_user_id
     and s.revocation_date is null
     and (s.status in (1, 4)
          or (s.expires_at is not null and s.expires_at > now()))
   order by tier_rank(s.tier) desc, s.expires_at desc nulls last
   limit 1;

  v_apple_active := v_apple_tier is not null;

  if v_manual_active and not v_apple_active then
    v_tier := v_manual_tier; v_exp := v_manual_exp;
    v_source := coalesce(v_manual_src, 'code');

  elsif v_apple_active and not v_manual_active then
    v_tier := v_apple_tier; v_exp := v_apple_exp; v_source := 'apple';

  elsif v_manual_active and v_apple_active then
    if tier_rank(v_manual_tier) > tier_rank(v_apple_tier) then
      v_tier := v_manual_tier; v_exp := v_manual_exp;
      v_source := coalesce(v_manual_src, 'code');
    elsif tier_rank(v_apple_tier) > tier_rank(v_manual_tier) then
      v_tier := v_apple_tier; v_exp := v_apple_exp; v_source := 'apple';
    -- Same tier: the later expiry wins, and a lifetime grant (NULL)
    -- beats any date. Never shorten what someone already holds.
    elsif v_manual_exp is null
       or (v_apple_exp is not null and v_manual_exp >= v_apple_exp) then
      v_tier := v_manual_tier; v_exp := v_manual_exp;
      v_source := coalesce(v_manual_src, 'code');
    else
      v_tier := v_apple_tier; v_exp := v_apple_exp; v_source := 'apple';
    end if;
  end if;

  update user_accounts
     set subscription_tier = v_tier,
         tier_expires_at   = v_exp,
         billing_source    = v_source
   where user_id = p_user_id;
end;
$fn$;

comment on function public.recompute_user_entitlement(uuid) is
  'The ONLY thing that may write subscription_tier / tier_expires_at. '
  'Codes and admin grants write manual_*; Apple writes apple_subscriptions.';


-- ── 8. Keep Apple writes consistent automatically ────────────────────
-- So apple-verify-purchase and apple-notifications cannot forget to
-- recompute. Two triggers, and the split matters:
--
--   BEFORE — stamp updated_at, which requires mutating NEW.
--   AFTER  — recompute, which QUERIES apple_subscriptions. In a BEFORE
--            trigger the new row is not yet visible to that query, so a
--            first purchase would compute entitlement from a table that
--            does not contain it and grant nothing at all.
create or replace function public.apple_subscription_touch()
returns trigger
language plpgsql
as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

create or replace function public.apple_subscription_recompute()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  if new.user_id is not null then
    perform recompute_user_entitlement(new.user_id);
  end if;
  -- A restore that re-binds an OTI to a different account must also
  -- demote the account that lost it.
  if tg_op = 'UPDATE' and old.user_id is not null
     and old.user_id is distinct from new.user_id then
    perform recompute_user_entitlement(old.user_id);
  end if;
  return null;  -- AFTER trigger: return value is ignored
end;
$fn$;

drop trigger if exists trg_apple_subscription_touch on public.apple_subscriptions;
create trigger trg_apple_subscription_touch
before insert or update on public.apple_subscriptions
for each row execute function public.apple_subscription_touch();

drop trigger if exists trg_apple_subscription_recompute on public.apple_subscriptions;
create trigger trg_apple_subscription_recompute
after insert or update on public.apple_subscriptions
for each row execute function public.apple_subscription_recompute();


-- ── 9. BACKFILL — must run before any Apple write ────────────────────
-- Everything currently entitled was granted manually (both live rows are
-- billing_source='code'). Move that into manual_* so the first recompute
-- does not wipe it.
update public.user_accounts
   set manual_tier            = subscription_tier,
       manual_tier_expires_at = tier_expires_at,
       manual_tier_source     = case when billing_source = 'admin'
                                     then 'admin' else 'code' end
 where subscription_tier is not null
   and subscription_tier <> 'free'
   and manual_tier is null;


-- ═══════════════════════════════════════════════════════════════════
-- VERIFY AFTER APPLYING — expect exactly 2 rows, unchanged entitlement
--
--   select email, subscription_tier, tier_expires_at, billing_source,
--          manual_tier, manual_tier_expires_at, manual_tier_source
--     from user_accounts
--    where subscription_tier <> 'free' or manual_tier is not null;
--
-- Then prove recompute is a no-op for them (it must NOT downgrade
-- anyone), inside a transaction you roll back:
--
--   begin;
--   select recompute_user_entitlement(user_id) from user_accounts;
--   select email, subscription_tier, tier_expires_at, billing_source
--     from user_accounts where subscription_tier <> 'free';
--   -- expect the SAME 2 premium rows, expiries unchanged,
--   -- billing_source now 'code'
--   rollback;
--
-- Guard: no one should be entitled without a source.
--   select count(*) from user_accounts
--    where subscription_tier <> 'free' and manual_tier is null;   -- 0
--
-- ── ACTUAL RESULT, production, 2026-07-28 ───────────────────────────
-- Backfill:
--   cheetahokok@gmail.com  tier=premium exp=2027-07-04 src=code
--                          manual=premium mexp=2027-07-04 msrc=code
--   peempatpi@gmail.com    tier=premium exp=2026-08-14 src=code
--                          manual=premium mexp=2026-08-14 msrc=code
--   entitled-without-source = 0      free-rows-touched = 0
--
-- recompute_user_entitlement() then run across ALL 7 accounts:
--   PAID COUNT = 2 (both expiries UNCHANGED)   FREE COUNT = 5
--   free rows carrying a stale expiry = 0
-- i.e. a clean no-op for existing users, which is the whole point.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- COMPANION CHANGES — required, NOT in this file
--
-- a) redeem-code.ts step 8: write manual_tier / manual_tier_expires_at /
--    manual_tier_source='code' and then call recompute_user_entitlement.
--    Keep its existing stacking behaviour, but stack from
--    manual_tier_expires_at rather than tier_expires_at.
--
-- b) change_user_subscription_tier: write manual_* + recompute. While
--    there, fix the bug the audit found — it currently sets
--    subscription_tier and NEVER touches tier_expires_at, so an admin
--    upgrading a user whose expiry is in the past does nothing at all.
--    Add an explicit expiry argument (default NULL = lifetime) rather
--    than leaving a stale date in place.
--
-- c) delete-account/index.ts: do NOT add apple_subscriptions to
--    USER_TABLES (see the FK comment above). Apple also requires telling
--    the user their subscription continues and must be cancelled in
--    Settings — the delete confirmation needs that line.
-- ═══════════════════════════════════════════════════════════════════
