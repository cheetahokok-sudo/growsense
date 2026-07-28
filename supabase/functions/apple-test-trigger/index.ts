// ══════════════════════════════════════════════════════════════════
// TEMPORARY DIAGNOSTIC — delete after the loop is green.
//
// Runs Apple's Request-a-Test-Notification loop, which is the single
// most useful thing available to a developer with no Mac:
//
//   POST /inApps/v1/notifications/test          -> testNotificationToken
//   GET  /inApps/v1/notifications/test/{token}  -> what Apple SAW,
//                                                  including the HTTP
//                                                  status our endpoint
//                                                  returned
//
// That validates, with zero app builds: the .p8 key, ES256 JWT signing,
// the ASC-registered URL, our receiver being reachable, its JSON
// handling, the DB insert, and the 200 we return.
//
// It is also the only thing that catches JWT-verification-left-on,
// which otherwise fails INVISIBLY — the 401 happens in Supabase's
// gateway before our code runs, so our logs stay clean while every
// renewal is silently dropped.
//
// This function must exist only briefly: it can make Apple send
// notifications. Deleted immediately after use.
// ══════════════════════════════════════════════════════════════════

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { appleJwt } from "../_shared/apple.ts";

const HOSTS: Record<string, string> = {
  production: "https://api.storekit.itunes.apple.com",
  sandbox: "https://api.storekit-sandbox.itunes.apple.com",
};

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const only = url.searchParams.get("env");
  const token = await appleJwt();
  const out: Record<string, unknown> = {};

  for (const [env, host] of Object.entries(HOSTS)) {
    if (only && only !== env) continue;
    try {
      // 1. Ask Apple to send a TEST notification to the configured URL.
      const reqRes = await fetch(`${host}/inApps/v1/notifications/test`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
      });
      const reqBody = await reqRes.text();

      if (!reqRes.ok) {
        out[env] = { step: "request", status: reqRes.status, body: reqBody.slice(0, 300) };
        continue;
      }

      const testToken = JSON.parse(reqBody).testNotificationToken as string;

      // 2. Give Apple a moment to deliver, then ask what happened.
      await new Promise((r) => setTimeout(r, 6000));

      const chkRes = await fetch(
        `${host}/inApps/v1/notifications/test/${encodeURIComponent(testToken)}`,
        { headers: { Authorization: `Bearer ${token}` } },
      );
      const chkBody = await chkRes.text();

      out[env] = {
        step: "check",
        requestOk: true,
        testNotificationToken: testToken,
        checkStatus: chkRes.status,
        // sendAttempts[].sendAttemptResult === "SUCCESS" is the goal.
        result: chkBody.slice(0, 900),
      };
    } catch (e) {
      out[env] = { error: String(e).slice(0, 300) };
    }
  }

  return new Response(JSON.stringify(out, null, 2), {
    headers: { "content-type": "application/json" },
  });
});
