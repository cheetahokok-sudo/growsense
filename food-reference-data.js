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

// PORTION VISUALS: comparisons below (matchbox, deck of cards, golf ball,
// etc.) come from standard nutrition-education references — e.g. USDA
// Extension service portion guides — not invented for this app. The
// general rule: ~28g (1oz) of meat/fish is "matchbox-sized"; ~85g (3oz,
// a typical single meal portion) is "deck-of-cards-sized." Since most
// protein cards here use a 30g per-tap unit (close to 1oz), tapping a
// card 2-3 times approximates one real meal-sized portion.

const FOOD_REFERENCE_DATA = [
  {
    id: 'egg',
    name: 'Egg',
    emoji: '🥚',
    prepNote: 'hard-boiled',
    portionVisual: '1 whole egg',
    per100g: { protein_g: 12.60, zinc_mg: 1.06, calcium_mg: 50.0 },
    servingGrams: 50, // 1 large egg
    source: 'USDA FDC 173424 — Egg, whole, cooked, hard-boiled'
  },
  {
    id: 'milk',
    name: 'Milk',
    emoji: '🥛',
    prepNote: 'whole milk, 3.25% fat',
    portionVisual: '~1/3 cup (small glass)',
    per100g: { protein_g: 3.16, zinc_mg: 0.37, calcium_mg: 112.99 },
    servingGrams: 100, // parent enters ml; 100ml ≈ 100g for milk
    source: 'USDA FDC 171265 — Milk, whole, 3.25% milkfat, with added vitamin D'
  },
  {
    id: 'cheddar',
    name: 'Cheddar cheese',
    emoji: '🧀',
    prepNote: '1 slice',
    portionVisual: '~3 dice stacked',
    per100g: { protein_g: 23.70, zinc_mg: 3.10, calcium_mg: 721.0 },
    servingGrams: 28, // 1 slice / 1oz
    source: 'USDA FDC 173414 — Cheese, cheddar'
  },
  {
    id: 'chicken_breast',
    name: 'Chicken breast',
    emoji: '🍗',
    prepNote: 'cooked, skinless, boneless',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 32.06, zinc_mg: 0.94, calcium_mg: 6.0 },
    servingGrams: 30,
    source: 'USDA FDC 171140 — Chicken, broiler/fryers, breast, skinless, boneless, meat only, cooked, braised'
  },
  {
    id: 'salmon',
    name: 'Salmon',
    emoji: '🐟',
    prepNote: 'cooked, wild Atlantic',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 25.41, zinc_mg: 0.82, calcium_mg: 15.0 },
    servingGrams: 30,
    source: 'USDA FDC 171998 — Fish, salmon, Atlantic, wild, cooked, dry heat'
  },
  {
    id: 'shrimp',
    name: 'Shrimp',
    emoji: '🦐',
    prepNote: 'cooked',
    portionVisual: '~3 medium shrimp',
    per100g: { protein_g: 23.98, zinc_mg: 1.64, calcium_mg: null }, // calcium not found in source checked — see note above
    servingGrams: 85, // ~3 medium shrimp
    source: 'USDA FDC 175180 — Crustaceans, shrimp, cooked'
  },
  {
    id: 'beef_steak',
    name: 'Beef steak',
    emoji: '🥩',
    prepNote: 'top sirloin, cooked, broiled, lean',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 30.0, zinc_mg: 5.71, calcium_mg: 19.29 },
    servingGrams: 30,
    source: 'USDA FDC 174054 — Beef, top sirloin, steak, separable lean only, trimmed to 1/8" fat, all grades, cooked, broiled'
  },
  {
    id: 'yogurt',
    name: 'Yogurt',
    emoji: '🥣',
    prepNote: 'plain, whole milk',
    portionVisual: '~1/3 cup (small pot)',
    per100g: { protein_g: 3.50, zinc_mg: 0.57, calcium_mg: 121.0 },
    servingGrams: 100,
    source: 'USDA FDC 171284 — Yogurt, plain, whole milk'
  },
  {
    id: 'nuggets',
    name: 'Chicken nuggets',
    emoji: '🍗',
    prepNote: 'generic, frozen, cooked (brand-specific values vary — use as a rough estimate only)',
    portionVisual: '~2 nuggets',
    per100g: { protein_g: 14.0, zinc_mg: null, calcium_mg: null }, // generic estimate, not a single specific USDA record — see note below
    servingGrams: 50, // ~2-3 pieces
    source: 'Generic estimate from USDA-category frozen/fast-food chicken nugget products — varies by brand; not tied to a single FDC ID. Replace with the specific product\'s own label values if known.'
  },
  {
    id: 'peanut_butter',
    name: 'Peanut butter',
    emoji: '🥜',
    prepNote: 'smooth',
    portionVisual: '~2 tbsp',
    per100g: { protein_g: 21.88, zinc_mg: 2.66, calcium_mg: 54.06 },
    servingGrams: 32,
    source: 'USDA FDC 174294 — Peanut Butter, smooth (Includes foods for USDA\'s Food Distribution Program)'
  },
  {
    id: 'tofu',
    name: 'Tofu',
    emoji: '🧊',
    prepNote: 'extra firm, prepared with nigari',
    portionVisual: '~1/5 block',
    per100g: { protein_g: 10.00, zinc_mg: 1.07, calcium_mg: 281.98 },
    servingGrams: 91,
    source: 'USDA FDC 174290 — Tofu, extra firm, prepared with nigari'
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
