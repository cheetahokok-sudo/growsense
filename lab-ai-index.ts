// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: lab-ai-analysis
//
// A plain-language, parent-facing interpretation of a child's logged
// lab values. PREMIUM feature (gated server-side on subscription_tier).
//
// Model: Haiku 4.5 (text only, cheap — see ai-credits-economics). This
// is NOT a diagnosis engine: it explains what analytes mean, flags
// which logged values fall outside the family's OWN printed reference
// interval, notes growth relevance, and suggests questions for the
// doctor. Every response ends with a hard clinical caveat.
//
// SAFETY / no-fabrication rules baked into the prompt:
//   • Use ONLY the reference interval the family entered (their lab's
//     own, already age/sex-matched). NEVER invent or substitute a
//     "normal range" — pediatric intervals are age-dependent.
//   • If no interval was entered for an analyte, say the range is
//     unknown; do not guess whether it is high or low.
//   • No diagnosis, no medication or dosing advice, no treatment plans.
//   • Educational second-read only; defer to the treating clinician.
//
// The client sends only { child_id }. The function reads that child's
// lab_results itself (service role) so a tampered client cannot inject
// fake values, and verifies the child belongs to the caller.
//
// DEPLOY (dashboard → Edge Functions → new function "lab-ai-analysis",
// paste this file, Deploy). Reuses existing secrets: ANTHROPIC_API_KEY,
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ALLOWED_ORIGIN.
// Requires migration 2026-07-15_lab_ai_reports.sql.
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

const SYSTEM_PROMPT =
  `You are a pediatric health educator helping a parent understand their child's laboratory results. You are NOT diagnosing and NOT prescribing.

ABSOLUTE RULES:
1. Use ONLY the reference interval provided with each result. It comes from the family's own lab report and is already matched to the child's age and sex. NEVER invent, recall, or substitute a "normal range". If reference_low/reference_high are null, state that the range was not provided and do NOT judge whether the value is high or low.
2. Compare each value only to its own provided interval. "outside range" = below reference_low or above reference_high.
3. No diagnosis of any disease. No medication names, doses, or treatment plans. No alarming language.
4. Plain language at about a 7th-grade reading level. Warm, calm, factual.
5. Where an analyte is relevant to growth/nutrition (e.g. IGF-1, vitamin D, ferritin, TSH, hemoglobin), you may note that link in one neutral sentence.
6. If a value is far outside its interval, you may gently suggest confirming with the child's doctor — never state urgency or a diagnosis.

Return ONLY valid JSON (no markdown, no text outside the object) with this schema:
{
  "overview": "<2-3 sentence plain-language summary of the panel as a whole>",
  "analytes": [
    {
      "name": "<analyte name as given>",
      "value_note": "<what this value is, compared to its provided range; if no range: 'Reference range not provided'>",
      "status": "<in_range|below_range|above_range|unknown_range>",
      "meaning": "<1-2 sentences: what this test looks at, in plain language>",
      "growth_relevance": "<1 sentence if relevant to growth/nutrition, else empty string>"
    }
  ],
  "questions_for_doctor": ["<up to 3 short, specific questions the parent could ask>"],
  "caveat": "This is an educational summary, not a medical diagnosis. Reference ranges are from your own lab report. Always review results with your child's doctor."
}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  if (!ANTHROPIC_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: "Service not configured" }, 500);
  }

  // ── Auth ─────────────────────────────────────────────────────────
  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!jwt) return jsonResponse({ error: "Authentication required" }, 401);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: { user }, error: authError } = await adminClient.auth.getUser(jwt);
  if (authError || !user) return jsonResponse({ error: "Invalid or expired session" }, 401);

  // ── Parse ────────────────────────────────────────────────────────
  let body: { child_id?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body" }, 400);
  }
  const childId = body.child_id;
  if (!childId) return jsonResponse({ error: "child_id is required" }, 400);

  // ── Ownership ────────────────────────────────────────────────────
  const { data: child, error: childErr } = await adminClient
    .from("children")
    .select("child_id, parent_id, date_of_birth, biological_sex")
    .eq("child_id", childId)
    .single();
  if (childErr || !child) return jsonResponse({ error: "Child not found" }, 404);
  if (child.parent_id !== user.id) {
    return jsonResponse({ error: "Not authorized for this child" }, 403);
  }

  // ── Premium gate (server-side enforcement) ───────────────────────
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

  // ── Read the child's labs ourselves (never trust client values) ──
  const { data: labs, error: labErr } = await adminClient
    .from("lab_results")
    .select("analyte_name, result_value, unit, reference_low, reference_high, lab_date")
    .eq("child_id", childId)
    .order("lab_date", { ascending: false })
    .limit(60);
  if (labErr) return jsonResponse({ error: "Could not read lab results" }, 500);
  if (!labs || labs.length === 0) {
    return jsonResponse({ error: "no_labs" }, 400);
  }

  // Keep only the latest entry per analyte for the interpretation.
  const latestByAnalyte = new Map<string, typeof labs[number]>();
  for (const l of labs) {
    const key = (l.analyte_name ?? "").trim().toLowerCase();
    if (!latestByAnalyte.has(key)) latestByAnalyte.set(key, l);
  }
  const panel = [...latestByAnalyte.values()];

  // Child age in months for context (not used to pick ranges — the
  // family's printed interval already encodes age).
  let ageMonths: number | null = null;
  if (child.date_of_birth) {
    const dob = new Date(child.date_of_birth);
    ageMonths = Math.floor(
      (Date.now() - dob.getTime()) / (1000 * 60 * 60 * 24 * 30.4375),
    );
  }

  const userMessage =
    `Child context: ${child.biological_sex ?? "unknown sex"}, ` +
    `${ageMonths != null ? `${ageMonths} months old` : "age unknown"}.\n\n` +
    `Lab results (each with the reference interval printed on the family's report; null means no range was provided):\n` +
    JSON.stringify(
      panel.map((l) => ({
        analyte: l.analyte_name,
        value: l.result_value,
        unit: l.unit,
        reference_low: l.reference_low,
        reference_high: l.reference_high,
        date: l.lab_date,
      })),
      null,
      2,
    ) +
    `\n\nInterpret this panel for the parent following all rules. Return only the JSON object.`;

  // ── Call Claude (Haiku 4.5) ──────────────────────────────────────
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
        max_tokens: 1500,
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

    // ── Persist ────────────────────────────────────────────────────
    const { data: saved } = await adminClient
      .from("lab_ai_reports")
      .insert({
        child_id: childId,
        created_by: user.id,
        report,
        model: "claude-haiku-4-5-20251001",
        analyte_count: panel.length,
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
