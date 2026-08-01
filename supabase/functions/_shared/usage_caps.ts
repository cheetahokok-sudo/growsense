// Per-feature monthly usage caps — the ai-coach-proxy pattern made
// reusable for bone-age and lab AI.
//
// These are ABUSE BOUNDS, not pricing: normal use never touches them
// (an X-ray gets analyzed a few times a year), but without them one
// account could burn unbounded Sonnet-vision spend against a $5
// subscription. Deliberately NOT a shared credit pool with the coach:
// a parent must never have to "spend" scarce coach questions on a
// clinically important X-ray read — each feature carries its own
// quiet cap.
//
// Cap semantics per tier (subscription_tier_limits):
//   0    -> feature not in plan
//   null -> unlimited
//   N    -> N calls per UTC month
//
// The columns are read defensively (select *): this code deploys
// safely BEFORE the migration that adds them — a missing column reads
// as undefined -> uncapped (existing behaviour) — and the caps
// activate the moment the migration runs. Counting happens BEFORE the
// Anthropic call so an aborted request still counts.

export type CapVerdict =
  | { ok: true }
  | { ok: false; status: number; body: Record<string, unknown> };

export async function checkAndCountFeatureUse(
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  opts: {
    userId: string;
    tier: string;
    feature: "bone_age" | "lab_ai";
    capColumn: "bone_age_monthly_cap" | "lab_ai_monthly_cap";
  },
): Promise<CapVerdict> {
  const { data: limits } = await adminClient
    .from("subscription_tier_limits")
    .select("*")
    .eq("tier", opts.tier)
    .maybeSingle();

  const cap = limits?.[opts.capColumn];
  if (cap === undefined || cap === null) return { ok: true };
  if (cap === 0) {
    return { ok: false, status: 402, body: { error: "premium_required" } };
  }

  const now = new Date();
  const yearMonth = `${now.getUTCFullYear()}-${
    String(now.getUTCMonth() + 1).padStart(2, "0")
  }`;

  const { data: usage } = await adminClient
    .from("ai_feature_usage_monthly")
    .select("call_count")
    .eq("user_id", opts.userId)
    .eq("year_month", yearMonth)
    .eq("feature", opts.feature)
    .maybeSingle();

  const used = usage?.call_count ?? 0;
  if (used >= cap) {
    console.log(
      `[usage_caps] ${opts.feature} cap exceeded for ${opts.userId}: ${used}/${cap} (${opts.tier}, ${yearMonth})`,
    );
    return {
      ok: false,
      status: 429,
      body: {
        error: "monthly_cap_exceeded",
        code: "MONTHLY_CAP_EXCEEDED",
        cap,
        used,
        message:
          `Monthly limit for this analysis reached (${cap}/month). It resets on the 1st.`,
      },
    };
  }

  const { error } = await adminClient
    .from("ai_feature_usage_monthly")
    .upsert({
      user_id: opts.userId,
      year_month: yearMonth,
      feature: opts.feature,
      call_count: used + 1,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id,year_month,feature" });
  if (error) {
    // Never deny service over an accounting write failure — log it.
    console.error("[usage_caps] counter write failed:", error);
  }
  return { ok: true };
}
