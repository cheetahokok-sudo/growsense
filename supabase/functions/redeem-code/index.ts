// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: redeem-code
//
// Called when a parent submits an activation code in the Account screen.
// Validates the code, records a MANUAL grant, marks the code as used.
//
// ⚠️ Entitlement model (since the v1.1 IAP work):
//   This function writes manual_tier / manual_tier_expires_at /
//   manual_tier_source ONLY. It must never touch subscription_tier or
//   tier_expires_at — those are owned exclusively by
//   recompute_user_entitlement(), which combines the manual grant with
//   any Apple subscription and picks the winner. Writing them directly
//   again would resurrect the clobbering bug the split was built to fix.
//   See migrations/2026-07-28_iap_entitlement_foundation.sql.
//
// Security guarantees:
//   · Requires valid session JWT — unauthenticated users cannot redeem
//   · Code lookup is case-insensitive + whitespace-stripped
//   · One-time use enforced at DB level (redeemed_by unique constraint)
//   · Code expiry checked server-side
//   · IP logged for fraud detection
//   · Checks app_config.redemption_enabled before processing
//
// DEPLOY:
//   supabase functions deploy redeem-code --project-ref ogpkmcqaulohexanucng
//
//   (This file was called redeem-code.ts and was dashboard-pasted, unlike
//   the other six functions. The CLI requires <name>/index.ts, so it is
//   now named to match and deploys like everything else.)
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";

const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  if (!SUPABASE_URL || !SUPABASE_SRK) {
    return json({ error: "Service not configured" }, 500);
  }

  // ── 1. Authenticate caller ─────────────────────────────────────
  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!jwt) return json({ error: "Authentication required" }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SRK);
  const { data: { user }, error: authErr } = await admin.auth.getUser(jwt);
  if (authErr || !user) return json({ error: "Invalid or expired session" }, 401);

  // ── 2. Parse request ───────────────────────────────────────────
  let body: { code?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const rawCode = (body.code || "").trim().toUpperCase().replace(/\s+/g, "");
  if (!rawCode || rawCode.length < 6) {
    return json({ error: "Please enter a valid activation code" }, 400);
  }

  // ── 3. Check redemption is enabled (feature flag) ──────────────
  const { data: config } = await admin
    .from("app_config")
    .select("value")
    .eq("key", "redemption_enabled")
    .maybeSingle();

  if (config?.value !== "true") {
    return json({
      error: "Code redemption is not currently active. Check growsense.app for current promotions.",
    }, 403);
  }

  // ── 4. Look up the code ────────────────────────────────────────
  const { data: codeRow, error: codeErr } = await admin
    .from("activation_codes")
    .select("*")
    .eq("code", rawCode)
    .maybeSingle();

  if (codeErr || !codeRow) {
    console.log(`[redeem-code] Code not found: ${rawCode} by user ${user.id}`);
    return json({ error: "Code not found. Check for typos and try again." }, 404);
  }

  // ── 5. Validate: not already redeemed ─────────────────────────
  if (codeRow.redeemed_by) {
    if (codeRow.redeemed_by === user.id) {
      return json({ error: "You have already redeemed this code." }, 409);
    }
    return json({ error: "This code has already been used." }, 409);
  }

  // ── 6. Validate: code itself not expired ──────────────────────
  if (codeRow.code_expires_at && new Date(codeRow.code_expires_at) < new Date()) {
    return json({ error: "This code has expired and is no longer valid." }, 410);
  }

  // ── 7. Compute new MANUAL tier expiry ──────────────────────────
  // Redemption date + duration_days, stacking on any existing future
  // manual grant.
  //
  // ⚠️ Stacks from manual_tier_expires_at, NOT tier_expires_at.
  // tier_expires_at is the EFFECTIVE entitlement and may come from an
  // Apple subscription. Stacking a code onto Apple's expiry would hand
  // out free months and, worse, the next recompute would overwrite the
  // result with Apple's own date — silently destroying the granted time.
  // Codes own manual_*; Apple owns apple_subscriptions; the two are
  // combined by recompute_user_entitlement().
  const { data: currentAccount } = await admin
    .from("user_accounts")
    .select("manual_tier, manual_tier_expires_at")
    .eq("user_id", user.id)
    .maybeSingle();

  const base = (
    currentAccount?.manual_tier_expires_at &&
    new Date(currentAccount.manual_tier_expires_at) > new Date()
  )
    ? new Date(currentAccount.manual_tier_expires_at)  // stack on the grant
    : new Date();                                      // start from today

  const newExpiry = new Date(base);
  newExpiry.setDate(newExpiry.getDate() + codeRow.duration_days);

  // ── 8. Record the manual grant ─────────────────────────────────
  // Never writes subscription_tier / tier_expires_at / billing_source —
  // recompute_user_entitlement() is the only thing allowed to do that.
  const { error: upgradeErr } = await admin
    .from("user_accounts")
    .update({
      manual_tier:            codeRow.tier,
      manual_tier_expires_at: newExpiry.toISOString(),
      manual_tier_source:     "code",
      signup_promo_user:      true,
    })
    .eq("user_id", user.id);

  if (upgradeErr) {
    console.error("[redeem-code] Grant failed:", upgradeErr);
    return json({ error: "Could not apply upgrade. Please try again." }, 500);
  }

  // ── 8b. Fold the grant into the effective entitlement ──────────
  const { error: recomputeErr } = await admin
    .rpc("recompute_user_entitlement", { p_user_id: user.id });

  if (recomputeErr) {
    // The grant IS recorded, so this is recoverable rather than lost —
    // but the user would not see it yet, so fail loudly.
    console.error("[redeem-code] Recompute failed:", recomputeErr);
    return json({
      error: "Your code was accepted but access could not be activated. Please contact contact@growsense.life.",
    }, 500);
  }

  // ── 9. Mark code as redeemed ───────────────────────────────────
  const ip = req.headers.get("x-forwarded-for") ||
             req.headers.get("cf-connecting-ip") || "";

  await admin
    .from("activation_codes")
    .update({
      redeemed_by:  user.id,
      redeemed_at:  new Date().toISOString(),
      redeemed_ip:  ip.split(",")[0].trim(),
    })
    .eq("code_id", codeRow.code_id);

  // ── 10. Report the EFFECTIVE entitlement, not the raw grant ─────
  // Both clients mirror this response into local state (app.js:1571,
  // app_state.dart:1474), so it has to match what recompute actually
  // decided. They can differ: a user with an Apple subscription running
  // longer than the code keeps the later date, and telling them their
  // access ends sooner than it does would be simply wrong.
  const { data: effective } = await admin
    .from("user_accounts")
    .select("subscription_tier, tier_expires_at, billing_source")
    .eq("user_id", user.id)
    .maybeSingle();

  const tier = effective?.subscription_tier ?? codeRow.tier;
  const expiresAt = effective?.tier_expires_at ?? newExpiry.toISOString();
  const expiresDate = new Date(expiresAt);

  console.log(
    `[redeem-code] ✓ Code ${rawCode} (${codeRow.batch_name}) redeemed by ${user.id} → granted ${codeRow.tier} until ${newExpiry.toISOString().split("T")[0]}; effective ${tier} until ${expiresAt?.split?.("T")[0] ?? expiresAt} (source ${effective?.billing_source})`
  );

  return json({
    success:       true,
    tier,
    expires_at:    expiresAt,
    expires_date:  typeof expiresAt === "string" ? expiresAt.split("T")[0] : null,
    billing_source: effective?.billing_source ?? "code",
    duration_days: codeRow.duration_days,
    // What the code itself was worth, so the UI can say "added 365 days"
    // even when a longer Apple subscription is what is actually in force.
    granted_tier:       codeRow.tier,
    granted_expires_at: newExpiry.toISOString(),
    message: `Welcome to GrowSense ${tier === 'pro' ? 'Pro 👑' : 'Premium ⭐'}! Your access is active until ${expiresDate.toLocaleDateString('en-GB', { day:'numeric', month:'long', year:'numeric' })}.`,
  });
});
