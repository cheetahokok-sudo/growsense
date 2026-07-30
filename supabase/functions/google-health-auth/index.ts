// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: google-health-auth
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const GOOGLE_CLIENT_ID     = Deno.env.get("GOOGLE_HEALTH_CLIENT_ID");
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_HEALTH_CLIENT_SECRET");
const GOOGLE_REDIRECT_URI  = Deno.env.get("GOOGLE_HEALTH_REDIRECT_URI");
const SUPABASE_URL         = Deno.env.get("SUPABASE_URL");
const SUPABASE_SRK         = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ALLOWED_ORIGIN       = Deno.env.get("ALLOWED_ORIGIN") || "*";

// Token exchange must reuse the SAME redirect_uri the client used to start
// the OAuth flow. GrowSense clients differ (Flutter /app/, PWA /webapp.html),
// so accept it per-request — allowlisted — and fall back to the env default.
const ALLOWED_REDIRECTS = [
  "https://www.growsense.life/app/",
  "https://www.growsense.life/webapp.html",
  "https://www.growsense.life/",
  "https://cheetahokok-sudo.github.io/growsense/",
];

const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !GOOGLE_REDIRECT_URI || !SUPABASE_URL || !SUPABASE_SRK) {
    console.error("[google-health-auth] Missing environment variables");
    return json({ error: "Service not configured" }, 500);
  }

  // ── 1. Verify the caller's GrowSense session ───────────────────
  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!jwt) return json({ error: "Authentication required" }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SRK);
  const { data: { user }, error: authErr } = await admin.auth.getUser(jwt);
  if (authErr || !user) return json({ error: "Invalid or expired session" }, 401);

  // ── 2. Validate request body ───────────────────────────────────
  let body: { code?: string; child_id?: string; redirect_uri?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }

  const { code, child_id, redirect_uri } = body;
  if (!code || !child_id) return json({ error: "code and child_id are required" }, 400);

  const effectiveRedirectUri =
    redirect_uri && ALLOWED_REDIRECTS.includes(redirect_uri)
      ? redirect_uri
      : GOOGLE_REDIRECT_URI;

  // ── 3. Verify this child belongs to the calling parent ────────
  const { data: child } = await admin
    .from("children")
    .select("child_id, name")
    .eq("child_id", child_id)
    .eq("parent_id", user.id)
    .maybeSingle();

  if (!child) {
    console.log(`[google-health-auth] Child ${child_id} not found for parent ${user.id}`);
    return json({ error: "Child not found or not authorised" }, 403);
  }

  // ── 4. Exchange auth code for Google OAuth tokens ──────────────
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      redirect_uri: effectiveRedirectUri,
      grant_type: "authorization_code",
    }),
  });

  const tokens = await tokenRes.json();

  if (!tokenRes.ok || !tokens.access_token) {
    console.error("[google-health-auth] Token exchange failed:", tokens);
    return json({ error: "Google token exchange failed", detail: tokens.error_description }, 400);
  }

  if (!tokens.refresh_token) {
    console.warn("[google-health-auth] No refresh_token in response — user may need to revoke and reconnect");
    return json({ error: "No refresh token received. Please disconnect and reconnect Fitbit." }, 400);
  }

  const expiresAt = new Date(Date.now() + tokens.expires_in * 1000).toISOString();

  // ── 5. Identify the connected Google/Fitbit account ───────────
  const userInfoRes = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
    headers: { "Authorization": `Bearer ${tokens.access_token}` },
  });
  const googleUser = await userInfoRes.json();
  const googleEmail = googleUser.email || "unknown";
  const googleUserId = googleUser.id || "";

  // ── 6. Upsert the connection ───────────────────────────────────
  const { data: conn, error: upsertErr } = await admin
    .from("google_health_connections")
    .upsert({
      child_id,
      parent_id: user.id,
      google_user_id: googleUserId,
      google_email: googleEmail,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      token_expires_at: expiresAt,
      scope: tokens.scope,
      last_sync_status: "connected",
      last_sync_error: null,
    }, { onConflict: "child_id" })
    .select("connection_id, google_email, last_sync_status, created_at")
    .single();

  if (upsertErr) {
    console.error("[google-health-auth] DB upsert failed:", upsertErr);
    return json({ error: "Failed to save connection" }, 500);
  }

  console.log(`[google-health-auth] ✓ Connected ${googleEmail} → child ${child.name} (${child_id})`);

  return json({
    success: true,
    google_email: googleEmail,
    child_name: child.name,
    connection: conn,
  });
});