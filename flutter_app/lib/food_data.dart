// ══════════════════════════════════════════════════════════════════
// Food reference data — loaded from assets/food_reference.json,
// which is generated from the PWA's food-reference-data.js by
// tool/convert_food_data.js. The JS file is the source of truth;
// regenerate the JSON when it changes.
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class FoodItem {
  final String id;
  final String name;
  final String emoji;
  final String region; // global | cn | kr | ae | th | vn | us | eu
  final String
  category; // chicken | beef | pork | fish | seafood | egg | dairy | plant | composite
  final String? prepNote;
  final String? portionVisual;
  final double proteinPer100g;
  final double? zincPer100g;
  final double? calciumPer100g;
  final double? sodiumPer100g;
  // v2.2 quiet data-collection layer — parsed and held but not shown in
  // any UI yet. Present only on foods whose value is verified from the
  // cited USDA record; null = not collected yet (never a guess).
  final double? ironPer100g;
  final double? vitaminDIuPer100g;
  final double servingGrams;
  final String source;

  FoodItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      emoji = j['emoji'] as String? ?? '🍽️',
      region = j['region'] as String? ?? 'global',
      category = j['category'] as String? ?? 'composite',
      prepNote = j['prepNote'] as String?,
      portionVisual = j['portionVisual'] as String?,
      proteinPer100g = ((j['per100g']?['protein_g']) as num?)?.toDouble() ?? 0,
      zincPer100g = ((j['per100g']?['zinc_mg']) as num?)?.toDouble(),
      calciumPer100g = ((j['per100g']?['calcium_mg']) as num?)?.toDouble(),
      sodiumPer100g = ((j['per100g']?['sodium_mg']) as num?)?.toDouble(),
      ironPer100g = ((j['per100g']?['iron_mg']) as num?)?.toDouble(),
      vitaminDIuPer100g = ((j['per100g']?['vitamin_d_iu']) as num?)?.toDouble(),
      servingGrams = (j['servingGrams'] as num?)?.toDouble() ?? 100,
      source = j['source'] as String? ?? '';

  double get proteinPerServing => proteinPer100g * servingGrams / 100;
  double? get zincPerServing =>
      zincPer100g == null ? null : zincPer100g! * servingGrams / 100;
  double? get calciumPerServing =>
      calciumPer100g == null ? null : calciumPer100g! * servingGrams / 100;

  /// A food is flagged "Salty" when it is a high-sodium food in its own
  /// right (≥500 mg/100g) — a property of the food, not the serving, so
  /// the flag is stable regardless of portion. Whole foods (egg, tofu,
  /// fresh meat) sit well under this; deli/processed meats clear it.
  bool get isHighSodium => (sodiumPer100g ?? 0) >= 500;
}

/// Same category order as the PWA's browse-modal tabs. `deli` groups
/// processed/cold-cut meats, which also carry the Salty flag.
const foodCategories = [
  'chicken',
  'beef',
  'pork',
  'fish',
  'seafood',
  'egg',
  'dairy',
  'plant',
  'composite',
  'deli',
];

List<FoodItem>? _cache;

Future<List<FoodItem>> loadFoodReference() async {
  if (_cache != null) return _cache!;
  final raw = await rootBundle.loadString('assets/food_reference.json');
  final list = jsonDecode(raw) as List;
  _cache = [for (final e in list) FoodItem.fromJson(e as Map<String, dynamic>)];
  return _cache!;
}
