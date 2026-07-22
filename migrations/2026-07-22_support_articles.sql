-- ==========================================
-- Troubleshooting library (2026-07-22). Run in Supabase SQL editor.
--
-- One system, two doors: articles live as DATA with a status column,
-- so "publish to the user menu later" is flipping status to 'public' —
-- not a migration. Admin door opens now (control-tower Troubleshooting
-- section); the future user door is the "public read" policy below,
-- already in place so the app only needs UI when the time comes.
--
-- Editorial model (Apple support style, e.g. support.apple.com/108905):
--   title     = the SYMPTOM as a user would say it, one problem per article
--   symptom   = one-line expansion of what the user sees
--   steps     = the fix ladder, ONE STEP PER LINE, escalating order
--   escalation= "if that didn't work" — what to collect / where it goes
--
-- Flywheel: bug_reports gains support_article_slug so a resolved issue
-- can point at (or become) the article that answers the next identical
-- report. An article that has closed 3-4 real issues is proven enough
-- to consider publishing.
-- ==========================================

CREATE TABLE IF NOT EXISTS support_articles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        TEXT NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,79}$'),
  title       TEXT NOT NULL CHECK (char_length(title) <= 160),
  symptom     TEXT NOT NULL CHECK (char_length(symptom) <= 400),
  platform    TEXT NOT NULL DEFAULT 'all' CHECK (platform IN ('all','web','ios','android')),
  status      TEXT NOT NULL DEFAULT 'internal' CHECK (status IN ('internal','public')),
  lang        TEXT NOT NULL DEFAULT 'en',
  steps       TEXT NOT NULL CHECK (char_length(steps) <= 4000),
  escalation  TEXT CHECK (escalation IS NULL OR char_length(escalation) <= 1000),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

ALTER TABLE support_articles ENABLE ROW LEVEL SECURITY;

-- Admin door: full control under a system_admin session (the same
-- SECURITY DEFINER guard the rest of the admin console uses).
DROP POLICY IF EXISTS "admins manage support articles" ON support_articles;
CREATE POLICY "admins manage support articles" ON support_articles
    FOR ALL USING (public.is_system_admin());

-- Future user door: signed-in users can read PUBLISHED articles only.
-- Internal drafts never leave the admin console.
DROP POLICY IF EXISTS "users read public support articles" ON support_articles;
CREATE POLICY "users read public support articles" ON support_articles
    FOR SELECT TO authenticated USING (status = 'public');

-- Flywheel link: closing an issue can reference the article that
-- answers it. Plain text slug (not FK) so deleting/renaming an article
-- never blocks issue triage.
ALTER TABLE bug_reports
  ADD COLUMN IF NOT EXISTS support_article_slug TEXT;

-- ==========================================
-- Seed: the 8 failure modes already known from this project's own
-- history. All internal. Content is a starting point — edit in the
-- admin console, not here.
-- ==========================================
INSERT INTO support_articles (slug, title, symptom, platform, steps, escalation) VALUES
(
  'google-signin-fails',
  'Google sign-in fails or loops back to the login screen',
  'Parent taps Continue with Google, approves, but lands back on the login screen or sees an error.',
  'all',
  'Confirm they are using the SAME Google account they signed up with — a different Gmail silently creates a separate, empty account.
Ask them to try a normal (non-incognito) browser window — private mode and blocked third-party cookies can break the Google redirect.
If it loops: clear site data for growsense.life (browser settings > site data), then sign in again.
If Google itself shows an error page, ask for a screenshot — the message text tells us which side failed.',
  'Collect device, browser + version, screenshot of the exact error, and the time it happened (matches Supabase Auth logs). Check Supabase > Authentication > Logs around that minute.'
),
(
  'apple-signin-availability',
  'Continue with Apple is missing or does not work',
  'Parent cannot find Apple sign-in on the website, or it errors.',
  'all',
  'On the website and on Android this is EXPECTED — Apple sign-in is only offered inside the iOS app, where the native flow works. The web button is intentionally hidden.
On web, point them to Google or email sign-in instead.
Warn about account identity: Apple, Google, and email sign-ins are SEPARATE accounts — data does not merge across sign-in methods. They should keep using whichever method they registered with.',
  'If it fails INSIDE the iOS app, capture the exact error text — the native flow depends on the Apple provider configuration in Supabase (bundle ID whitelist).'
),
(
  'install-app-home-screen',
  'How to install GrowSense on the phone home screen',
  'Parent wants an app icon instead of opening the browser each time.',
  'all',
  'iPhone: open https://www.growsense.life/app in SAFARI (not Chrome), tap the Share button, then "Add to Home Screen".
Android: open the same address in Chrome, tap the three-dot menu, then "Add to Home screen" / "Install app".
If the option is missing on iPhone, they are almost certainly inside the Facebook or LINE in-app browser — tap "Open in Safari" first, then repeat.',
  'If the icon installs but opens a blank page, ask for phone model + OS version and a screenshot.'
),
(
  'wrong-date-early-morning',
  'An entry saved with yesterday''s date (early morning)',
  'Something logged before ~07:00 Bangkok time appears under the previous day.',
  'web',
  'Known limitation of the WEB version: saves before ~07:00 Asia/Bangkok can be stamped with the previous date (UTC offset). The iOS/Flutter app is not affected.
Fast fix for the family: edit the entry''s date, or re-log it after 7am.
If dates look wrong at OTHER times of day, that is a different problem — check the device clock and timezone are set to automatic.',
  'This is on the fix list (todayISO() local-time constructor). If reports come from the Flutter app rather than the web version, escalate immediately — that would be new.'
),
(
  'fitbit-not-syncing',
  'Fitbit is connected but steps or sleep are not appearing',
  'The provider shows connected, but recent days are empty in GrowSense.',
  'all',
  'First check the Fitbit app itself shows the data — GrowSense can only mirror what Fitbit has already synced from the tracker.
Fitbit authorizations expire: disconnect the provider in GrowSense and reconnect it to refresh the token.
Sync covers recent days only — data from before the connection date does not backfill.
After reconnecting, reopen GrowSense and give it a minute; sync runs on load, not continuously.',
  'If reconnect does not fix it, collect the family email + which days are missing, and check the sync logs / google_health_connections row for that user.'
),
(
  'activation-code-rejected',
  'Activation code is not accepted',
  'Parent or clinic enters a code and gets an error instead of the tier upgrade.',
  'all',
  'Codes are single-use — check it in Admin > Activation codes: status, expiry, and which batch it belongs to.
If it shows as used: it may have been redeemed on a different account belonging to the same family — search their other emails under Families.
Have them paste the code rather than type it (easy to confuse look-alike characters).
If the code is valid and unused but still rejected, get the exact error message text.',
  'Cross-check the batch in Admin > Activation codes. If a whole batch fails, that is a generation problem, not a user problem.'
),
(
  'entry-on-wrong-day',
  'An entry was logged to the wrong day',
  'Food, activity, or sleep landed on a different date than intended.',
  'all',
  'In the app, open the day in question (tap the date on the Today screen to reach the calendar).
Remove the wrong entry, then re-log it on the correct day.
If this happened in the early morning on the web version, see the "entry saved with yesterday''s date" article — that is a known limitation, not user error.',
  NULL
),
(
  'data-missing-other-device',
  'Data is not appearing on another device',
  'Family logs on one phone; a second phone or the web shows nothing or old data.',
  'all',
  'Confirm BOTH devices are signed into the same account — same email AND same sign-in method. Google, Apple, and email accounts are separate even with the same address.
Close and reopen the app on the second device — data syncs on load.
Check the second device has internet access.
If the second device runs an old cached version, reinstall the home-screen app / clear site data and sign in again.',
  'If both devices are confirmed on the same account and data still differs, collect the account email and which entries are missing — that would be a real sync defect, file it as an issue.'
)
ON CONFLICT (slug) DO NOTHING;
