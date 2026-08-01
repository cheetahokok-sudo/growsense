// ══════════════════════════════════════════════════════════════════
// GrowSense Edge Function: food-scan  (Food Lens)
//
// Two camera modes behind one cap ('food_scan'):
//   mode:"meal"  — a photo of a child's meal. The model identifies
//                  foods ONLY as ids from the GrowSense reference
//                  library (closed set) plus portion RANGES in grams.
//                  It NEVER outputs nutrient values — the client
//                  computes nutrients from its own cited per-100g
//                  data. Unmatched foods come back as plain names
//                  with same-category proxy candidates the parent
//                  can explicitly choose.
//   mode:"label" — a photo of a packaged food's nutrition panel.
//                  The model transcribes ONLY what is printed (the
//                  photo is the citation — the no-guess rule extended
//                  to packaged food). A deterministic validation pass
//                  flags unit/plausibility problems for parent review.
//
// Design notes:
//   * Photos are TRANSIENT — base64 in, nothing stored, no bucket.
//   * Structured outputs (output_config.format) — guaranteed JSON,
//     no markdown-fence stripping.
//   * cache_control on the system prompt: the food index + rules are
//     byte-identical across calls. (Haiku's min cacheable prefix may
//     exceed this prompt; the marker is harmless either way.)
//   * Skeleton (auth → ownership → premium → cap → Anthropic) copied
//     from bone-age-analysis; same error conventions.
//
// DEPLOY:
//   supabase functions deploy food-scan --project-ref ogpkmcqaulohexanucng
//   No new secrets. REQUIRES migrations/2026-08-01_food_scan_caps.sql
//   (CHECK-constraint widening) before real traffic, else the usage
//   counter silently never increments.
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkAndCountFeatureUse } from "../_shared/usage_caps.ts";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";

const MODEL = "claude-haiku-4-5-20251001";

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

// ── Food reference index (closed identification set) ──────────────
// REGENERATE when the library changes:
//   cd flutter_app && node -e "const j=require('./assets/food_reference.json');
//     console.log(JSON.stringify(j.map(f=>({id:f.id,name:f.name,
//     region:f.region||'global',category:f.category||'composite'}))))"
// Source of truth: food-reference-data.js → assets/food_reference.json.
const FOOD_INDEX: { id: string; name: string; region: string; category: string }[] = [{"id":"egg","name":"Egg","region":"global","category":"egg"},{"id":"milk","name":"Milk","region":"global","category":"dairy"},{"id":"cheddar","name":"Cheddar cheese","region":"global","category":"dairy"},{"id":"chicken_breast","name":"Chicken breast","region":"global","category":"chicken"},{"id":"salmon","name":"Salmon","region":"global","category":"fish"},{"id":"shrimp","name":"Shrimp","region":"global","category":"seafood"},{"id":"beef_steak","name":"Beef steak","region":"global","category":"beef"},{"id":"yogurt","name":"Yogurt","region":"global","category":"dairy"},{"id":"nuggets","name":"Chicken nuggets","region":"global","category":"chicken"},{"id":"peanut_butter","name":"Peanut butter","region":"global","category":"plant"},{"id":"tofu","name":"Tofu","region":"global","category":"plant"},{"id":"pork_loin","name":"Pork loin","region":"global","category":"pork"},{"id":"bacon","name":"Bacon","region":"global","category":"pork"},{"id":"deli_ham","name":"Ham (deli)","region":"global","category":"deli"},{"id":"deli_turkey","name":"Turkey breast (deli)","region":"global","category":"deli"},{"id":"bologna","name":"Bologna (pork)","region":"global","category":"deli"},{"id":"salami","name":"Salami (dry)","region":"global","category":"deli"},{"id":"hot_dog","name":"Hot dog / frankfurter","region":"global","category":"deli"},{"id":"vienna_sausage","name":"Vienna sausage","region":"global","category":"deli"},{"id":"raw_salmon","name":"Salmon (raw)","region":"global","category":"fish"},{"id":"squid","name":"Squid","region":"global","category":"seafood"},{"id":"crab","name":"Crab","region":"global","category":"seafood"},{"id":"tuna","name":"Tuna","region":"global","category":"fish"},{"id":"tilapia","name":"Tilapia (white fish)","region":"global","category":"fish"},{"id":"duck","name":"Duck","region":"global","category":"chicken"},{"id":"miso","name":"Miso","region":"global","category":"plant"},{"id":"cn_steamed_egg","name":"Steamed Egg Custard","region":"cn","category":"egg"},{"id":"cn_pork_dumplings","name":"Pork Dumplings (Jiaozi)","region":"cn","category":"pork"},{"id":"cn_tomato_egg","name":"Stir-Fried Tomato & Egg","region":"cn","category":"egg"},{"id":"cn_lions_head","name":"Lion's Head Meatball","region":"cn","category":"pork"},{"id":"cn_char_siu","name":"Char Siu (BBQ Pork)","region":"cn","category":"pork"},{"id":"cn_braised_tofu","name":"Braised Tofu Cubes","region":"cn","category":"plant"},{"id":"cn_chicken_congee","name":"Chicken Congee","region":"cn","category":"composite"},{"id":"cn_beef_broccoli","name":"Beef with Broccoli","region":"cn","category":"beef"},{"id":"cn_steamed_fish","name":"Steamed Fish Fillet","region":"cn","category":"fish"},{"id":"cn_shrimp_wonton","name":"Shrimp Wonton","region":"cn","category":"seafood"},{"id":"kr_beef_bulgogi","name":"Beef Bulgogi","region":"kr","category":"beef"},{"id":"kr_rolled_omelette","name":"Rolled Omelette (Gyeran-mari)","region":"kr","category":"egg"},{"id":"kr_fried_chicken","name":"Korean Fried Chicken","region":"kr","category":"chicken"},{"id":"kr_tteok_galbi","name":"Tteok-galbi","region":"kr","category":"beef"},{"id":"kr_fish_cakes","name":"Korean Fish Cakes (Eomuk)","region":"kr","category":"fish"},{"id":"kr_gim","name":"Roasted Seaweed (Gim)","region":"kr","category":"plant"},{"id":"kr_soft_tofu","name":"Soft Tofu (Soon-dubu)","region":"kr","category":"plant"},{"id":"kr_grilled_mackerel","name":"Grilled Mackerel (Godeungeo)","region":"kr","category":"fish"},{"id":"kr_donkasu","name":"Pork Cutlet (Donkasu)","region":"kr","category":"pork"},{"id":"kr_miyeok_guk","name":"Beef Seaweed Soup (Miyeok-guk)","region":"kr","category":"composite"},{"id":"ae_chicken_shawarma","name":"Chicken Shawarma","region":"ae","category":"chicken"},{"id":"ae_shish_tawook","name":"Shish Tawook","region":"ae","category":"chicken"},{"id":"ae_lentil_soup","name":"Lentil Soup (Adas)","region":"ae","category":"plant"},{"id":"ae_halloumi","name":"Grilled Halloumi Cheese","region":"ae","category":"dairy"},{"id":"ae_kofta","name":"Kofta Kebab","region":"ae","category":"beef"},{"id":"ae_machboos_chicken","name":"Chicken Machboos (meat only)","region":"ae","category":"chicken"},{"id":"ae_falafel","name":"Falafel","region":"ae","category":"plant"},{"id":"ae_labneh","name":"Labneh","region":"ae","category":"dairy"},{"id":"ae_hummus","name":"Hummus","region":"ae","category":"plant"},{"id":"ae_hammour","name":"Baked Hammour / Sea Bream","region":"ae","category":"fish"},{"id":"th_moo_ping","name":"Moo Ping (Grilled Pork Skewer)","region":"th","category":"pork"},{"id":"th_kai_jeow","name":"Thai Omelette (Kai Jeow)","region":"th","category":"egg"},{"id":"th_gai_tod","name":"Thai Fried Chicken (Gai Tod)","region":"th","category":"chicken"},{"id":"th_pad_kra_prow","name":"Minced Pork Kra Prow (mild)","region":"th","category":"pork"},{"id":"th_khao_man_gai","name":"Poached Chicken (Khao Man Gai)","region":"th","category":"chicken"},{"id":"th_look_chin","name":"Pork Meatball Skewers (Look Chin)","region":"th","category":"pork"},{"id":"th_kun_chiang","name":"Sweet Chinese Sausage (Kun Chiang)","region":"th","category":"pork"},{"id":"th_gaeng_jued","name":"Clear Soup (Gaeng Jued)","region":"th","category":"composite"},{"id":"th_shrimp_garlic","name":"Garlic Shrimp (Kung Kratiam)","region":"th","category":"seafood"},{"id":"th_moo_yong","name":"Pork Floss (Moo Yong)","region":"th","category":"pork"},{"id":"vn_thit_kho","name":"Caramelized Pork & Egg (Thịt Kho)","region":"vn","category":"pork"},{"id":"vn_pho_beef","name":"Phở Sliced Beef (meat only)","region":"vn","category":"beef"},{"id":"vn_cha_lua","name":"Vietnamese Pork Sausage (Chả Lụa)","region":"vn","category":"pork"},{"id":"vn_fish_sauce_wings","name":"Fish Sauce Fried Wings","region":"vn","category":"chicken"},{"id":"vn_cha_trung","name":"Steamed Egg Meatloaf (Chả Trứng)","region":"vn","category":"egg"},{"id":"vn_tom_rim","name":"Caramelized Shrimp (Tôm Rim)","region":"vn","category":"seafood"},{"id":"vn_xiu_mai","name":"Vietnamese Tomato Meatballs (Xíu Mại)","region":"vn","category":"pork"},{"id":"vn_trung_cut","name":"Fried Quail Eggs (Trứng Cút)","region":"vn","category":"egg"},{"id":"vn_fried_tofu","name":"Fried Tofu with Tomato Sauce","region":"vn","category":"plant"},{"id":"vn_thit_luoc","name":"Boiled Pork Belly (Thịt Luộc)","region":"vn","category":"pork"},{"id":"us_beef_burger","name":"Beef Burger Patty","region":"us","category":"beef"},{"id":"us_mac_cheese","name":"Macaroni and Cheese","region":"us","category":"composite"},{"id":"us_turkey_slices","name":"Turkey Breast Slices","region":"us","category":"chicken"},{"id":"us_fish_sticks","name":"Fish Sticks","region":"us","category":"fish"},{"id":"us_pepperoni_pizza","name":"Pepperoni Pizza","region":"us","category":"composite"},{"id":"us_string_cheese","name":"String Cheese","region":"us","category":"dairy"},{"id":"us_pork_sausage","name":"Pork Breakfast Sausage","region":"us","category":"pork"},{"id":"us_hot_dog","name":"Beef Hot Dog","region":"us","category":"beef"},{"id":"us_tuna_salad","name":"Canned Tuna Salad","region":"us","category":"fish"},{"id":"us_chicken_leg","name":"Rotisserie Chicken Leg","region":"us","category":"chicken"},{"id":"eu_pork_schnitzel","name":"Pork Schnitzel","region":"eu","category":"pork"},{"id":"eu_bolognese_sauce","name":"Bolognese Meat Sauce","region":"eu","category":"beef"},{"id":"eu_fish_fingers","name":"Fish Fingers (Cod)","region":"eu","category":"fish"},{"id":"eu_swedish_meatballs","name":"Swedish Meatballs (Köttbullar)","region":"eu","category":"beef"},{"id":"eu_wiener_sausage","name":"Wiener Sausage","region":"eu","category":"pork"},{"id":"eu_boiled_ham","name":"Boiled Ham (Prosciutto Cotto)","region":"eu","category":"pork"},{"id":"eu_gouda_cheese","name":"Gouda / Edam Cheese","region":"eu","category":"dairy"},{"id":"eu_greek_yogurt","name":"Greek Strained Yogurt","region":"eu","category":"dairy"},{"id":"eu_baked_beans","name":"Baked Beans in Tomato Sauce","region":"eu","category":"plant"},{"id":"eu_cordon_bleu","name":"Chicken Cordon Bleu","region":"eu","category":"chicken"}];

const VALID_IDS = new Set(FOOD_INDEX.map((f) => f.id));
const VALID_CATEGORIES = [
  "chicken", "beef", "pork", "fish", "seafood",
  "egg", "dairy", "plant", "composite", "deli", "other",
];

const INDEX_LINES = FOOD_INDEX
  .map((f) => `${f.id} | ${f.name} | ${f.region} | ${f.category}`)
  .join("\n");

// ── Meal mode ──────────────────────────────────────────────────────

const MEAL_SYSTEM_PROMPT = `You identify foods in a photo of a child's meal for GrowSense, a growth-nutrition app for parents.

HARD RULES:
1. Identify foods ONLY as ids from the REFERENCE LIBRARY below. Never invent ids. Never output nutrient values — the app computes nutrients itself from verified data.
2. A food with no reasonable library match goes in "unmatched" with its plain name — do NOT force-fit a wrong id. A missed item is better than a wrong item. For each unmatched food, suggest up to 3 SAME-CATEGORY library ids a parent could knowingly log it as ("proxy_candidates"). Set "packaged" true when the unmatched food is a branded/packaged product whose carton, bottle, wrapper or pouch is visible in the photo (a milk carton, a yogurt cup, a snack bag) — the app then offers to read its nutrition label.
3. Portions are RANGES in grams (low/best/high), rounded to the nearest 5 g, AS SERVED TO A CHILD of the stated age. Photos exaggerate; adult and restaurant portions are not child portions. When uncertain between two amounts choose the SMALLER — parents adjust upward easily.
4. Use in-frame scale references: a standard dinner plate is ~23 cm across (unless a different plate size is given), a tablespoon ~15 cm long, chopsticks ~20 cm. Say nothing about scale in the output — just use it.
5. Composite dishes (fried rice, noodle soup, congee): match the composite library entry when one exists rather than decomposing into ingredients.
6. Food in a bowl, soup, or covered by rice/noodles cannot be fully seen: set container to "bowl" and wants_side_view true so the app can ask the parent for a fullness estimate or a side-angle photo.
7. "confidence" is about IDENTIFICATION, not grams. Grams are always rough — the app tells the parent that.
8. If the image is not food or is unreadably poor, return an empty items array and explain briefly in not_food_note.
9. If a region hint is given, prefer that region's dishes when a dish is ambiguous between regions.

REFERENCE LIBRARY (id | name | region | category):
${INDEX_LINES}`;

const MEAL_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["items", "unmatched", "wants_side_view", "not_food_note"],
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["food_id", "low_g", "best_g", "high_g", "confidence", "container", "note"],
        properties: {
          food_id: { type: "string" },
          low_g: { type: "integer" },
          best_g: { type: "integer" },
          high_g: { type: "integer" },
          confidence: { type: "string", enum: ["high", "medium", "low"] },
          container: { type: "string", enum: ["plate", "bowl", "cup", "skewer", "other"] },
          note: { type: "string" },
        },
      },
    },
    unmatched: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "best_g", "category", "proxy_candidates", "packaged"],
        properties: {
          name: { type: "string" },
          best_g: { type: "integer" },
          category: { type: "string", enum: VALID_CATEGORIES },
          proxy_candidates: { type: "array", items: { type: "string" } },
          packaged: { type: "boolean" },
        },
      },
    },
    wants_side_view: { type: "boolean" },
    not_food_note: { type: "string" },
  },
};

// ── Label mode ─────────────────────────────────────────────────────

const LABEL_SYSTEM_PROMPT = `You read a nutrition-facts label photographed by a parent for GrowSense, a growth-nutrition app. The label IS the source of truth — transcribe only what is printed on it. Labels may be in Thai, Korean, Vietnamese, Chinese, Arabic or English.

HARD RULES:
1. Copy numbers exactly as printed. Convert units only when exact and trivial (e.g. 0.2 g -> 200 mg). Never estimate a value that is not printed — use null.
2. Report which basis the values you transcribed use: the per-serving column, the per-100g/per-100ml column, or unknown. Prefer per-serving when both are printed. Do not mix columns.
3. serving_grams: the printed serving size in grams or ml. If printed as "1 ซอง (30 g)" style text, extract the number. null when not printed.
4. name: the product name if visible (in the photo's packaging), translated to English with the original in parentheses; otherwise a short generic descriptor of what the label appears to belong to.
5. energy: kcal as printed (Thai labels: กิโลแคลอรี; if only kJ is printed, divide by 4.184 and note it in low_confidence_fields).
6. Minerals printed ONLY as a percent of daily intake (e.g. "แคลเซียม 15%", "칼슘 15%") — common on Thai labels: put the percent number in rdi_percents and leave the absolute value null. Never convert percents yourself.
7. List any field you are not certain you read correctly in low_confidence_fields.
8. If the image is not a nutrition label or is unreadable, set unreadable true with a short reason.`;

const LABEL_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "name", "serving_grams", "basis", "values", "rdi_percents",
    "label_language", "low_confidence_fields", "unreadable", "unreadable_reason",
  ],
  properties: {
    name: { type: "string" },
    serving_grams: { anyOf: [{ type: "number" }, { type: "null" }] },
    basis: { type: "string", enum: ["per_serving", "per_100g", "unknown"] },
    values: {
      type: "object",
      additionalProperties: false,
      required: ["energy_kcal", "protein_g", "calcium_mg", "zinc_mg"],
      properties: {
        energy_kcal: { anyOf: [{ type: "number" }, { type: "null" }] },
        protein_g: { anyOf: [{ type: "number" }, { type: "null" }] },
        calcium_mg: { anyOf: [{ type: "number" }, { type: "null" }] },
        zinc_mg: { anyOf: [{ type: "number" }, { type: "null" }] },
      },
    },
    // Minerals printed only as % of daily intake (Thai labels do this).
    rdi_percents: {
      type: "object",
      additionalProperties: false,
      required: ["calcium_pct", "zinc_pct"],
      properties: {
        calcium_pct: { anyOf: [{ type: "number" }, { type: "null" }] },
        zinc_pct: { anyOf: [{ type: "number" }, { type: "null" }] },
      },
    },
    label_language: { type: "string" },
    low_confidence_fields: { type: "array", items: { type: "string" } },
    unreadable: { type: "boolean" },
    unreadable_reason: { type: "string" },
  },
};

// ── Thai RDI %→mg conversion (deterministic, published table) ──────
// Thai FDA RDI (Notification 445 basis, 2,000 kcal reference), verified
// 2026-08-01: calcium 800 mg, zinc 15 mg. Thai labels routinely print
// minerals as %Thai RDI only ("แคลเซียม 15%") — converting against the
// published table is arithmetic, not a guess. Converted fields are
// reported in computed_from_rdi AND flagged needs_review so the parent
// verifies against the package. Only applied for Thai labels; other
// locales' reference tables are not yet verified here.
const THAI_RDI_MG: Record<string, number> = { calcium_mg: 800, zinc_mg: 15 };

function applyThaiRdi(r: Record<string, unknown>): string[] {
  const computed: string[] = [];
  const lang = String(r.label_language ?? "").toLowerCase();
  if (!lang.startsWith("th")) return computed;
  const values = (r.values ?? {}) as Record<string, number | null>;
  const pcts = (r.rdi_percents ?? {}) as Record<string, number | null>;
  const pairs: [string, string][] = [
    ["calcium_mg", "calcium_pct"],
    ["zinc_mg", "zinc_pct"],
  ];
  for (const [field, pctField] of pairs) {
    const pct = pcts[pctField];
    if (values[field] == null && typeof pct === "number" && pct > 0 && pct <= 200) {
      values[field] = Math.round((pct / 100) * THAI_RDI_MG[field]);
      computed.push(field);
    }
  }
  r.values = values;
  return computed;
}

// ── Deterministic label sanity checks (never auto-correct) ─────────
function labelNeedsReview(r: Record<string, unknown>): string[] {
  const review = new Set<string>(
    Array.isArray(r.low_confidence_fields) ? r.low_confidence_fields as string[] : [],
  );
  const values = (r.values ?? {}) as Record<string, number | null>;
  const serving = typeof r.serving_grams === "number" ? r.serving_grams : null;
  const perServing = r.basis === "per_serving" && serving != null;
  const base = perServing ? serving : 100;

  const protein = values.protein_g;
  if (protein != null && (protein < 0 || protein > base)) review.add("protein_g");
  const calcium = values.calcium_mg;
  if (calcium != null && (calcium < 0 || calcium > base * 50)) review.add("calcium_mg"); // >5 g/100g ⇒ likely g↔mg slip
  const zinc = values.zinc_mg;
  if (zinc != null && (zinc < 0 || zinc > base)) review.add("zinc_mg");
  const kcal = values.energy_kcal;
  if (kcal != null && (kcal < 0 || kcal > base * 9)) review.add("energy_kcal"); // > pure fat
  if (serving != null && (serving <= 0 || serving > 2000)) review.add("serving_grams");
  return [...review];
}

// ── Handler ────────────────────────────────────────────────────────

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
    mode: string;
    images: { base64: string; media_type?: string }[];
    child_id: string;
    region_hint?: string;
    plate_hint_cm?: number;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body" }, 400);
  }

  const { mode, images, child_id, region_hint, plate_hint_cm } = body;
  if (mode !== "meal" && mode !== "label") {
    return jsonResponse({ error: "mode must be 'meal' or 'label'" }, 400);
  }
  if (!Array.isArray(images) || images.length < 1 || images.length > 2 ||
    images.some((i) => !i?.base64)) {
    return jsonResponse({ error: "images must contain 1-2 entries with base64 data" }, 400);
  }
  if (!child_id) return jsonResponse({ error: "child_id is required" }, 400);

  // ── Step 3: Ownership ────────────────────────────────────────────
  const { data: child, error: childError } = await adminClient
    .from("children")
    .select("child_id, parent_id, date_of_birth")
    .eq("child_id", child_id)
    .single();
  if (childError || !child) return jsonResponse({ error: "Child not found" }, 404);
  if (child.parent_id !== user.id) {
    return jsonResponse({ error: "Not authorized to log for this child" }, 403);
  }

  // ── Step 3.5: Premium gate (server-side; client key is public) ───
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

  // ── Step 3.6: Monthly abuse cap (meal + label share one bucket) ──
  const capVerdict = await checkAndCountFeatureUse(adminClient, {
    userId: user.id,
    tier,
    feature: "food_scan",
    capColumn: "food_scan_monthly_cap",
  });
  if (!capVerdict.ok) return jsonResponse(capVerdict.body, capVerdict.status);

  // ── Step 4: Build the request ────────────────────────────────────
  let ageYears: number | null = null;
  if (child.date_of_birth) {
    ageYears = Math.max(0, Math.floor(
      (Date.now() - new Date(child.date_of_birth).getTime()) / (365.25 * 24 * 3600 * 1000),
    ));
  }

  const imageBlocks = images.map((img) => ({
    type: "image",
    source: {
      type: "base64",
      media_type: img.media_type || "image/jpeg",
      data: img.base64,
    },
  }));

  const isMeal = mode === "meal";
  const contextText = isMeal
    ? [
      `Child age: ${ageYears != null ? `~${ageYears} years` : "unknown"}.`,
      `Region hint: ${region_hint || "unknown"}.`,
      plate_hint_cm ? `The family's plate is ~${plate_hint_cm} cm across.` : "",
      images.length === 2
        ? "Two photos of the SAME meal: overhead view and side/angled view — use both for portion estimation."
        : "",
      "Identify the foods and estimate child portions per the rules.",
    ].filter(Boolean).join("\n")
    : "Transcribe this nutrition label per the rules." +
      (images.length === 2 ? " Two photos of the SAME package (e.g. front + panel)." : "");

  // ── Step 5: Call Claude (structured output, cached system) ───────
  try {
    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 1500,
        system: [
          {
            type: "text",
            text: isMeal ? MEAL_SYSTEM_PROMPT : LABEL_SYSTEM_PROMPT,
            cache_control: { type: "ephemeral" },
          },
        ],
        output_config: {
          format: {
            type: "json_schema",
            schema: isMeal ? MEAL_SCHEMA : LABEL_SCHEMA,
          },
        },
        messages: [
          { role: "user", content: [...imageBlocks, { type: "text", text: contextText }] },
        ],
      }),
    });

    const data = await anthropicRes.json();
    if (!anthropicRes.ok) {
      console.error("[food-scan] Anthropic error:", data);
      return jsonResponse({ error: "AI analysis failed", detail: data }, 502);
    }

    const rawText = data.content?.[0]?.text || "";
    let result: Record<string, unknown>;
    try {
      result = JSON.parse(rawText);
    } catch {
      console.error("[food-scan] unparseable output:", rawText.slice(0, 500));
      return jsonResponse({ error: "AI returned unparseable result" }, 500);
    }

    // ── Step 6: Mode-specific post-validation ──────────────────────
    if (isMeal) {
      const clamp = (n: unknown) =>
        Math.min(500, Math.max(5, Math.round((Number(n) || 0) / 5) * 5));
      const items = Array.isArray(result.items) ? result.items as Record<string, unknown>[] : [];
      const unmatched = Array.isArray(result.unmatched)
        ? result.unmatched as Record<string, unknown>[]
        : [];

      const validItems: Record<string, unknown>[] = [];
      for (const it of items) {
        if (!VALID_IDS.has(String(it.food_id))) {
          // Belt-and-braces on the no-guess rule: an invented id becomes
          // an unmatched item instead of silently logging wrong nutrients.
          unmatched.push({
            name: String(it.food_id).replace(/_/g, " "),
            best_g: clamp(it.best_g),
            category: "other",
            proxy_candidates: [],
            packaged: false,
          });
          continue;
        }
        const low = clamp(it.low_g), best = clamp(it.best_g), high = clamp(it.high_g);
        const [l, b, h] = [low, best, high].sort((a, z) => a - z);
        validItems.push({ ...it, low_g: l, best_g: b, high_g: h });
      }
      for (const u of unmatched) {
        u.best_g = clamp(u.best_g);
        u.proxy_candidates = (Array.isArray(u.proxy_candidates) ? u.proxy_candidates : [])
          .filter((id) => VALID_IDS.has(String(id))).slice(0, 3);
      }
      result.items = validItems;
      result.unmatched = unmatched;
    } else {
      const computed = applyThaiRdi(result);
      result.computed_from_rdi = computed;
      // Computed values join the review list — parent verifies them.
      result.needs_review = [
        ...new Set([...labelNeedsReview(result), ...computed]),
      ];
    }

    return jsonResponse({ success: true, mode, result });
  } catch (e) {
    console.error("[food-scan] Unexpected error:", e);
    return jsonResponse({ error: "Internal error" }, 500);
  }
});
