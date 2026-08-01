// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: bone-age-analysis
//
// Sends a pediatric left-hand X-ray to Claude Vision and returns a
// structured bone age second-opinion analysis using the Greulich-Pyle
// (GP) framework.
//
// ALGORITHM v2 — REVISED after case study validation (Peem, Mar 2019):
//
// WHAT WENT WRONG IN v1 (lessons that shaped this prompt):
//   1. Counted a shadow as "triquetrum" → overcounted carpals → bone
//      age overestimated by 6 months → clinical conclusion flipped
//      from "delayed" to "normal"
//   2. Used TW3 epiphysis:metaphysis pixel ratios → systematic upward
//      bias from JPEG compression vs DICOM → further overestimation
//   3. Reported a single number (24.0 mo) with false precision →
//      doctor's result was 18.0 mo → 6-month error, reversed meaning
//
// CORRECTIONS IN v2:
//   1. Carpal count is the PRIMARY anchor at age <48 months.
//      When uncertain, count FEWER (JPEG shows more shadows than bones)
//   2. GP = HOLISTIC visual matching only, no pixel ratio calculations
//   3. Always output a RANGE with ≥6 month uncertainty bounds
//   4. When uncertain, bias toward YOUNGER estimate (JPEG upward bias)
//
// DEPLOY:
//   Dashboard → Edge Functions → "New function" → name: bone-age-analysis
//   Paste this file into the Code tab → Deploy
//   No new secrets needed: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
//   ANTHROPIC_API_KEY are all already set from ai-coach-proxy.
//   ALLOWED_ORIGIN is also already set.
//
// FUTURE PHASE — DICOM support:
//   When DICOM upload is added, the client will use a WASM DICOM parser
//   (e.g. dcmjs) to extract a calibrated PNG with real mm/pixel ratio,
//   send the calibration factor alongside the image, and this function
//   will use it to qualify the measurement precision note in the result.
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkAndCountFeatureUse } from "../_shared/usage_caps.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";

const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Revised GP-framework system prompt ───────────────────────────
// Every line is deliberate — shaped by real case study validation.
const GP_SYSTEM_PROMPT = `You are analyzing a pediatric left-hand PA radiograph for bone age assessment using the Greulich-Pyle (GP) method only.

CRITICAL FAILURE MODES TO AVOID (from validated case study):
1. JPEG/screen-resolution images contain shadows and artifacts that mimic carpal bones. When uncertain about any spot in the carpal region, do NOT count it. Conservative (fewer) carpal count is always more accurate from JPEG.
2. Do NOT calculate epiphysis-to-metaphysis pixel ratios. This is a TW3 technique that introduces systematic upward bias when applied to JPEG images. Use qualitative descriptors only.
3. Never output a single month as the bone age. Always output a range with minimum ±6 months uncertainty.
4. When uncertain between two interpretations, always choose the one that estimates YOUNGER. JPEG compression and screen resolution both bias toward apparent over-maturation.

ANALYSIS PROTOCOL — follow in order:

STEP 1 — CARPAL COUNT (PRIMARY DETERMINANT for age <48 months):
This is the most important step for young children. Carefully examine the wrist region.
Count ONLY ossification centers that are: clearly distinct, clearly rounded or oval, clearly brighter than surrounding soft tissue. Any spot you are uncertain about: do NOT count.
Male carpal reference sequence and age constraints:
- 2 carpals clearly visible → constrain bone age range to 0–20 months
- 3 carpals clearly visible → constrain bone age range to 15–36 months
- 4 carpals clearly visible → constrain bone age range to 22–48 months
- 5+ carpals → constrain to 36+ months
State exactly how many you see and why. Name which bones you are confident are present.

STEP 2 — QUALITATIVE EPIPHYSEAL APPEARANCE (secondary, must not override carpal constraint):
For each bone group below, use ONLY these descriptors. Do not use percentages or measurements:
- "absent": no separate ossification center visible
- "barely_visible": just appearing as a thin sliver or tiny dot
- "small_clear": clearly present but distinctly smaller than the shaft
- "well_formed": clearly present, comparable width to shaft
- "wide_capping": clearly wider than shaft or beginning to overhang

Assess these groups only:
1. Distal radius epiphysis
2. Distal ulna epiphysis
3. Metacarpal distal epiphyses (assess as a group)
4. Proximal phalangeal epiphyses (as a group)
5. Middle phalangeal epiphyses (as a group)
6. Distal phalangeal epiphyses (as a group)

STEP 3 — BONE AGE ESTIMATE:
Use carpal count range (Step 1) as the HARD CONSTRAINT. Epiphyseal appearance (Step 2) refines within that range only.
Example: if carpal count = 2 (range 0-20mo) and epiphyses appear "small_clear" → range 12-20mo, not 24mo.
Output a range. State best estimate within range. State confidence and what limits it.

STEP 4 — STATISTICAL CONTEXT:
Reference population SDs for GP method (males, from published literature):
- Age <24 months: SD = 5.1 months
- Age 24-36 months: SD = 5.6 months
- Age 36-60 months: SD = 6.8 months
- Age 60-96 months: SD = 7.8 months
- Age 96-144 months: SD = 9.5 months
- Age >144 months: SD = 11.0 months

Compute: delta = best_estimate_months - chronological_age_months
Compute: SDS = delta / population_sd
Clinical interpretation: |SDS| < 1.0 = normal; 1.0-2.0 = borderline; > 2.0 = significant

RESPONSE: Return ONLY valid JSON. No markdown. No text before or after the JSON object.`;

// ── JSON schema description appended to user message ─────────────
const JSON_SCHEMA = `{
  "carpal_analysis": {
    "count_visible": <integer>,
    "count_confidence": "<high|medium|low>",
    "bones_identified": ["capitate", "hamate"],
    "age_range_constraint_months": [<low>, <high>],
    "count_note": "<explain any uncertainty>"
  },
  "epiphyseal_observations": [
    {
      "bone_group": "<distal_radius|distal_ulna|metacarpals|proximal_phalanges|middle_phalanges|distal_phalanges>",
      "appearance": "<absent|barely_visible|small_clear|well_formed|wide_capping>",
      "observation": "<1 sentence qualitative description, no pixel ratios>",
      "gp_reference": "<which GP atlas age plate this resembles>"
    }
  ],
  "gp_plate_match": "<overall GP plate comparison — which plate or between which plates>",
  "bone_age_estimate": {
    "range_low_months": <integer>,
    "range_high_months": <integer>,
    "best_estimate_months": <integer>,
    "confidence": "<low|medium|high>",
    "primary_determinant": "<carpals|epiphyses|combined>",
    "limiting_factor": "<carpal_count_uncertainty|image_quality|normal_variation>",
    "reasoning": "<2-3 sentences explaining the estimate>"
  },
  "statistical_analysis": {
    "chronological_age_months": <number>,
    "delta_months": <number>,
    "population_sd_months": <number>,
    "sds_score": <number>,
    "p_value_approx": <number>,
    "clinical_significance": "<normal|borderline|significant>",
    "interpretation": "<1 clear sentence>"
  },
  "image_quality_assessment": "<note on JPEG/resolution quality and its effect on precision>",
  "dicom_note": "DICOM-grade imaging would improve carpal boundary detection and epiphysis measurement precision by ~15-20%. Consider requesting DICOM format for future studies.",
  "clinical_caveat": "Educational AI reference only. Not a clinical diagnosis. Requires verification by a board-certified pediatric radiologist."
}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  if (!ANTHROPIC_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: "Service not configured" }, 500);
  }

  // ── Step 1: Verify session ───────────────────────────────────────
  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!jwt) return jsonResponse({ error: "Authentication required" }, 401);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: { user }, error: authError } = await adminClient.auth.getUser(jwt);
  if (authError || !user) return jsonResponse({ error: "Invalid or expired session" }, 401);

  // ── Step 2: Parse request ────────────────────────────────────────
  let body: {
    image_base64: string;
    media_type: string;
    chronological_age_months: number;
    sex: string;
    assessment_id: string;
  };

  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body" }, 400);
  }

  const { image_base64, media_type, chronological_age_months, sex, assessment_id } = body;

  if (!image_base64 || !chronological_age_months || !assessment_id) {
    return jsonResponse({ error: "image_base64, chronological_age_months and assessment_id are required" }, 400);
  }

  // ── Step 3: Verify this record belongs to this user ──────────────
  const { data: record, error: recordError } = await adminClient
    .from("bone_age_assessments")
    .select("assessment_id, child_id, children!inner(parent_id)")
    .eq("assessment_id", assessment_id)
    .single();

  if (recordError || !record) {
    return jsonResponse({ error: "Assessment record not found" }, 404);
  }

  const parentId = (record as any).children?.parent_id;
  if (parentId !== user.id) {
    return jsonResponse({ error: "Not authorized to analyze this record" }, 403);
  }

  // ── Step 3.5: Premium gate (server-side enforcement) ─────────────
  // The AI second opinion is a paid feature; storing + viewing X-ray
  // history and the maturation timeline stay free. The Flutter client
  // shows a paywall first, but a stale/forged client must still be
  // rejected here — the client key is public. An expired paid tier
  // counts as free. `premium_required` is the machine-readable signal
  // the client maps back to the upgrade sheet.
  const { data: acct } = await adminClient
    .from("user_accounts")
    .select("subscription_tier, tier_expires_at")
    .eq("user_id", user.id)
    .single();

  const tier = acct?.subscription_tier ?? "free";
  const notExpired =
    !acct?.tier_expires_at || new Date(acct.tier_expires_at) > new Date();
  const isPremium = tier !== "free" && notExpired;
  if (!isPremium) {
    return jsonResponse({ error: "premium_required" }, 402);
  }

  // ── Step 3.6: Monthly abuse cap ──────────────────────────────────
  // This is the priciest AI call in the product (Sonnet + vision).
  // Premium is the gate; this is the bound — generous enough that a
  // multi-hospital history backfill never hits it.
  const capVerdict = await checkAndCountFeatureUse(adminClient, {
    userId: user.id,
    tier,
    feature: "bone_age",
    capColumn: "bone_age_monthly_cap",
  });
  if (!capVerdict.ok) {
    return jsonResponse(capVerdict.body, capVerdict.status);
  }

  // ── Step 4: Build user message with image + context ──────────────
  const ageYears = Math.floor(chronological_age_months / 12);
  const ageMonths = Math.round(chronological_age_months % 12);
  const sexLabel = sex === "female" ? "Female" : "Male";

  const userMessage = {
    role: "user",
    content: [
      {
        type: "image",
        source: {
          type: "base64",
          media_type: media_type || "image/jpeg",
          data: image_base64,
        },
      },
      {
        type: "text",
        text: `Please analyze this pediatric left-hand PA radiograph for bone age assessment.

Patient context:
- Sex: ${sexLabel}
- Chronological age: ${chronological_age_months} months (${ageYears} years ${ageMonths} months)
- Image format: JPEG from digital radiograph (apply JPEG quality caveats)

Follow the protocol exactly and return your result as JSON matching this schema:
${JSON_SCHEMA}`,
      },
    ],
  };

  // ── Step 5: Call Claude Vision ───────────────────────────────────
  try {
    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 2000,
        system: GP_SYSTEM_PROMPT,
        messages: [userMessage],
      }),
    });

    const data = await anthropicRes.json();

    if (!anthropicRes.ok) {
      console.error("[bone-age-analysis] Anthropic error:", data);
      return jsonResponse({ error: "AI analysis failed", detail: data }, 502);
    }

    // ── Step 6: Parse and validate the JSON response ─────────────────
    const rawText = data.content?.[0]?.text || "";
    let analysisResult: Record<string, unknown>;

    try {
      // Strip any accidental markdown fences Claude might have added
      const cleaned = rawText.replace(/^```json\s*/i, "").replace(/\s*```$/i, "").trim();
      analysisResult = JSON.parse(cleaned);
    } catch {
      console.error("[bone-age-analysis] Failed to parse Claude JSON:", rawText.slice(0, 500));
      return jsonResponse({ error: "AI returned unparseable result", raw: rawText.slice(0, 500) }, 500);
    }

    // ── Step 7: Save result to database ─────────────────────────────
    await adminClient
      .from("bone_age_assessments")
      .update({
        ai_analysis_result: analysisResult,
        ai_analysis_date: new Date().toISOString(),
        ai_analysis_model: "claude-sonnet-4-6",
      })
      .eq("assessment_id", assessment_id);

    return jsonResponse({ success: true, result: analysisResult });

  } catch (e) {
    console.error("[bone-age-analysis] Unexpected error:", e);
    return jsonResponse({ error: "Internal error" }, 500);
  }
});
