// ══════════════════════════════════════════════════════════════════
// Activity library — Dart port of ACTIVITY_LIBRARY in app.js (the
// source of truth; keep in sync when it changes there). Tier weights
// rank OSTEOGENIC LOADING (bone strength), not added height — exercise
// builds stronger bone, not longer bone. Notes follow the honest voice
// of the GS-041 article "Can exercise make children taller?".
// ══════════════════════════════════════════════════════════════════

class Activity {
  final String id;
  final String tier; // high_impact | weight_bearing | cardio | flexibility | lifestyle
  final String category;
  final String emoji;
  final String displayName;
  final String unit; // 'min' | 'reps'
  final String presets; // 'standard_min' | 'small_min' | 'reps'
  final bool outdoor;
  final String? note;

  const Activity({
    required this.id,
    required this.tier,
    required this.category,
    required this.emoji,
    required this.displayName,
    this.unit = 'min',
    String? presets,
    this.outdoor = false,
    this.note,
  }) : presets = presets ?? (unit == 'reps' ? 'reps' : 'standard_min');
}

/// Same tier weights as ACTIVITY_TIER_CONFIG in app.js.
class ActivityTier {
  final String label;
  final String shortLabel;
  final double weight;
  const ActivityTier(this.label, this.shortLabel, this.weight);
}

const activityTierConfig = {
  'high_impact': ActivityTier('HIGH IMPACT', 'HIGH', 1.00),
  'weight_bearing': ActivityTier('WEIGHT-BEARING', 'MEDIUM', 0.65),
  'cardio': ActivityTier('CARDIO', 'CARDIO', 0.35),
  'flexibility': ActivityTier('FLEXIBILITY', 'FLEX', 0.15),
  'lifestyle': ActivityTier('LIFESTYLE', 'MOVE', 0.15),
};

// Duration presets per preset type — same values as app.js.
const durationPresetsMin = [5, 10, 15, 20, 30, 45, 60, 90];
const durationPresetsSmallMin = [1, 2, 3, 4, 5, 10, 15, 20];
const durationPresetsReps = [10, 20, 30, 40, 50, 60, 80, 100];

const activityLibrary = <Activity>[
  // ── TIER 1 — HIGH IMPACT ──────────────────────────────────────
  Activity(
      id: 'gymnastics', tier: 'high_impact', category: 'gymnastics',
      emoji: '🤸', displayName: 'Gymnastics',
      note: 'Highest osteogenic evidence — 10.4× body weight impacts per session (Daly et al. 1999)'),
  Activity(
      id: 'box_jumps', tier: 'high_impact', category: 'jumping',
      emoji: '📦', displayName: 'Box Jumps', unit: 'reps',
      note: 'One of the strongest bone-loading drills. A small 24-week trial in short-stature children saw faster short-term growth velocity — that reflects bone and velocity, not proven adult height (BMC Pediatrics 2025).'),
  Activity(
      id: 'vertical_jumps', tier: 'high_impact', category: 'jumping',
      emoji: '⬆️', displayName: 'Vertical Jumps', unit: 'reps'),
  Activity(
      id: 'jump_rope', tier: 'high_impact', category: 'jumping',
      emoji: '🪢', displayName: 'Jump Rope',
      note: 'Repeated moderate-impact loading — builds bone strength. Convenient, low-cost, and easy to do daily.'),
  Activity(
      id: 'basketball', tier: 'high_impact', category: 'sports',
      emoji: '🏀', displayName: 'Basketball',
      note: 'Highest BMD among all team sports. Multi-directional impact loading (PMID 38040837)'),
  Activity(
      id: 'volleyball', tier: 'high_impact', category: 'sports',
      emoji: '🏐', displayName: 'Volleyball',
      note: 'High-impact, repeated vertical jumps. BMD superior to swimmers and controls'),
  Activity(
      id: 'football', tier: 'high_impact', category: 'sports',
      emoji: '⚽', displayName: 'Football / Soccer',
      note: 'Running + impact loading. ~39% of adult bone mass acquired in 5 years around PHV'),
  Activity(
      id: 'taekwondo', tier: 'high_impact', category: 'martial_arts',
      emoji: '🥋', displayName: 'Taekwondo',
      note: 'Systematic review: significantly better bone outcomes vs non-sport (Barbeta et al.)'),
  Activity(
      id: 'muay_thai', tier: 'high_impact', category: 'martial_arts',
      emoji: '🥊', displayName: 'Muay Thai'),
  Activity(
      id: 'judo', tier: 'high_impact', category: 'martial_arts',
      emoji: '🥋', displayName: 'Judo'),
  Activity(
      id: 'karate', tier: 'high_impact', category: 'martial_arts',
      emoji: '🥋', displayName: 'Karate'),
  Activity(
      id: 'sprinting', tier: 'high_impact', category: 'running',
      emoji: '💨', displayName: 'Sprint Training',
      note: 'Sprint/plyometric work raised bone density and GH/IGF-1 markers in a small adolescent trial — signs of a healthy loading response, not a proven height gain (ASJSM 2024).'),
  Activity(
      id: 'dance', tier: 'high_impact', category: 'dance',
      emoji: '💃', displayName: 'Dance',
      note: 'Multi-directional high-impact loading, underrated osteogenic activity'),
  Activity(
      id: 'parkour', tier: 'high_impact', category: 'bodyweight',
      emoji: '🏃', displayName: 'Parkour',
      note: 'Very high impact, novel multi-directional loading — excellent during growth window'),
  Activity(
      id: 'basketball_drills', tier: 'high_impact', category: 'sports',
      emoji: '🏀', displayName: 'Basketball Drills'),
  Activity(
      id: 'hopscotch', tier: 'high_impact', category: 'jumping',
      emoji: '🎯', displayName: 'Hopscotch', unit: 'reps'),

  // ── TIER 2 — WEIGHT-BEARING ──────────────────────────────────
  Activity(
      id: 'running', tier: 'weight_bearing', category: 'running',
      emoji: '🏃', displayName: 'Running'),
  Activity(
      id: 'tag_games', tier: 'weight_bearing', category: 'running',
      emoji: '🏷️', displayName: 'Tag Games'),
  Activity(
      id: 'tennis', tier: 'weight_bearing', category: 'sports',
      emoji: '🎾', displayName: 'Tennis',
      note: 'More favourable bone outcomes vs absence of PA (Krahenbüh systematic review)'),
  Activity(
      id: 'badminton', tier: 'weight_bearing', category: 'sports',
      emoji: '🏸', displayName: 'Badminton'),
  Activity(
      id: 'trampoline', tier: 'weight_bearing', category: 'jumping',
      emoji: '🦘', displayName: 'Trampoline',
      note: 'Reduces peak GRF vs floor jumping — osteogenic but lower intensity than box jumps'),
  Activity(
      id: 'indoor_climbing', tier: 'weight_bearing', category: 'climbing',
      emoji: '🧗', displayName: 'Indoor Climbing'),
  Activity(
      id: 'playground_climbing', tier: 'weight_bearing', category: 'climbing',
      emoji: '🛝', displayName: 'Playground Climbing'),
  Activity(
      id: 'monkey_bars', tier: 'weight_bearing', category: 'bodyweight',
      emoji: '🐒', displayName: 'Overhead Bar Traverse', presets: 'small_min',
      note: 'Dynamic brachiation — swing hand-to-hand on overhead bars. Upper body weight-bearing; distinct from static bar hanging.'),
  Activity(
      id: 'obstacle_course', tier: 'weight_bearing', category: 'bodyweight',
      emoji: '🏁', displayName: 'Obstacle Course'),
  Activity(
      id: 'outdoor_play', tier: 'weight_bearing', category: 'lifestyle',
      emoji: '☀️', displayName: 'Outdoor Play', outdoor: true,
      note: 'If running/jumping involved — often equivalent to Tier 1. ☀️ Sunlight exposure → Vitamin D synthesis.'),
  Activity(
      id: 'playground', tier: 'weight_bearing', category: 'lifestyle',
      emoji: '🛝', displayName: 'Playground Activities', outdoor: true),

  // ── TIER 3 — CARDIO ──────────────────────────────────────────
  Activity(
      id: 'swimming', tier: 'cardio', category: 'cardio',
      emoji: '🏊', displayName: 'Swimming',
      note: 'Excellent cardiovascular + GH stimulus. No osteogenic benefit — combine with weight-bearing (PMID 29199168)'),
  Activity(
      id: 'cycling', tier: 'cardio', category: 'cardio',
      emoji: '🚲', displayName: 'Cycling',
      note: 'Good cardiovascular. High-volume cycling associated with low BMD — complement with weight-bearing'),

  // ── TIER 4 — FLEXIBILITY / DECOMPRESSION ─────────────────────
  Activity(
      id: 'yoga', tier: 'flexibility', category: 'flexibility',
      emoji: '🧘', displayName: 'Yoga (Growth Poses)',
      note: 'Flexibility and recovery. Non-impact — not effective for bone density alone. Spinal extension poses (Cobra, Downward Dog, Cat-Cow, Tree) support disc hydration and postural alignment.'),
  Activity(
      id: 'stretching', tier: 'flexibility', category: 'flexibility',
      emoji: '🤸', displayName: 'Stretching'),
  Activity(
      id: 'bar_hanging', tier: 'flexibility', category: 'flexibility',
      emoji: '🏋️', displayName: 'Bar Hanging (Decompression)', presets: 'small_min',
      note: 'Static spinal decompression — good for disc hydration and lumbar posture. NOT osteogenic. Best after high-impact activity.'),
  Activity(
      id: 'walking', tier: 'lifestyle', category: 'lifestyle',
      emoji: '🚶', displayName: 'Walking',
      note: 'Minimal osteogenic effect at normal pace. Good daily movement baseline.'),
];
