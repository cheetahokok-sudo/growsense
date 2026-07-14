// supabase/functions/delete-account/index.ts
//
// In-app account deletion for GrowSense (App Store Guideline 5.1.1(v)).
// Deletes the caller's own data and their auth user. Called from the
// Flutter app via `supabase.functions.invoke('delete-account')`, which
// forwards the signed-in user's JWT in the Authorization header.
//
// Deploy:
//   supabase functions deploy delete-account
// (SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are
//  injected automatically by the platform.)
//
// Schema note: children are keyed by `parent_id`, per-child data by
// `child_id`, and account/report rows by `user_id`. We delete children's
// data first, then children, then user-level rows, then the auth user —
// so no non-cascading foreign key blocks the final auth-user delete.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

// Tables keyed by child_id (deleted for every child the user owns).
// Most also have ON DELETE CASCADE on the children FK, so deleting the
// child row (step 3) would remove them anyway — this explicit pass is
// belt-and-suspenders and keeps the deletion order FK-safe. Keep this in
// sync as new per-child tables are added.
const CHILD_TABLES = [
  "nutrition_log_items",
  "daily_nutrition",
  "daily_activity_items",
  "custom_activities",
  "favorite_activities",
  "daily_sleep",
  "sleep_naps",              // added 2026-07-13
  "google_health_connections", // wearable tokens (added 2026-07)
  "measurements",
  "custom_foods",
  "favorite_foods",
];

// Tables keyed by user_id (the account's own rows).
const USER_TABLES = ["bug_reports", "user_accounts"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  // Identify the caller from their JWT (never trust a body-supplied id).
  const asUser = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await asUser.auth.getUser();
  if (userErr || !user) return json({ error: "Invalid session" }, 401);

  const uid = user.id;
  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1) Collect the user's children.
  const { data: kids, error: kidsErr } = await admin
    .from("children")
    .select("child_id")
    .eq("parent_id", uid);
  if (kidsErr) return json({ error: `children lookup: ${kidsErr.message}` }, 500);
  const childIds = (kids ?? []).map((k: { child_id: string }) => k.child_id);

  // 2) Delete per-child data. Best-effort: a missing table shouldn't
  //    abort the whole deletion, but a real error is surfaced.
  const warnings: string[] = [];
  if (childIds.length > 0) {
    for (const table of CHILD_TABLES) {
      const { error } = await admin.from(table).delete().in("child_id", childIds);
      if (error) warnings.push(`${table}: ${error.message}`);
    }
  }

  // 3) Delete the children themselves.
  {
    const { error } = await admin.from("children").delete().eq("parent_id", uid);
    if (error) warnings.push(`children: ${error.message}`);
  }

  // 4) Delete user-level rows.
  for (const table of USER_TABLES) {
    const { error } = await admin.from(table).delete().eq("user_id", uid);
    if (error) warnings.push(`${table}: ${error.message}`);
  }

  // 5) Delete the auth user. This is the compliance-critical step; if a
  //    foreign key still references it, this fails loudly so we can add
  //    the offending table above (rather than silently half-deleting).
  const { error: delErr } = await admin.auth.admin.deleteUser(uid);
  if (delErr) {
    return json(
      { error: `auth user delete: ${delErr.message}`, warnings },
      500,
    );
  }

  return json({ success: true, deleted_children: childIds.length, warnings });
});
