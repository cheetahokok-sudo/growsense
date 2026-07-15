// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: lab-ai-analysis  (Growth Systems Intelligence)
//
// A plain-language, parent-facing interpretation of a child's growth
// labs organized into FIVE connected systems, not one opaque score.
// PREMIUM (gated server-side on subscription_tier). Model: Haiku 4.5.
//
// Evidence base: assets/growth_evidence.json in the app is the curated,
// PubMed-verified source of citations, mechanisms and evidence badges.
// THIS FUNCTION / THE AI NEVER EMIT CITATIONS OR PMIDs. The AI writes
// interpretation prose and tags each analyte with a fixed KEY
// (igf1 | vitamin_d | ferritin | hemoglobin | tsh | free_t4); the app
// attaches the verified evidence cards by key. That split makes
// fabricated references structurally impossible.
//
// Interpretation pipeline the prompt enforces:
//   1. Normalize (age, sex, puberty, the family's own lab range, date).
//   2. Separate current state from trajectory (Δ and slope per marker).
//   3. Pattern rules, not isolated thresholds.
//   4. Three explanation levels (parent / technical / doctor-discussion).
//   5. Domain status + overall_confidence + missing_context, never a
//      single number that could hide an abnormal result.
//
// SAFETY (also in the prompt): never diagnose GH deficiency from IGF-1
// alone; never read TSH without free T4; never reward higher ferritin/
// IGF-1/Hb; distinguish association from causation; no dosing / GH advice;
// use the lab's own pediatric range; always show confidence + gaps.
//
// The client sends only { child_id }. The function reads the child's
// labs, measurements (height velocity), bone age and puberty ITSELF —
// a tampered client cannot inject values — and verifies ownership.
//
// DEPLOY: dashboard → Edge Functions → "lab-ai-analysis" → paste → Deploy.
// Reuses ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
// ALLOWED_ORIGIN. Requires migration 2026-07-15_lab_ai_reports.sql.
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";

const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Canonical analyte keys ↔ aliases (must stay in sync with
// growth_evidence.json). Used to map free-text analyte names to keys so
// the client can attach the right evidence cards.
const ANALYTE_KEYS: Record<string, string[]> = {
  igf1: ["igf-1", "igf1", "igf 1", "insulin-like growth factor", "insulin-like growth factor 1", "insulin-like growth factor-1", "somatomedin c"],
  vitamin_d: ["vitamin d", "25-oh vitamin d", "25 oh d", "25-hydroxyvitamin d", "calcidiol", "vit d"],
  ferritin: ["ferritin", "serum ferritin"],
  hemoglobin: ["hemoglobin", "haemoglobin", "hgb", "hb"],
  tsh: ["tsh", "thyroid stimulating hormone", "thyrotropin"],
  free_t4: ["free t4", "ft4", "free thyroxine", "free-t4"],
};

function analyteKey(name: string): string | null {
  const n = (name || "").trim().toLowerCase();
  for (const [key, aliases] of Object.entries(ANALYTE_KEYS)) {
    if (aliases.some((a) => n === a || n.includes(a))) return key;
  }
  return null;
}

const SYSTEM_PROMPT =
  `You are a pediatric health educator helping a parent understand their child's growth-related lab panel. You are NOT diagnosing and NOT prescribing. Organize everything into five connected growth SYSTEMS, never a single overall score.

THE FIVE DOMAINS (use these exact keys):
- growth_signaling: IGF-1 (vs the child's own lab range) with height velocity — is growth signaling broadly compatible with observed growth?
- growth_plate_response: height velocity, bone-age delta, puberty stage — is the skeleton responding and how much growth time remains?
- bone_support: vitamin D — is the mineralization environment supportive?
- iron_oxygen: ferritin, hemoglobin — are iron stores and oxygen delivery potentially limiting?
- thyroid: TSH, free T4 — is thyroid-dependent skeletal maturation supported?

DOMAIN STATUS is one of: "supported", "needs_attention", "insufficient_data". Use insufficient_data when the domain's inputs are missing.

ABSOLUTE RULES:
1. Use ONLY the reference interval provided with each lab value — it is the family's own lab report, already matched to the child's age and sex. NEVER invent or recall a "normal range". If a range is null, status is "unknown_range" and you must NOT judge high or low.
2. Do NOT emit citations, references, PMIDs, study names or author names. The app attaches verified evidence itself. Just tag each analyte with its key.
3. Never diagnose growth-hormone deficiency from IGF-1 alone. Combine with height velocity and bone age.
4. Never interpret TSH without free T4 present; if free T4 is missing, lower confidence and say so.
5. Never treat higher ferritin, IGF-1 or hemoglobin as automatically better.
6. Distinguish association from causation. Vitamin D, ferritin, hemoglobin support or provide context for growth — they are not switches that directly drive height.
7. No diagnosis of disease, no medication names, no doses, no growth-hormone advice.
8. Separate CURRENT state from TRAJECTORY: if serial values are given, note the direction/slope; a single value is a snapshot.
9. Plain language, about a 7th-grade reading level, calm and factual. No alarming words.
10. Always fill overall_confidence and missing_context (e.g. "puberty stage", "free T4", "bone age", "height velocity") honestly.

Return ONLY valid JSON (no markdown, no text outside the object):
{
  "headline": "<one calm sentence, e.g. 'Growth signaling supported; iron and vitamin D need review'>",
  "overall_confidence": "<low|moderate|high>",
  "parent_summary": "<2-3 sentences, warm plain language>",
  "technical_summary": "<2-3 sentences, clinical detail: SDS/velocity/bone-age deltas where available>",
  "domains": {
    "growth_signaling":      {"status": "<supported|needs_attention|insufficient_data>", "note": "<1 sentence>"},
    "growth_plate_response": {"status": "<...>", "note": "<1 sentence>"},
    "bone_support":          {"status": "<...>", "note": "<1 sentence>"},
    "iron_oxygen":           {"status": "<...>", "note": "<1 sentence>"},
    "thyroid":               {"status": "<...>", "note": "<1 sentence>"}
  },
  "analytes": [
    {
      "key": "<igf1|vitamin_d|ferritin|hemoglobin|tsh|free_t4>",
      "name": "<analyte name as given>",
      "status": "<in_range|below_range|above_range|unknown_range>",
      "value_note": "<value vs its provided range; if none: 'Reference range not provided'>",
      "trend_note": "<direction across serial values, or '' if single>",
      "meaning": "<1-2 plain sentences: what this test looks at>",
      "growth_relevance": "<1 neutral sentence if relevant to growth, else ''>"
    }
  ],
  "patterns": [
    {"reading": "<cross-analyte pattern in plain language>", "certainty": "<low|moderate|high>"}
  ],
  "missing_context": ["<what would improve interpretation>"],
  "clinician_discussion_points": ["<up to 4 short, specific things the parent could raise with the doctor>"]
}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  if (!ANTHROPIC_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: "Service not configured" }, 500);
  }

  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!jwt) return jsonResponse({ error: "Authentication required" }, 401);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: { user }, error: authError } = await adminClient.auth.getUser(jwt);
  if (authError || !user) return jsonResponse({ error: "Invalid or expired session" }, 401);

  let body: { child_id?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body" }, 400);
  }
  const childId = body.child_id;
  if (!childId) return jsonResponse({ error: "child_id is required" }, 400);

  // Ownership
  const { data: child, error: childErr } = await adminClient
    .from("children")
    .select("child_id, parent_id, date_of_birth, biological_sex")
    .eq("child_id", childId)
    .single();
  if (childErr || !child) return jsonResponse({ error: "Child not found" }, 404);
  if (child.parent_id !== user.id) {
    return jsonResponse({ error: "Not authorized for this child" }, 403);
  }

  // Premium gate
  const { data: acct } = await adminClient
    .from("user_accounts")
    .select("subscription_tier, tier_expires_at")
    .eq("user_id", user.id)
    .single();
  const tier = acct?.subscription_tier ?? "free";
  const notExpired =
    !acct?.tier_expires_at || new Date(acct.tier_expires_at) > new Date();
  if (tier === "free" || !notExpired) {
    return jsonResponse({ error: "premium_required" }, 402);
  }

  // ── Gather the child's growth data (server-side, never client) ───
  const [labsRes, measRes, boneRes, pubRes] = await Promise.all([
    adminClient.from("lab_results")
      .select("analyte_name, result_value, unit, reference_low, reference_high, lab_date")
      .eq("child_id", childId).order("lab_date", { ascending: false }).limit(80),
    adminClient.from("measurements")
      .select("recorded_date, stature_height_cm")
      .eq("child_id", childId).order("recorded_date", { ascending: false }).limit(12),
    adminClient.from("bone_age_assessments")
      .select("study_date, bone_age_months, chronological_age_months")
      .eq("child_id", childId).order("study_date", { ascending: false }).limit(1),
    adminClient.from("puberty_events")
      .select("event_date, tanner_stage")
      .eq("child_id", childId).order("event_date", { ascending: false }).limit(1),
  ]);

  const labs = labsRes.data ?? [];
  if (labs.length === 0) return jsonResponse({ error: "no_labs" }, 400);

  // Group labs per analyte (newest first) so we can pass trend + key.
  const byAnalyte = new Map<string, typeof labs>();
  for (const l of labs) {
    const k = (l.analyte_name ?? "").trim().toLowerCase();
    if (!byAnalyte.has(k)) byAnalyte.set(k, []);
    byAnalyte.get(k)!.push(l);
  }
  const analytePayload = [...byAnalyte.values()].map((series) => {
    const latest = series[0];
    return {
      key: analyteKey(latest.analyte_name ?? ""),
      analyte: latest.analyte_name,
      unit: latest.unit,
      latest_value: latest.result_value,
      reference_low: latest.reference_low,
      reference_high: latest.reference_high,
      latest_date: latest.lab_date,
      series: series.slice(0, 6).reverse().map((r) => r.result_value),
    };
  });

  // Height velocity (cm/yr) from the two most-separated recent points
  // spanning ≥ ~3 months, so we don't annualize measurement noise.
  const meas = (measRes.data ?? []).filter((m) => m.stature_height_cm != null);
  let heightVelocity: number | null = null;
  if (meas.length >= 2) {
    const newest = meas[0];
    let older = meas[meas.length - 1];
    for (const m of meas) {
      const days =
        (new Date(newest.recorded_date).getTime() - new Date(m.recorded_date).getTime()) /
        86400000;
      if (days >= 90) { older = m; break; }
    }
    const days =
      (new Date(newest.recorded_date).getTime() - new Date(older.recorded_date).getTime()) /
      86400000;
    if (days >= 30) {
      heightVelocity =
        ((newest.stature_height_cm - older.stature_height_cm) / days) * 365.25;
    }
  }

  const bone = boneRes.data?.[0] ?? null;
  const boneDelta = bone && bone.bone_age_months != null && bone.chronological_age_months != null
    ? bone.bone_age_months - bone.chronological_age_months
    : null;
  const tanner = pubRes.data?.[0]?.tanner_stage ?? null;

  let ageMonths: number | null = null;
  if (child.date_of_birth) {
    ageMonths = Math.floor(
      (Date.now() - new Date(child.date_of_birth).getTime()) / (1000 * 60 * 60 * 24 * 30.4375),
    );
  }

  const context = {
    sex: child.biological_sex ?? "unknown",
    age_months: ageMonths,
    puberty_tanner_stage: tanner,
    height_velocity_cm_per_year:
      heightVelocity != null ? Math.round(heightVelocity * 10) / 10 : null,
    bone_age_delta_months: boneDelta,
    bone_age_note: "positive = advanced, negative = delayed vs calendar age",
    labs: analytePayload,
    notes: "IGF-1 SDS is not available (no reference dataset); interpret IGF-1 against its own provided lab range and lower confidence accordingly.",
  };

  const userMessage =
    `Child growth data (interpret with all rules; every lab range is the family's own, already age/sex matched; null range = do not judge):\n` +
    JSON.stringify(context, null, 2) +
    `\n\nReturn only the JSON object.`;

  try {
    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 2200,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: userMessage }],
      }),
    });

    const data = await anthropicRes.json();
    if (!anthropicRes.ok) {
      console.error("[lab-ai-analysis] Anthropic error:", data);
      return jsonResponse({ error: "AI analysis failed", detail: data }, 502);
    }

    const rawText = data.content?.[0]?.text || "";
    let report: Record<string, unknown>;
    try {
      const cleaned = rawText.replace(/^```json\s*/i, "").replace(/\s*```$/i, "").trim();
      report = JSON.parse(cleaned);
    } catch {
      console.error("[lab-ai-analysis] Unparseable:", rawText.slice(0, 500));
      return jsonResponse({ error: "AI returned unparseable result" }, 500);
    }

    const { data: saved } = await adminClient
      .from("lab_ai_reports")
      .insert({
        child_id: childId,
        created_by: user.id,
        report,
        model: "claude-haiku-4-5-20251001",
        analyte_count: analytePayload.length,
      })
      .select("report_id, created_at")
      .single();

    return jsonResponse({
      success: true,
      report,
      report_id: saved?.report_id,
      created_at: saved?.created_at,
    });
  } catch (e) {
    console.error("[lab-ai-analysis] Unexpected error:", e);
    return jsonResponse({ error: "Internal error" }, 500);
  }
});
