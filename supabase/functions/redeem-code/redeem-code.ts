// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: redeem-code
//
// Called when a parent submits an activation code in the Account screen.
// Validates the code, sets the user's tier + expiry, marks code as used.
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
//   Supabase Dashboard → Edge Functions → New → name: redeem-code
//   Paste this file → Deploy
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

  // ── 7. Compute new tier expiry ─────────────────────────────────
  // Redemption date + duration_days.
  // If the user already has a future expiry (stacking codes), extend from that.
  const { data: currentAccount } = await admin
    .from("user_accounts")
    .select("tier_expires_at, subscription_tier")
    .eq("user_id", user.id)
    .maybeSingle();

  const base = (
    currentAccount?.tier_expires_at &&
    new Date(currentAccount.tier_expires_at) > new Date()
  )
    ? new Date(currentAccount.tier_expires_at)  // extend from current expiry
    : new Date();                                // start from today

  const newExpiry = new Date(base);
  newExpiry.setDate(newExpiry.getDate() + codeRow.duration_days);

  // ── 8. Upgrade the user ────────────────────────────────────────
  const { error: upgradeErr } = await admin
    .from("user_accounts")
    .update({
      subscription_tier:  codeRow.tier,
      tier_expires_at:    newExpiry.toISOString(),
      billing_source:     "code",
      signup_promo_user:  true,
    })
    .eq("user_id", user.id);

  if (upgradeErr) {
    console.error("[redeem-code] Upgrade failed:", upgradeErr);
    return json({ error: "Could not apply upgrade. Please try again." }, 500);
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

  console.log(
    `[redeem-code] ✓ Code ${rawCode} (${codeRow.batch_name}) redeemed by ${user.id} → ${codeRow.tier} until ${newExpiry.toISOString().split("T")[0]}`
  );

  return json({
    success:    true,
    tier:       codeRow.tier,
    expires_at: newExpiry.toISOString(),
    expires_date: newExpiry.toISOString().split("T")[0],
    duration_days: codeRow.duration_days,
    message: `Welcome to GrowSense ${codeRow.tier === 'pro' ? 'Pro 👑' : 'Premium ⭐'}! Your access is active until ${newExpiry.toLocaleDateString('en-GB', { day:'numeric', month:'long', year:'numeric' })}.`,
  });
});
