// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: apple-notifications
//
// Receives App Store Server Notifications V2.
//
// ⚠️ MUST be deployed with --no-verify-jwt. Supabase verifies the
//    Authorization JWT by default and Apple sends none. Left on, this
//    fails INVISIBLY: the 401 happens in the gateway before our code
//    runs, so the function logs stay clean while every renewal is
//    silently dropped. The Request-a-Test-Notification loop is what
//    catches it — it reports the status code Apple actually received.
//
//    supabase functions deploy apple-notifications \
//      --project-ref ogpkmcqaulohexanucng --no-verify-jwt
//
// Register BOTH URLs in App Store Connect (App Information → App Store
// Server Notifications, Version 2) — production and sandbox point at
// this same function; data.environment distinguishes them.
//
// ── Contract ──────────────────────────────────────────────────────
// Respond 200 as fast as possible. Apple retries on any non-2xx (5
// attempts over ~3 days) and treats slowness as failure. So: log the
// notification durably, then reconcile. Once a notification is IN the
// log we return 200 even if reconciliation fails, because the row can be
// reprocessed — asking Apple to retry our own bug for three days helps
// nobody. We only return non-2xx when we could not durably record it.
//
// Security: authenticity does NOT come from the payload. Nothing in it
// is trusted; the originalTransactionId is used only to ask Apple's
// authenticated API what is actually true. See _shared/apple.ts.
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  APPLE_BUNDLE_ID,
  decodeJwsPayload,
  fetchSubscriptionState,
  persistSubscription,
} from "../_shared/apple.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
// Optional shared secret appended to the URL registered in ASC. Not a
// security boundary — it just drops internet noise before we spend CPU.
const URL_TOKEN = Deno.env.get("APPLE_NOTIFICATIONS_TOKEN") ?? "";

interface NotificationPayload {
  notificationType?: string;
  subtype?: string;
  notificationUUID?: string;
  version?: string;
  signedDate?: number;
  data?: {
    bundleId?: string;
    environment?: string;
    status?: number;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

const ok = () => new Response("", { status: 200 });

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("", { status: 405 });

  if (URL_TOKEN) {
    const supplied = new URL(req.url).searchParams.get("k") ?? "";
    if (supplied !== URL_TOKEN) return new Response("", { status: 404 });
  }

  if (!SUPABASE_URL || !SUPABASE_SRK) {
    console.error("[apple-notifications] service not configured");
    return new Response("", { status: 500 });
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SRK);

  // ── 1. Decode (NOT trust) the envelope ───────────────────────────
  let signedPayload = "";
  try {
    const body = await req.json();
    signedPayload = body?.signedPayload ?? "";
  } catch {
    console.warn("[apple-notifications] unparseable body");
    return new Response("", { status: 400 });
  }

  const payload = decodeJwsPayload<NotificationPayload>(signedPayload);
  if (!payload?.notificationUUID) {
    console.warn("[apple-notifications] no notificationUUID in payload");
    return new Response("", { status: 400 });
  }

  // Cheap sanity check — a payload for another app is not ours.
  const bundleId = payload.data?.bundleId;
  if (bundleId && APPLE_BUNDLE_ID && bundleId !== APPLE_BUNDLE_ID) {
    console.warn(`[apple-notifications] bundle mismatch: ${bundleId}`);
    return new Response("", { status: 400 });
  }

  const txn = decodeJwsPayload<{ originalTransactionId?: string }>(
    payload.data?.signedTransactionInfo ?? "",
  );
  const oti = txn?.originalTransactionId ?? null;

  // ── 2. Log FIRST — this is the idempotency mechanism ─────────────
  // Apple redelivers freely. The primary key on notification_uuid means
  // a redelivery conflicts here and we stop, rather than reprocessing.
  const { error: logErr } = await admin
    .from("apple_notification_log")
    .insert({
      notification_uuid: payload.notificationUUID,
      notification_type: payload.notificationType ?? null,
      subtype: payload.subtype ?? null,
      original_transaction_id: oti,
      environment: payload.data?.environment ?? null,
      signed_date: payload.signedDate
        ? new Date(payload.signedDate).toISOString()
        : null,
      payload: payload as unknown as Record<string, unknown>,
    });

  if (logErr) {
    // 23505 = unique violation = we have already seen this one.
    if ((logErr as { code?: string }).code === "23505") {
      console.log(`[apple-notifications] redelivery ${payload.notificationUUID}`);
      return ok();
    }
    // Could not record it — this is the one case worth a retry from Apple.
    console.error("[apple-notifications] log insert failed:", logErr);
    return new Response("", { status: 500 });
  }

  console.log(
    `[apple-notifications] ${payload.notificationType}/${payload.subtype ?? "-"} ` +
      `env=${payload.data?.environment} oti=${oti} uuid=${payload.notificationUUID}`,
  );

  // ── 3. TEST notifications carry no subscription ──────────────────
  // This is what the Request-a-Test-Notification loop exercises, and
  // proves the whole path end to end without a build.
  if (payload.notificationType === "TEST") {
    await admin
      .from("apple_notification_log")
      .update({ processed: true })
      .eq("notification_uuid", payload.notificationUUID);
    return ok();
  }

  // ── 4. Reconcile against Apple's own state ───────────────────────
  let processed = false;
  let errorText: string | null = null;

  try {
    if (!oti) {
      errorText = "no originalTransactionId in payload";
    } else {
      const state = await fetchSubscriptionState(oti, payload.data?.environment);
      if (!state) {
        errorText = "Apple returned no subscription for this id";
      } else {
        const { error } = await persistSubscription(admin, state, null, {
          type: payload.notificationType,
          subtype: payload.subtype,
        });
        if (error) errorText = error;
        else processed = true;
      }
    }
  } catch (e) {
    errorText = String(e).slice(0, 500);
    console.error("[apple-notifications] reconcile failed:", errorText);
  }

  await admin
    .from("apple_notification_log")
    .update({ processed, error: errorText })
    .eq("notification_uuid", payload.notificationUUID);

  // 200 regardless: the notification is durably logged and replayable.
  return ok();
});
