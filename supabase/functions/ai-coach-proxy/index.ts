// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: ai-coach-proxy (updated with server-side
// cap enforcement)
//
// WHAT'S NEW vs the previous version:
// 1. Verifies the caller has a real Supabase session (JWT check) —
//    previously the Authorization header carried the publishable/anon
//    key, which meant the function had no way to know who was calling,
//    making server-side cap enforcement structurally impossible.
// 2. Checks the caller's subscription tier against live_ai_monthly_cap
//    in subscription_tier_limits — the same cap that exists client-side
//    in app.js, but enforced here where it can't be bypassed by
//    anyone opening dev tools and posting directly to this URL.
// 3. Increments live_ai_usage_monthly atomically before hitting
//    Anthropic — so the counter is accurate even if the Anthropic call
//    itself fails or the client disconnects mid-response.
//
// WHY THE CLIENT-SIDE CHECK STILL EXISTS IN app.js:
// It stays there as the UX layer — it gives the user a friendly
// message before the round trip, and shows them their remaining
// count without a server call. But it's no longer the real gate;
// this function is. A user who bypasses the client check gets a
// 429 from this function instead of a free Anthropic call.
//
// DEPLOY:
//   supabase functions deploy ai-coach-proxy
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase secrets set ALLOWED_ORIGIN=https://www.growsense.life,https://cheetahokok-sudo.github.io
//
// ALLOWED_ORIGIN is a comma-separated allowlist. It MUST include
// https://www.growsense.life or the Flutter web build at /app/ is
// blocked by CORS — a failure that only shows in the browser console.
// The native iOS app sends no Origin header and is unaffected.
//
// NOTE: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are automatically
// injected by Supabase into every Edge Function — do NOT try to set
// them manually as secrets (Supabase reserves the SUPABASE_ prefix
// and will reject any attempt to set variables with that prefix).
// They are simply available via Deno.env.get() without any setup.
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
// Comma-separated allowlist. The Flutter WEB build is served from
// growsense.life/app/ and runs in a browser, so it sends an Origin
// header and is subject to CORS; the native iOS app sends none and is
// unaffected either way. A single pinned origin silently blocked the
// web build — hence the list.
const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGIN") || "*")
  .split(",")
  .map((o) => o.trim())
  .filter(Boolean);

function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const allow = ALLOWED_ORIGINS.includes("*")
    ? "*"
    : ALLOWED_ORIGINS.includes(origin)
      ? origin
      : ALLOWED_ORIGINS[0] ?? "*";
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    // Responses differ per Origin now — keep caches honest.
    "Vary": "Origin",
  };
}

Deno.serve(async (req) => {
  const corsHeaders = corsFor(req);

  function jsonResponse(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: { message: "Method not allowed" } }, 405);
  }

  if (!ANTHROPIC_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("[ai-coach-proxy] Missing required environment variables");
    return jsonResponse({ error: { message: "AI service is not configured" } }, 500);
  }

  // ── Step 1: Verify the caller's session JWT ────────────────────
  // The Authorization header must carry the user's real session token
  // (not the publishable/anon key) — app.js now sends APP.session.
  // access_token for this. Without a valid session, we can't identify
  // the caller, and identification is required for the cap check.
  const authHeader = req.headers.get("Authorization") || "";
  const jwt = authHeader.replace("Bearer ", "").trim();

  if (!jwt) {
    return jsonResponse({ error: { message: "Authentication required" } }, 401);
  }

  // Use a service-role client so we can verify the JWT and then
  // read subscription data / write usage counters without being
  // subject to the user's own RLS policies.
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // getUser() verifies the JWT signature against Supabase's auth
  // keys — it's not just decoding; it validates the token is real,
  // unexpired, and issued by this project.
  const { data: { user }, error: authError } = await adminClient.auth.getUser(jwt);

  if (authError || !user) {
    console.log("[ai-coach-proxy] Invalid session JWT:", authError?.message);
    return jsonResponse({ error: { message: "Invalid or expired session" } }, 401);
  }

  const userId = user.id;

  // ── Step 2: Look up this user's tier and cap ───────────────────
  const { data: accountData, error: accountError } = await adminClient
    .from("user_accounts")
    .select("subscription_tier")
    .eq("user_id", userId)
    .maybeSingle();

  if (accountError || !accountData) {
    console.log("[ai-coach-proxy] Could not load account for user:", userId);
    return jsonResponse({ error: { message: "Could not verify account" } }, 403);
  }

  const tier = accountData.subscription_tier || "free";

  const { data: limitData, error: limitError } = await adminClient
    .from("subscription_tier_limits")
    .select("live_ai_monthly_cap")
    .eq("tier", tier)
    .maybeSingle();

  if (limitError || !limitData) {
    console.log("[ai-coach-proxy] Could not load tier limits for tier:", tier);
    return jsonResponse({ error: { message: "Could not verify subscription limits" } }, 500);
  }

  const cap = limitData.live_ai_monthly_cap;

  // cap === 0 means live AI is explicitly unavailable on this tier
  if (cap === 0) {
    return jsonResponse({
      error: {
        message: "Live AI is not included in your current plan. Upgrade to Premium or Pro to unlock it.",
        code: "LIVE_AI_NOT_IN_PLAN"
      }
    }, 403);
  }

  // ── Step 3: Check and increment the monthly usage counter ─────
  // Year-month key in UTC — consistent and unambiguous for the
  // server, even though the client uses local time for its own UX
  // display. They'll be off by at most a few hours at month
  // boundaries, which is acceptable; what matters is that the
  // server's counter is the authoritative gate.
  const now = new Date();
  const yearMonth = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;

  // If cap is null, the tier has unlimited live AI — skip the
  // counter entirely (Pro tier's current behaviour).
  if (cap !== null) {
    const { data: usageData } = await adminClient
      .from("live_ai_usage_monthly")
      .select("call_count")
      .eq("user_id", userId)
      .eq("year_month", yearMonth)
      .maybeSingle();

    const currentCount = usageData?.call_count ?? 0;

    if (currentCount >= cap) {
      console.log(`[ai-coach-proxy] Cap exceeded for ${userId}: ${currentCount}/${cap} (${tier}, ${yearMonth})`);
      return jsonResponse({
        error: {
          message: `Monthly live AI limit reached (${cap} calls on ${tier} plan). Resets on the 1st of next month.`,
          code: "MONTHLY_CAP_EXCEEDED",
          cap,
          used: currentCount
        }
      }, 429);
    }

    // Increment before the Anthropic call — so the counter is
    // accurate even if the call fails or the client disconnects.
    // An aborted call still counts; this prevents gaming the cap
    // by opening many requests and closing them before completion.
    const { error: upsertError } = await adminClient
      .from("live_ai_usage_monthly")
      .upsert({
        user_id: userId,
        year_month: yearMonth,
        call_count: currentCount + 1
      }, { onConflict: "user_id,year_month" });

    if (upsertError) {
      console.error("[ai-coach-proxy] Failed to increment usage counter:", upsertError);
      // Don't block the call for a counter write failure — log and
      // continue, rather than denying service due to an accounting error.
    }
  }

  // ── Step 4: Forward to Anthropic ──────────────────────────────
  try {
    const body = await req.json();
    const { system, messages, max_tokens } = body;

    if (!Array.isArray(messages) || messages.length === 0) {
      return jsonResponse({ error: { message: "messages array is required" } }, 400);
    }

    const safeMaxTokens = Math.min(typeof max_tokens === "number" ? max_tokens : 1000, 1500);

    // Haiku, not Sonnet: a coach answer is a short, grounded, single-turn
    // reply — exactly Haiku's job — and the arithmetic decides it. At
    // ~2k in / ~800 out, Sonnet 4.6 ($3/$15 per MTok) costs ~$0.018 a
    // question, so the 50-call monthly allowance is ~$0.90 against a
    // ~$0.30 AI budget on a $5/mo subscription. Haiku 4.5 ($1/$5) lands
    // at ~$0.006, i.e. ~$0.30 for the same 50 calls. Sonnet-tier stays
    // where the reasoning earns it: bone-age and lab interpretation.
    const MODEL = "claude-haiku-4-5";

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: safeMaxTokens,
        system: typeof system === "string" ? system : undefined,
        messages,
      }),
    });

    const data = await anthropicRes.json();
    // Tell the client which tier answered, so usage can be costed later
    // without guessing what the function was configured with at the time.
    if (anthropicRes.ok && data && typeof data === "object") {
      (data as Record<string, unknown>).growsense_model = MODEL;
    }

    if (!anthropicRes.ok) {
      console.log("[ai-coach-proxy] Anthropic rejected request. Status:", anthropicRes.status, "Body:", JSON.stringify(data));
    }

    return jsonResponse(data, anthropicRes.status);
  } catch (e) {
    console.error("[ai-coach-proxy] Unexpected error:", e);
    return jsonResponse({ error: { message: "Internal proxy error" } }, 500);
  }
});
