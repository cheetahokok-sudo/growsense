// ══════════════════════════════════════════════════════════════════
// GrowSense Food Reference Data — protein, zinc, calcium per 100g
//
// Every value below is transcribed from a real USDA FoodData Central
// record (cited per food, with FDC ID), normalized to a consistent
// per-100g, cooked/as-eaten basis — not estimated, not from memory.
// Where a nutrient wasn't available from the source checked, it's
// marked null rather than guessed.
//
// IMPORTANT — cooked vs raw: protein content per 100g differs
// meaningfully between raw and cooked meat/fish (cooking removes
// water, concentrating nutrients per gram). Every entry here is the
// COOKED/prepared form, since that's what's actually eaten. If you
// add a food, look up the cooked entry, not raw, unless the food is
// genuinely eaten raw (milk, yogurt).
//
// Source pattern: USDA FoodData Central (fdc.nal.usda.gov), most
// retrieved via myfooddata.com's display of the same USDA records
// (each entry links back to the original fdc.nal.usda.gov page).
// USDA data is public domain (CC0 1.0) — see FORMULAS.md for the
// citation policy.
// ══════════════════════════════════════════════════════════════════

const FOOD_REFERENCE_DATA = [
  {
    id: 'egg',
    name: 'Egg',
    emoji: '🥚',
    prepNote: 'hard-boiled, 1 large (50g)',
    per100g: { protein_g: 12.60, zinc_mg: 1.06, calcium_mg: 50.0 },
    servingGrams: 50, // 1 large egg
    source: 'USDA FDC 173424 — Egg, whole, cooked, hard-boiled'
  },
  {
    id: 'milk',
    name: 'Milk',
    emoji: '🥛',
    prepNote: 'whole milk, 3.25% fat',
    per100g: { protein_g: 3.16, zinc_mg: 0.37, calcium_mg: 112.99 },
    servingGrams: 100, // parent enters ml; 100ml ≈ 100g for milk
    source: 'USDA FDC 171265 — Milk, whole, 3.25% milkfat, with added vitamin D'
  },
  {
    id: 'cheddar',
    name: 'Cheddar cheese',
    emoji: '🧀',
    prepNote: 'per slice, ~28g',
    per100g: { protein_g: 23.70, zinc_mg: 3.10, calcium_mg: 721.0 },
    servingGrams: 28, // 1 slice / 1oz
    source: 'USDA FDC 173414 — Cheese, cheddar'
  },
  {
    id: 'chicken_breast',
    name: 'Chicken breast',
    emoji: '🍗',
    prepNote: 'cooked, skinless, boneless',
    per100g: { protein_g: 32.06, zinc_mg: 0.94, calcium_mg: 6.0 },
    servingGrams: 30,
    source: 'USDA FDC 171140 — Chicken, broiler/fryers, breast, skinless, boneless, meat only, cooked, braised'
  },
  {
    id: 'salmon',
    name: 'Salmon',
    emoji: '🐟',
    prepNote: 'cooked, wild Atlantic',
    per100g: { protein_g: 25.41, zinc_mg: 0.82, calcium_mg: 15.0 },
    servingGrams: 30,
    source: 'USDA FDC 171998 — Fish, salmon, Atlantic, wild, cooked, dry heat'
  },
  {
    id: 'shrimp',
    name: 'Shrimp',
    emoji: '🦐',
    prepNote: 'cooked',
    per100g: { protein_g: 23.98, zinc_mg: 1.64, calcium_mg: null }, // calcium not found in source checked — see note above
    servingGrams: 85, // ~3 medium shrimp
    source: 'USDA FDC 175180 — Crustaceans, shrimp, cooked'
  },
  {
    id: 'beef_steak',
    name: 'Beef steak',
    emoji: '🥩',
    prepNote: 'top sirloin, cooked, broiled, lean',
    per100g: { protein_g: 30.0, zinc_mg: 5.71, calcium_mg: 19.29 },
    servingGrams: 30,
    source: 'USDA FDC 174054 — Beef, top sirloin, steak, separable lean only, trimmed to 1/8" fat, all grades, cooked, broiled'
  },
  {
    id: 'yogurt',
    name: 'Yogurt',
    emoji: '🥣',
    prepNote: 'plain, whole milk',
    per100g: { protein_g: 3.50, zinc_mg: 0.57, calcium_mg: 121.0 },
    servingGrams: 100,
    source: 'USDA FDC 171284 — Yogurt, plain, whole milk'
  },
  {
    id: 'nuggets',
    name: 'Chicken nuggets',
    emoji: '🍗',
    prepNote: 'generic, frozen, cooked (brand-specific values vary — use as a rough estimate only)',
    per100g: { protein_g: 14.0, zinc_mg: null, calcium_mg: null }, // generic estimate, not a single specific USDA record — see note below
    servingGrams: 50, // ~2-3 pieces
    source: 'Generic estimate from USDA-category frozen/fast-food chicken nugget products — varies by brand; not tied to a single FDC ID. Replace with the specific product\'s own label values if known.'
  }
];

// "Protein Boost" is intentionally NOT a database entry — it's a flat
// manual +10g quick-add button for whenever a parent reads a protein
// number off any product's own label (a supplement, protein bar,
// fortified drink, etc.) and wants to log it without searching for it.
// This is explicitly self-reported/manual, not sourced from any
// nutrition database — see app.js's logProteinBoost() and the
// dq-badge "estimated" styling applied to it in the UI.

if (typeof module !== 'undefined') {
  module.exports = { FOOD_REFERENCE_DATA };
}
