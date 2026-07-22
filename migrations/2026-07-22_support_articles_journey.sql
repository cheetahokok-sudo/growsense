-- ==========================================
-- Troubleshooting library v2 — full user-journey coverage (2026-07-22).
-- Run in Supabase SQL editor AFTER 2026-07-22_support_articles.sql.
--
-- Adds a `section` column (browse taxonomy, in user-journey order) and
-- seeds ~22 articles covering every screen of the app, mapped from
-- flutter_app/lib/screens/. Sections:
--   account    Account & sign-in
--   children   Child profiles & family
--   logging    Daily logging (food / activity / sleep / readiness)
--   estimates  Estimates & the calendar (gold days, gap-fill)
--   growth     Growth charts & analytics
--   medical    Medical records (measurements, bone age, labs, PDF)
--   premium    Premium & codes
--   devices    Wearables & sync
--   technical  App & technical
--
-- Content rails: percentiles/projections are always ranges; no claim
-- that any food/sport adds height; AI features are educational, not
-- diagnosis; never phrase growth concern as a child "becoming shorter".
-- ==========================================

ALTER TABLE support_articles
  ADD COLUMN IF NOT EXISTS section TEXT NOT NULL DEFAULT 'technical'
      CHECK (section IN ('account','children','logging','estimates','growth',
                         'medical','premium','devices','technical'));

-- File the 8 v1 articles into the taxonomy
UPDATE support_articles SET section = 'account'
  WHERE slug IN ('google-signin-fails','apple-signin-availability');
UPDATE support_articles SET section = 'premium'   WHERE slug = 'activation-code-rejected';
UPDATE support_articles SET section = 'devices'   WHERE slug = 'fitbit-not-syncing';
UPDATE support_articles SET section = 'logging'   WHERE slug = 'entry-on-wrong-day';
UPDATE support_articles SET section = 'technical'
  WHERE slug IN ('install-app-home-screen','wrong-date-early-morning','data-missing-other-device');

-- ==========================================
-- Journey articles. All internal. Edit in the admin console.
-- ==========================================
INSERT INTO support_articles (slug, section, title, symptom, platform, steps, escalation) VALUES

-- ── account ──────────────────────────────────────────────────────
(
  'forgot-password-reset', 'account',
  'Forgot the password / cannot sign in with email',
  'Parent has an email account but the password does not work.',
  'all',
  'First check HOW they registered: Google and Apple accounts have NO password — they must tap that provider button, not the email form.
For email accounts: on the sign-in screen tap "Forgot password?", enter the email, and send the reset link.
Check the inbox AND spam folder for the reset email.
The link opens a "Set new password" screen — the new password must be at least 8 characters.
After setting it, sign in normally with email + the new password.',
  'If no reset email arrives after 10 minutes and spam is clear, verify the address actually has an account (Admin > Families) — a typo at signup is the usual cause.'
),
(
  'change-email-or-password', 'account',
  'How to change the account email or password',
  'Parent wants to update their sign-in email or set a new password.',
  'all',
  'Open Account & settings > "Email & password".
Password changes apply to email accounts only — Google and Apple accounts manage their password with that provider, not with us.
Changing the email sends a confirmation to the NEW address; the change completes only after they confirm it.
Remind them: the email is the account identity — the new address is what they sign in with afterwards.',
  'If a confirmation email never lands, check spam first, then verify the new address was typed correctly.'
),
(
  'delete-account-what-happens', 'account',
  'What happens when an account is deleted',
  'Parent asks to delete their account, or deleted it and regrets it.',
  'all',
  'Deletion is in Account & settings > "Delete account" > "Delete everything" — the app asks for confirmation first.
Suggest exporting first: Account > "Export data (CSV)" saves growth, clinical records and recent logs.
After deletion the family immediately loses access to all children and data in the app.
This is designed to be permanent — treat it as unrecoverable when talking to the family.',
  'If a family says they deleted by MISTAKE, check Admin > Archived promptly — recently removed data may still be restorable before its permanent purge. Never promise recovery before checking.'
),

-- ── children ─────────────────────────────────────────────────────
(
  'child-dob-or-sex-wrong', 'children',
  'Percentiles look wrong — check date of birth and sex first',
  'Every chart looks off; the child seems misplaced against the curve.',
  'all',
  'WHO percentiles are computed against the child''s EXACT age and sex — a wrong date of birth or sex shifts every number in the app.
Open Account & settings > Children profiles > the child > "Edit child profile".
Verify date of birth (year included — a one-year slip is the classic error) and biological sex.
Save; charts and percentiles recompute from the corrected profile automatically.',
  'If the profile is correct and the numbers still look implausible, check the measurements themselves next (a 115 cm typed as 151 cm moves a child dozens of percentile points).'
),
(
  'multiple-children-switching', 'children',
  'Tracking more than one child / switching between children',
  'Family has several kids and cannot find where to switch.',
  'all',
  'Add each child once: Account & settings > Children profiles > "Add another child".
Each child has their OWN logs, measurements and charts — nothing is shared between siblings.
Switch the active child from the child selector at the top of the app; every tab then shows that child.
The app keeps at least one active profile — the last child cannot be removed.',
  NULL
),
(
  'birth-details-why-asked', 'children',
  'Why the app asks for birth weight, length and gestation',
  'Parent is unsure why the child profile has birth details, or whether to fill them.',
  'all',
  'The birth details block (gestation weeks, birth weight, birth length, doctor-confirmed SGA) is OPTIONAL — the app works fully without it.
It exists for children born small or early: with it, GrowSense can put early growth in the right context (catch-up growth tracking).
It can be filled in or corrected at any time via "Edit child profile" — no need to know it at signup.
If the parent does not know the numbers, they are usually in the maternity book / health record booklet.',
  'For the clinical background, see the blog article "Born small" (born-small-catch-up-growth) — linkable if the parent wants the science.'
),
(
  'parent-heights-genetic-target', 'children',
  'Genetic target height is missing or seems surprising',
  'The genetic target (adult) shows nothing, or the parent questions the number.',
  'all',
  'The genetic target needs BOTH parents'' heights — enter them under Parent heights (Account) or the family heights section in Medical.
It is the standard mid-parental calculation: a RANGE the child''s genetics point toward, not a promise or a prediction of one number.
Heights are entered in cm; a guessed or rounded parent height moves the target, so encourage measured values.
The target is one reference line — the child''s own measured curve always matters more than the target.',
  NULL
),

-- ── logging ──────────────────────────────────────────────────────
(
  'readiness-ring-explained', 'logging',
  'What the readiness ring on Today means',
  'Parent asks what the ring is, why it is not full, or what "carrying today" means.',
  'all',
  'The ring wraps the day''s three levers — nutrition, activity and sleep — into one picture; its color deepens as each intake fills.
"Nutrition/Activity/Sleep is carrying today" simply names which lever has contributed most so far.
It resets every day and reflects only what was LOGGED — an empty ring means an unlogged day, not a bad day.
It is a logging companion, not a medical score — do not read it as a health judgment.',
  NULL
),
(
  'food-portions-and-custom-foods', 'logging',
  'Logging food, portions, and adding your own foods',
  'Parent cannot find a food, or hits the custom-food limit.',
  'all',
  'Log from the Food tab: search the preset library, tap a food, adjust the portion, save.
A dish that is not in the library can be added via "Add your own food": name, serving size (g) and protein (g) are required; calcium and zinc are optional.
Custom foods can be edited or removed later from the same tab.
Limits: 5 custom foods on Free, 50 on Premium — hitting the cap is the usual reason "Save food" is refused.
Targets (protein, calcium, hydration) are set for the child''s age automatically.',
  'If a COMMON local food is missing from the presets, note it — recurring requests feed the next library update.'
),
(
  'activity-tiers-explained', 'logging',
  'Why activities count differently toward the day',
  'Parent asks why swimming scores differently from jumping rope, or which sport is "best".',
  'all',
  'Activities are grouped by how strongly they load the skeleton: high-impact and weight-bearing play gives a stronger bone-loading stimulus; swimming and cycling are great for the heart with lower bone-loading; stretching is mobility.
That grouping is what the tier filter on the Activity tab shows — it is about the TYPE of stimulus, not a ranking of sports.
Be careful with phrasing: no sport makes a child taller, and we never claim that. Movement supports healthy bones, sleep and appetite.
Outdoor activities carry a sun icon — daylight time is also how the body makes vitamin D.',
  'For the evidence, the blog article on exercise and growth (can-exercise-make-children-taller) is the reference answer.'
),
(
  'sleep-log-naps-wakes', 'logging',
  'Logging sleep: bedtime, wake time, naps and night wakes',
  'Parent is unsure what to enter on the sleep card, or how to fix a saved night.',
  'all',
  'On Today, the sleep card takes bedtime and morning wake time; night wakes and naps are optional extras.
Naps have their own start/end fields — "Add nap" adds another.
Save with "Save sleep"; the values can be reopened and edited on that day afterwards.
The bedtime target shown (e.g. before 21:30) is a gentle age-based guide, not a rule — a different family rhythm is not an error.',
  NULL
),

-- ── estimates ────────────────────────────────────────────────────
(
  'gold-estimates-explained', 'estimates',
  'What the gold entries are (estimated days)',
  'Parent sees gold-colored values and asks whether the app invented data.',
  'all',
  'Gold ALWAYS means estimated; blue/normal means measured or logged by you. The app never silently mixes the two.
When a recent day was left unlogged, the "Forgot to log yesterday?" card offers to fill it from the family''s own usual pattern (the last logged similar days).
The parent stays in control: they can adjust ("much less … much more"), confirm, or choose "Leave empty" — nothing is filled without them.
A confirmed estimate is still marked as backfilled in the calendar — the honesty trail is kept.
Estimated days are also treated more cautiously in Analytics so trends stay trustworthy.',
  'If a parent objects to estimation on principle, point out "Leave empty" is always offered — estimation is opt-in per day, never automatic.'
),
(
  'calendar-correct-a-day', 'estimates',
  'Reading the logging calendar and correcting a day',
  'Parent asks what the calendar dots/bars mean or how to fix a past day.',
  'all',
  'The logging-history calendar (tap the date on Today, or "Logging history" in Analytics) shows each day''s three levers — nutrition, activity, sleep.
Solid entries were logged by the family; gold entries were estimated or backfilled from memory; the legend on the screen spells out each state.
To fix a past day, open it and use "Correct this day" — it reopens that date for editing exactly like a normal day.
Gaps are normal and visible on purpose: an honest gap beats an invented streak.',
  NULL
),

-- ── growth ───────────────────────────────────────────────────────
(
  'first-measurement-no-curve', 'growth',
  'Added a measurement but there is no curve yet',
  'Parent logged one height and expected a chart with a trend.',
  'all',
  'One measurement is a POINT, not a curve — the app shows the WHO percentile snapshot for it, and the curve builds as more points are added.
This is by design: a single measurement cannot show direction, and we do not fake one.
Measuring every few months is plenty — height changes slowly, and over-frequent measuring mostly captures measurement noise.
Measure the same way each time (morning, no shoes, heels against the wall) so points are comparable.',
  NULL
),
(
  'percentile-what-it-means', 'growth',
  'Is my child''s percentile bad? (reading P25, P50, P75…)',
  'Parent sees a percentile below 50 and worries.',
  'all',
  'A percentile is a position among healthy children of the same age and sex — P25 means taller than about 25 of 100 peers, and it is a NORMAL, healthy position.
What matters is the child''s own channel over time: steadily tracking along P25 is reassuring; what deserves attention is drifting across channels over months.
Phrase growth concerns as "growing more slowly than their curve" — children do not become shorter, and we never say that.
One low-looking reading is a snapshot; the app is built to watch the trajectory instead.',
  'If a chart shows a real downward drift across channels, the right move is a pediatrician visit with the Visit summary PDF — not reassurance from us.'
),
(
  'height-velocity-needs-two-points', 'growth',
  'Height velocity shows nothing or looks extreme',
  'Velocity is empty, or shows an implausible cm/year figure.',
  'all',
  'Velocity (cm/year) needs at least two measurements with real time between them — with one point it stays empty by design.
Two measurements taken close together make velocity swing wildly: a 0.5 cm measuring difference over two weeks extrapolates to an absurd yearly rate.
Give it months between points and the number settles into a meaningful range.
If velocity looks extreme, check the two underlying measurements first — a typo in either is the usual cause.',
  NULL
),
(
  'adult-height-projection-locked', 'growth',
  'Where is the adult height prediction?',
  'Parent expected an adult-height number right after signing up.',
  'all',
  'The projection unlocks as the child is TRACKED over time — a single measurement cannot honestly project adult height, so we refuse to fake one from it.
Entering both parents'' heights (genetic target) is part of the picture and can be done right away.
When shown, the projection is always a RANGE that narrows as more measurements come in — never one exact number.
This is a feature, not a gap: apps that print one confident number from one measurement are guessing.',
  NULL
),

-- ── medical ──────────────────────────────────────────────────────
(
  'bone-age-add-study', 'medical',
  'Adding a bone age study and what the AI second opinion is',
  'Parent has a bone age X-ray result and wants it in the timeline.',
  'all',
  'Medical tab > Bone age > "Add a bone age study": enter the doctor''s reading, the date, and optionally the hospital and notes.
Attaching the hand X-ray photo at entry is optional — but it is what enables the AI second opinion (Premium).
The point of the module is the TIMELINE: studies from different hospitals in one place, showing whether the bone-age gap stays steady across years — the history no single clinic keeps.
The AI reading is an educational reference (Greulich-Pyle framework), NOT a clinical diagnosis — the doctor''s reading always leads, and the app says so on screen.
If AI and doctor disagree a lot, the app itself flags to treat the AI reading with caution.',
  'AI analysis failures are usually image quality — ask for a straight, well-lit photo of the film without glare.'
),
(
  'lab-values-entry', 'medical',
  'Entering lab results and why we ask for YOUR lab''s range',
  'Parent has blood-test results and is unsure what to type in.',
  'all',
  'Medical tab > Lab values > "Add lab result": analyte name, result value, and the reference range printed on YOUR lab report.
We ask for the report''s own range because ranges genuinely differ between laboratories — comparing against a generic range would mislead.
If the report shows an SDS / z-score, it can be entered too (optional).
Logging and charting lab values is free — always. The AI interpretation of a panel is the Premium part, and it is educational reading support, not a diagnosis.
Values chart over time per analyte, so repeat tests build a picture.',
  'Unit mismatches are the classic error (e.g. ng/mL vs nmol/L for vitamin D) — if a value looks wildly off, check the unit on the report first.'
),
(
  'visit-summary-pdf', 'medical',
  'Getting a summary PDF for the doctor visit',
  'Parent wants to bring the child''s data to a pediatrician appointment.',
  'all',
  'Account & settings > "Share with a doctor" > "Visit summary (PDF)".
It is a clean, printable summary: growth, clinical records, and the recent logs for the ACTIVE child — switch children first if needed.
Print it or share the file directly from the phone to LINE/email.
This is the intended way to bring GrowSense data into a clinic — doctors get one tidy document instead of an app to scroll.',
  NULL
),

-- ── premium ──────────────────────────────────────────────────────
(
  'free-vs-premium-limits', 'premium',
  'What is free, what is Premium, and where to upgrade',
  'Parent hits a limit or asks what paying adds.',
  'all',
  'Free covers the core promise: growth tracking, WHO charts, daily logging, lab value charting — with a 30-day history window, a lifetime measurement allowance, and 5 custom foods.
Premium extends it: full history, 50 custom foods, and the AI features (bone-age second opinion, lab interpretation, monthly AI coach questions).
Current usage is visible in Account > Subscription (AI questions this month, measurements used).
Upgrade and billing are managed in the WEB app — the mobile app says so by design (store rules).
An activation code (Account > "Have an activation code?") grants a tier for a period without billing.',
  'For code problems see the "Activation code is not accepted" article. Never quote prices from memory — point at the pricing page, which is the source of truth.'
),

-- ── devices ──────────────────────────────────────────────────────
(
  'connect-fitbit-how', 'devices',
  'Connecting a Fitbit for automatic activity and sleep',
  'Parent wants wearable data flowing in, or taps Connect and nothing happens.',
  'all',
  'Connection happens in the WEB app: open growsense.life/app in a browser, go to Devices & sensors, and tap Connect on Fitbit — the mobile app will say "Open the web app to connect this device", which is expected.
The Fitbit authorization page asks the parent to approve access; after approving, the device shows Connected.
Back in the app, "Sync now" pulls the recent data; afterwards the Today screen shows a "Synced from Fitbit" chip.
Disconnect any time from the same screen — data already synced stays.
Other providers listed as Planned are not connectable yet.',
  'If Connect completes but data never appears, continue with the "Fitbit is connected but steps or sleep are not appearing" article.'
),

-- ── technical ────────────────────────────────────────────────────
(
  'coach-answers-source', 'technical',
  'Where the Coach''s answers come from',
  'Parent asks whether the Coach is a doctor, an AI, or something else.',
  'all',
  'The Coach answers from GrowSense''s curated question library — written answers with citations to the underlying evidence, shown under each reply.
If a question has no library match, the Coach suggests browsing topics rather than inventing an answer.
Premium accounts have a monthly allowance of AI-assisted questions (visible in Account > Subscription).
Either way it is educational information, not medical advice — for a concern about a specific child, the answer is always the pediatrician, ideally with the Visit summary PDF.',
  NULL
)
ON CONFLICT (slug) DO NOTHING;
