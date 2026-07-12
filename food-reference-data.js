// ══════════════════════════════════════════════════════════════════
// GrowSense Food Reference Data v2.1
// 76 presets: 20 global staples + 50 international regional foods
//             + 6 deli / processed meats
//
// Fields added in v2:
//   region   — 'global' | 'cn' | 'kr' | 'ae' | 'th' | 'vn' | 'us' | 'eu'
//   category — protein type for optional filter UI
//              'chicken' | 'beef' | 'pork' | 'fish' | 'seafood'
//              | 'egg' | 'dairy' | 'plant' | 'composite' | 'deli'
//
// v2.1: optional per100g.sodium_mg — present on processed/deli meats.
// The app shows a "Salty" flag when a food is ≥500 mg sodium /100g so
// parents see the trade-off at the moment they log. Absent (undefined)
// on whole foods, which are naturally low-sodium.
//
// All values per-100g cooked/as-eaten basis (USDA FoodData Central
// or noted national database). Where a nutrient is genuinely absent
// from the source checked it is null — never guessed.
// Sodium notes appended to source string where a single tap delivers
// a meaningful fraction of a child's daily sodium limit.
//
// Serving size convention (v2 calibration):
//   Dense proteins (meat, fish, firm tofu, cheese): 28–50 g
//   Liquid / composite foods (soups, congee, mac&cheese): 100–120 g
//   Ultra-light toppings (pork floss, seaweed): 5–10 g
// ══════════════════════════════════════════════════════════════════

const FOOD_REFERENCE_DATA = [

  // ════════════════════════════════════════════
  // GLOBAL STAPLES (20) — shown as default set
  // ════════════════════════════════════════════

  {
    id: 'egg',
    name: 'Egg',
    emoji: '🥚',
    region: 'global', category: 'egg',
    prepNote: 'hard-boiled',
    portionVisual: '1 whole egg',
    per100g: { protein_g: 12.60, zinc_mg: 1.06, calcium_mg: 50.0 },
    servingGrams: 50,
    source: 'USDA FDC 173424 — Egg, whole, cooked, hard-boiled'
  },
  {
    id: 'milk',
    name: 'Milk',
    emoji: '🥛',
    region: 'global', category: 'dairy',
    prepNote: 'whole milk, 3.25% fat',
    portionVisual: '~1/3 cup (small glass)',
    per100g: { protein_g: 3.16, zinc_mg: 0.37, calcium_mg: 112.99 },
    servingGrams: 100,
    source: 'USDA FDC 171265 — Milk, whole, 3.25% milkfat, with added vitamin D'
  },
  {
    id: 'cheddar',
    name: 'Cheddar cheese',
    emoji: '🧀',
    region: 'global', category: 'dairy',
    prepNote: '1 slice',
    portionVisual: '~3 dice stacked',
    per100g: { protein_g: 23.70, zinc_mg: 3.10, calcium_mg: 721.0 },
    servingGrams: 28,
    source: 'USDA FDC 173414 — Cheese, cheddar'
  },
  {
    id: 'chicken_breast',
    name: 'Chicken breast',
    emoji: '🍗',
    region: 'global', category: 'chicken',
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
    region: 'global', category: 'fish',
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
    region: 'global', category: 'seafood',
    prepNote: 'cooked',
    portionVisual: '1 medium shrimp (tap ~3× for a typical 3-shrimp portion)',
    per100g: { protein_g: 23.98, zinc_mg: 1.64, calcium_mg: 64.0 },
    servingGrams: 28,
    source: 'USDA FDC 175180 — Crustaceans, shrimp, cooked'
  },
  {
    id: 'beef_steak',
    name: 'Beef steak',
    emoji: '🥩',
    region: 'global', category: 'beef',
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
    region: 'global', category: 'dairy',
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
    region: 'global', category: 'chicken',
    prepNote: 'generic, frozen, cooked (brand-specific values vary — rough estimate only)',
    portionVisual: '~2 nuggets',
    per100g: { protein_g: 14.0, zinc_mg: null, calcium_mg: null },
    servingGrams: 50,
    source: 'Generic estimate from USDA-category frozen chicken nugget products — not tied to a single FDC ID. Replace with product label values if known.'
  },
  {
    id: 'peanut_butter',
    name: 'Peanut butter',
    emoji: '🥜',
    region: 'global', category: 'plant',
    prepNote: 'smooth',
    portionVisual: '~2 tbsp',
    per100g: { protein_g: 21.88, zinc_mg: 2.66, calcium_mg: 54.06 },
    servingGrams: 32,
    source: "USDA FDC 174294 — Peanut Butter, smooth"
  },
  {
    id: 'tofu',
    name: 'Tofu',
    emoji: '🧊',
    region: 'global', category: 'plant',
    prepNote: 'extra firm, prepared with nigari',
    portionVisual: '~1/5 block',
    per100g: { protein_g: 10.00, zinc_mg: 1.07, calcium_mg: 281.98 },
    servingGrams: 91,
    source: 'USDA FDC 174290 — Tofu, extra firm, prepared with nigari'
  },
  {
    id: 'pork_loin',
    name: 'Pork loin',
    emoji: '🥩',
    region: 'global', category: 'pork',
    prepNote: 'lean, cooked, roasted',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 28.62, zinc_mg: 2.5, calcium_mg: 18.0 },
    servingGrams: 30,
    source: 'USDA FDC 168233 — Pork, fresh, loin, whole, separable lean only, cooked, roasted'
  },
  {
    id: 'bacon',
    name: 'Bacon',
    emoji: '🥓',
    region: 'global', category: 'pork',
    prepNote: 'cooked, pan-fried',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 33.89, zinc_mg: 3.06, calcium_mg: 11.11, sodium_mg: 1717.0 },
    servingGrams: 28,
    source: 'USDA FDC 168322 — Pork, cured, bacon, pre-sliced, cooked, pan-fried. NOTE: high sodium — one 28g tap provides ~9% of a child\'s daily recommended sodium intake.'
  },

  // ════════════════════════════════════════════
  // DELI & PROCESSED MEATS (6)
  // Convenient, real foods kids eat — but salty and processed, so each
  // carries a sodium_mg value that drives the "Salty" flag. Portions
  // reflect pieces as sold in the supermarket (e.g. CP Pork Bologna
  // 150 g ≈ 8 pieces). Nutrients: USDA. Piece sizes: real products.
  // ════════════════════════════════════════════
  {
    id: 'deli_ham',
    name: 'Ham (deli)',
    emoji: '🍖',
    region: 'global', category: 'deli',
    prepNote: 'sliced, regular ~11% fat',
    portionVisual: '1 sandwich slice',
    per100g: { protein_g: 16.60, zinc_mg: 1.90, calcium_mg: 6.0, sodium_mg: 1203.0 },
    servingGrams: 28,
    source: 'USDA FDC 173864 — Ham, sliced, regular (approximately 11% fat). NOTE: processed/high sodium — one 28 g slice ≈ 337 mg sodium (~22% of a young child\'s daily limit).'
  },
  {
    id: 'deli_turkey',
    name: 'Turkey breast (deli)',
    emoji: '🦃',
    region: 'global', category: 'deli',
    prepNote: 'sliced, low-salt deli',
    portionVisual: '1 sandwich slice',
    per100g: { protein_g: 13.70, zinc_mg: 1.10, calcium_mg: 5.0, sodium_mg: 772.0 },
    servingGrams: 28,
    source: 'USDA FDC 174572 — Turkey breast, low salt, prepackaged or deli, luncheon meat. Leaner and lower-sodium than most cold cuts, but still salty.'
  },
  {
    id: 'bologna',
    name: 'Bologna (pork)',
    emoji: '🥪',
    region: 'global', category: 'deli',
    prepNote: 'e.g. CP Pork Bologna',
    portionVisual: '1 piece (CP 150 g pack ≈ 8 pieces)',
    per100g: { protein_g: 15.30, zinc_mg: 2.00, calcium_mg: 11.0, sodium_mg: 907.0 },
    servingGrams: 19,
    source: 'USDA SR — Bologna, pork (NDB 07064). Portion from CP Pork Bologna 150 g ≈ 8 pieces (~19 g each). NOTE: processed/high sodium.'
  },
  {
    id: 'salami',
    name: 'Salami (dry)',
    emoji: '🥩',
    region: 'global', category: 'deli',
    prepNote: 'dry/hard, thin slices',
    portionVisual: '3 very thin slices',
    per100g: { protein_g: 22.60, zinc_mg: 4.20, calcium_mg: 13.0, sodium_mg: 2261.0 },
    servingGrams: 10,
    source: 'USDA FDC 174603 — Salami, dry or hard, pork. NOTE: very high sodium — thin slices only; 10 g ≈ 226 mg sodium (~15% of a young child\'s daily limit).'
  },
  {
    id: 'hot_dog',
    name: 'Hot dog / frankfurter',
    emoji: '🌭',
    region: 'global', category: 'deli',
    prepNote: 'beef frankfurter',
    portionVisual: '1 whole hot dog',
    per100g: { protein_g: 11.70, zinc_mg: 2.10, calcium_mg: 13.0, sodium_mg: 810.0 },
    servingGrams: 45,
    source: 'USDA FDC 171357 — Frankfurter, beef. NOTE: processed/high sodium — one frank ≈ 365 mg sodium (~24% of a young child\'s daily limit).'
  },
  {
    id: 'vienna_sausage',
    name: 'Vienna sausage',
    emoji: '🥫',
    region: 'global', category: 'deli',
    prepNote: 'canned',
    portionVisual: '1 piece',
    per100g: { protein_g: 10.50, zinc_mg: 1.60, calcium_mg: 10.0, sodium_mg: 879.0 },
    servingGrams: 16,
    source: 'USDA FDC 172942 — Sausage, Vienna, canned, chicken, beef, pork. NOTE: processed/high sodium.'
  },
  {
    id: 'raw_salmon',
    name: 'Salmon (raw)',
    emoji: '🍣',
    region: 'global', category: 'fish',
    prepNote: 'raw, wild Atlantic — sashimi / sushi use',
    portionVisual: 'matchbox-sized (tap ~3× for a deck-of-cards portion)',
    per100g: { protein_g: 19.88, zinc_mg: 0.64, calcium_mg: 12.00 },
    servingGrams: 30,
    source: 'USDA FDC 173686 — Fish, salmon, Atlantic, wild, raw'
  },
  {
    id: 'squid',
    name: 'Squid',
    emoji: '🦑',
    region: 'global', category: 'seafood',
    prepNote: 'steamed or boiled',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 31.43, zinc_mg: 3.07, calcium_mg: 64.64 },
    servingGrams: 28,
    source: 'USDA FNNDS 782749 — Squid, steamed or boiled'
  },
  {
    id: 'crab',
    name: 'Crab',
    emoji: '🦀',
    region: 'global', category: 'seafood',
    prepNote: 'Dungeness, cooked',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 22.35, zinc_mg: 5.41, calcium_mg: 59.06 },
    servingGrams: 30,
    source: 'USDA FDC 172007 — Crustaceans, crab, dungeness, cooked, moist heat'
  },
  {
    id: 'tuna',
    name: 'Tuna',
    emoji: '🐟',
    region: 'global', category: 'fish',
    prepNote: 'yellowfin, cooked',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 29.18, zinc_mg: 0.45, calcium_mg: 4.00 },
    servingGrams: 30,
    source: 'USDA FDC 172006 — Fish, tuna, yellowfin, fresh, cooked, dry heat'
  },
  {
    id: 'tilapia',
    name: 'Tilapia (white fish)',
    emoji: '🐠',
    region: 'global', category: 'fish',
    prepNote: 'cooked',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 26.18, zinc_mg: 0.41, calcium_mg: 14.00 },
    servingGrams: 30,
    source: 'USDA FDC 175177 — Fish, tilapia, cooked, dry heat'
  },
  {
    id: 'duck',
    name: 'Duck',
    emoji: '🦆',
    region: 'global', category: 'chicken',
    prepNote: 'roasted, meat and skin',
    portionVisual: 'matchbox-sized (tap ~3× for a full deck-of-cards portion)',
    per100g: { protein_g: 23.50, zinc_mg: 2.57, calcium_mg: 12.00 },
    servingGrams: 30,
    source: 'USDA FDC 172411 — Duck, domesticated, meat only, cooked, roasted'
  },
  {
    id: 'miso',
    name: 'Miso',
    emoji: '🍲',
    region: 'global', category: 'plant',
    prepNote: 'soybean paste — condiment, not a protein portion',
    portionVisual: '~1 tbsp (typical soup serving)',
    per100g: { protein_g: 12.94, zinc_mg: 2.59, calcium_mg: 57.06 },
    servingGrams: 17,
    source: 'USDA FDC 172442 — Miso. NOTE: very high sodium — a single 1-tbsp tap provides ~28% of a child\'s daily recommended sodium intake.'
  },

  // ════════════════════════════════════════════
  // 🇨🇳 CHINA (10)
  // ════════════════════════════════════════════

  {
    id: 'cn_steamed_egg',
    name: 'Steamed Egg Custard',
    emoji: '🥚',
    region: 'cn', category: 'egg',
    prepNote: 'Chinese style, savory, smooth texture',
    portionVisual: '~3 tablespoons (small child starter portion; multiply for a full bowl)',
    per100g: { protein_g: 5.10, zinc_mg: 0.45, calcium_mg: 22.0 },
    servingGrams: 50,
    source: 'USDA FNDDS 21121110 — Egg, whole, cooked, steamed (diluted with water/broth)'
  },
  {
    id: 'cn_pork_dumplings',
    name: 'Pork Dumplings (Jiaozi)',
    emoji: '🥟',
    region: 'cn', category: 'pork',
    prepNote: 'boiled, pork and chive filling',
    portionVisual: '2 small dumplings (tap to add more)',
    per100g: { protein_g: 9.30, zinc_mg: 1.12, calcium_mg: 18.0 },
    servingGrams: 40,
    source: 'USDA FDC 1104381 — Dumpling, with meat and vegetable filling, boiled'
  },
  {
    id: 'cn_tomato_egg',
    name: 'Stir-Fried Tomato & Egg',
    emoji: '🍳',
    region: 'cn', category: 'egg',
    prepNote: 'savory-sweet stir fry',
    portionVisual: '~2 tablespoons (tap to scale up)',
    per100g: { protein_g: 4.50, zinc_mg: 0.40, calcium_mg: 19.0 },
    servingGrams: 45,
    source: 'USDA FNDDS 27246100 — Egg and tomato stir-fry'
  },
  {
    id: 'cn_lions_head',
    name: "Lion's Head Meatball",
    emoji: '🧆',
    region: 'cn', category: 'pork',
    prepNote: 'large pork meatball, stewed and tender',
    portionVisual: '~1/3 of a large meatball (tap 3× for one full meatball)',
    per100g: { protein_g: 15.20, zinc_mg: 2.10, calcium_mg: 14.0 },
    servingGrams: 40,
    source: 'USDA FDC 174034 — Pork, ground, lean, cooked, braised (with bread soaker / tofu dilution reducing per-100g protein)'
  },
  {
    id: 'cn_char_siu',
    name: 'Char Siu (BBQ Pork)',
    emoji: '🍖',
    region: 'cn', category: 'pork',
    prepNote: 'sweet marinated roasted pork',
    portionVisual: '2–3 thin slices (matchbox size; tap 3× for a teenager portion)',
    per100g: { protein_g: 24.50, zinc_mg: 2.31, calcium_mg: 12.0 },
    servingGrams: 35,
    source: 'USDA FDC 167905 — Pork, shoulder, cooked, roasted (Char Siu marinade variation)'
  },
  {
    id: 'cn_braised_tofu',
    name: 'Braised Tofu Cubes',
    emoji: '🧊',
    region: 'cn', category: 'plant',
    prepNote: 'soybean curd stewed in mild brown sauce',
    portionVisual: '~2–3 small cubes (tap to multiply)',
    per100g: { protein_g: 8.50, zinc_mg: 0.85, calcium_mg: 145.0 },
    servingGrams: 40,
    source: 'USDA FDC 172447 — Tofu, prepared with calcium sulfate, braised'
  },
  {
    id: 'cn_chicken_congee',
    name: 'Chicken Congee',
    emoji: '🥣',
    region: 'cn', category: 'composite',
    prepNote: 'savory rice porridge with shredded chicken',
    portionVisual: '1/3 small cup bowl (liquid base; tap 3× for a full standard bowl)',
    per100g: { protein_g: 3.80, zinc_mg: 0.35, calcium_mg: 8.0 },
    servingGrams: 100,
    source: 'Composite estimate — cooked rice porridge with ~8% shredded chicken breast. No single USDA FDC record; values are calculated from component proportions.'
  },
  {
    id: 'cn_beef_broccoli',
    name: 'Beef with Broccoli',
    emoji: '🥦',
    region: 'cn', category: 'beef',
    prepNote: 'mild stir-fry, tenderized beef slices',
    portionVisual: '1–2 slices of beef + 1 floret (tap to add)',
    per100g: { protein_g: 11.40, zinc_mg: 2.80, calcium_mg: 28.0 },
    servingGrams: 45,
    source: 'USDA FNDDS 27116130 — Beef and broccoli stir-fry'
  },
  {
    id: 'cn_steamed_fish',
    name: 'Steamed Fish Fillet',
    emoji: '🐟',
    region: 'cn', category: 'fish',
    prepNote: 'white fish seasoned with mild soy and ginger',
    portionVisual: '1 small matchbox-sized chunk (tap 3× for a large fillet portion)',
    per100g: { protein_g: 22.50, zinc_mg: 0.52, calcium_mg: 15.0 },
    servingGrams: 35,
    source: 'USDA FDC 175177 — Fish, tilapia/perch, cooked, steamed'
  },
  {
    id: 'cn_shrimp_wonton',
    name: 'Shrimp Wonton',
    emoji: '🥟',
    region: 'cn', category: 'seafood',
    prepNote: 'boiled, pure shrimp filling wrapped in thin pastry',
    portionVisual: '2 small wontons (tap to add)',
    per100g: { protein_g: 12.10, zinc_mg: 0.95, calcium_mg: 32.0 },
    servingGrams: 30,
    source: 'USDA FDC 175180 — Crustaceans, shrimp, boiled; calcium estimated from shrimp filling + wheat wrapper combination'
  },

  // ════════════════════════════════════════════
  // 🇰🇷 SOUTH KOREA (10)
  // ════════════════════════════════════════════

  {
    id: 'kr_beef_bulgogi',
    name: 'Beef Bulgogi',
    emoji: '🥩',
    region: 'kr', category: 'beef',
    prepNote: 'sweet marinated thinly sliced beef, grilled',
    portionVisual: '1 heaped tablespoon (matchbox size; tap 3× for a full lunch plate)',
    per100g: { protein_g: 22.80, zinc_mg: 4.85, calcium_mg: 12.0 },
    servingGrams: 35,
    source: 'USDA FNDDS 27116400 — Beef bulgogi, cooked'
  },
  {
    id: 'kr_rolled_omelette',
    name: 'Rolled Omelette (Gyeran-mari)',
    emoji: '🍳',
    region: 'kr', category: 'egg',
    prepNote: 'layered pan-fried egg roll — classic banchan',
    portionVisual: '1–2 medium cut slices (classic side-dish size)',
    per100g: { protein_g: 11.20, zinc_mg: 1.01, calcium_mg: 48.0 },
    servingGrams: 35,
    source: 'USDA FDC 173424 — Egg, whole, cooked, pan-fried (rolled variation)'
  },
  {
    id: 'kr_fried_chicken',
    name: 'Korean Fried Chicken',
    emoji: '🍗',
    region: 'kr', category: 'chicken',
    prepNote: 'boneless crunchy chicken glazed in mild soy sauce',
    portionVisual: '1 medium boneless chunk (tap to scale up)',
    per100g: { protein_g: 18.50, zinc_mg: 0.78, calcium_mg: 14.0 },
    servingGrams: 35,
    source: 'USDA FDC 21229 — Fast foods, chicken, breaded and fried, boneless pieces'
  },
  {
    id: 'kr_tteok_galbi',
    name: 'Tteok-galbi',
    emoji: '🧆',
    region: 'kr', category: 'beef',
    prepNote: 'sweet minced beef and pork patties, grilled',
    portionVisual: '1 small mini patty (tap 2–3× for older kids)',
    per100g: { protein_g: 18.90, zinc_mg: 3.90, calcium_mg: 16.0 },
    servingGrams: 40,
    source: 'USDA FDC 174034 / 174054 — Minced beef and pork blend, seasoned, grilled'
  },
  {
    id: 'kr_fish_cakes',
    name: 'Korean Fish Cakes (Eomuk)',
    emoji: '🍢',
    region: 'kr', category: 'fish',
    prepNote: 'stir-fried or skewered fish paste sheets',
    portionVisual: '1/2 skewer or small handful of cut strips',
    per100g: { protein_g: 12.30, zinc_mg: 0.65, calcium_mg: 90.0 },
    servingGrams: 30,
    source: 'Generic industry standard for Asian fried fish paste cake (surimi base) — no single FDC ID. Values approximate; use product label if available.'
  },
  {
    id: 'kr_gim',
    name: 'Roasted Seaweed (Gim)',
    emoji: '🌿',
    region: 'kr', category: 'plant',
    prepNote: 'seasoned with sesame oil and salt — ultra-light topping/snack',
    portionVisual: '1 mini packet (~8 tiny sheets)',
    per100g: { protein_g: 28.10, zinc_mg: 2.10, calcium_mg: 320.0 },
    servingGrams: 5,
    source: 'USDA FDC 169429 — Seaweed, laver, roasted. NOTE: very high sodium per weight — 1 mini packet (~5g) provides ~170mg sodium (~7% of a child\'s daily limit).'
  },
  {
    id: 'kr_soft_tofu',
    name: 'Soft Tofu (Soon-dubu)',
    emoji: '🥣',
    region: 'kr', category: 'plant',
    prepNote: 'silken tofu cooked in mild broth',
    portionVisual: '~1/4 cup scooped (tap to multiply)',
    per100g: { protein_g: 5.10, zinc_mg: 0.51, calcium_mg: 85.0 },
    servingGrams: 50,
    source: 'USDA FDC 172446 — Tofu, silken'
  },
  {
    id: 'kr_grilled_mackerel',
    name: 'Grilled Mackerel (Godeungeo)',
    emoji: '🐟',
    region: 'kr', category: 'fish',
    prepNote: 'salted and grilled crisp',
    portionVisual: '1 small side fillet fragment (matchbox size)',
    per100g: { protein_g: 23.80, zinc_mg: 0.90, calcium_mg: 15.0 },
    servingGrams: 35,
    source: 'USDA FDC 173663 — Fish, mackerel, Atlantic, cooked, dry heat'
  },
  {
    id: 'kr_donkasu',
    name: 'Pork Cutlet (Donkasu)',
    emoji: '🥩',
    region: 'kr', category: 'pork',
    prepNote: 'breaded crisp pork loin cutlet',
    portionVisual: '2 small cut strips (tap 3× for a full cutlet platter)',
    per100g: { protein_g: 19.40, zinc_mg: 1.80, calcium_mg: 11.0 },
    servingGrams: 40,
    source: 'USDA FNDDS 24100010 — Pork cutlet, breaded, fried'
  },
  {
    id: 'kr_miyeok_guk',
    name: 'Beef Seaweed Soup (Miyeok-guk)',
    emoji: '🍲',
    region: 'kr', category: 'composite',
    prepNote: 'traditional soup with tender beef and seaweed',
    portionVisual: '1/3 small soup bowl (liquid base; tap 3× for a full large bowl)',
    per100g: { protein_g: 4.20, zinc_mg: 0.85, calcium_mg: 45.0 },
    servingGrams: 100,
    source: 'USDA FNDDS 27116410 — Korean style beef and seaweed soup'
  },

  // ════════════════════════════════════════════
  // 🇦🇪 UAE / MIDDLE EAST (10)
  // ════════════════════════════════════════════

  {
    id: 'ae_chicken_shawarma',
    name: 'Chicken Shawarma',
    emoji: '🌯',
    region: 'ae', category: 'chicken',
    prepNote: 'shaved spit-grilled chicken meat only (no bread)',
    portionVisual: '1 small handful of meat shavings (matchbox size)',
    per100g: { protein_g: 26.50, zinc_mg: 1.10, calcium_mg: 12.0 },
    servingGrams: 35,
    source: 'USDA FNDDS 24123300 — Chicken rotisserie/spit meat, skinless, cooked'
  },
  {
    id: 'ae_shish_tawook',
    name: 'Shish Tawook',
    emoji: '🍢',
    region: 'ae', category: 'chicken',
    prepNote: 'yogurt-marinated grilled chicken cubes',
    portionVisual: '2 chicken chunks (tap 2–3× for a full long skewer)',
    per100g: { protein_g: 29.10, zinc_mg: 0.95, calcium_mg: 18.0 },
    servingGrams: 40,
    source: 'USDA FDC 171140 — Chicken breast, marinated with yogurt, grilled'
  },
  {
    id: 'ae_lentil_soup',
    name: 'Lentil Soup (Adas)',
    emoji: '🥣',
    region: 'ae', category: 'plant',
    prepNote: 'smooth puréed yellow lentils — Ramadan staple',
    portionVisual: '1/2 small deep bowl (liquid base; tap 2–3× for a standard soup plate)',
    per100g: { protein_g: 4.80, zinc_mg: 0.61, calcium_mg: 14.0 },
    servingGrams: 100,
    source: 'USDA FDC 172421 — Lentils, mature seeds, cooked, boiled (soup dilution)'
  },
  {
    id: 'ae_halloumi',
    name: 'Grilled Halloumi Cheese',
    emoji: '🧀',
    region: 'ae', category: 'dairy',
    prepNote: 'pan-seared semi-hard cheese',
    portionVisual: '1 thin rectangular slice (tap to add multiple pieces)',
    per100g: { protein_g: 22.00, zinc_mg: 3.30, calcium_mg: 700.0 },
    servingGrams: 30,
    source: 'UK McCance and Widdowson / USDA Branded Food data for Halloumi. NOTE: very high sodium — one 30g slice provides ~360mg sodium (~15% of a child\'s daily limit).'
  },
  {
    id: 'ae_kofta',
    name: 'Kofta Kebab',
    emoji: '🍢',
    region: 'ae', category: 'beef',
    prepNote: 'minced beef and lamb grilled skewer',
    portionVisual: '1/2 of a standard long skewer log',
    per100g: { protein_g: 24.10, zinc_mg: 5.10, calcium_mg: 18.0 },
    servingGrams: 35,
    source: 'USDA FDC 174054 — Beef and lamb ground blend, cooked, grilled'
  },
  {
    id: 'ae_machboos_chicken',
    name: 'Chicken Machboos (meat only)',
    emoji: '🍗',
    region: 'ae', category: 'chicken',
    prepNote: 'spiced chicken pulled from traditional Gulf rice dish',
    portionVisual: 'small shredded pile (matchbox size; tap to add more)',
    per100g: { protein_g: 27.20, zinc_mg: 1.20, calcium_mg: 14.0 },
    servingGrams: 35,
    source: 'USDA FDC 171140 — Chicken meat, spiced, moist-heat cooked'
  },
  {
    id: 'ae_falafel',
    name: 'Falafel',
    emoji: '🧆',
    region: 'ae', category: 'plant',
    prepNote: 'fried chickpea/fava bean croquettes',
    portionVisual: '2 small round balls (tap to multiply)',
    per100g: { protein_g: 13.30, zinc_mg: 1.50, calcium_mg: 54.0 },
    servingGrams: 35,
    source: 'USDA FDC 174242 — Falafel, commercial'
  },
  {
    id: 'ae_labneh',
    name: 'Labneh',
    emoji: '🥣',
    region: 'ae', category: 'dairy',
    prepNote: 'thick strained probiotic yogurt dip',
    portionVisual: '~1.5 thick dollops / tablespoons',
    per100g: { protein_g: 6.20, zinc_mg: 0.80, calcium_mg: 210.0 },
    servingGrams: 30,
    source: 'USDA Branded Food database entries for Strained Labneh Cream'
  },
  {
    id: 'ae_hummus',
    name: 'Hummus',
    emoji: '🍯',
    region: 'ae', category: 'plant',
    prepNote: 'creamy chickpea and tahini spread',
    portionVisual: '~1.5 tablespoons scooped',
    per100g: { protein_g: 7.90, zinc_mg: 1.80, calcium_mg: 38.0 },
    servingGrams: 30,
    source: 'USDA FDC 173757 — Hummus, commercial'
  },
  {
    id: 'ae_hammour',
    name: 'Baked Hammour / Sea Bream',
    emoji: '🐟',
    region: 'ae', category: 'fish',
    prepNote: 'local Gulf white fish fillet, baked mild',
    portionVisual: '1 small matchbox-sized piece (tap 3× for a teenager meal)',
    per100g: { protein_g: 21.40, zinc_mg: 0.48, calcium_mg: 24.0 },
    servingGrams: 35,
    source: 'USDA FDC 171965 — Fish, Grouper/Sea Bream, cooked, dry heat'
  },

  // ════════════════════════════════════════════
  // 🇹🇭 THAILAND (10)
  // ════════════════════════════════════════════

  {
    id: 'th_moo_ping',
    name: 'Moo Ping (Grilled Pork Skewer)',
    emoji: '🍢',
    region: 'th', category: 'pork',
    prepNote: 'sweet marinated tender pork — Thai street staple',
    portionVisual: '1 small skewer (meat section only; tap to add extra sticks)',
    per100g: { protein_g: 25.40, zinc_mg: 2.40, calcium_mg: 14.0 },
    servingGrams: 35,
    source: 'Thai Food Composition / USDA FDC 168233 — Pork loin/shoulder marinated, grilled'
  },
  {
    id: 'th_kai_jeow',
    name: 'Thai Omelette (Kai Jeow)',
    emoji: '🍳',
    region: 'th', category: 'egg',
    prepNote: 'fluffy, shallow oil-fried egg',
    portionVisual: '1/3 of a standard round omelette',
    per100g: { protein_g: 11.80, zinc_mg: 1.02, calcium_mg: 46.0 },
    servingGrams: 35,
    source: 'USDA FNDDS 21111000 — Eggs, fried'
  },
  {
    id: 'th_gai_tod',
    name: 'Thai Fried Chicken (Gai Tod)',
    emoji: '🍗',
    region: 'th', category: 'chicken',
    prepNote: 'savory crispy skin, boneless chicken meat',
    portionVisual: '1 small boneless strip (matchbox size)',
    per100g: { protein_g: 22.10, zinc_mg: 1.10, calcium_mg: 15.0 },
    servingGrams: 35,
    source: 'USDA FDC 5012 — Chicken, broilers or fryers, meat only, fried'
  },
  {
    id: 'th_pad_kra_prow',
    name: 'Minced Pork Kra Prow (mild)',
    emoji: '🍛',
    region: 'th', category: 'pork',
    prepNote: 'stir-fried minced pork with sweet basil, non-spicy version',
    portionVisual: '1.5 heaped tablespoons (tap to add)',
    per100g: { protein_g: 16.80, zinc_mg: 2.85, calcium_mg: 18.0 },
    servingGrams: 40,
    source: 'USDA FDC 174034 — Pork, ground, stir-fried with aromatics'
  },
  {
    id: 'th_khao_man_gai',
    name: 'Poached Chicken (Khao Man Gai)',
    emoji: '🐔',
    region: 'th', category: 'chicken',
    prepNote: 'skinless, ultra-tender poached chicken breast/thigh',
    portionVisual: '3 flat sliced strips (matchbox size; tap 3–4× for older kids)',
    per100g: { protein_g: 28.40, zinc_mg: 1.15, calcium_mg: 9.0 },
    servingGrams: 35,
    source: 'USDA FDC 171140 — Chicken, breast/thigh, skinless, cooked, boiled/poached'
  },
  {
    id: 'th_look_chin',
    name: 'Pork Meatball Skewers (Look Chin)',
    emoji: '🍡',
    region: 'th', category: 'pork',
    prepNote: 'steamed/grilled bouncy pork balls — Thai school canteen staple',
    portionVisual: '1 short skewer (~3 small round balls)',
    per100g: { protein_g: 14.10, zinc_mg: 1.80, calcium_mg: 32.0 },
    servingGrams: 35,
    source: 'Thai Food Composition Database / Commercial surimi-pork emulsified meatballs — no single FDC ID; values approximate.'
  },
  {
    id: 'th_kun_chiang',
    name: 'Sweet Chinese Sausage (Kun Chiang)',
    emoji: '🌭',
    region: 'th', category: 'pork',
    prepNote: 'pan-fried sweet pork sausage slices — concentrated flavor',
    portionVisual: '~4 thin diagonal coin slices (small serving)',
    per100g: { protein_g: 18.00, zinc_mg: 1.90, calcium_mg: 10.0 },
    servingGrams: 20,
    source: 'USDA Branded Database — Chinese Style Sweet Sausage. NOTE: high sodium and fat — treat as a topping not a primary protein source.'
  },
  {
    id: 'th_gaeng_jued',
    name: 'Clear Soup (Gaeng Jued)',
    emoji: '🍲',
    region: 'th', category: 'composite',
    prepNote: 'mild clear broth with minced pork and tofu — classic Thai kid food',
    portionVisual: '1/3 small cup bowl (liquid soup base; tap to scale up)',
    per100g: { protein_g: 5.50, zinc_mg: 0.60, calcium_mg: 45.0 },
    servingGrams: 100,
    source: 'Composite estimate — 50% clear broth, 25% silken tofu, 25% minced pork; values calculated from component proportions.'
  },
  {
    id: 'th_shrimp_garlic',
    name: 'Garlic Shrimp (Kung Kratiam)',
    emoji: '🦐',
    region: 'th', category: 'seafood',
    prepNote: 'stir-fried shelled shrimp with garlic and sweet soy',
    portionVisual: '~3 small/medium shrimp (matchbox weight)',
    per100g: { protein_g: 23.98, zinc_mg: 1.64, calcium_mg: 40.0 },
    servingGrams: 30,
    source: 'USDA FDC 175180 — Crustaceans, shrimp, cooked'
  },
  {
    id: 'th_moo_yong',
    name: 'Pork Floss (Moo Yong)',
    emoji: '🥠',
    region: 'th', category: 'pork',
    prepNote: 'sweet crispy dehydrated shredded pork — rice/congee topping',
    portionVisual: '1 small loose pinch (cotton-candy texture; weighs very little)',
    per100g: { protein_g: 40.20, zinc_mg: 3.80, calcium_mg: 20.0 },
    servingGrams: 8,
    source: 'Asian Food Analytics — Dried shredded savory sweet pork floss. High protein per 100g due to dehydration concentration.'
  },

  // ════════════════════════════════════════════
  // 🇻🇳 VIETNAM (10)
  // ════════════════════════════════════════════

  {
    id: 'vn_thit_kho',
    name: 'Caramelized Pork & Egg (Thịt Kho)',
    emoji: '🍲',
    region: 'vn', category: 'pork',
    prepNote: 'tender pork stewed in coconut water — Vietnamese home staple',
    portionVisual: '1 chunk of tender lean pork, matchbox size (egg excluded)',
    per100g: { protein_g: 18.20, zinc_mg: 2.10, calcium_mg: 24.0 },
    servingGrams: 40,
    source: 'USDA FDC 168233 / 173424 blend — Pork shoulder and egg braised'
  },
  {
    id: 'vn_pho_beef',
    name: 'Phở Sliced Beef (meat only)',
    emoji: '🥩',
    region: 'vn', category: 'beef',
    prepNote: 'thin beef slices flash-boiled in broth — log broth separately',
    portionVisual: '~3 tender flat ribbons of meat (tap to add counts)',
    per100g: { protein_g: 28.10, zinc_mg: 5.40, calcium_mg: 10.0 },
    servingGrams: 35,
    source: 'USDA FDC 174054 — Beef, eye of round / flank slices, cooked in broth'
  },
  {
    id: 'vn_cha_lua',
    name: 'Vietnamese Pork Sausage (Chả Lụa)',
    emoji: '🥖',
    region: 'vn', category: 'pork',
    prepNote: 'steamed smooth pork loaf wrapped in banana leaf — baguette staple',
    portionVisual: '1 thin circular disc slice cut in half',
    per100g: { protein_g: 14.50, zinc_mg: 1.60, calcium_mg: 25.0 },
    servingGrams: 30,
    source: 'Vietnam National Food Composition — Giò Lụa / Chả Lụa (steamed pork). NOTE: high sodium ~700mg/100g; 30g tap provides ~210mg sodium.'
  },
  {
    id: 'vn_fish_sauce_wings',
    name: 'Fish Sauce Fried Wings',
    emoji: '🍗',
    region: 'vn', category: 'chicken',
    prepNote: 'crispy chicken wings in caramelized sweet glaze',
    portionVisual: '1 small wing mid-joint section (meat/skin only)',
    per100g: { protein_g: 24.20, zinc_mg: 1.45, calcium_mg: 16.0 },
    servingGrams: 35,
    source: 'USDA FDC 5106 — Chicken, wings, meat and skin, fried with sticky glaze sauce'
  },
  {
    id: 'vn_cha_trung',
    name: 'Steamed Egg Meatloaf (Chả Trứng)',
    emoji: '🥮',
    region: 'vn', category: 'egg',
    prepNote: 'soft steamed pork, egg and glass noodle cake',
    portionVisual: '1 small narrow wedge slice (tap to double)',
    per100g: { protein_g: 13.80, zinc_mg: 1.50, calcium_mg: 35.0 },
    servingGrams: 45,
    source: 'USDA FNDDS 21415100 — Egg and pork combined loaf / savory custard casserole'
  },
  {
    id: 'vn_tom_rim',
    name: 'Caramelized Shrimp (Tôm Rim)',
    emoji: '🦐',
    region: 'vn', category: 'seafood',
    prepNote: 'shelled shrimp cooked down sweet-savory in sugar and fish sauce',
    portionVisual: '~4 small shrimp',
    per100g: { protein_g: 24.50, zinc_mg: 1.70, calcium_mg: 40.0 },
    servingGrams: 28,
    source: 'USDA FDC 175180 — Crustaceans, shrimp; calcium estimated for pan-reduced preparation'
  },
  {
    id: 'vn_xiu_mai',
    name: 'Vietnamese Tomato Meatballs (Xíu Mại)',
    emoji: '🥫',
    region: 'vn', category: 'pork',
    prepNote: 'ultra-soft pork meatballs simmered in sweet tomato sauce',
    portionVisual: '1 small round meatball (tap 3× for a school lunch size)',
    per100g: { protein_g: 14.20, zinc_mg: 2.10, calcium_mg: 18.0 },
    servingGrams: 35,
    source: 'USDA FNDDS 27116110 — Meatballs cooked in tomato-based sauce'
  },
  {
    id: 'vn_trung_cut',
    name: 'Fried Quail Eggs (Trứng Cút)',
    emoji: '🥚',
    region: 'vn', category: 'egg',
    prepNote: 'pan-fried whole quail eggs, lightly salted — ubiquitous Vietnamese street snack',
    portionVisual: '3 small whole quail eggs (tap to add more)',
    per100g: { protein_g: 13.05, zinc_mg: 1.47, calcium_mg: 64.0 },
    servingGrams: 30,
    source: 'USDA FDC 172185 — Quail eggs, whole, cooked (pan-fried; moisture comparable to canned drained)'
  },
  {
    id: 'vn_fried_tofu',
    name: 'Fried Tofu with Tomato Sauce',
    emoji: '🧊',
    region: 'vn', category: 'plant',
    prepNote: 'puffed fried tofu cubes simmered soft with green onions and tomato',
    portionVisual: '~2 small cubes with sauce coating',
    per100g: { protein_g: 9.80, zinc_mg: 0.98, calcium_mg: 180.0 },
    servingGrams: 45,
    source: 'USDA FDC 172447 — Tofu, fried cubes, simmered with sauce'
  },
  {
    id: 'vn_thit_luoc',
    name: 'Boiled Pork Belly (Thịt Luộc)',
    emoji: '🥓',
    region: 'vn', category: 'pork',
    prepNote: 'thin cleanly boiled tender pork slices — eaten with fish sauce dip',
    portionVisual: '2 thin ribbon slices (matchbox weight)',
    per100g: { protein_g: 21.10, zinc_mg: 1.95, calcium_mg: 12.0 },
    servingGrams: 35,
    source: 'USDA FDC 168238 — Pork, fresh, belly, cooked, water-boiled'
  },

  // ════════════════════════════════════════════
  // 🇺🇸 UNITED STATES (10)
  // ════════════════════════════════════════════

  {
    id: 'us_beef_burger',
    name: 'Beef Burger Patty',
    emoji: '🍔',
    region: 'us', category: 'beef',
    prepNote: 'grilled ground lean beef patty, meat only (no bun)',
    portionVisual: '1/2 of a standard junior burger patty (tap 2–3× for big kids)',
    per100g: { protein_g: 26.54, zinc_mg: 5.86, calcium_mg: 18.0 },
    servingGrams: 40,
    source: 'USDA FDC 174032 — Beef, ground, 80% lean / 20% fat, cooked, grilled patty'
  },
  {
    id: 'us_mac_cheese',
    name: 'Macaroni and Cheese',
    emoji: '🧀',
    region: 'us', category: 'composite',
    prepNote: 'baked or stovetop cheddar cheese pasta',
    portionVisual: '~1/4 cup small starter scoop (tap to add)',
    per100g: { protein_g: 6.70, zinc_mg: 0.85, calcium_mg: 122.0 },
    servingGrams: 60,
    source: 'USDA FNDDS 42202000 — Macaroni with cheese, home-prepared or standard school lunch'
  },
  {
    id: 'us_turkey_slices',
    name: 'Turkey Breast Slices',
    emoji: '🦃',
    region: 'us', category: 'chicken',
    prepNote: 'oven-roasted deli or carved skinless meat',
    portionVisual: '1.5 thin deli slices folded (matchbox size)',
    per100g: { protein_g: 24.70, zinc_mg: 1.41, calcium_mg: 14.0 },
    servingGrams: 30,
    source: 'USDA FDC 171161 — Turkey, breast, meat only, cooked, roasted'
  },
  {
    id: 'us_fish_sticks',
    name: 'Fish Sticks',
    emoji: '🐟',
    region: 'us', category: 'fish',
    prepNote: 'minced white fish, breaded and oven-baked',
    portionVisual: '1.5 fish sticks (tap to increase count)',
    per100g: { protein_g: 14.29, zinc_mg: 0.43, calcium_mg: 29.0 },
    servingGrams: 35,
    source: 'USDA FDC 174194 — Fish, fish sticks, frozen, prepared'
  },
  {
    id: 'us_pepperoni_pizza',
    name: 'Pepperoni Pizza',
    emoji: '🍕',
    region: 'us', category: 'composite',
    prepNote: 'thin crust, regular cheese and pepperoni slice',
    portionVisual: '1/2 of a medium-sized slice (tap 2–4× for school-age kids)',
    per100g: { protein_g: 11.40, zinc_mg: 1.34, calcium_mg: 194.0 },
    servingGrams: 45,
    source: 'USDA FNDDS 53500340 — Pizza with meat topping, thin crust, baked'
  },
  {
    id: 'us_string_cheese',
    name: 'String Cheese',
    emoji: '🧀',
    region: 'us', category: 'dairy',
    prepNote: 'low-moisture part-skim mozzarella stick — standard kid snack',
    portionVisual: '1 individual stick package (standard kid snack size)',
    per100g: { protein_g: 28.57, zinc_mg: 3.57, calcium_mg: 714.0 },
    servingGrams: 28,
    source: 'USDA FDC 1029 — Cheese, mozzarella, low-moisture, part-skim'
  },
  {
    id: 'us_pork_sausage',
    name: 'Pork Breakfast Sausage',
    emoji: '🌭',
    region: 'us', category: 'pork',
    prepNote: 'pan-fried country breakfast sausage link',
    portionVisual: '2 small mini links (tap to add counts)',
    per100g: { protein_g: 19.38, zinc_mg: 2.22, calcium_mg: 15.0 },
    servingGrams: 26,
    source: 'USDA FDC 168194 — Pork, sausage, link/patty, cooked, pan-fried. NOTE: high sodium — two links (~52g) provide ~540mg sodium (~22% of a child\'s daily limit).'
  },
  {
    id: 'us_hot_dog',
    name: 'Beef Hot Dog',
    emoji: '🌭',
    region: 'us', category: 'beef',
    prepNote: 'boiled or grilled beef frankfurter, no bun',
    portionVisual: '1 single standard link (classic toddler/kid baseline)',
    per100g: { protein_g: 11.60, zinc_mg: 2.15, calcium_mg: 13.0 },
    servingGrams: 45,
    source: 'USDA FDC 174221 — Frankfurters, beef. NOTE: high sodium — one 45g link provides ~270mg sodium (~11% of a child\'s daily limit).'
  },
  {
    id: 'us_tuna_salad',
    name: 'Canned Tuna Salad',
    emoji: '🐟',
    region: 'us', category: 'fish',
    prepNote: 'flaked light tuna mixed with mild mayo',
    portionVisual: '1 small packed tablespoon/scoop (matchbox weight)',
    per100g: { protein_g: 16.45, zinc_mg: 0.70, calcium_mg: 13.0 },
    servingGrams: 35,
    source: 'USDA FNDDS 27150050 — Tuna salad with mayonnaise'
  },
  {
    id: 'us_chicken_leg',
    name: 'Rotisserie Chicken Leg',
    emoji: '🍗',
    region: 'us', category: 'chicken',
    prepNote: 'cooked dark meat drumstick/thigh, shredded, skinless',
    portionVisual: 'small shredded bundle (matchbox size; tap to add)',
    per100g: { protein_g: 26.24, zinc_mg: 1.94, calcium_mg: 11.0 },
    servingGrams: 30,
    source: 'USDA FDC 171143 — Chicken, broilers or fryers, thigh/drumstick meat only, cooked, roasted'
  },

  // ════════════════════════════════════════════
  // 🇪🇺 EUROPE (10)
  // ════════════════════════════════════════════

  {
    id: 'eu_pork_schnitzel',
    name: 'Pork Schnitzel',
    emoji: '🥩',
    region: 'eu', category: 'pork',
    prepNote: 'thin tender pork loin, fine breading, pan-fried',
    portionVisual: '1/4 of a standard kids-menu sheet slice (matchbox size)',
    per100g: { protein_g: 20.10, zinc_mg: 1.70, calcium_mg: 12.0 },
    servingGrams: 35,
    source: 'EuroFIR / German BLS — Schweineschnitzel, paniert, gebraten'
  },
  {
    id: 'eu_bolognese_sauce',
    name: 'Bolognese Meat Sauce',
    emoji: '🍝',
    region: 'eu', category: 'beef',
    prepNote: 'simmered ground beef/pork in tomato vegetable base',
    portionVisual: '~1.5 heavy spoonfuls coating pasta (tap to increase)',
    per100g: { protein_g: 8.80, zinc_mg: 1.85, calcium_mg: 22.0 },
    servingGrams: 40,
    source: 'USDA FNDDS 27130000 — Meat sauce, tomato-based with minced beef'
  },
  {
    id: 'eu_fish_fingers',
    name: 'Fish Fingers (Cod)',
    emoji: '🐟',
    region: 'eu', category: 'fish',
    prepNote: 'Atlantic cod fillet centre, crisp fine breading',
    portionVisual: '1.5 standard fish fingers (tap to add)',
    per100g: { protein_g: 15.10, zinc_mg: 0.45, calcium_mg: 24.0 },
    servingGrams: 40,
    source: 'UK McCance and Widdowson — Cod fish fingers, baked'
  },
  {
    id: 'eu_swedish_meatballs',
    name: 'Swedish Meatballs (Köttbullar)',
    emoji: '🧆',
    region: 'eu', category: 'beef',
    prepNote: 'small minced pork/beef meatballs in cream gravy',
    portionVisual: '~2–3 tiny meatballs (tap 3× for a teenager plate)',
    per100g: { protein_g: 14.90, zinc_mg: 2.30, calcium_mg: 19.0 },
    servingGrams: 35,
    source: 'Swedish National Food Agency (Livsmedelsverket) — Köttbullar frysta stekt'
  },
  {
    id: 'eu_wiener_sausage',
    name: 'Wiener Sausage',
    emoji: '🌭',
    region: 'eu', category: 'pork',
    prepNote: 'mild lightly smoked parboiled pork sausage link',
    portionVisual: '1 single standard thin link',
    per100g: { protein_g: 12.20, zinc_mg: 2.10, calcium_mg: 11.0 },
    servingGrams: 40,
    source: 'German BLS / USDA FDC 174221 — Wiener Würstchen. NOTE: high sodium — one 40g link provides ~360mg sodium (~15% of a child\'s daily limit).'
  },
  {
    id: 'eu_boiled_ham',
    name: 'Boiled Ham (Prosciutto Cotto)',
    emoji: '🥓',
    region: 'eu', category: 'pork',
    prepNote: 'mild non-spicy cooked lean ham — lunchbox slice',
    portionVisual: '1 single square cold-cut sheet folded (matchbox weight)',
    per100g: { protein_g: 21.30, zinc_mg: 2.10, calcium_mg: 9.0 },
    servingGrams: 30,
    source: 'Anses CIQUAL — Jambon cuit supérieur'
  },
  {
    id: 'eu_gouda_cheese',
    name: 'Gouda / Edam Cheese',
    emoji: '🧀',
    region: 'eu', category: 'dairy',
    prepNote: 'mild semi-hard lunchbox slice',
    portionVisual: '1 standard rectangle cheese slice',
    per100g: { protein_g: 24.94, zinc_mg: 3.90, calcium_mg: 700.0 },
    servingGrams: 25,
    source: 'Dutch NEVO database / USDA FDC 1009 — Gouda cheese'
  },
  {
    id: 'eu_greek_yogurt',
    name: 'Greek Strained Yogurt',
    emoji: '🥣',
    region: 'eu', category: 'dairy',
    prepNote: 'plain thick strained high-protein yogurt — 3× protein of regular yogurt',
    portionVisual: '~1/4 cup container (tap to increase)',
    per100g: { protein_g: 9.00, zinc_mg: 0.60, calcium_mg: 110.0 },
    servingGrams: 50,
    source: 'USDA FDC 1293 — Yogurt, Greek, plain, whole milk'
  },
  {
    id: 'eu_baked_beans',
    name: 'Baked Beans in Tomato Sauce',
    emoji: '🥫',
    region: 'eu', category: 'plant',
    prepNote: 'stewed white haricot beans, mild sweet tomato reduction — UK school staple',
    portionVisual: '~1.5 heavy tablespoons (tap to add)',
    per100g: { protein_g: 5.50, zinc_mg: 0.75, calcium_mg: 43.0 },
    servingGrams: 45,
    source: 'UK McCance and Widdowson — Baked beans in tomato sauce (tinned)'
  },
  {
    id: 'eu_cordon_bleu',
    name: 'Chicken Cordon Bleu',
    emoji: '🍗',
    region: 'eu', category: 'chicken',
    prepNote: 'breaded chicken wrap with ham and melted cheese inside',
    portionVisual: '1/4 of a standard round cutlet (tap to scale up)',
    per100g: { protein_g: 17.80, zinc_mg: 1.15, calcium_mg: 95.0 },
    servingGrams: 45,
    source: 'Anses CIQUAL — Cordon bleu de volaille, cuit'
  }

];

// "Protein Boost" (+10g) is intentionally NOT a database entry —
// it is a flat manual quick-add for when a parent reads a protein
// number off any product label. Self-reported / not USDA-verified.

if (typeof module !== 'undefined') {
  module.exports = { FOOD_REFERENCE_DATA };
}
