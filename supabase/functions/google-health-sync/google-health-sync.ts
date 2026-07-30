// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: google-health-sync
//
// Fetches sleep data for a connected child from the Google Health
// API v4 (the Fitbit replacement) and upserts into daily_sleep.
//
// Handles:
//   · Token refresh (access tokens expire after 1 hour)
//   · Sleep stage parsing → deep_sleep_min, rem_sleep_min, night wakes
//   · De-duplication (upsert on child_id + log_date)
//   · Multiple sessions on one date — longest = the night, the rest
//     are routed to sleep_naps (see section 8)
//   · Per-night log_date attribution (uses the civil WAKE date — the
//     morning the night ended, same convention as manual entry)
//
// Sleep data mapped to daily_sleep columns:
//   total_sleep_min     ← total duration minus awake minutes
//   bedtime             ← civil start time HH:MM
//   wake_time           ← civil end time HH:MM
//   sleep_efficiency_score ← (asleep / time_in_bed) * 100
//   deep_sleep_min      ← DEEP stage total minutes (GH proxy)
//   rem_sleep_min       ← REM stage total minutes
//   wake_count          ← AWAKE stage segment count
//   night_wakes         ← same as wake_count (existing column)
//   data_source         ← 'google_health_fitbit'
//
// DEPLOY:
//   Supabase Dashboard → Edge Functions → Create new → name: google-health-sync
//   Paste this file → Deploy
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const GOOGLE_CLIENT_ID     = Deno.env.get("GOOGLE_HEALTH_CLIENT_ID");
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_HEALTH_CLIENT_SECRET");
const SUPABASE_URL         = Deno.env.get("SUPABASE_URL");
const SUPABASE_SRK         = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ALLOWED_ORIGIN       = Deno.env.get("ALLOWED_ORIGIN") || "*";

const GOOGLE_HEALTH_BASE = "https://health.googleapis.com/v4";

const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// ── Token refresh ─────────────────────────────────────────────────
async function refreshAccessToken(admin: ReturnType<typeof createClient>, childId: string, refreshToken: string) {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID!,
      client_secret: GOOGLE_CLIENT_SECRET!,
      refresh_token: refreshToken,
      grant_type: "refresh_token",
    }),
  });

  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error(`Token refresh failed: ${data.error_description || data.error}`);
  }

  const expiresAt = new Date(Date.now() + data.expires_in * 1000).toISOString();

  await admin
    .from("google_health_connections")
    .update({ access_token: data.access_token, token_expires_at: expiresAt })
    .eq("child_id", childId);

  console.log(`[google-health-sync] ✓ Token refreshed for child ${childId}`);
  return data.access_token as string;
}

// ── Parse a single sleep data point from the Google Health API ────
// Actual API response uses:
//   sleep.interval.startTime      — UTC ISO string
//   sleep.interval.startUtcOffset — e.g. "25200s" (= +7h for Bangkok)
//   sleep.stages[]                — array of {startTime, endTime, type}
//   (NOT civilStartTime / summary.stages with totalDurationSeconds)
function parseSleepDataPoint(dp: Record<string, unknown>) {
  const sleep = dp.sleep as Record<string, unknown>;
  if (!sleep) return null;

  const interval = sleep.interval as Record<string, unknown>;
  const stages   = (sleep.stages as Array<Record<string,unknown>>) || [];

  if (!interval?.startTime || !interval?.endTime) return null;

  // Parse UTC epoch milliseconds
  const startUtcMs = new Date(interval.startTime as string).getTime();
  const endUtcMs   = new Date(interval.endTime   as string).getTime();
  if (isNaN(startUtcMs) || isNaN(endUtcMs)) return null;

  // Offset: "25200s" → +7 hours for Bangkok (UTC+7)
  // Local time = UTC + offset
  const offsetStr = ((interval.startUtcOffset as string) || "0s").replace("s", "");
  const offsetMs  = parseInt(offsetStr) * 1000;

  const localStartMs = startUtcMs + offsetMs;
  const localEndMs   = endUtcMs   + offsetMs;
  const localStart   = new Date(localStartMs);
  const localEnd     = new Date(localEndMs);

  // log_date = local WAKE date. A night that runs 21:00 → 06:00 belongs
  // to the morning it ended, matching how a parent logs sleep by hand
  // (filed under the day being viewed) and how sleep_naps is keyed. It
  // also matches the civil_end_time filter this function queries on.
  const logDate = [
    localEnd.getUTCFullYear(),
    String(localEnd.getUTCMonth() + 1).padStart(2, "0"),
    String(localEnd.getUTCDate()).padStart(2, "0"),
  ].join("-");

  // HH:MM strings in local time
  const bedtime  = `${String(localStart.getUTCHours()).padStart(2,"0")}:${String(localStart.getUTCMinutes()).padStart(2,"0")}`;
  const wakeTime = `${String(localEnd.getUTCHours()).padStart(2,"0")}:${String(localEnd.getUTCMinutes()).padStart(2,"0")}`;

  // Accumulate stage durations from individual stage segments
  let deepMs = 0, remMs = 0, lightMs = 0, awakeMs = 0, wakeCount = 0;
  for (const stage of stages) {
    const ss = new Date(stage.startTime as string).getTime();
    const se = new Date(stage.endTime   as string).getTime();
    if (isNaN(ss) || isNaN(se)) continue;
    const ms = se - ss;
    switch (stage.type) {
      case "DEEP":  deepMs  += ms; break;
      case "REM":   remMs   += ms; break;
      case "LIGHT": lightMs += ms; break;
      case "AWAKE": awakeMs += ms; wakeCount++; break;
    }
  }

  const totalMs   = endUtcMs - startUtcMs;
  const asleepMs  = deepMs + remMs + lightMs;
  const efficiency = totalMs > 0 ? Math.round((asleepMs / totalMs) * 100) : null;

  console.log(`[parse] ${logDate} bedtime=${bedtime} wake=${wakeTime} asleep=${Math.round(asleepMs/60000)}min deep=${Math.round(deepMs/60000)}min stages=${stages.length}`);

  return {
    log_date: logDate,
    total_sleep_min: Math.round(asleepMs / 60000),
    bedtime,
    wake_time: wakeTime,
    sleep_efficiency_score: efficiency,
    deep_sleep_min: Math.round(deepMs / 60000),
    rem_sleep_min:  Math.round(remMs  / 60000),
    night_wakes: wakeCount,
    data_source: "google_health_fitbit",
    // Not a daily_sleep column — used only to tell a night from a nap.
    _startHour: localStart.getUTCHours(),
  };
}

type ParsedSleep = NonNullable<ReturnType<typeof parseSleepDataPoint>>;

// A session counts as the main night if it is long enough to be one, or
// if it began in the night window. A lone 20-minute afternoon session is
// a nap, and that day simply gets no daily_sleep row — better than
// filing a nap as a night and deflating the sleep score.
function isMainNight(s: ParsedSleep) {
  return s.total_sleep_min >= 120 || s._startHour >= 18 || s._startHour < 6;
}

function toDailySleepRow(s: ParsedSleep, childId: string) {
  return {
    child_id: childId,
    log_date: s.log_date,
    total_sleep_min: s.total_sleep_min,
    bedtime: s.bedtime,
    wake_time: s.wake_time,
    sleep_efficiency_score: s.sleep_efficiency_score,
    deep_sleep_min: s.deep_sleep_min,
    rem_sleep_min: s.rem_sleep_min,
    night_wakes: s.night_wakes,
    data_source: s.data_source,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET || !SUPABASE_URL || !SUPABASE_SRK) {
    return json({ error: "Service not configured" }, 500);
  }

  // ── 1. Verify the caller's GrowSense session ───────────────────
  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!jwt) return json({ error: "Authentication required" }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SRK);
  const { data: { user }, error: authErr } = await admin.auth.getUser(jwt);
  if (authErr || !user) return json({ error: "Invalid or expired session" }, 401);

  // ── 2. Parse request body ──────────────────────────────────────
  let body: { child_id?: string; days_back?: number };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }

  const { child_id, days_back = 7 } = body;
  if (!child_id) return json({ error: "child_id is required" }, 400);

  // ── 3. Load the stored connection ─────────────────────────────
  const { data: conn, error: connErr } = await admin
    .from("google_health_connections")
    .select("*")
    .eq("child_id", child_id)
    .maybeSingle();

  if (connErr || !conn) return json({ error: "No Fitbit connection found for this child" }, 404);

  // ── 4. Verify the child belongs to the calling parent ────────
  const { data: child } = await admin
    .from("children")
    .select("child_id")
    .eq("child_id", child_id)
    .eq("parent_id", user.id)
    .maybeSingle();

  if (!child) return json({ error: "Child not found or not authorised" }, 403);

  // ── 5. Refresh token if expired (or within 5 min of expiry) ──
  let accessToken = conn.access_token;
  const expiresAt = new Date(conn.token_expires_at);
  const needsRefresh = expiresAt.getTime() - Date.now() < 5 * 60 * 1000;

  if (needsRefresh) {
    try {
      accessToken = await refreshAccessToken(admin, child_id, conn.refresh_token);
    } catch (e) {
      console.error("[google-health-sync] Token refresh failed:", e);
      await admin
        .from("google_health_connections")
        .update({ last_sync_status: "error", last_sync_error: String(e) })
        .eq("child_id", child_id);
      return json({ error: "Token refresh failed — user may need to reconnect Fitbit", detail: String(e) }, 401);
    }
  }

  // ── 6. Build date filter ──────────────────────────────────────
  const since = new Date();
  since.setDate(since.getDate() - Math.min(days_back, 90));
  // Format as YYYY-MM-DD for the filter
  const sinceDate = since.toISOString().split("T")[0];

  // ── 7. Fetch sleep data from Google Health API ────────────────
  // Try without dataSourceFamily filter first — the wearables-only
  // filter may be too restrictive if the account migration from
  // Fitbit to Google Health is still in progress, or if the Fitbit
  // data is stored under a different source family label.
  const url = new URL(`${GOOGLE_HEALTH_BASE}/users/me/dataTypes/sleep/dataPoints:reconcile`);
  url.searchParams.set("filter", `sleep.interval.civil_end_time >= "${sinceDate}"`);
  url.searchParams.set("pageSize", "30");

  console.log(`[google-health-sync] Fetching sleep from ${sinceDate} for child ${child_id}`);
  console.log(`[google-health-sync] URL: ${url.toString()}`);

  const ghRes = await fetch(url.toString(), {
    headers: { "Authorization": `Bearer ${accessToken}`, "Accept": "application/json" },
  });

  const ghData = await ghRes.json();
  console.log(`[google-health-sync] HTTP status: ${ghRes.status}`);
  console.log(`[google-health-sync] Response keys: ${Object.keys(ghData).join(', ')}`);

  if (!ghRes.ok) {
    const errMsg = ghData.error?.message || JSON.stringify(ghData.error);
    console.error("[google-health-sync] Google Health API error:", JSON.stringify(ghData));
    await admin
      .from("google_health_connections")
      .update({ last_sync_status: "error", last_sync_error: errMsg })
      .eq("child_id", child_id);
    return json({ error: "Google Health API error", detail: errMsg }, 502);
  }

  const dataPoints = (ghData.dataPoints || []) as Array<Record<string, unknown>>;
  console.log(`[google-health-sync] dataPoints count: ${dataPoints.length}`);
  if (dataPoints.length > 0) {
    // Log the first data point's structure to understand what fields exist
    console.log(`[google-health-sync] First dataPoint keys: ${Object.keys(dataPoints[0]).join(', ')}`);
    console.log(`[google-health-sync] First dataPoint: ${JSON.stringify(dataPoints[0]).slice(0, 500)}`);
  } else {
    // Log the full response when empty to understand why
    console.log(`[google-health-sync] Full response (no dataPoints): ${JSON.stringify(ghData).slice(0, 1000)}`);
  }

  if (dataPoints.length === 0) {
    await admin
      .from("google_health_connections")
      .update({ last_sync_at: new Date().toISOString(), last_sync_status: "synced", last_sync_nights_updated: 0 })
      .eq("child_id", child_id);
    return json({ success: true, nights_synced: 0, message: "No sleep data found in this period" });
  }

  // ── 8. Parse, then split each day's sessions ─────────────────
  // Fitbit can return MORE THAN ONE session for the same date — a main
  // night plus a daytime nap. daily_sleep is UNIQUE(child_id, log_date),
  // so upserting both in one batch raises Postgres 21000 "ON CONFLICT DO
  // UPDATE cannot affect row a second time" and NOTHING is saved (the
  // whole sync fails on a single napped day). Per date: the longest
  // qualifying session is the night; every other session is a nap, kept
  // in sleep_naps so its minutes survive without touching the score.
  const parsed = dataPoints
    .map(parseSleepDataPoint)
    .filter(Boolean) as ParsedSleep[];

  const byDate = new Map<string, ParsedSleep[]>();
  for (const p of parsed) {
    const list = byDate.get(p.log_date) ?? [];
    list.push(p);
    byDate.set(p.log_date, list);
  }

  const rows: ReturnType<typeof toDailySleepRow>[] = [];
  const napRows: Record<string, unknown>[] = [];

  for (const [logDate, sessions] of byDate) {
    sessions.sort((a, b) => b.total_sleep_min - a.total_sleep_min);
    const nightIdx = sessions.findIndex(isMainNight); // longest first → longest night wins
    const seenStarts = new Set<string>();

    sessions.forEach((s, i) => {
      if (i === nightIdx) {
        rows.push(toDailySleepRow(s, child_id));
        return;
      }
      // sleep_naps is UNIQUE(child_id, log_date, start_time) — two
      // sessions sharing a start minute would re-raise the same 21000.
      if (seenStarts.has(s.bedtime)) return;
      seenStarts.add(s.bedtime);
      napRows.push({
        child_id,
        log_date: logDate,
        start_time: s.bedtime,
        end_time: s.wake_time,
        total_sleep_min: s.total_sleep_min,
        data_source: "google_health_fitbit",
      });
    });
  }

  console.log(`[google-health-sync] ${rows.length} nights, ${napRows.length} naps from ${parsed.length} sessions`);

  if (rows.length > 0) {
    const { error: upsertErr } = await admin
      .from("daily_sleep")
      .upsert(rows, { onConflict: "child_id,log_date" });

    if (upsertErr) {
      console.error("[google-health-sync] DB upsert error:", upsertErr);
      await admin
        .from("google_health_connections")
        .update({ last_sync_status: "error", last_sync_error: upsertErr.message })
        .eq("child_id", child_id);
      return json({ error: "Failed to save sleep data", detail: upsertErr.message }, 500);
    }
  }

  // Naps are a bonus, never a reason to fail the sync — and the
  // sleep_naps migration may not have been run on this project yet.
  let napsSynced = 0;
  if (napRows.length > 0) {
    const { error: napErr } = await admin
      .from("sleep_naps")
      .upsert(napRows, { onConflict: "child_id,log_date,start_time" });
    if (napErr) console.error("[google-health-sync] Nap upsert skipped:", napErr.message);
    else napsSynced = napRows.length;
  }

  // ── 9. Update connection status ───────────────────────────────
  await admin
    .from("google_health_connections")
    .update({
      last_sync_at: new Date().toISOString(),
      last_sync_status: "synced",
      last_sync_nights_updated: rows.length,
      last_sync_error: null,
    })
    .eq("child_id", child_id);

  console.log(`[google-health-sync] ✓ Upserted ${rows.length} nights for child ${child_id}`);

  return json({
    success: true,
    nights_synced: rows.length,
    naps_synced: napsSynced,
    dates: rows.map(r => r.log_date),
  });
});
