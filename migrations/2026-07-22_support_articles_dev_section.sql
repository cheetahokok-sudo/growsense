-- ==========================================
-- Troubleshooting library v3 — dev/internal section (2026-07-22).
-- Run in Supabase SQL editor AFTER the v1 + v2 support_articles files.
--
-- Adds section 'dev' for developer/operator runbook articles. These are
-- CONFIDENTIAL-internal: a CHECK constraint makes it impossible to set
-- a dev article to status='public', so the future user-menu door
-- (which only reads status='public') can never expose them — even by
-- an accidental click in the editor.
-- ==========================================

-- Widen the section taxonomy (inline CHECK from v2 gets replaced)
ALTER TABLE support_articles
  DROP CONSTRAINT IF EXISTS support_articles_section_check;
ALTER TABLE support_articles
  ADD CONSTRAINT support_articles_section_check
      CHECK (section IN ('account','children','logging','estimates','growth',
                         'medical','premium','devices','technical','dev'));

-- The confidentiality guarantee: dev articles can never be public.
ALTER TABLE support_articles
  DROP CONSTRAINT IF EXISTS support_articles_dev_never_public;
ALTER TABLE support_articles
  ADD CONSTRAINT support_articles_dev_never_public
      CHECK (NOT (section = 'dev' AND status = 'public'));

-- ==========================================
-- Seed: the operator runbook — hard-won project gotchas. Wording can
-- be blunt here; no parent ever sees these.
-- ==========================================
INSERT INTO support_articles (slug, section, title, symptom, platform, steps, escalation) VALUES
(
  'dev-pages-deploy-silent', 'dev',
  'DEV: GitHub Pages deploys fail silently — always verify live',
  'Pushed to main but the live site did not change, with no error anywhere.',
  'web',
  'GitHub Pages gives NO failure feedback — a broken deploy looks identical to a slow one. Never assume a push is live.
After every push, curl or load the live URL with a cache-buster (?cb=123) and grep for a string that only exists in the new version.
Pages sits behind its own Fastly CDN — first check can be stale; retry with a fresh cb value for up to ~2 minutes.
The .nojekyll file at the repo root is LOAD-BEARING: without it Jekyll processing eats underscore-prefixed paths (Flutter build output). Never delete it.',
  'If the change is still not live after ~5 minutes, check the Pages build status under the repo''s Actions/Settings > Pages.'
),
(
  'dev-flutter-web-rebuild', 'dev',
  'DEV: Rebuilding the Flutter app into /app/ (PowerShell only)',
  'Changes to flutter_app/ are committed but growsense.life/app still runs the old build.',
  'web',
  'The /app/ bundle is NOT rebuilt by CI — it is committed build output. Editing flutter_app/ alone changes nothing live.
Build in POWERSHELL, never git-bash: bash mangles the --base-href /app/ argument and produces a broken bundle.
Command: flutter build web --release --base-href /app/  (run inside flutter_app/).
Mirror the output into the served folder: robocopy build\web ..\app /MIR
Commit BOTH flutter_app/ sources and the regenerated app/ folder, push, then verify live per the Pages article.',
  'A blank page at /app/ after deploy usually means a base-href built wrong (bash) or a partial robocopy — rebuild in PowerShell and re-mirror.'
),
(
  'dev-migrations-runbook', 'dev',
  'DEV: Applying database migrations',
  'A feature expects a table/column that does not exist yet.',
  'all',
  'Migrations are HAND-RUN in the Supabase SQL editor — nothing applies them automatically.
Files live in migrations/, named by date; run pending ones in filename order.
They are written idempotent (IF NOT EXISTS / DROP POLICY IF EXISTS) — re-running a file is safe.
After running, reload the admin console / app; features gate on the schema existing.
The admin console''s empty-state messages name the exact migration file they are waiting for.',
  'If a migration errors midway, read which statement failed — because files are idempotent, fixing the statement and re-running the whole file is the correct recovery.'
),
(
  'dev-charset-mojibake', 'dev',
  'DEV: Thai/emoji render as garbage like "à¸¥à¸¹à¸" or "â€™"',
  'Non-ASCII text turns into Latin gibberish on a published page or artifact.',
  'web',
  'Cause: UTF-8 bytes decoded as Latin-1 — happens whenever a server/viewer serves the file without a charset declaration.
Robust fix: make the SOURCE pure ASCII — HTML entities (&#xNNNN;) in markup, \uNNNN escapes in JS strings. Then no decoder can corrupt it.
Never hand-edit an entity-encoded file — keep a UTF-8 working copy, edit that, re-run the encoder before publishing.
Proof of immunity: serve the file from a charset-less local server (python -m http.server) and confirm Thai + emoji render.
Related rule: keep em-dashes out of copy meant for pasting into social posts — use commas — so a charset slip can never corrupt what gets posted.',
  NULL
),
(
  'dev-dart-web-int-footguns', 'dev',
  'DEV: Flutter web crashes where mobile works (integer math)',
  'Code passes flutter analyze and runs on device, but throws only in the web build.',
  'web',
  'On the web, Dart ints are JS doubles — three footguns follow.
Random.nextInt(1 << 32) throws RangeError on web (max is 2^32 as a value, and 1<<32 overflows to 0 in JS semantics anyway).
Bit shifts beyond 32 bits do not behave like the VM — avoid 64-bit shift tricks entirely.
Integers above 2^53 silently lose precision — never encode IDs or timestamps that big in web-reachable Dart int math.
flutter analyze will NOT catch any of these; the only test that counts is exercising the code path in an actual web build.',
  NULL
),
(
  'dev-utc-date-bug', 'dev',
  'DEV: Web PWA stamps entries with yesterday before 07:00 Bangkok',
  'Early-morning saves land on the previous date (users may report it).',
  'web',
  'Root cause: todayISO() in the web codebase derives the date from UTC parts; before 07:00 Asia/Bangkok, UTC is still yesterday.
The Flutter app is NOT affected — its date handling is already local.
The repo rule (CLAUDE.md): always use LOCAL-time date constructors for Bangkok UTC+7. The fix is applying that rule to todayISO().
Until fixed, the user-facing workaround article lives in App & technical ("An entry saved with yesterday''s date").
Fixing this properly deletes that user-facing article — the preferred outcome.',
  NULL
),
(
  'dev-admin-child-data-model', 'dev',
  'DEV: Why the admin console cannot query children directly',
  'A new admin feature needs child/health data and the query returns nothing.',
  'all',
  'By design, children has NO blanket admin SELECT policy — admins must not have row-level access to children''s health data. Do not "fix" this with a new read policy.
Admin operations on children go through SECURITY DEFINER RPCs (e.g. admin_restore_child, admin_delete_child_permanently), each guarded by public.is_system_admin().
A new admin metric touching child data must follow the same pattern: an RPC that returns AGGREGATE COUNTS only, never rows.
user_accounts and bug_reports, by contrast, are admin-readable via RLS policies — plain queries are fine there.',
  'The reference implementations live in migrations/2026-07-15_admin_read_user_accounts.sql and 2026-07-15_admin_child_lifecycle.sql.'
),
(
  'dev-release-process', 'dev',
  'DEV: Shipping an app release (version bump checklist)',
  'A build went out but the What''s-new screen or version numbers are stale.',
  'all',
  'Three things move together on every release: the version/build in app_meta, CHANGELOG.md, and release_notes.json.
release_notes.json is what feeds the in-app What''s-new screen — forgetting it means users see nothing about the release.
Bug reports capture app_version + build + channel automatically, so a stale bump also pollutes issue triage.
After the bump: rebuild the web bundle (see the Flutter rebuild article), push, verify live.',
  NULL
)
ON CONFLICT (slug) DO NOTHING;
