// ══════════════════════════════════════════════════════════════════
// Shared App Store Server API client + entitlement mapping.
//
// DESIGN: notifications are TRIGGERS, not truth.
//
// Nothing that arrives from the outside is trusted. Every entitlement
// write goes through resolveAppleEntitlement(originalTransactionId),
// which asks Apple's own API for the current state and recomputes from
// scratch. We never write "extend by a month" — only "Apple says this
// expires at X with status Y".
//
// Consequences, all of them good:
//   · A forged notification costs one wasted API call to Apple and can
//     never produce a wrong entitlement.
//   · The ~20 notification types collapse into ONE code path.
//   · Idempotency is free — replaying a notification recomputes the
//     same answer.
//   · A missed notification self-heals on the next event or reconcile.
//
// It also means we do not need x5c certificate-chain validation against
// Apple's root CA on the correctness path. That is the part of a
// self-hosted IAP integration where a subtle mistake becomes a security
// hole rather than a bug.
//
// The ES256 JWT signing below is empirically confirmed against Apple:
// probing GET /inApps/v1/subscriptions/<bogus> returns 400
// errorCode 4000006 "Invalid transaction id" on both hosts — i.e. Apple
// validated the signature, issuer, key id and bundle id, and rejected
// only the fake id. A broken JWT returns 401.
// ══════════════════════════════════════════════════════════════════

import * as jose from "npm:jose@5";

const KEY_ID = Deno.env.get("APPLE_IAP_KEY_ID") ?? "";
const ISSUER_ID = Deno.env.get("APPLE_IAP_ISSUER_ID") ?? "";
const BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") ?? "";
const RAW_KEY = Deno.env.get("APPLE_IAP_PRIVATE_KEY") ?? "";

export const APPLE_BUNDLE_ID = BUNDLE_ID;

const PROD_HOST = "https://api.storekit.itunes.apple.com";
const SANDBOX_HOST = "https://api.storekit-sandbox.itunes.apple.com";

/** Product id → entitlement tier. Must agree with App Store Connect. */
const PRODUCT_TIERS: Record<string, "premium" | "pro"> = {
  "life.growsense.premium.monthly": "premium",
  "life.growsense.premium.yearly": "premium",
};

export function tierForProduct(productId: string): "premium" | "pro" | null {
  return PRODUCT_TIERS[productId] ?? null;
}

// ── JWT ────────────────────────────────────────────────────────────
// Apple caps token lifetime at 60 minutes. Cache in module scope and
// re-sign a little early rather than per request.
let cachedJwt: { token: string; expiresAt: number } | null = null;

/** A .p8 pasted through some editors arrives with literal \n. */
function normalizePem(raw: string): string {
  return raw.includes("\\n") ? raw.replace(/\\n/g, "\n") : raw;
}

export async function appleJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwt.expiresAt - 120 > now) return cachedJwt.token;

  if (!RAW_KEY || !KEY_ID || !ISSUER_ID || !BUNDLE_ID) {
    throw new Error(
      "Apple IAP secrets missing: need APPLE_IAP_PRIVATE_KEY, APPLE_IAP_KEY_ID, APPLE_IAP_ISSUER_ID, APPLE_BUNDLE_ID",
    );
  }

  const key = await jose.importPKCS8(normalizePem(RAW_KEY), "ES256");
  const exp = now + 3000; // 50 min, inside Apple's 60 min ceiling
  const token = await new jose.SignJWT({ bid: BUNDLE_ID })
    .setProtectedHeader({ alg: "ES256", kid: KEY_ID, typ: "JWT" })
    .setIssuer(ISSUER_ID)
    .setIssuedAt(now)
    .setExpirationTime(exp)
    .setAudience("appstoreconnect-v1")
    .sign(key);

  cachedJwt = { token, expiresAt: exp };
  return token;
}

// ── JWS payload decoding ───────────────────────────────────────────
/**
 * Decode a compact JWS payload WITHOUT verifying its signature.
 *
 * Safe here precisely because nothing decoded this way is trusted: it is
 * only used to learn WHICH subscription to ask Apple about, and to log.
 * Every value that reaches the database comes from the authenticated
 * Server API response instead.
 */
export function decodeJwsPayload<T = Record<string, unknown>>(
  jws: string,
): T | null {
  try {
    const part = jws.split(".")[1];
    if (!part) return null;
    const json = new TextDecoder().decode(
      jose.base64url.decode(part),
    );
    return JSON.parse(json) as T;
  } catch {
    return null;
  }
}

// ── Server API ─────────────────────────────────────────────────────
export interface AppleTransaction {
  originalTransactionId?: string;
  transactionId?: string;
  productId?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  revocationReason?: number;
  isUpgraded?: boolean;
  offerType?: number;
  offerIdentifier?: string;
  appAccountToken?: string;
  environment?: string;
  type?: string;
}

export interface AppleRenewalInfo {
  autoRenewStatus?: number;
  autoRenewProductId?: string;
  gracePeriodExpiresDate?: number;
  expirationIntent?: number;
}

export interface ResolvedSubscription {
  originalTransactionId: string;
  environment: "Sandbox" | "Production";
  status: number | null;
  transaction: AppleTransaction;
  renewal: AppleRenewalInfo;
  raw: unknown;
}

/**
 * Ask Apple for the authoritative state of a subscription.
 *
 * Tries production first and falls back to sandbox on Apple's
 * "transaction id not found" (4040010) — a single deployed function
 * serves both, since TestFlight purchases are always sandbox.
 */
export async function fetchSubscriptionState(
  originalTransactionId: string,
  preferredEnvironment?: string,
): Promise<ResolvedSubscription | null> {
  const order = preferredEnvironment === "Sandbox"
    ? [SANDBOX_HOST, PROD_HOST]
    : [PROD_HOST, SANDBOX_HOST];

  const token = await appleJwt();
  let lastBody = "";

  for (const host of order) {
    const res = await fetch(
      `${host}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`,
      { headers: { Authorization: `Bearer ${token}` } },
    );

    if (res.status === 401) {
      throw new Error("Apple rejected our JWT (401) — check the IAP key secrets");
    }

    const body = await res.text();
    lastBody = body;

    if (!res.ok) {
      // 4040010 = transaction id not found in THIS environment: try the other.
      if (body.includes("4040010") || res.status === 404) continue;
      throw new Error(`Apple API ${res.status}: ${body.slice(0, 300)}`);
    }

    const parsed = JSON.parse(body) as {
      environment?: string;
      data?: Array<{
        lastTransactions?: Array<{
          originalTransactionId?: string;
          status?: number;
          signedTransactionInfo?: string;
          signedRenewalInfo?: string;
        }>;
      }>;
    };

    // Find the entry for this OTI (a group can hold several).
    for (const group of parsed.data ?? []) {
      for (const item of group.lastTransactions ?? []) {
        if (item.originalTransactionId !== originalTransactionId) continue;
        return {
          originalTransactionId,
          environment: host === SANDBOX_HOST ? "Sandbox" : "Production",
          status: item.status ?? null,
          transaction:
            decodeJwsPayload<AppleTransaction>(item.signedTransactionInfo ?? "") ?? {},
          renewal:
            decodeJwsPayload<AppleRenewalInfo>(item.signedRenewalInfo ?? "") ?? {},
          raw: parsed,
        };
      }
    }
  }

  console.warn(
    `[apple] no subscription found for ${originalTransactionId}: ${lastBody.slice(0, 200)}`,
  );
  return null;
}

// ── Persistence ────────────────────────────────────────────────────
const ms = (v?: number) => (v ? new Date(v).toISOString() : null);

/**
 * Write Apple's state into apple_subscriptions.
 *
 * The AFTER trigger on that table calls recompute_user_entitlement(),
 * so the user's effective tier follows automatically — this function
 * must never write subscription_tier itself.
 *
 * userId is only applied when known. A notification can arrive before
 * the client's verify call, in which case the row is created with a null
 * user_id and bound later; passing null here must NOT unbind an existing
 * row, hence the coalesce-style guard.
 */
export async function persistSubscription(
  // deno-lint-ignore no-explicit-any
  admin: any,
  sub: ResolvedSubscription,
  userId?: string | null,
  notification?: { type?: string; subtype?: string },
): Promise<{ tier: string | null; error?: string }> {
  const productId = sub.transaction.productId ?? "";
  const tier = tierForProduct(productId);

  if (!tier) {
    return { tier: null, error: `unknown product ${productId}` };
  }

  const row: Record<string, unknown> = {
    original_transaction_id: sub.originalTransactionId,
    product_id: productId,
    tier,
    environment: sub.environment,
    latest_transaction_id: sub.transaction.transactionId ?? null,
    purchase_date: ms(sub.transaction.purchaseDate),
    expires_at: ms(sub.transaction.expiresDate),
    status: sub.status,
    auto_renew_status: sub.renewal.autoRenewStatus === 1,
    auto_renew_product_id: sub.renewal.autoRenewProductId ?? null,
    grace_period_expires_at: ms(sub.renewal.gracePeriodExpiresDate),
    revocation_date: ms(sub.transaction.revocationDate),
    revocation_reason: sub.transaction.revocationReason ?? null,
    is_upgraded: sub.transaction.isUpgraded ?? null,
    offer_type: sub.transaction.offerType ?? null,
    offer_identifier: sub.transaction.offerIdentifier ?? null,
    last_notification_type: notification?.type ?? null,
    last_notification_subtype: notification?.subtype ?? null,
    last_synced_at: new Date().toISOString(),
    raw_status_response: sub.raw,
  };

  // Prefer an explicitly supplied user, else Apple's appAccountToken
  // (we pass the Supabase user id as applicationUserName at purchase).
  const resolvedUser = userId ?? sub.transaction.appAccountToken ?? null;
  if (resolvedUser) {
    row.user_id = resolvedUser;
    row.app_account_token = sub.transaction.appAccountToken ?? null;
  }

  const { error } = await admin
    .from("apple_subscriptions")
    .upsert(row, { onConflict: "original_transaction_id" });

  if (error) return { tier, error: error.message };
  return { tier };
}
