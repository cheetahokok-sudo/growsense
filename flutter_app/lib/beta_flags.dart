// ══════════════════════════════════════════════════════════════════
// Beta feature flags — the "superhost gate" from the Health Story
// Phase 0 spec (§9). Features are enabled per user, by email.
//
// TWO GATES, not one (spec §9.1):
//   • Gate 1 — capture / read face: safe to show the beta cohort.
//   • Gate 2 — pattern flags (P1–P7 "worth discussing"): stays dark
//     for EVERYONE until clinician review passes. Never flip this on
//     from here without that sign-off.
//
// See content/specs/health-story-pattern-engine.md
// ══════════════════════════════════════════════════════════════════

import 'app_state.dart';

/// Beta cohort — the only accounts that see beta features. Add emails
/// deliberately; keep it small enough to review outcomes by hand.
const Set<String> _betaCohort = {
  'cheetahokok@gmail.com',
};

bool _inCohort(AppState s) {
  final email = s.sb.auth.currentUser?.email?.toLowerCase().trim();
  return email != null && email.isNotEmpty && _betaCohort.contains(email);
}

/// Gate 1 — Health Story capture + read face (episode list, P0
/// frequency reassurance, visit summary). Reassurance-only, no
/// diagnosis, no flags. Safe for the beta cohort.
bool healthStoryCapture(AppState s) => _inCohort(s);

/// Gate 2 — Health Story pattern flags (P1–P7, "worth discussing").
/// FALSE for everyone until a paediatrician reviews the rules and
/// wording (spec §8 H-D, §9.5). Do not gate this on cohort alone.
bool healthStoryFlags(AppState s) => false;
