// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: apple-verify-purchase
//
// Called by the Flutter client after a StoreKit purchase or restore.
// AUTHENTICATED — keeps Supabase's default JWT verification, unlike
// apple-notifications, because we must know WHICH user is buying.
//
//   supabase functions deploy apple-verify-purchase \
//     --project-ref ogpkmcqaulohexanucng
//
// The client's payload is never trusted. It is used only to learn which
// subscription to ask about; the entitlement itself comes from Apple's
// authenticated Server API, is written to apple_subscriptions, and the
// AFTER trigger there calls recompute_user_entitlement(). This function
// must never write subscription_tier itself.
//
// Accepts either shape, so plugin behaviour cannot break a Mac-less
// build:
//   · StoreKit 2 — a signed JWS transaction (three base64url segments)
//   · StoreKit 1 — a base64 PKCS#7 app receipt, which we cannot parse
//     without ASN.1 work; in that case the client must also send the
//     transactionId it already holds. Apple's endpoint accepts ANY
//     transaction id from the subscription, not just the original.
//
// Everything is logged to iap_verification_log. With no Mac there is no
// device console, so that table is the only place a failed first
// purchase can be diagnosed.
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  decodeJwsPayload,
  fetchSubscriptionState,
  persistSubscription,
} from "../_shared/apple.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";

const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

/** Three base64url segments whose header decodes to an ES256 JWS. */
function looksLikeJws(s: string): boolean {
  const parts = s.split(".");
  if (parts.length !== 3) return false;
  const header = decodeJwsPayload<{ alg?: string; x5c?: string[] }>(
    `x.${parts[0]}.x`,
  );
  return header?.alg === "ES256";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!SUPABASE_URL || !SUPABASE_SRK) {
    return json({ error: "Service not configured" }, 500);
  }

  const jwt = (req.headers.get("Authorization") || "")
    .replace("Bearer ", "")
    .trim();
  if (!jwt) return json({ error: "Authentication required" }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SRK);
  const { data: { user }, error: authErr } = await admin.auth.getUser(jwt);
  if (authErr || !user) return json({ error: "Invalid or expired session" }, 401);

  let body: { payload?: string; transactionId?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const payload = (body.payload ?? "").trim();
  const clientTxnId = (body.transactionId ?? "").trim();

  // ── Work out which subscription to ask Apple about ───────────────
  let shape = "unknown";
  let lookupId = "";

  if (payload && looksLikeJws(payload)) {
    shape = "sk2_jws";
    const txn = decodeJwsPayload<{
      originalTransactionId?: string;
      transactionId?: string;
    }>(payload);
    lookupId = txn?.originalTransactionId ?? txn?.transactionId ?? "";
  } else if (payload) {
    // StoreKit 1 app receipt — opaque to us without ASN.1 parsing.
    shape = "sk1_receipt";
  }
  if (!lookupId && clientTxnId) lookupId = clientTxnId;

  const logRow: Record<string, unknown> = {
    user_id: user.id,
    payload_shape: shape,
    app_account_token_present: false,
  };

  if (!lookupId) {
    logRow.outcome = "rejected";
    logRow.error = `no usable transaction id (shape=${shape})`;
    await admin.from("iap_verification_log").insert(logRow);
    return json({
      error: "Could not read the purchase. Please contact contact@growsense.life.",
    }, 400);
  }

  // ── Ask Apple what is actually true ──────────────────────────────
  try {
    const state = await fetchSubscriptionState(lookupId);
    if (!state) {
      logRow.original_transaction_id = lookupId;
      logRow.outcome = "rejected";
      logRow.error = "Apple returned no subscription for this id";
      await admin.from("iap_verification_log").insert(logRow);
      return json({ error: "Apple does not recognise this purchase." }, 404);
    }

    logRow.original_transaction_id = state.originalTransactionId;
    logRow.product_id = state.transaction.productId ?? null;
    logRow.environment = state.environment;
    logRow.app_account_token_present = !!state.transaction.appAccountToken;

    // ── One Apple subscription belongs to one GrowSense account ────
    // Without this, a single subscription could be restored onto
    // unlimited accounts, because entitlement lives on the server
    // account rather than the device. This is the usual way
    // self-hosted IAP leaks revenue.
    const { data: existing } = await admin
      .from("apple_subscriptions")
      .select("user_id")
      .eq("original_transaction_id", state.originalTransactionId)
      .maybeSingle();

    if (existing?.user_id && existing.user_id !== user.id) {
      logRow.outcome = "rejected";
      logRow.error = `already bound to ${existing.user_id}`;
      await admin.from("iap_verification_log").insert(logRow);
      return json({
        error: "in_use_by_other_account",
        message:
          "This subscription is already active on another GrowSense account. Sign in with that account, or contact contact@growsense.life.",
      }, 409);
    }

    const { tier, error: persistErr } = await persistSubscription(
      admin,
      state,
      user.id,
    );
    if (persistErr) {
      logRow.outcome = "error";
      logRow.error = persistErr;
      await admin.from("iap_verification_log").insert(logRow);
      return json({ error: "Could not activate the purchase." }, 500);
    }

    // persistSubscription's AFTER trigger already recomputed the
    // entitlement; read back what it decided.
    const { data: account } = await admin
      .from("user_accounts")
      .select("subscription_tier, tier_expires_at, billing_source")
      .eq("user_id", user.id)
      .maybeSingle();

    logRow.outcome = "ok";
    await admin.from("iap_verification_log").insert(logRow);

    console.log(
      `[apple-verify-purchase] ${user.id} ${shape} ${state.environment} ` +
        `oti=${state.originalTransactionId} status=${state.status} -> ` +
        `${account?.subscription_tier} until ${account?.tier_expires_at}`,
    );

    return json({
      success: true,
      tier: account?.subscription_tier ?? tier,
      expires_at: account?.tier_expires_at ?? null,
      billing_source: account?.billing_source ?? "apple",
      environment: state.environment,
    });
  } catch (e) {
    logRow.outcome = "error";
    logRow.error = String(e).slice(0, 500);
    await admin.from("iap_verification_log").insert(logRow);
    console.error("[apple-verify-purchase] failed:", e);
    return json({ error: "Could not verify the purchase. Please try again." }, 500);
  }
});
