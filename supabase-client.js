// ══════════════════════════════════════════════════════════════════
// GrowSense shared Supabase client
// The single source of truth for which database GrowSense talks to.
// Both the parent-facing app (app.js) and the admin dashboard
// (admin.js, once split out) call createGrowSenseClient() rather than
// each constructing their own client — so a future change (rotating
// the publishable key, enabling realtime, adding client options)
// happens in exactly one place instead of needing to be remembered in
// two.
//
// Deliberately NOT included here: session-check flow, sign-in/sign-out
// UI logic, enterApp()-style boot sequences. Those are legitimately
// different between the two surfaces — the parent app's boot sequence
// assumes screens and element IDs (#authScreen, #appRoot) that won't
// exist in a separate admin.html, and the admin dashboard's own boot
// sequence should check for system_admin specifically before showing
// anything at all, not reuse the parent app's generic "is there a
// session" check. Forcing those into a shared file would create the
// wrong kind of coupling — only the client connection itself belongs
// here.
//
// These are project-level credentials (URL + publishable key), not a
// per-user secret — identifying which GrowSense database to talk to,
// the same way an API base URL would. Actual data access is gated by
// Postgres Row Level Security policies tied to the signed-in user, not
// by hiding this key. Never put a secret/service_role key here.
// ══════════════════════════════════════════════════════════════════

const SUPABASE_URL = 'https://ogpkmcqaulohexanucng.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_tNs8cyaiOYn8Q21wZxIYOQ_y5XXLXnf';

function createGrowSenseClient() {
  return supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
}
