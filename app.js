// ══════════════════════════════════════════
// GLOBAL STATE
// Daily-log state is keyed per child index, so switching children
// never carries one child's half-entered numbers into another's form.
// ══════════════════════════════════════════
const DEFAULT_DAY_STATE = {
  protein: 0, calcium: 0, zinc: 0, water: 0,
  hanging: 0, jumps: 0, yogaMin: 0,
  deepSleep: 0, nightWakes: 0, steroid: 0,
  bed: '21:15', wake: '06:30',
  savedToday: false
};

// ══════════════════════════════════════════
// SUPABASE CLIENT
// Initialized via the shared factory in supabase-client.js —
// see that file for why URL/key live there instead of here.
// ══════════════════════════════════════════
const sb = createGrowSenseClient();

// ══════════════════════════════════════════════════════════════════
// INTERNATIONALISATION (i18n) — Phase 1
//
// Architecture:
//   · Locale strings live in /locales/{lang}.json
//   · t(key, fallback) looks up the active language, never throws
//   · data-i18n="key" on HTML elements updated by applyI18n()
//   · Preference saved to localStorage — survives page refresh
//   · Default: English. User chooses in Account screen.
//
// Flutter / React Native migration path:
//   · /locales/*.json are the source files, format is portable
//   · Key format: "screen.component.element" in snake_case
//   · Interpolation: {value} — compatible with flutter_localizations
//     ARB and i18next
//
// Safety: t() has 4 fallback layers and never throws.
// data-i18n is additive — hardcoded text is the ultimate fallback.
// ══════════════════════════════════════════════════════════════════

const SUPPORTED_LANGUAGES = [
  { code: 'en', label: 'EN', name: 'English',       flag: '🇬🇧' },
  { code: 'th', label: 'TH', name: 'ภาษาไทย',     flag: '🇹🇭' },
  { code: 'zh', label: 'ZH', name: '中文（简体）',  flag: '🇨🇳' },
  { code: 'ko', label: 'KO', name: '한국어',         flag: '🇰🇷' },
  { code: 'vi', label: 'VI', name: 'Tiếng Việt',    flag: '🇻🇳' },
  { code: 'ar', label: 'AR', name: 'العربية',        flag: '🇦🇪' },
];
const LOCALES = {}; // populated by loadLocales() at boot

async function loadLocales() {
  await Promise.all(SUPPORTED_LANGUAGES.map(async ({ code }) => {
    try {
      const res = await fetch(`locales/${code}.json`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const { _meta, ...strings } = await res.json();
      LOCALES[code] = strings;
    } catch (e) {
      console.warn(`[i18n] Could not load ${code}.json:`, e.message);
      LOCALES[code] = {};
    }
  }));
}

// 4-layer fallback — NEVER throws, NEVER returns undefined.
function t(key, fallback) {
  try {
    const lang = (typeof APP !== 'undefined' && APP.language) || 'en';
    return LOCALES[lang]?.[key]
      || LOCALES['en']?.[key]
      || fallback
      || key;
  } catch (e) {
    return fallback || key;
  }
}

function restoreLanguagePreference() {
  try {
    const saved = localStorage.getItem('growsense_language');
    if (saved && SUPPORTED_LANGUAGES.find(l => l.code === saved)) {
      APP.language = saved;
    } else {
      APP.language = 'en';
    }
  } catch (e) {
    APP.language = 'en';
  }
  // Apply direction immediately — before any rendering
  const lang = APP.language;
  document.documentElement.setAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
  document.documentElement.setAttribute('lang', lang);
}

function applyI18n() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    const key = el.getAttribute('data-i18n');
    if (!el.hasAttribute('data-i18n-fallback')) {
      el.setAttribute('data-i18n-fallback', el.textContent.trim());
    }
    const fallback = el.getAttribute('data-i18n-fallback');
    el.textContent = t(key, fallback);
  });
  // Also translate placeholder attributes
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    const key = el.getAttribute('data-i18n-placeholder');
    const fallback = el.getAttribute('placeholder') || '';
    el.placeholder = t(key, fallback);
  });
}

async function switchLanguage(lang) {
  if (!SUPPORTED_LANGUAGES.find(l => l.code === lang)) return;
  APP.language = lang;
  try { localStorage.setItem('growsense_language', lang); } catch (e) {}

  // RTL support — Arabic reads right to left
  document.documentElement.setAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
  document.documentElement.setAttribute('lang', lang);

  applyI18n();
  renderLanguageSelector();
}

function renderLanguageSelector() {
  const pillsHTML = SUPPORTED_LANGUAGES.map(l => `
    <button class="lang-pill${APP.language === l.code ? ' active' : ''}"
      onclick="switchLanguage('${l.code}')"
      aria-label="Switch to ${l.name}">
      ${l.flag} ${l.label}
    </button>`).join('');
  // Render in Account screen and also in Auth screen (pre-login)
  const acctEl = document.getElementById('languageSelector');
  if (acctEl) acctEl.innerHTML = pillsHTML;
  const authEl = document.getElementById('authLanguageSelector');
  if (authEl) authEl.innerHTML = pillsHTML;
}

// ── end i18n ──────────────────────────────────────────────────────

// ══════════════════════════════════════════════════════════════════
// ACTIVITY LIBRARY
// Evidence-based taxonomy from mechanotransduction + GH/IGF-1
// research. Tier drives the readiness score weight and the visual
// badge colour on every activity card.
//
// Evidence basis (weights rank OSTEOGENIC LOADING — bone strength, not
// added height; exercise builds stronger bone, not longer bone. See
// the GS-041 article "Can exercise make children taller?"):
//   high_impact    1.0 — highest peak ground-reaction force; gymnastics,
//                         basketball, martial arts show superior BMD in
//                         RCTs. Loading strengthens bone; it does not
//                         lengthen it.
//   weight_bearing 0.65 — osteogenic via gravity + muscle tension but
//                          lower peak GRF than Tier 1
//   cardio         0.35 — excellent GH release via large-muscle
//                          recruitment but ZERO osteogenic benefit
//                          (swimming inferior to controls for BMD;
//                          high-volume cycling associated with low BMD)
//   flexibility    0.15 — recovery value, injury prevention, spinal
//                          decompression; not a primary growth driver
// ══════════════════════════════════════════════════════════════════
const ACTIVITY_LIBRARY = [
  // ── TIER 1 — HIGH IMPACT ──────────────────────────────────────
  // Gymnastics: highest osteogenic evidence — 10.4× BW impacts/session,
  // 102–217 impacts per session (Daly et al. 1999). BMD superior to all
  // other sports including soccer and basketball.
  { id:'gymnastics',        tier:'high_impact',   category:'gymnastics',   emoji:'🤸', displayName:'Gymnastics',
    note:'Highest osteogenic evidence — 10.4× body weight impacts per session (Daly et al. 1999)' },

  // Jumping — high peak-force bone loading
  { id:'box_jumps',         tier:'high_impact',   category:'jumping',      emoji:'📦', displayName:'Box Jumps',        unit:'reps',
    note:'One of the strongest bone-loading drills. A small 24-week trial in short-stature children saw faster short-term growth velocity — that reflects bone and velocity, not proven adult height (BMC Pediatrics 2025).' },
  { id:'vertical_jumps',    tier:'high_impact',   category:'jumping',      emoji:'⬆️', displayName:'Vertical Jumps',   unit:'reps' },
  { id:'jump_rope',         tier:'high_impact',   category:'jumping',      emoji:'🪢', displayName:'Jump Rope',
    note:'Repeated moderate-impact loading — builds bone strength. Convenient, low-cost, and easy to do daily.' },

  // Ball sports
  { id:'basketball',        tier:'high_impact',   category:'sports',       emoji:'🏀', displayName:'Basketball',
    note:'Highest BMD among all team sports. Multi-directional impact loading (PMID 38040837)' },
  { id:'volleyball',        tier:'high_impact',   category:'sports',       emoji:'🏐', displayName:'Volleyball',
    note:'High-impact, repeated vertical jumps. BMD superior to swimmers and controls' },
  { id:'football',          tier:'high_impact',   category:'sports',       emoji:'⚽', displayName:'Football / Soccer',
    note:'Running + impact loading. ~39% of adult bone mass acquired in 5 years around PHV' },

  // Martial arts — significantly better bone outcomes vs non-sport
  { id:'taekwondo',         tier:'high_impact',   category:'martial_arts', emoji:'🥋', displayName:'Taekwondo',
    note:'Systematic review: significantly better bone outcomes vs non-sport (Barbeta et al.)' },
  { id:'muay_thai',         tier:'high_impact',   category:'martial_arts', emoji:'🥊', displayName:'Muay Thai' },
  { id:'judo',              tier:'high_impact',   category:'martial_arts', emoji:'🥋', displayName:'Judo' },
  { id:'karate',            tier:'high_impact',   category:'martial_arts', emoji:'🥋', displayName:'Karate' },

  // Sprint / plyometric
  { id:'sprinting',         tier:'high_impact',   category:'running',      emoji:'💨', displayName:'Sprint Training',
    note:'Sprint/plyometric work raised bone density and GH/IGF-1 markers in a small adolescent trial — signs of a healthy loading response, not a proven height gain (ASJSM 2024).' },

  // Multi-directional high-impact
  { id:'dance',             tier:'high_impact',   category:'dance',        emoji:'💃', displayName:'Dance',
    note:'Multi-directional high-impact loading, underrated osteogenic activity' },
  { id:'parkour',           tier:'high_impact',   category:'bodyweight',   emoji:'🏃', displayName:'Parkour',
    note:'Very high impact, novel multi-directional loading — excellent during growth window' },
  { id:'basketball_drills', tier:'high_impact',   category:'sports',       emoji:'🏀', displayName:'Basketball Drills' },
  { id:'hopscotch',         tier:'high_impact',   category:'jumping',      emoji:'🎯', displayName:'Hopscotch', unit:'reps' },

  // ── TIER 2 — WEIGHT-BEARING ──────────────────────────────────
  { id:'running',           tier:'weight_bearing',category:'running',      emoji:'🏃', displayName:'Running' },
  { id:'tag_games',         tier:'weight_bearing',category:'running',      emoji:'🏷️', displayName:'Tag Games' },
  { id:'tennis',            tier:'weight_bearing',category:'sports',       emoji:'🎾', displayName:'Tennis',
    note:'More favourable bone outcomes vs absence of PA (Krahenbüh systematic review)' },
  { id:'badminton',         tier:'weight_bearing',category:'sports',       emoji:'🏸', displayName:'Badminton' },
  { id:'trampoline',        tier:'weight_bearing',category:'jumping',      emoji:'🦘', displayName:'Trampoline',
    note:'Reduces peak GRF vs floor jumping — osteogenic but lower intensity than box jumps' },
  { id:'indoor_climbing',   tier:'weight_bearing',category:'climbing',     emoji:'🧗', displayName:'Indoor Climbing' },
  { id:'playground_climbing',tier:'weight_bearing',category:'climbing',    emoji:'🛝', displayName:'Playground Climbing' },
  { id:'monkey_bars',       tier:'weight_bearing',category:'bodyweight',   emoji:'🐒', displayName:'Overhead Bar Traverse', presets:'small_min',
    note:'Dynamic brachiation — swing hand-to-hand on overhead bars. Upper body weight-bearing; distinct from static bar hanging.',
    citation:'ACSM resistance guidelines; weight-bearing grip activity linked to cortical bone density (Nikander et al. 2009 JBMR)' },
  { id:'obstacle_course',   tier:'weight_bearing',category:'bodyweight',   emoji:'🏁', displayName:'Obstacle Course' },
  { id:'outdoor_play',      tier:'weight_bearing',category:'lifestyle',    emoji:'☀️', displayName:'Outdoor Play',     outdoor:true,
    note:'If running/jumping involved — often equivalent to Tier 1. ☀️ Sunlight exposure → Vitamin D synthesis.' },
  { id:'playground',        tier:'weight_bearing',category:'lifestyle',    emoji:'🛝', displayName:'Playground Activities', outdoor:true },

  // ── TIER 3 — CARDIO ──────────────────────────────────────────
  // Excellent for GH release and cardiovascular health but swimming
  // is INFERIOR to controls for bone density (BMD). High-volume
  // cycling is associated with low BMD. Both should COMPLEMENT
  // weight-bearing activity, not replace it.
  { id:'swimming',          tier:'cardio',        category:'cardio',       emoji:'🏊', displayName:'Swimming',
    note:'Excellent cardiovascular + GH stimulus. No osteogenic benefit — combine with weight-bearing (PMID 29199168)' },
  { id:'cycling',           tier:'cardio',        category:'cardio',       emoji:'🚲', displayName:'Cycling',
    note:'Good cardiovascular. High-volume cycling associated with low BMD — complement with weight-bearing' },

  // ── TIER 4 — FLEXIBILITY / DECOMPRESSION ─────────────────────
  // Bar hanging was previously listed as a growth activity. Evidence:
  // it is spinal DECOMPRESSION — beneficial for posture/disc health,
  // zero evidence for osteogenesis or GH/IGF-1 stimulation.
  { id:'yoga',              tier:'flexibility',   category:'flexibility',  emoji:'🧘', displayName:'Yoga (Growth Poses)',
    note:'Flexibility and recovery. Non-impact — not effective for bone density alone (AAOS position statement). However, specific spinal extension and axial loading poses (Cobra, Downward Dog, Cat-Cow, Tree) promote disc hydration, spinal elongation, and postural alignment that support growth-plate health.',
    citation:'AAOS position; yoga + spinal decompression mechanics (Howe et al. 2019 Complementary Therapies)' },
  { id:'stretching',        tier:'flexibility',   category:'flexibility',  emoji:'🤸', displayName:'Stretching' },
  { id:'bar_hanging',       tier:'flexibility',   category:'flexibility',  emoji:'🏋️', displayName:'Bar Hanging (Decompression)', presets:'small_min',
    note:'Static spinal decompression — beneficial for intervertebral disc hydration and lumbar posture. NOT osteogenic. Best performed after high-impact activity when discs are loaded.',
    citation:'McGill & Karpowicz, Spine 2009; spinal decompression mechanics' },
  { id:'walking',           tier:'lifestyle',     category:'lifestyle',    emoji:'🚶', displayName:'Walking',
    note:'Minimal osteogenic effect at normal pace. Good daily movement baseline.' },
];

// Tier display config — used by card render and browser
const ACTIVITY_TIER_CONFIG = {
  high_impact:   { label:'HIGH IMPACT',   shortLabel:'HIGH',   badgeCls:'act-tier-high',   weight:1.00 },
  weight_bearing:{ label:'WEIGHT-BEARING',shortLabel:'MEDIUM', badgeCls:'act-tier-medium', weight:0.65 },
  cardio:        { label:'CARDIO',        shortLabel:'CARDIO', badgeCls:'act-tier-cardio',  weight:0.35 },
  flexibility:   { label:'FLEXIBILITY',   shortLabel:'FLEX',   badgeCls:'act-tier-flex',    weight:0.15 },
  lifestyle:     { label:'LIFESTYLE',     shortLabel:'MOVE',   badgeCls:'act-tier-flex',    weight:0.15 },
};

// Personalized recommendations by activity + child age/sex.
// Shown in the log sheet below the tier badge.
// Based on ACSM guidelines, clinical study doses, and pediatric
// exercise physiology consensus (Turner loading principles).
const ACTIVITY_RECS = {
  'box_jumps':      (age, sex) => `${age < 10 ? 20 : age < 13 ? 40 : 60} reps/day · short burst, full recovery between reps`,
  'vertical_jumps': (age, sex) => `${age < 10 ? 20 : age < 13 ? 40 : 60} reps/day · same stimulus as box jumps`,
  'hopscotch':      (age, sex) => '30–50 reps · great osteogenic activity for younger children',
  'gymnastics':     (age, sex) => '45–60 min · 3× per week · highest osteogenic evidence of any sport',
  'basketball':     (age, sex) => '30–60 min · 3–5× per week · multi-directional impact, excellent for bone',
  'volleyball':     (age, sex) => '45–60 min · 3× per week · repeated vertical jumps are highly osteogenic',
  'football':       (age, sex) => '45–60 min · 3–5× per week · running + impact loading',
  'taekwondo':      (age, sex) => '45 min · 3× per week · significantly better bone outcomes than non-sport',
  'muay_thai':      (age, sex) => '45 min · 3× per week · impact + resistance combination',
  'judo':           (age, sex) => '45 min · 3× per week · throwing mechanics — multi-axis loading',
  'karate':         (age, sex) => '45 min · 3× per week · kata + sparring = varied osteogenic stimulus',
  'jump_rope':      (age, sex) => `${age < 10 ? 5 : age < 13 ? 10 : 15} min/day · interval style (30s on, 30s rest) maximises GH release`,
  'sprinting':      (age, sex) => '6–8 × 30m sprints · 3× per week · interval training > continuous for GH release',
  'dance':          (age, sex) => '30–60 min · 3× per week · multi-directional, high-impact load',
  'running':        (age, sex) => '20–30 min · 3–5× per week · aerobic base + weight-bearing stimulus',
  'tennis':         (age, sex) => '45–60 min · 2–3× per week · racket sports linked to better bone outcomes',
  'badminton':      (age, sex) => '30–45 min · 2–3× per week · good weight-bearing sport for Asian families',
  'trampoline':     (age, sex) => '15–20 min · lower peak ground force than floor jumping but still osteogenic',
  'indoor_climbing':(age, sex) => '30–45 min · 2–3× per week · full-body weight-bearing resistance',
  'monkey_bars':    (age, sex) => `${age < 10 ? '1–2' : '2–4'} min total · 3–5 traversals · rest between sets · grip strength + upper body weight-bearing`,
  'swimming':       (age, sex) => '20–30 min · good GH stimulus (large muscles) but ZERO bone benefit — pair with weight-bearing',
  'cycling':        (age, sex) => '20–30 min · cardiovascular health · no bone benefit · avoid high-volume to protect BMD',
  'yoga':           (age, sex) => `${age < 10 ? '10–15' : '15–20'} min · use the growth-specific poses below · Cobra → Downward Dog → Cat-Cow → Tree`,
  'bar_hanging':    (age, sex) => `${age < 10 ? '1–2' : '2–3'} min total · 3 sets of 20–30 sec each · rest fully between sets · best done AFTER impact activity`,
  'outdoor_play':   (age, sex) => '60+ min/day · if running and jumping involved, equivalent to high-impact · ☀️ Vitamin D synthesis bonus',
  'playground':     (age, sex) => '30–60 min · mix of climbing, running, jumping = excellent stimulus for this age',
  'walking':        (age, sex) => '30+ min/day · minimal bone stimulus but good daily movement baseline',
};

// Default card grid shown before the parent sets favourites
const DEFAULT_FAVOURITE_ACTIVITIES = [
  'basketball','box_jumps','jump_rope','football','swimming','yoga'
];

// ── end ACTIVITY_LIBRARY ──────────────────────────────────────────


const APP = {
  session: null,        // Supabase auth session
  account: null,         // row from user_accounts: { user_id, email, account_role, ... }
  children: [],          // rows from `children`, scoped by RLS to what this user can see
  activeChild: 0,
  dayStateByChild: {},   // in-memory draft of the Today form per child, before save
  weekStreakByChild: {}, // in-memory only today; not yet reloaded from DB on boot — see loadWeekStreak() TODO
  signupRole: 'parent_subscriber',
  logDate: todayISO(),    // which date the Today screen is currently editing — defaults to today, changeable via the date selector
  nutritionLogItems: [],  // nutrition_log_items rows for the active child + logDate, loaded fresh on date/child change
  activeMealSlot: 'breakfast', // which meal new food-card taps get tagged with; defaults to breakfast each load (see setMealSlot)
  referenceStandard: 'who', // 'who' or 'thai' — which growth chart reference is displayed; see setReferenceStandard()
  chartZoom: 'auto', // 'auto' (zoomed to current age, existing behavior) or 'full' (always shows 0-19y) — see setChartZoom()
  labResults: [],    // lab_results rows for the active child, loaded when the Medical tab opens
  language: 'en',    // active UI language — 'en' | 'th' | 'zh', saved to localStorage
  todayActivityItems: [],   // daily_activity_items for today — loaded on tab switch + after logging
  favoriteActivities: null, // Set of activity_ids starred for active child; null = use defaults
  customActivities: [],     // custom_activities rows for this parent account
  pubertyEvents: [], // puberty_events rows for the active child, loaded when the Medical tab opens
  illnessEvents: [], // illness_events rows for the active child, loaded when the Medical tab opens
  foodFavorites: [], // food_favorites rows for the active child — determines which cards show on the Nutrition grid
  customFoods: [], // custom_foods rows for the active child — parent-defined foods with manually-entered values
  boneAgeAssessments: [], // bone_age_assessments rows for the active child
  familyHeightRecords: [], // family_height_records rows - reference only by default; see targetHeightFormula
  targetHeightFormula: 'parents', // 'parents' (validated, default) or 'extended' (exploratory) — see setTargetHeightFormula()
  aiChatHistory: [], // [{role:'user'|'assistant', content:'...'}] for the active child's AI coach conversation — reset on child switch, see askClaude()
  aiCoachMode: null // 'template' or 'live_ai', loaded once from system_settings via getAICoachMode() and cached for the session
};

function todayISO() {
  return new Date().toISOString().split('T')[0];
}

// Produces the right save-button label depending on whether the
// currently-selected log date is today or a backdated entry.
function saveButtonLabel(savedAlready) {
  const isToday = APP.logDate === todayISO();
  if (savedAlready) return 'Saved — tap to update';
  return isToday ? "Save today's data" : 'Save entry for ' + APP.logDate;
}

function currentState() {
  if (!APP.dayStateByChild[APP.activeChild]) {
    APP.dayStateByChild[APP.activeChild] = { ...DEFAULT_DAY_STATE };
  }
  return APP.dayStateByChild[APP.activeChild];
}

function currentStreak() {
  if (!APP.weekStreakByChild[APP.activeChild]) {
    APP.weekStreakByChild[APP.activeChild] = [0,0,0,0,0,0,0];
  }
  return APP.weekStreakByChild[APP.activeChild];
}

function activeChildId() {
  const c = APP.children[APP.activeChild];
  return c ? c.child_id : null;
}

function isClinicianRole() {
  return APP.account && (APP.account.account_role === 'doctor' || APP.account.account_role === 'scientist');
}

function isSystemAdmin() {
  return APP.account && APP.account.account_role === 'system_admin';
}

// The full admin dashboard (user list, tier management, archived data,
// audit log, AI mode toggle) used to live here, embedded in this file.
// It's been moved to its own standalone bundle — admin.html, admin.css,
// admin.js — confirmed working live, so the embedded copy was removed
// rather than maintained as a second, divergence-prone version of the
// same thing. See FORMULAS.md §6f for the full reasoning. isSystemAdmin()
// itself stays here, since it still gates the small "manage at
// admin.html" link in Account & Settings (see openSetup()/index.html).

// ══════════════════════════════════════════
// BOOT — gated on auth session
// ══════════════════════════════════════════
window.addEventListener('DOMContentLoaded', async () => {
  // Load locale files and restore language preference FIRST,
  // before any UI renders, so the correct language is applied
  // from the very first paint.
  await loadLocales();
  restoreLanguagePreference();

  const { data } = await sb.auth.getSession();
  if (data.session) {
    await enterApp(data.session);
    applyI18n(); // update all data-i18n elements to active language
    await handleGoogleHealthOAuthCallback();
  } else {
    showAuthScreen();
  }

  sb.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT') {
      showAuthScreen();
    }
  });

  document.getElementById('logDate').valueAsDate = new Date();
  document.getElementById('newPubertyDate').valueAsDate = new Date();
});

// ══════════════════════════════════════════════════════════════════
// GOOGLE HEALTH API (FITBIT) INTEGRATION
// OAuth 2.0 flow + sleep sync via google-health-auth and
// google-health-sync Edge Functions.
// ══════════════════════════════════════════════════════════════════

const GOOGLE_HEALTH_CLIENT_ID = '703084084864-g9vctf4sfaufjdqklmq4a11qsi3epk48.apps.googleusercontent.com';
const GOOGLE_HEALTH_REDIRECT_URI = 'https://www.growsense.life/webapp.html';
const GOOGLE_HEALTH_SCOPES = [
  'openid',
  'email',
  'https://www.googleapis.com/auth/googlehealth.sleep.readonly'
].join(' ');

// ── Start the OAuth flow ─────────────────────────────────────────
// Called when the user taps "Connect Fitbit" in child settings.
// Saves child_id + CSRF token to sessionStorage, then redirects to
// Google's consent screen.
function initiateGoogleHealthOAuth(childId) {
  const csrf = crypto.randomUUID();
  sessionStorage.setItem('gh_csrf', csrf);
  sessionStorage.setItem('gh_child_id', childId);

  const params = new URLSearchParams({
    client_id: GOOGLE_HEALTH_CLIENT_ID,
    redirect_uri: GOOGLE_HEALTH_REDIRECT_URI,
    response_type: 'code',
    scope: GOOGLE_HEALTH_SCOPES,
    access_type: 'offline',   // required for refresh_token
    prompt: 'consent',        // always get a fresh refresh_token
    state: `${childId}:${csrf}`
  });

  window.location.href = `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}

// ── Handle the OAuth callback ────────────────────────────────────
// Runs on every page load. Does nothing unless ?code= is in the URL.
async function handleGoogleHealthOAuthCallback() {
  const params = new URLSearchParams(window.location.search);
  const code   = params.get('code');
  const state  = params.get('state');
  const error  = params.get('error');

  if (!code && !error) return; // not an OAuth callback

  // Clean up URL immediately so a page refresh doesn't replay the code
  window.history.replaceState({}, document.title, window.location.pathname);

  if (error) {
    showToast('⚠️', `Fitbit connection cancelled: ${error}`);
    return;
  }

  // Parse child_id from state — format is "{childId}:{csrfToken}"
  const colonIdx = (state || '').indexOf(':');
  const childId  = colonIdx > 0 ? state.slice(0, colonIdx) : state;
  const csrfFromState = colonIdx > 0 ? state.slice(colonIdx + 1) : '';

  // UUID format sanity check on the childId
  const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!childId || !uuidRe.test(childId)) {
    showToast('⚠️', 'Connection failed: invalid state parameter.');
    return;
  }

  // CSRF check — best-effort only.
  // Some browsers (Edge Tracking Prevention, Safari ITP) block
  // sessionStorage access when the page loads from a cross-site
  // redirect, so storedCsrf may be null even when the flow is
  // legitimate. The server enforces real security: it verifies the
  // session JWT and confirms child ownership before doing anything.
  try {
    const storedCsrf    = sessionStorage.getItem('gh_csrf');
    const storedChildId = sessionStorage.getItem('gh_child_id');
    sessionStorage.removeItem('gh_csrf');
    sessionStorage.removeItem('gh_child_id');

    if (storedCsrf && csrfFromState !== storedCsrf) {
      console.warn('[Google Health] CSRF token mismatch — aborting');
      showToast('⚠️', 'Connection failed: security check error. Please try again.');
      return;
    }
    if (storedChildId && childId !== storedChildId) {
      console.warn('[Google Health] Child ID mismatch in state');
      showToast('⚠️', 'Connection failed: child mismatch. Please try again.');
      return;
    }
    if (!storedCsrf) {
      console.warn('[Google Health] sessionStorage unavailable (browser privacy mode or tracking prevention) — skipping CSRF, relying on server-side validation');
    }
  } catch (storageErr) {
    console.warn('[Google Health] sessionStorage blocked:', storageErr);
    // Continue — server will validate JWT + child ownership
  }

  if (!APP.session) {
    showToast('⚠️', 'Please sign in before connecting Fitbit.');
    return;
  }

  showToast('🔄', t('toast.connecting_fitbit','Connecting Fitbit…'));

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/google-health-auth`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${APP.session.access_token}`
      },
      // redirect_uri must match the one used to start the OAuth flow so
      // the Edge Function's token exchange doesn't hit redirect_uri_mismatch.
      body: JSON.stringify({ code, child_id: childId, redirect_uri: GOOGLE_HEALTH_REDIRECT_URI })
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Connection failed');

    // ── Wearable email mismatch check ────────────────────────────
    // If the parent pre-declared a wearable email for this child
    // and the connected account doesn't match, warn them.
    // Only fires on mismatch — no notice shown when matched or blank.
    const child = APP.children.find(c => c.child_id === childId);
    const expected  = (child?.wearable_account_email || '').toLowerCase().trim();
    const connected = (data.google_email || '').toLowerCase().trim();

    if (expected && connected && expected !== connected) {
      const proceed = confirm(
        `⚠️  Fitbit account mismatch for ${child?.name || 'this child'}\n\n` +
        `Expected:  ${child.wearable_account_email}\n` +
        `Connected: ${data.google_email}\n\n` +
        `This might be the wrong Fitbit device.\n` +
        `Connect anyway?`
      );
      if (!proceed) {
        // Remove the just-created connection so the DB stays clean
        await sb.from('google_health_connections').delete().eq('child_id', childId);
        showToast('⚠️', 'Connection cancelled. Check the Fitbit account and try again.');
        return;
      }
    };

    showToast('✅', `${t('toast.fitbit_connected','Fitbit connected')} (${data.google_email})`);

    if (!APP.googleHealthConnections) APP.googleHealthConnections = {};
    APP.googleHealthConnections[childId] = data.connection;
    renderGoogleHealthConnectionStatus(childId);

    // Trigger first sync — pull the last 14 nights immediately
    await syncGoogleHealthSleep(childId, 14);

  } catch (e) {
    console.error('[Google Health Auth]', e);
    showToast('⚠️', t('toast.error.fitbit_failed','Fitbit connection failed') + ': ' + e.message);
  }
}

// ── Load connection status from DB ───────────────────────────────
async function loadGoogleHealthConnections() {
  if (!APP.session || !activeChildId()) return;
  const childId = activeChildId();

  const { data } = await sb
    .from('google_health_connection_status')  // safe view (no tokens)
    .select('*')
    .eq('child_id', childId)
    .maybeSingle();

  if (!APP.googleHealthConnections) APP.googleHealthConnections = {};
  APP.googleHealthConnections[childId] = data || null;
  renderGoogleHealthConnectionStatus(childId);
}

// ── Render the Connect/Sync button in the UI ─────────────────────
function renderGoogleHealthConnectionStatus(childId) {
  const btn = document.getElementById('fitbitConnectBtn');
  if (!btn) return;

  const conn = APP.googleHealthConnections?.[childId];

  if (!conn) {
    btn.innerHTML = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 16.92v3a2 2 0 01-2.18 2 19.79 19.79 0 01-8.63-3.07A19.5 19.5 0 013.07 8.8a19.79 19.79 0 01-3.07-8.6A2 2 0 012 0h3a2 2 0 012 1.72c.127.96.361 1.903.7 2.81a2 2 0 01-.45 2.11L6.09 7.91a16 16 0 006 6l1.27-1.27a2 2 0 012.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0122 14z"/></svg> Connect Fitbit`;
    btn.className = 'btn-secondary';
    btn.onclick = () => initiateGoogleHealthOAuth(childId);
    return;
  }

  // Connected — show sync button with last sync time
  const lastSync = conn.last_sync_at
    ? new Date(conn.last_sync_at).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })
    : 'never';
  const statusColor = conn.last_sync_status === 'error' ? 'var(--flag)' : 'var(--accent)';

  btn.innerHTML = `<span style="color:${statusColor};">●</span> Fitbit synced ${lastSync} &nbsp;·&nbsp; Sync now`;
  btn.className = 'btn-secondary';
  btn.onclick = () => syncGoogleHealthSleep(childId, 7);
}

// ── Sync sleep data ───────────────────────────────────────────────
async function syncGoogleHealthSleep(childId, daysBack = 7) {
  if (!APP.session) return;

  const btn = document.getElementById('fitbitConnectBtn');
  if (btn) { btn.textContent = '⏳ Syncing…'; btn.disabled = true; }

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/google-health-sync`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${APP.session.access_token}`
      },
      body: JSON.stringify({ child_id: childId, days_back: daysBack })
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Sync failed');

    showToast('✅', `${data.nights_synced} ${t('toast.nights_synced','nights synced from Fitbit')}`);

    // Refresh connection status (updates last_sync_at)
    await loadGoogleHealthConnections();

    // If Today is visible, reload so the synced sleep values appear
    const todayActive = document.getElementById('screenToday')?.classList.contains('active');
    if (todayActive && typeof loadTodayLog === 'function') await loadTodayLog();

  } catch (e) {
    console.error('[Google Health Sync]', e);
    showToast('⚠️', t('toast.error.sync_failed','Sync failed') + ': ' + e.message);
    if (btn) { btn.disabled = false; renderGoogleHealthConnectionStatus(childId); }
  }
}

// ── Disconnect ────────────────────────────────────────────────────
async function disconnectGoogleHealth(childId) {
  if (!confirm(t('confirm.disconnect_fitbit','Disconnect Fitbit? Sleep data already synced will remain.'))) return;

  await sb.from('google_health_connections').delete().eq('child_id', childId);

  if (APP.googleHealthConnections) APP.googleHealthConnections[childId] = null;
  renderGoogleHealthConnectionStatus(childId);
  showToast('✅', t('toast.fitbit_disconnected','Fitbit disconnected'));
}

// ══════════════════════════════════════════════════════════════════
// end Google Health integration
// ══════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════
// CLINIC PDF EXPORT
// Opens a print-ready HTML page in a new window then triggers the
// browser print dialog. User selects "Save as PDF" (all platforms)
// or "Save to Files" on iPhone. No server, no library — charts are
// captured from the existing canvas elements via toDataURL().
// ══════════════════════════════════════════════════════════════════

async function generateClinicPDF() {
  const child = APP.children[APP.activeChild];
  if (!child) { showToast('⚠️', t('toast.error.no_child','No child selected')); return; }

  showToast('🔄', t('toast.building_report','Building clinic report…'));

  // ── Capture chart images ───────────────────────────────────────
  // Charts are rendered when Analytics tab is open.
  // If not yet rendered (zero width), trigger them first.
  const growthCanvas = document.getElementById('growthCanvas');
  const bmiCanvas    = document.getElementById('bmiChartCanvas');
  if (growthCanvas && !growthCanvas.width) {
    drawGrowthChart();
    drawBMIChart();
    await new Promise(r => setTimeout(r, 350));
  }
  const growthImg = growthCanvas?.toDataURL?.('image/png') || '';
  const bmiImg    = bmiCanvas?.toDataURL?.('image/png') || '';

  // ── Measurements (newest first) ───────────────────────────────
  const meas = (APP.activeChildMeasurements || [])
    .slice().sort((a,b) => new Date(b.recorded_date) - new Date(a.recorded_date));
  const latest = meas[0] || null;

  // ── Height velocity ────────────────────────────────────────────
  let velocityCmYr = null;
  const measAsc = [...meas].reverse();
  if (measAsc.length >= 2) {
    const n = measAsc[measAsc.length-1], o = measAsc[0];
    const days = (new Date(n.recorded_date) - new Date(o.recorded_date)) / 86400000;
    if (days > 0) velocityCmYr = ((Number(n.stature_height_cm) - Number(o.stature_height_cm)) / days * 365.25).toFixed(1);
  }

  // ── 30-day averages (require Analytics tab to have been opened) ─
  const nut30 = filterByPeriod(APP.nutritionHistory || [], 'M');
  const slp30 = filterByPeriod(APP.sleepHistory     || [], 'M');

  const avg = (arr, key) => arr.length ? Math.round(arr.reduce((a,r)=>a+(r[key]||0),0)/arr.length) : null;

  const avgProtein  = avg(nut30, 'total_protein_g');
  const avgCalcium  = avg(nut30, 'calcium_mg');
  const avgSleepMin = avg(slp30, 'total_sleep_min');
  const slpDeep     = slp30.filter(r => r.deep_sleep_min != null);
  const avgDeepMin  = slpDeep.length ? Math.round(slpDeep.reduce((a,r)=>a+(r.deep_sleep_min||0),0)/slpDeep.length) : null;
  const fitbitNights = slp30.filter(r => r.data_source === 'google_health_fitbit').length;

  const onTimeNights = slp30.filter(r => {
    if (!r.bedtime) return false;
    const [h,m] = r.bedtime.split(':').map(Number);
    return h < 21 || (h === 21 && m <= 30);
  }).length;

  // Average bedtime
  const avgBedtime = (() => {
    const beds = slp30.map(r=>r.bedtime).filter(Boolean).map(t => {
      const [h,m] = t.split(':').map(Number);
      return h < 12 ? h*60+m+1440 : h*60+m;
    });
    if (!beds.length) return null;
    const a = Math.round(beds.reduce((s,b)=>s+b,0)/beds.length) % 1440;
    return `${String(Math.floor(a/60)).padStart(2,'0')}:${String(a%60).padStart(2,'0')}`;
  })();

  // ── Bone age (most recent) ─────────────────────────────────────
  const { data: boneAgeData } = await sb
    .from('bone_age_assessments')
    .select('*')
    .eq('child_id', child.child_id)
    .order('study_date', { ascending: false })
    .limit(1);
  const boneAge = boneAgeData?.[0] || null;

  // ── Protein targets ────────────────────────────────────────────
  const { standard: proteinStd, boost: proteinBoost } = activeChildProteinTargets();

  // ── Build and open ─────────────────────────────────────────────
  const html = buildClinicReportHTML({
    child, meas, latest, velocityCmYr,
    avgProtein, avgCalcium, proteinStd, proteinBoost,
    avgSleepMin, avgDeepMin, avgBedtime, onTimeNights,
    nut30Days: nut30.length, slp30Days: slp30.length, fitbitNights,
    boneAge,
    labResults: (APP.labResults || []).slice(0, 15),
    growthImg, bmiImg,
    exportDate: new Date().toLocaleDateString('en-GB', {day:'numeric', month:'long', year:'numeric'}),
  });

  const win = window.open('', '_blank');
  if (!win) { showToast('⚠️', t('toast.error.popup_blocked','Pop-up blocked — allow pop-ups for this site and try again')); return; }
  win.document.write(html);
  win.document.close();
  win.focus();
  setTimeout(() => { try { win.print(); } catch(e) {} }, 700);
}

function buildClinicReportHTML(d) {
  const {
    child, meas, latest, velocityCmYr,
    avgProtein, avgCalcium, proteinStd, proteinBoost,
    avgSleepMin, avgDeepMin, avgBedtime, onTimeNights,
    nut30Days, slp30Days, fitbitNights,
    boneAge, labResults, growthImg, bmiImg, exportDate,
  } = d;

  // Design token hex values (same as the app's CSS custom properties)
  const G = '#2F6B4F', B = '#2A5C8A', A = '#9C7A3D', R = '#A23B3B';
  const T = '#1F2B22', T2 = '#4A5E4D', T3 = '#95A092';
  const BDR = '#D5DDD6', BG2 = '#F4F7F4';

  const fmtDate = s => s
    ? new Date(s+'T00:00:00').toLocaleDateString('en-GB', {day:'numeric', month:'short', year:'numeric'})
    : '—';
  const fmtMin  = m => m ? `${Math.floor(m/60)}h ${m%60}m` : '—';
  const fmtBA   = mo => {
    if (mo == null) return '—';
    const y = Math.floor(mo/12), rem = Math.round(mo%12);
    return rem > 0 ? `${y}y ${rem}m` : `${y}y`;
  };

  const ageYears  = child.date_of_birth ? Math.floor((Date.now()-new Date(child.date_of_birth))/(365.25*86400000)) : null;
  const ageMos    = child.date_of_birth ? Math.floor((Date.now()-new Date(child.date_of_birth))/(30.4375*86400000))%12 : null;
  const ageStr    = ageYears != null ? `${ageYears} years ${ageMos} months` : '—';

  // Measurement history rows
  const measRows = meas.slice(0,8).map(m => `<tr>
    <td style="padding:5px 8px;border:1px solid ${BDR};">${fmtDate(m.recorded_date)}</td>
    <td style="padding:5px 8px;border:1px solid ${BDR};font-weight:600;">${Number(m.stature_height_cm).toFixed(1)}</td>
    <td style="padding:5px 8px;border:1px solid ${BDR};">${Number(m.mass_weight_kg).toFixed(1)}</td>
    <td style="padding:5px 8px;border:1px solid ${BDR};">${m.calculated_bmi!=null?Number(m.calculated_bmi).toFixed(1):'—'}</td>
  </tr>`).join('');

  // Lab result rows
  const labRows = labResults.length
    ? labResults.map(r => `<tr>
        <td style="padding:5px 8px;border:1px solid ${BDR};">${fmtDate(r.lab_date)}</td>
        <td style="padding:5px 8px;border:1px solid ${BDR};">${r.analyte_name}</td>
        <td style="padding:5px 8px;border:1px solid ${BDR};font-weight:600;">${r.result_value} ${r.unit}</td>
        <td style="padding:5px 8px;border:1px solid ${BDR};color:${T3};">${r.reference_low!=null&&r.reference_high!=null?`${r.reference_low}–${r.reference_high} ${r.unit}`:'—'}</td>
      </tr>`).join('')
    : `<tr><td colspan="4" style="padding:12px;text-align:center;color:${T3};border:1px solid ${BDR};">No lab results recorded</td></tr>`;

  // Bone age section
  const boneAgeHTML = !boneAge ? '' : (() => {
    const delta = boneAge.bone_age_months!=null && boneAge.chronological_age_months!=null
      ? (boneAge.bone_age_months - boneAge.chronological_age_months).toFixed(1) : null;
    const dColor = delta && Math.abs(Number(delta)) > 12 ? R : A;
    const aiEst  = boneAge.ai_analysis_result?.bone_age_estimate?.best_estimate_months;
    return `
    <div style="margin-bottom:20px;">
      <div style="font-size:11pt;font-weight:700;color:${A};border-left:3px solid ${A};padding-left:10px;margin-bottom:10px;text-transform:uppercase;letter-spacing:.5px;">Bone Age Assessment</div>
      <table style="font-size:9pt;">
        <thead><tr style="background:${BG2};">
          <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Study date</th>
          <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Bone age</th>
          <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Chronological age</th>
          <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Delta</th>
          <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Method / Radiologist</th>
          ${aiEst ? `<th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">AI second opinion</th>` : ''}
        </tr></thead>
        <tbody><tr>
          <td style="padding:6px 8px;border:1px solid ${BDR};">${fmtDate(boneAge.study_date)}</td>
          <td style="padding:6px 8px;border:1px solid ${BDR};font-weight:700;">${fmtBA(boneAge.bone_age_months)}</td>
          <td style="padding:6px 8px;border:1px solid ${BDR};">${fmtBA(boneAge.chronological_age_months)}</td>
          <td style="padding:6px 8px;border:1px solid ${BDR};font-weight:700;color:${dColor};">${delta!=null?(Number(delta)>=0?'+':'')+delta+' mo':'—'}</td>
          <td style="padding:6px 8px;border:1px solid ${BDR};">${boneAge.method||'—'}${boneAge.report_doctor?' · '+boneAge.report_doctor:''}</td>
          ${aiEst ? `<td style="padding:6px 8px;border:1px solid ${BDR};color:${B};">${fmtBA(aiEst)} (AI · Claude Vision)</td>` : ''}
        </tr></tbody>
      </table>
    </div>`;
  })();

  // Section header helper
  const sh = (label, color) =>
    `<div style="font-size:11pt;font-weight:700;color:${color};border-left:3px solid ${color};padding-left:10px;margin-bottom:10px;text-transform:uppercase;letter-spacing:.5px;">${label}</div>`;

  // Stat box helper
  const sb2 = (label, value, sub) =>
    `<div style="background:${BG2};border-radius:6px;padding:10px;">
      <div style="font-size:9pt;color:${T3};margin-bottom:2px;">${label}</div>
      <div style="font-size:16pt;font-weight:700;color:${T};">${value}</div>
      ${sub ? `<div style="font-size:9pt;color:${T3};margin-top:2px;">${sub}</div>` : ''}
    </div>`;

  return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<title>GrowSense Clinic Report — ${child.name} — ${exportDate}</title>
<style>
*{box-sizing:border-box;margin:0;padding:0;}
body{font-family:-apple-system,'Helvetica Neue',Arial,sans-serif;font-size:10pt;color:${T};background:#fff;padding:28px 36px;max-width:820px;margin:0 auto;line-height:1.4;}
table{border-collapse:collapse;width:100%;}
th,td{text-align:left;vertical-align:top;}
img{max-width:100%;display:block;}
.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:12px;}
.grid4{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:12px;}
.grid2{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin-bottom:12px;}
.section{margin-bottom:22px;}
@media print{
  body{padding:0;max-width:100%;}
  .no-print{display:none!important;}
  .pg-break{page-break-before:always;}
  @page{margin:16mm 14mm;}
}
</style>
</head><body>

<div class="no-print" style="margin-bottom:20px;display:flex;align-items:center;gap:12px;">
  <button onclick="window.print()" style="background:${G};color:#fff;border:none;padding:10px 22px;border-radius:8px;font-size:12pt;cursor:pointer;font-weight:700;">↓ Save as PDF</button>
  <span style="font-size:10pt;color:${T3};">File → Print → Save as PDF &nbsp;(or Share → Print on iPhone)</span>
</div>

<!-- HEADER -->
<div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:20px;padding-bottom:14px;border-bottom:2.5px solid ${G};">
  <div>
    <div style="font-size:20pt;font-weight:800;color:${G};letter-spacing:-.5px;">GrowSense</div>
    <div style="font-size:9pt;color:${T3};margin-top:2px;">Pediatric Growth Intelligence Report</div>
  </div>
  <div style="text-align:right;">
    <div style="font-size:9pt;color:${T3};">Generated</div>
    <div style="font-size:10pt;font-weight:600;">${exportDate}</div>
    <div style="font-size:8pt;color:${T3};margin-top:6px;max-width:190px;line-height:1.4;">Educational reference only.<br>Not a clinical diagnosis.</div>
  </div>
</div>

<!-- PATIENT -->
<div style="background:${BG2};border-radius:8px;padding:14px;margin-bottom:22px;" class="grid3">
  <div>
    <div style="font-size:9pt;color:${T3};margin-bottom:2px;">Patient</div>
    <div style="font-size:16pt;font-weight:800;">${child.name}</div>
  </div>
  <div>
    <div style="font-size:9pt;color:${T3};margin-bottom:2px;">Age</div>
    <div style="font-size:13pt;font-weight:700;">${ageStr}</div>
    <div style="font-size:9pt;color:${T2};">Born ${fmtDate(child.date_of_birth)}</div>
  </div>
  <div>
    <div style="font-size:9pt;color:${T3};margin-bottom:2px;">Sex</div>
    <div style="font-size:13pt;font-weight:700;">${child.biological_sex==='male'?'Male':child.biological_sex==='female'?'Female':'—'}</div>
  </div>
</div>

<!-- MEASUREMENTS -->
<div class="section">
  ${sh('Current Measurements', G)}
  ${latest ? `
  <div class="grid4">
    ${sb2('Height', Number(latest.stature_height_cm).toFixed(1)+' cm', fmtDate(latest.recorded_date))}
    ${sb2('Weight', Number(latest.mass_weight_kg).toFixed(1)+' kg', '')}
    ${sb2('BMI', latest.calculated_bmi!=null?Number(latest.calculated_bmi).toFixed(1)+' kg/m²':'—', 'WHO 2007 reference')}
    ${sb2('Height velocity', (velocityCmYr||'—')+' cm/yr', 'annualised from measurements')}
  </div>` : `<div style="color:${T3};padding:10px;">No measurements recorded yet.</div>`}
  ${meas.length ? `
  <table style="font-size:9pt;">
    <thead><tr style="background:${BG2};">
      <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Date</th>
      <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Height (cm)</th>
      <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Weight (kg)</th>
      <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">BMI</th>
    </tr></thead>
    <tbody>${measRows}</tbody>
  </table>` : ''}
</div>

<!-- CHARTS -->
${growthImg ? `
<div class="section">
  ${sh('Height-for-Age (WHO 2007 Reference)', B)}
  <img src="${growthImg}" style="border:1px solid ${BDR};border-radius:6px;width:100%;">
  <div style="font-size:8pt;color:${T3};margin-top:4px;">Shaded bands: WHO 2007 percentile channels (3rd–97th, 15th–85th). Blue line: measured. Dashed: projected trajectory.</div>
</div>` : ''}

${bmiImg ? `
<div class="section pg-break">
  ${sh('BMI-for-Age (WHO 2007 Reference)', B)}
  <img src="${bmiImg}" style="border:1px solid ${BDR};border-radius:6px;width:100%;">
  <div style="font-size:8pt;color:${T3};margin-top:4px;">Amber dashed: +1SD overweight cutoff. Red dashed: +2SD obesity cutoff. Screening signal only — not a diagnosis.</div>
</div>` : ''}

<!-- BONE AGE -->
${boneAgeHTML}

<!-- SLEEP -->
${slp30Days > 0 ? `
<div class="section">
  ${sh(`Sleep — ${slp30Days}-day summary${fitbitNights>0?` (${fitbitNights} nights Fitbit Charge 6)`:', manual'}`, B)}
  <div class="grid3">
    ${sb2('Avg duration', fmtMin(avgSleepMin), 'Goal: 9h 30m')}
    ${sb2('Avg deep sleep', avgDeepMin!=null?avgDeepMin+' min':'—', 'GH secretion proxy')}
    ${sb2('GH window (≤21:30)', `${onTimeNights} / ${slp30Days} nights`, 'Avg bedtime: '+(avgBedtime||'—'))}
  </div>
</div>` : ''}

<!-- NUTRITION -->
${nut30Days > 0 ? `
<div class="section">
  ${sh(`Nutrition — ${nut30Days}-day average`, G)}
  <div class="grid2">
    ${sb2('Protein avg', (avgProtein!=null?avgProtein+'g':'—')+' / day',
      `Standard (WHO/DRI): ${proteinStd}g &nbsp;·&nbsp; Growth target: ${proteinBoost}g`)}
    ${sb2('Calcium avg', (avgCalcium!=null?avgCalcium+'mg':'—')+' / day', 'Target: 1,300mg')}
  </div>
</div>` : ''}

<!-- LAB RESULTS -->
<div class="section">
  ${sh('Laboratory Results', A)}
  <table style="font-size:9pt;">
    <thead><tr style="background:${BG2};">
      <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Date</th>
      <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Analyte</th>
      <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Result</th>
      <th style="padding:6px 8px;border:1px solid ${BDR};color:${T3};font-weight:600;">Reference range</th>
    </tr></thead>
    <tbody>${labRows}</tbody>
  </table>
</div>

<!-- DISCLAIMER -->
<div style="background:#FFFBF0;border:1px solid ${A};border-radius:8px;padding:12px;margin-top:20px;">
  <div style="font-size:9pt;font-weight:700;color:${A};margin-bottom:5px;">⚕️ Clinical disclaimer</div>
  <div style="font-size:8.5pt;color:${T2};line-height:1.5;">
    This report is generated by GrowSense for informational and educational purposes only. It is not a medical record, clinical diagnosis, or substitute for professional medical advice. Growth charts use the WHO 2007 Growth Reference (5–19 years) and WHO Child Growth Standards (0–5 years). Protein targets reference IOM 2005 DRI (Table 10-21) with growth-optimized adjustment based on IAAO methodology (Hudson et al., <em>Nutrients</em> 2021, PMID 34063030). Sleep staging from Fitbit Charge 6 via Google Health API where indicated. All clinical decisions must be made by a qualified pediatrician or pediatric endocrinologist.
  </div>
</div>

<!-- FOOTER -->
<div style="margin-top:14px;padding-top:10px;border-top:1px solid ${BDR};display:flex;justify-content:space-between;font-size:8pt;color:${T3};">
  <span>GrowSense · growsense.life</span>
  <span>Generated ${exportDate}</span>
</div>

</body></html>`;
}

// ══════════════════════════════════════════════════════════════════
// end clinic PDF export
// ══════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════
// ACTIVITY LIBRARY — load, save, render, browser
// ══════════════════════════════════════════════════════════════════

// ── Score calculation ─────────────────────────────────────────────
// Called by updateHUD(). Reads APP.todayActivityItems.
// Returns 0.0–1.0 where 1.0 = 60 min of high-impact equivalent.
function calcActivityScore() {
  const items = APP.todayActivityItems || [];
  if (!items.length) return 0;
  const TARGET_MIN = 60; // 60 min high-impact = 100%
  const weighted = items.reduce((sum, item) => {
    const w = (ACTIVITY_TIER_CONFIG[item.tier] || ACTIVITY_TIER_CONFIG.lifestyle).weight;
    return sum + item.duration_min * w;
  }, 0);
  return Math.min(weighted / TARGET_MIN, 1.0);
}

// ── Load today's activity items ───────────────────────────────────
async function loadTodayActivityItems() {
  if (!activeChildId() || !APP.session) return;
  const { data, error } = await sb
    .from('daily_activity_items')
    .select('*')
    .eq('child_id', activeChildId())
    .eq('log_date', APP.logDate)
    .order('created_at', { ascending: true });
  if (error) { console.error('[Activity]', error); return; }
  APP.todayActivityItems = data || [];
  renderActivityLoggedItems();
  updateHUD();
}

// ── Load favourite activity IDs for active child ──────────────────
async function loadFavouriteActivities() {
  if (!activeChildId() || !APP.session) return;
  const { data } = await sb
    .from('favorite_activities')
    .select('activity_id')
    .eq('child_id', activeChildId());
  if (!data || data.length === 0) {
    APP.favoriteActivities = null; // null = show defaults
  } else {
    APP.favoriteActivities = new Set(data.map(r => r.activity_id));
  }
  renderActivityCards();
}

// ── Load parent's custom activities ──────────────────────────────
async function loadCustomActivities() {
  if (!APP.session) return;
  const { data } = await sb
    .from('custom_activities')
    .select('*')
    .eq('parent_id', APP.session.user.id);
  APP.customActivities = data || [];
}

// ── Helper: all activities (library + custom) ─────────────────────
function allActivities() {
  const custom = (APP.customActivities || []).map(c => ({
    id: c.activity_id, tier: c.tier, category: c.category || 'custom',
    emoji: c.emoji || '⭐', displayName: c.display_name, isCustom: true,
  }));
  return [...ACTIVITY_LIBRARY, ...custom];
}

// ── Render the card grid on Today tab ─────────────────────────────
function renderActivityCards() {
  const grid = document.getElementById('activityCardGrid');
  if (!grid) return;
  const fav = APP.favoriteActivities;
  const acts = allActivities();
  // Use defaults if: no favourites set (null) OR empty set
  const useDefaults = !fav || fav.size === 0;
  const shown = useDefaults
    ? acts.filter(a => DEFAULT_FAVOURITE_ACTIVITIES.includes(a.id))
    : acts.filter(a => fav.has(a.id));
  // Safety: if filter produced nothing, fall back to defaults
  const final = shown.length > 0
    ? shown
    : acts.filter(a => DEFAULT_FAVOURITE_ACTIVITIES.includes(a.id));
  grid.innerHTML = final.map(a => {
    const tc = ACTIVITY_TIER_CONFIG[a.tier] || ACTIVITY_TIER_CONFIG.lifestyle;
    return `<div class="activity-card" onclick="openActivityLogSheet('${a.id}')">
      <div class="activity-card-emoji">${a.emoji}</div>
      <div class="activity-card-name">${a.displayName}</div>
      <span class="act-tier-badge ${tc.badgeCls}">${tc.shortLabel}</span>
    </div>`;
  }).join('');
}

// ── Render logged-today list ──────────────────────────────────────
function renderActivityLoggedItems() {
  const list = document.getElementById('activityLoggedList');
  const section = document.getElementById('activityLoggedSection');
  if (!list || !section) return;
  const items = APP.todayActivityItems || [];
  section.classList.toggle('hidden', items.length === 0);
  list.innerHTML = items.map(item => {
    const tc = ACTIVITY_TIER_CONFIG[item.tier] || ACTIVITY_TIER_CONFIG.lifestyle;
    // Display label — use stored unit if available, else fall back to minutes
    let dLabel;
    const unit = item.unit || 'min';
    const val  = item.duration_value || Math.round(item.duration_min);
    if (unit === 'reps')     dLabel = `${val} reps`;
    else if (unit === 'sec') dLabel = val < 60 ? `${val}s` : `${Math.round(val/60)}min`;
    else                     dLabel = `${val} min`;
    const outdoorIcon = item.is_outdoor ? ' ☀️' : '';
    return `<div class="activity-log-item">
      <div class="activity-log-info">
        <span>${item.display_name}</span>
        <span class="act-tier-badge ${tc.badgeCls}">${dLabel}${outdoorIcon}</span>
      </div>
      <button class="activity-log-remove" onclick="removeActivityItem('${item.item_id}')" aria-label="Remove">×</button>
    </div>`;
  }).join('');
}

// ── Yoga growth-specific poses ────────────────────────────────────
// Displayed inside the yoga log sheet. Evidence basis: spinal
// extension and axial loading poses promote disc hydration,
// vertebral elongation, and pituitary stimulation (McGill 2009;
// Howe et al. 2019 Complementary Therapies in Medicine).
const YOGA_POSES = [
  {
    emoji: '🐍',
    name: 'Cobra (Bhujangasana)',
    howTo: 'Lie face down. Hands flat under shoulders. Slowly press chest upward, hips stay on floor. Hold 20–30 sec.',
    benefit: 'Spinal extension + pituitary stimulation. Opens chest, elongates anterior spine.',
    dose: '3 × 20–30 sec',
  },
  {
    emoji: '🐕',
    name: 'Downward Dog (Adho Mukha Svanasana)',
    howTo: 'Start on hands and knees. Push hips up and back. Straighten legs, heels toward floor, head between arms. Hold 30–60 sec.',
    benefit: 'Decompresses the spine and elongates the posterior chain. Promotes intervertebral disc hydration.',
    dose: '3 × 30–60 sec',
  },
  {
    emoji: '🐈',
    name: 'Cat-Cow Flow (Marjaryasana-Bitilasana)',
    howTo: 'On hands and knees. Arch back up toward ceiling (cat, breathe out), then dip belly and lift head (cow, breathe in). Repeat slowly.',
    benefit: 'Alternating spinal flexion/extension pumps disc fluid, maintains growth-plate flexibility and spinal mobility.',
    dose: '2 min continuous flow',
  },
  {
    emoji: '🌲',
    name: 'Tree Pose (Vrksasana)',
    howTo: 'Stand tall on one foot. Press the other foot against inner thigh (not the knee). Hands at heart or raised. Hold 30 sec each side.',
    benefit: 'Single-leg weight-bearing loading. Promotes skeletal alignment, balance, and lower limb bone density.',
    dose: '30 sec × 2 sides',
  },
];

// ── Open log sheet ────────────────────────────────────────────────
let _pendingActivityId = null;
let _pendingActivityDuration = 30;
let _pendingActivityUnit = 'min';
let _pendingActivityOutdoor = false;

// Duration presets per preset type
const DURATION_PRESETS_MIN       = [5, 10, 15, 20, 30, 45, 60, 90];
const DURATION_PRESETS_SMALL_MIN = [1, 2, 3, 4, 5, 10, 15, 20];
const DURATION_PRESETS_REPS      = [10, 20, 30, 40, 50, 60, 80, 100];

function openActivityLogSheet(activityId) {
  const act = allActivities().find(a => a.id === activityId);
  if (!act) return;

  const presetType = act.presets || (act.unit === 'reps' ? 'reps' : 'standard_min');
  const unit       = act.unit || 'min';
  _pendingActivityId      = activityId;
  _pendingActivityUnit    = unit;
  _pendingActivityOutdoor = act.outdoor || false;

  const defVals = { reps: 40, small_min: 2, standard_min: 30 };
  _pendingActivityDuration = defVals[presetType] || 30;

  document.getElementById('actLogEmoji').textContent = act.emoji;
  document.getElementById('actLogName').textContent  = act.displayName;
  const tc = ACTIVITY_TIER_CONFIG[act.tier] || ACTIVITY_TIER_CONFIG.lifestyle;
  const badge = document.getElementById('actLogBadge');
  badge.textContent = tc.label;
  badge.className   = `act-tier-badge ${tc.badgeCls}`;

  // ── Science note + citation ─────────────────────────────────────
  const sciEl = document.getElementById('actLogSciNote');
  if (sciEl) {
    if (act.note) {
      const citHtml = act.citation
        ? `<br><span style="color:var(--text3);font-size:9.5px;">📄 ${act.citation}</span>` : '';
      sciEl.innerHTML = `🔬 ${act.note}${citHtml}`;
      sciEl.style.display = 'block';
    } else { sciEl.style.display = 'none'; }
  }

  // ── Personalized recommendation ─────────────────────────────────
  const child  = APP.children[APP.activeChild];
  const ageYrs = child?.date_of_birth
    ? Math.floor((Date.now() - new Date(child.date_of_birth)) / (365.25 * 86400000)) : 9;
  const sex    = child?.biological_sex || 'male';
  const recFn  = ACTIVITY_RECS[activityId];
  const recText = recFn ? recFn(ageYrs, sex) : '';
  const noteEl = document.getElementById('actLogNote');
  if (noteEl) {
    if (recText) {
      noteEl.innerHTML = `<b>Age ${ageYrs}:</b> ${recText}`;
      noteEl.style.display = 'block';
    } else { noteEl.style.display = 'none'; }
  }

  // ── Duration presets ────────────────────────────────────────────
  const dGrid = document.getElementById('actLogDurationGrid');
  let presetList, unitLabel, defVal;
  if (presetType === 'reps')         { presetList = DURATION_PRESETS_REPS;       unitLabel = 'reps'; defVal = 40; }
  else if (presetType === 'small_min'){ presetList = DURATION_PRESETS_SMALL_MIN; unitLabel = 'min';  defVal = 2;  }
  else                               { presetList = DURATION_PRESETS_MIN;        unitLabel = 'min';  defVal = 30; }

  dGrid.innerHTML = presetList.map(d =>
    `<button class="duration-btn${d === defVal ? ' active' : ''}"
      onclick="selectActivityDuration(${d}, this)">
      ${d}<span class="duration-btn-unit">${unitLabel}</span>
    </button>`
  ).join('');

  document.getElementById('actLogCustomMin').value = '';
  document.getElementById('actLogConfirmBtn').textContent = `Log ${defVal} ${unitLabel}`;

  // ── Yoga poses ──────────────────────────────────────────────────
  const yogaEl = document.getElementById('actLogYogaPoses');
  if (yogaEl) {
    if (activityId === 'yoga') {
      yogaEl.innerHTML = `
        <div style="font-size:11.5px;font-weight:700;color:var(--accent);margin-bottom:8px;padding-top:14px;border-top:0.5px solid var(--border2);">
          Growth-specific poses
        </div>
        ${YOGA_POSES.map(p => `
          <div style="background:var(--surface2);border-radius:10px;padding:10px;margin-bottom:8px;">
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px;">
              <span style="font-size:20px;">${p.emoji}</span>
              <div>
                <div style="font-size:12.5px;font-weight:700;color:var(--text);">${p.name}</div>
                <div style="font-size:10px;font-weight:600;color:var(--accent);">${p.dose}</div>
              </div>
            </div>
            <div style="font-size:11px;color:var(--text2);line-height:1.45;margin-bottom:3px;"><b>How:</b> ${p.howTo}</div>
            <div style="font-size:10.5px;color:var(--text3);line-height:1.4;">✦ ${p.benefit}</div>
          </div>`).join('')}`;
      yogaEl.style.display = 'block';
    } else { yogaEl.style.display = 'none'; }
  }

  // ── Outdoor toggle ──────────────────────────────────────────────
  const outdoorToggle = document.getElementById('actLogOutdoorToggle');
  if (outdoorToggle) outdoorToggle.checked = _pendingActivityOutdoor;

  document.getElementById('activityLogModal').classList.remove('hidden');
}

function openActivityLogSheetFromBrowser(activityId) {
  document.getElementById('activityBrowserModal').classList.add('hidden');
  setTimeout(() => openActivityLogSheet(activityId), 180);
}

function closeActivityLogModal(e) {
  if (e && e.target !== document.getElementById('activityLogModal')) return;
  document.getElementById('activityLogModal').classList.add('hidden');
}

function selectActivityDuration(val, btn) {
  _pendingActivityDuration = val;
  document.querySelectorAll('#actLogDurationGrid .duration-btn').forEach(b => b.classList.remove('active'));
  btn?.classList.add('active');
  const unit  = _pendingActivityUnit;
  const label = unit === 'reps' ? `${val} reps` : `${val} min`;
  document.getElementById('actLogConfirmBtn').textContent = `Log ${label}`;
}

function selectCustomDuration(val) {
  const num = Math.max(1, Math.min(999, parseInt(val) || 0));
  if (num > 0) {
    _pendingActivityDuration = num;
    document.querySelectorAll('#actLogDurationGrid .duration-btn').forEach(b => b.classList.remove('active'));
    const unit  = _pendingActivityUnit;
    const label = unit === 'reps' ? `${num} reps` : `${num} min`;
    document.getElementById('actLogConfirmBtn').textContent = `Log ${label}`;
  }
}

// ── Confirm and save a logged activity ────────────────────────────
async function confirmLogActivity() {
  const act = allActivities().find(a => a.id === _pendingActivityId);
  if (!act || !activeChildId()) return;
  const rawValue  = _pendingActivityDuration || 30;
  const unit      = _pendingActivityUnit || 'min';
  const isOutdoor = document.getElementById('actLogOutdoorToggle')?.checked || _pendingActivityOutdoor || false;

  // Normalize to minutes for readiness score
  // reps: 40 box jumps ≈ 10 min equivalent high-impact (0.25 min/rep)
  // min: no conversion needed (integer values now — small_min ensures ≥1)
  let durationMin;
  if (unit === 'reps') durationMin = rawValue * 0.25;
  else                 durationMin = rawValue; // always integer minutes now

  document.getElementById('activityLogModal').classList.add('hidden');

  const actMeta = manualEntryMeta(APP.logDate);
  const { error } = await sb.from('daily_activity_items').insert({
    child_id:       activeChildId(),
    log_date:       APP.logDate,
    activity_id:    act.id,
    display_name:   act.displayName,
    category:       act.category,
    tier:           act.tier,
    duration_min:   durationMin,
    duration_value: rawValue,
    unit,
    is_outdoor:     isOutdoor,
    is_custom:      act.isCustom || false,
    estimation_method: actMeta.method,
    confidence:        actMeta.confidence,
  });

  if (error) { showToast('⚠️', 'Could not save activity'); return; }

  const label = unit === 'reps' ? `${rawValue} reps` : `${rawValue} min`;
  showToast('✅', `${act.emoji} ${act.displayName} · ${label}${isOutdoor ? ' ☀️' : ''}`);
  await loadTodayActivityItems();
}

// ── Remove a logged activity ──────────────────────────────────────
async function removeActivityItem(itemId) {
  await sb.from('daily_activity_items').delete().eq('item_id', itemId);
  APP.todayActivityItems = (APP.todayActivityItems || []).filter(i => i.item_id !== itemId);
  renderActivityLoggedItems();
  updateHUD();
}

// ── Toggle favourite (star) ───────────────────────────────────────
async function toggleFavouriteActivity(activityId, btn) {
  if (!activeChildId()) return;
  const fav = APP.favoriteActivities || new Set(DEFAULT_FAVOURITE_ACTIVITIES);
  const adding = !fav.has(activityId);
  if (adding) {
    await sb.from('favorite_activities').upsert({ child_id: activeChildId(), activity_id: activityId });
    fav.add(activityId);
  } else {
    await sb.from('favorite_activities').delete().eq('child_id', activeChildId()).eq('activity_id', activityId);
    fav.delete(activityId);
  }
  APP.favoriteActivities = fav;
  btn?.classList.toggle('act-star-active', adding);
  btn && (btn.textContent = adding ? '★' : '☆');
  renderActivityCards();
}

// ── Activity browser modal ────────────────────────────────────────
let _actBrowserFilter = 'all';

async function openActivityBrowserModal() {
  await loadCustomActivities();
  _actBrowserFilter = 'all';
  // Reset tabs
  document.querySelectorAll('.activity-browser-tab').forEach((b, i) => b.classList.toggle('active', i === 0));
  renderActivityBrowser();
  document.getElementById('activityBrowserModal').classList.remove('hidden');
}

function closeActivityBrowserModal(e) {
  if (e && e.target !== document.getElementById('activityBrowserModal')) return;
  document.getElementById('activityBrowserModal').classList.add('hidden');
}

function setActivityBrowserFilter(filter, btn) {
  _actBrowserFilter = filter;
  document.querySelectorAll('.activity-browser-tab').forEach(b => b.classList.remove('active'));
  btn?.classList.add('active');
  renderActivityBrowser();
}

function renderActivityBrowser() {
  const grid = document.getElementById('activityBrowserGrid');
  if (!grid) return;
  const fav = APP.favoriteActivities || new Set(DEFAULT_FAVOURITE_ACTIVITIES);
  let acts = allActivities();

  if (_actBrowserFilter === 'high_impact')   acts = acts.filter(a => a.tier === 'high_impact');
  else if (_actBrowserFilter === 'weight_bearing') acts = acts.filter(a => a.tier === 'weight_bearing');
  else if (_actBrowserFilter === 'cardio')    acts = acts.filter(a => a.tier === 'cardio');
  else if (_actBrowserFilter === 'flexibility') acts = acts.filter(a => a.tier === 'flexibility' || a.tier === 'lifestyle');
  else if (_actBrowserFilter === 'custom')    acts = acts.filter(a => a.isCustom);

  grid.innerHTML = acts.map(a => {
    const tc = ACTIVITY_TIER_CONFIG[a.tier] || ACTIVITY_TIER_CONFIG.lifestyle;
    const starred = fav.has(a.id);
    return `<div class="activity-browser-card">
      <button class="act-star-btn ${starred ? 'act-star-active' : ''}"
        onclick="toggleFavouriteActivity('${a.id}', this)" title="${starred ? 'Remove from Today grid' : 'Add to Today grid'}">
        ${starred ? '★' : '☆'}
      </button>
      <div class="activity-card-emoji">${a.emoji}</div>
      <div class="activity-card-name" style="font-size:11px;">${a.displayName}</div>
      <span class="act-tier-badge ${tc.badgeCls}">${tc.shortLabel}</span>
      ${a.note ? `<div class="activity-browser-note">${a.note}</div>` : ''}
      <button class="act-log-quick-btn" onclick="openActivityLogSheetFromBrowser('${a.id}')">Log</button>
    </div>`;
  }).join('');
}

// ── Save a custom activity ────────────────────────────────────────
async function saveCustomActivity() {
  const name  = document.getElementById('customActName')?.value?.trim();
  const emoji = document.getElementById('customActEmoji')?.value?.trim() || '⭐';
  const tier  = document.getElementById('customActTier')?.value || 'weight_bearing';
  if (!name) { showToast('⚠️', 'Enter an activity name'); return; }

  const actId = 'custom_' + Date.now().toString(36);
  const { error } = await sb.from('custom_activities').insert({
    activity_id: actId,
    parent_id: APP.session.user.id,
    display_name: name,
    emoji: emoji.slice(0, 4), // emoji may be multi-char
    tier,
    category: 'custom',
  });
  if (error) { showToast('⚠️', 'Could not save activity'); return; }

  document.getElementById('customActName').value = '';
  document.getElementById('customActEmoji').value = '';
  await loadCustomActivities();
  renderActivityBrowser();
  showToast('✅', `${emoji} ${name} added`);
}

// ── Load both favourites and activity items when Today opens ───────
async function loadActivitySectionForToday() {
  await Promise.all([
    loadFavouriteActivities(),
    loadTodayActivityItems(),
    loadCustomActivities(),
  ]);
}

// ══════════════════════════════════════════════════════════════════
// end activity library
// ══════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════
// SUBSCRIPTION & FEATURE GATING
// ══════════════════════════════════════════════════════════════════

// ── Tier checks ───────────────────────────────────────────────────
function isPremium() {
  const acct = APP.account;
  if (!acct) return false;
  const tier = acct.subscription_tier;
  if (tier === 'premium' || tier === 'pro') {
    if (!acct.tier_expires_at) return true;          // lifetime / admin grant
    return new Date(acct.tier_expires_at) > new Date();
  }
  return false;
}

function isPro() {
  const acct = APP.account;
  if (!acct) return false;
  if (acct.subscription_tier === 'pro') {
    if (!acct.tier_expires_at) return true;
    return new Date(acct.tier_expires_at) > new Date();
  }
  return false;
}

// Measurements: free users capped at 5 LIFETIME (never decremented on delete)
function canAddMeasurement() {
  if (isPremium()) return true;
  return (APP.account?.total_measurements_logged || 0) < 5;
}

// AI questions: free users get 3 per calendar month
function aiQuestionsRemaining() {
  if (isPremium()) return Infinity;
  const resetAt   = APP.account?.ai_questions_reset_at;
  const thisMonth = new Date().toISOString().slice(0, 7); // 'YYYY-MM'
  const resetMonth = resetAt ? resetAt.slice(0, 7) : '';
  const used = resetMonth === thisMonth
    ? (APP.account?.ai_questions_this_month || 0) : 0;
  return Math.max(0, 3 - used);
}

// History date cutoff: free = last 30 days, premium = all time
function historyStartDate() {
  if (isPremium()) return '2000-01-01';
  const d = new Date();
  d.setDate(d.getDate() - 30);
  return d.toISOString().split('T')[0];
}

// ── Upgrade modal ─────────────────────────────────────────────────
const UPGRADE_MESSAGES = {
  measurements: {
    title: "You've logged 5 measurements",
    body:  "Your growth data is safe and always visible. Upgrade to Premium to keep tracking and see the full velocity trend over time.",
  },
  history: {
    title: "See Peem's full growth history",
    body:  "Premium unlocks the complete timeline — every measurement, chart, and trend going back to day one.",
  },
  ai_coach: {
    title: "3 AI questions used this month",
    body:  "Premium gives you unlimited AI coach access — ask about sleep patterns, nutrition gaps, and growth data anytime.",
  },
  lab_values: {
    title: "Lab value tracking is Premium",
    body:  "Families working with a pediatric endocrinologist use IGF-1 and Vitamin D tracking to monitor treatment progress.",
  },
  bone_age_ai: {
    title: "AI bone age analysis is Premium",
    body:  "Get an AI second opinion on your radiologist's bone age report, with delta calculation and height potential estimate.",
  },
  fitbit: {
    title: "Fitbit sync is Premium",
    body:  "Connect Peem's Fitbit to automatically track deep sleep — the primary window for growth hormone release.",
  },
  pdf_export: {
    title: "Clean PDF export is Premium",
    body:  "Premium generates a clinic-ready PDF with charts, lab values, and bone age — no watermark.",
  },
  multiple_children: {
    title: "Multiple children is Premium",
    body:  "Premium supports up to 5 children — add siblings and track each independently.",
  },
};

function showUpgradeModal(feature) {
  const msg  = UPGRADE_MESSAGES[feature] || UPGRADE_MESSAGES.measurements;
  const modal = document.getElementById('upgradeModal');
  if (!modal) return;
  document.getElementById('upgradeModalTitle').textContent = msg.title;
  document.getElementById('upgradeModalBody').textContent  = msg.body;
  modal.classList.remove('hidden');
}

function closeUpgradeModal() {
  document.getElementById('upgradeModal')?.classList.add('hidden');
}

// ── Redemption ────────────────────────────────────────────────────
async function redeemActivationCode() {
  const input = document.getElementById('redeemCodeInput');
  const btn   = document.getElementById('redeemCodeBtn');
  const code  = input?.value?.trim().toUpperCase().replace(/\s+/g, '');
  if (!code) { showToast('⚠️', 'Enter an activation code'); return; }

  if (btn) { btn.textContent = 'Activating…'; btn.disabled = true; }

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/redeem-code`, {
      method:  'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${APP.session.access_token}`,
      },
      body: JSON.stringify({ code }),
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Redemption failed');

    // Update local account state immediately — no need to reload page
    if (APP.account) {
      APP.account.subscription_tier = data.tier;
      APP.account.tier_expires_at   = data.expires_at;
      APP.account.billing_source    = 'code';
    }

    // Refresh tier badge
    const tierBadge  = document.getElementById('accountTierBadge');
    const tierLabels  = { free:'Free', premium:'⭐ Premium', pro:'👑 Pro' };
    if (tierBadge) {
      tierBadge.className   = 'tier-badge ' + data.tier;
      tierBadge.textContent = tierLabels[data.tier] || data.tier;
    }

    // Show tier expiry in account screen
    renderTierStatus();

    if (input) input.value = '';
    showToast('🎉', data.message || `${data.tier} activated!`);

  } catch (e) {
    showToast('⚠️', e.message);
  } finally {
    if (btn) { btn.textContent = 'Activate'; btn.disabled = false; }
  }
}

// Render current tier + expiry in Account screen
function renderTierStatus() {
  const el = document.getElementById('tierStatusRow');
  if (!el || !APP.account) return;

  const tier    = APP.account.subscription_tier || 'free';
  const expiry  = APP.account.tier_expires_at;
  const labels  = { free:'Free', premium:'⭐ Premium', pro:'👑 Pro' };

  let expiryStr = '';
  if (expiry && isPremium()) {
    const d = new Date(expiry);
    expiryStr = ` · Active until ${d.toLocaleDateString('en-GB', { day:'numeric', month:'short', year:'numeric' })}`;
  }

  el.innerHTML = `
    <div style="font-size:12px; color:var(--text3); margin-bottom:3px;">Current plan</div>
    <div style="font-size:15px; font-weight:700; color:var(--text);">
      ${labels[tier] || tier}<span style="font-size:11px; font-weight:400; color:var(--text3);">${expiryStr}</span>
    </div>
    ${!isPremium() ? `
      <div style="margin-top:4px; font-size:11px; color:var(--text3);">
        Measurements logged: ${APP.account.total_measurements_logged || 0} of 5 free · AI questions: ${3 - (APP.account.ai_questions_this_month||0)} remaining this month
      </div>` : ''}`;
}

// ── Feature gate wrappers ─────────────────────────────────────────
// Call these before any premium action to check + show upgrade modal

function requirePremium(feature) {
  if (isPremium()) return true;
  showUpgradeModal(feature);
  return false;
}

function requireMeasurementQuota() {
  if (canAddMeasurement()) return true;
  showUpgradeModal('measurements');
  return false;
}

function requireAIQuota() {
  if (aiQuestionsRemaining() > 0) return true;
  showUpgradeModal('ai_coach');
  return false;
}

// ══════════════════════════════════════════════════════════════════
// end subscription
// ══════════════════════════════════════════════════════════════════

function showAuthScreen() {
  document.getElementById('authScreen').classList.remove('hidden');
  document.getElementById('appRoot').classList.add('hidden');
  setSyncStatus('disconnected', 'Not signed in');
  renderLanguageSelector(); // populate language pills on auth screen
}

// Runs once after a successful sign-in or an existing session is found on
// load: fetches the account row + role, loads whichever children this
// user can see (RLS handles the actual filtering), and reveals the app.
async function enterApp(session) {
  APP.session = session;
  setSyncStatus('pending', 'Loading…');

  const { data: account, error } = await sb
    .from('user_accounts')
    .select('*')
    .eq('user_id', session.user.id)
    .single();

  if (error || !account) {
    // This can happen if sign-up's user_accounts insert failed partway —
    // surface it rather than silently showing a broken app.
    showAuthError('Could not load your account profile. Try signing in again, or contact support if this persists.');
    await sb.auth.signOut();
    return;
  }

  APP.account = account;
  document.getElementById('accountEmail').textContent = account.email;
  const roleBadge = document.getElementById('accountRoleBadge');
  roleBadge.className = 'role-badge ' + account.account_role;
  roleBadge.textContent = account.account_role.replace('_', ' ');

  const tier = account.subscription_tier || 'free';
  const tierBadge = document.getElementById('accountTierBadge');
  tierBadge.className = 'tier-badge ' + tier;
  const tierLabels = { free: 'Free', premium: '⭐ Premium', pro: '👑 Pro' };
  tierBadge.textContent = tierLabels[tier] || tier;

  // Show a small "Admin dashboard" link for system_admin accounts,
  // pointing to the standalone admin.html rather than switching to an
  // embedded tab — the admin dashboard was moved to its own page.
  const adminLink = document.getElementById('adminDashboardLink');
  if (adminLink) adminLink.classList.toggle('hidden', !isSystemAdmin());

  document.getElementById('clinicianPanel').classList.toggle('hidden', !isClinicianRole());
  document.getElementById('parentPanel').classList.toggle('hidden', isClinicianRole());
  renderLanguageSelector();
  renderTierStatus(); // show current plan + expiry + usage counts

  initDateSelector();
  await loadChildren();

  document.getElementById('authScreen').classList.add('hidden');
  document.getElementById('appRoot').classList.remove('hidden');
  setSyncStatus('connected', account.email);
  setDateBadge();
  setTimeout(drawGrowthChart, 200);
}

// Repaint the entire Today form from the active child's stored state —
// called on boot and every time the child switcher changes selection.
// ══════════════════════════════════════════
// DATE SELECTOR — which date the Today screen edits
// ══════════════════════════════════════════
function initDateSelector() {
  const input = document.getElementById('logEntryDate');
  input.value = APP.logDate;
  input.max   = todayISO();
  updateDateSelectorUI();
  updateSaveBtnLabel();
}

function updateDateSelectorUI() {
  const bar = document.querySelector('.date-selector-bar');
  const todayBtn = document.getElementById('jumpToTodayBtn');
  const isToday = APP.logDate === todayISO();
  if (bar) bar.classList.toggle('backdated', !isToday);
  if (todayBtn) todayBtn.classList.toggle('is-today', isToday);
  const input = document.getElementById('logEntryDate');
  if (input) input.value = APP.logDate;
  // Backdating banner
  const banner = document.getElementById('backdatingBanner');
  if (banner) banner.classList.toggle('hidden', isToday);
}

function shiftLogDate(deltaDays) {
  // Parse APP.logDate as local date components to avoid UTC/timezone boundary bugs.
  // Using new Date('YYYY-MM-DDT00:00:00') in UTC+7 Bangkok converts midnight to
  // the previous UTC day, causing toISOString() to return the wrong date.
  const [y, m, d] = APP.logDate.split('-').map(Number);
  const shifted    = new Date(y, m - 1, d + deltaDays); // local-time constructor
  const newDate    = [
    shifted.getFullYear(),
    String(shifted.getMonth() + 1).padStart(2, '0'),
    String(shifted.getDate()).padStart(2, '0'),
  ].join('-');
  if (newDate > todayISO()) return; // no future logging
  setLogDate(newDate);
}

function jumpToToday() {
  setLogDate(todayISO());
}

function onLogDateChanged() {
  const val = document.getElementById('logEntryDate').value;
  if (val) setLogDate(val);
}

async function setLogDate(newDate) {
  APP.logDate = newDate;
  updateDateSelectorUI();
  updateSaveBtnLabel();           // reflect date on save button
  await loadDayIntoState();
  loadChildIntoForm();
  await loadTodayActivityItems(); // reload activity items for new date
}

// Update the Save button to show WHICH date is being logged.
// When backdating, the parent must be clearly aware they're saving
// historical data — not accidentally overwriting today.
function updateSaveBtnLabel() {
  const btn = document.getElementById('saveBtn');
  if (!btn) return;
  const today = todayISO();
  if (APP.logDate === today) {
    btn.textContent = t('today.save_btn', "Save Today's Data");
    btn.style.background = '';       // default green
    return;
  }
  const [y, m, d] = APP.logDate.split('-').map(Number);
  const dateObj    = new Date(y, m - 1, d);
  const readableDate = dateObj.toLocaleDateString('en-GB', { weekday:'short', day:'numeric', month:'short' });
  const yesterday  = new Date(); yesterday.setDate(yesterday.getDate() - 1);
  const isYesterday = APP.logDate === [
    yesterday.getFullYear(),
    String(yesterday.getMonth() + 1).padStart(2, '0'),
    String(yesterday.getDate()).padStart(2, '0'),
  ].join('-');
  const dayLabel = isYesterday ? 'Yesterday' : readableDate;
  btn.textContent = `↺ Save for ${dayLabel}`;
  btn.style.background = 'linear-gradient(135deg, var(--estimated) 0%, #8a6a1f 100%)'; // amber — visual caution
}

// Pulls this child's daily_nutrition/sleep/activity rows AND
// nutrition_log_items for APP.logDate, and populates currentState()
// from them — so revisiting a past date shows what was actually
// logged that day, not leftover numbers from today.
async function loadDayIntoState() {
  const childId = activeChildId();
  const s = currentState();
  if (!childId) { resetStateToDefaults(s); await loadNutritionLogItems(); return; }

  // Fire-and-forget background prune — runs once per child per session
  // (guarded by a session-level flag) so the Free-tier 30-day rolling
  // retention is enforced without blocking the page load or the parent
  // noticing any delay. Only actually deletes anything for Free-tier
  // accounts that have logs older than 30 days — skips immediately and
  // silently for Premium/Pro.
  pruneStaleLogItemsIfNeeded(childId);

  const [nutRes, sleepRes, actRes] = await Promise.all([
    sb.from('daily_nutrition').select('*').eq('child_id', childId).eq('log_date', APP.logDate).maybeSingle(),
    sb.from('daily_sleep').select('*').eq('child_id', childId).eq('log_date', APP.logDate).maybeSingle(),
    sb.from('daily_activity').select('*').eq('child_id', childId).eq('log_date', APP.logDate).maybeSingle()
  ]);

  resetStateToDefaults(s);

  const nut = nutRes.data;
  if (nut) {
    s.protein = Number(nut.total_protein_g) || 0;
    s.calcium = Number(nut.calcium_mg) || 0;
    s.zinc = Number(nut.zinc_mg) || 0;
    s.water = nut.fluids_ml ? Math.round(Number(nut.fluids_ml) / 250) : 0;
  }
  const sleep = sleepRes.data;
  if (sleep) {
    s.nightWakes = Number(sleep.night_wakes) || 0;
    // Postgres TIME columns come back as "HH:MM:SS" — the <input type="time">
    // element expects "HH:MM", so trim to 5 chars. Fall back to the
    // DEFAULT_DAY_STATE values (already set by resetStateToDefaults above)
    // if either column is null, e.g. for rows saved before this migration.
    if (sleep.bedtime) s.bed = String(sleep.bedtime).slice(0, 5);
    if (sleep.wake_time) s.wake = String(sleep.wake_time).slice(0, 5);
  }
  const act = actRes.data;
  if (act) {
    s.hanging = Number(act.hanging_decompression_sec) || 0;
    s.jumps = Number(act.box_jumps_reps) || 0;
    s.yogaMin = Number(act.stretching_yoga_duration_min) || 0;
  }
  s.savedToday = !!(nut || sleep || act);

  await loadNutritionLogItems();
}

function resetStateToDefaults(s) {
  Object.assign(s, { ...DEFAULT_DAY_STATE });
}

// ══════════════════════════════════════════
// NUTRITION LOG ITEMS — the per-food, reviewable, undoable trail
// underneath the daily_nutrition totals. See migration_nutrition_log_items.sql
// for why this table is meant to be permanent, not pruned.
// ══════════════════════════════════════════
// ── Free-tier daily-log retention pruning ────────────────────────────
// Free accounts have a 30-day rolling window on nutrition, sleep, and
// activity log entries (NOT on measurements, labs, puberty events, or
// illness events — those are never pruned regardless of tier, per the
// tier design decision documented in FORMULAS.md §5y).
//
// This function runs once per child per browser session (session-level
// flag prevents repeated sweeps) as a fire-and-forget background call.
// It deliberately does NOT await — the parent should never feel it.
// On Premium/Pro, it reads the limit, finds it NULL, and exits without
// touching anything. On Free, it issues a single DELETE for log rows
// older than 30 days for this child.
const _prunedThisSession = new Set(); // child_ids pruned in this session
async function pruneStaleLogItemsIfNeeded(childId) {
  if (_prunedThisSession.has(childId)) return; // already ran this session
  _prunedThisSession.add(childId); // mark before the async work to prevent re-entry

  const tier = (APP.account && APP.account.subscription_tier) || 'free';
  const limitRes = await sb.from('subscription_tier_limits')
    .select('daily_log_retention_days')
    .eq('tier', tier)
    .maybeSingle();

  if (limitRes.error || !limitRes.data) return;
  const retentionDays = limitRes.data.daily_log_retention_days;
  if (retentionDays === null) return; // NULL = unlimited — Premium/Pro, do nothing

  // Compute the cutoff date as a plain 'YYYY-MM-DD' string — matches
  // the log_date column type (date, not timestamptz), so the comparison
  // is a simple date string comparison rather than a timezone-sensitive
  // timestamp comparison that could silently prune the wrong day.
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - retentionDays);
  const cutoffStr = cutoffDate.toISOString().split('T')[0];

  // Tables to prune: nutrition_log_items, daily_sleep, daily_activity.
  // Errors are silently swallowed — background maintenance job.
  await Promise.all([
    sb.from('nutrition_log_items').delete().eq('child_id', childId).lt('log_date', cutoffStr),
    sb.from('daily_sleep').delete().eq('child_id', childId).lt('log_date', cutoffStr),
    sb.from('daily_activity').delete().eq('child_id', childId).lt('log_date', cutoffStr)
  ]).catch(() => {});
}

// ── Measurement row edit sheet ────────────────────────────────────
function openMeasurementEditSheet(measurementId) {
  const m = (APP.activeChildMeasurements || []).find(r => r.measurement_id === measurementId);
  if (!m) return;

  document.getElementById('editMeasId').value    = measurementId;
  document.getElementById('editMeasDate').value  = m.recorded_date;
  document.getElementById('editMeasHeight').value = Number(m.stature_height_cm).toFixed(1);
  document.getElementById('editMeasWeight').value = Number(m.mass_weight_kg).toFixed(2);

  document.getElementById('measurementEditModal').classList.remove('hidden');
}

function closeMeasurementEditSheet(e) {
  // Close on backdrop tap only (not on sheet content tap)
  if (e && e.target !== document.getElementById('measurementEditModal')) return;
  document.getElementById('measurementEditModal').classList.add('hidden');
}

async function saveMeasurementEdit() {
  const id     = document.getElementById('editMeasId').value;
  const date   = document.getElementById('editMeasDate').value;
  const height = parseFloat(document.getElementById('editMeasHeight').value);
  const weight = parseFloat(document.getElementById('editMeasWeight').value);

  if (!date || isNaN(height) || isNaN(weight) || height <= 0 || weight <= 0) {
    showToast('⚠️', t('toast.error.invalid_height_weight','Please enter valid height and weight')); return;
  }

  const bmi = parseFloat((weight / Math.pow(height / 100, 2)).toFixed(1));

  const { error } = await sb.from('measurements').update({
    recorded_date: date,
    stature_height_cm: height,
    mass_weight_kg: weight,
    calculated_bmi: bmi,
  }).eq('measurement_id', id);

  if (error) { showToast('⚠️', t('toast.error.save_failed','Save failed') + ': ' + error.message); return; }

  document.getElementById('measurementEditModal').classList.add('hidden');
  showToast('✅', t('toast.measurement_updated','Measurement updated'));
  await refreshActiveChildHistory();
  drawGrowthChart();
  drawBMIChart();
  updateInsightCards();
}

async function deleteMeasurement() {
  if (!confirm(t('confirm.delete_measurement','Delete this measurement? This cannot be undone.'))) return;

  const id = document.getElementById('editMeasId').value;
  const { error } = await sb.from('measurements').delete().eq('measurement_id', id);

  if (error) { showToast('⚠️', t('toast.error.delete_failed','Delete failed') + ': ' + error.message); return; }

  document.getElementById('measurementEditModal').classList.add('hidden');
  showToast('✅', t('toast.measurement_deleted','Measurement deleted'));
  await refreshActiveChildHistory();
  drawGrowthChart();
  drawBMIChart();
  updateInsightCards();
}

async function loadNutritionLogItems() {
  const childId = activeChildId();
  if (!childId) { APP.nutritionLogItems = []; renderNutritionLogList(); return; }

  const { data, error } = await sb
    .from('nutrition_log_items')
    .select('*')
    .eq('child_id', childId)
    .eq('log_date', APP.logDate)
    .order('logged_at', { ascending: true });

  if (error) {
    showToast('⚠️', 'Could not load food log: ' + error.message);
    APP.nutritionLogItems = [];
  } else {
    APP.nutritionLogItems = data || [];
  }
  renderNutritionLogList();
}

function renderNutritionLogList() {
  const list = document.getElementById('nutritionLogList');
  const empty = document.getElementById('logListEmpty');
  const countBadge = document.getElementById('logItemCount');
  const items = APP.nutritionLogItems;

  countBadge.textContent = items.length + (items.length === 1 ? ' item' : ' items');

  if (items.length === 0) {
    list.innerHTML = '<div class="log-list-empty" id="logListEmpty">Nothing logged yet for this date.</div>';
    updateFoodCardTapCounts();
    return;
  }

  const emojiFor = (foodId) => {
    if (!foodId) return '💪';
    const food = (typeof FOOD_REFERENCE_DATA !== 'undefined') ? FOOD_REFERENCE_DATA.find(f => f.id === foodId) : null;
    return food ? food.emoji : '🍽️';
  };

  list.innerHTML = items.map(item => {
    const time = new Date(item.logged_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    return `
      <div class="log-item-row" data-item-id="${item.item_id}">
        <div class="log-item-left">
          <span class="log-item-emoji">${emojiFor(item.food_id)}</span>
          <div class="log-item-info">
            <span class="log-item-name">${item.food_name}</span>
            <span class="log-item-meta">${time}${item.meal_slot && item.meal_slot !== 'unspecified' ? ' · ' + item.meal_slot : ''}</span>
          </div>
        </div>
        <div class="log-item-right">
          <span class="log-item-amount">+${Number(item.protein_g).toFixed(1)}g</span>
          <button class="log-item-delete" onclick="deleteNutritionLogItem('${item.item_id}')" aria-label="Remove">×</button>
        </div>
      </div>
    `;
  }).join('');

  updateFoodCardTapCounts();
}

// Shows, on each food card, how many times that specific food has
// already been tapped today (e.g. "Milk × 2" so a parent can see at a
// glance that they've logged 2 × 100ml = 200ml without having to scroll
// down to the log list and count rows themselves).
function updateFoodCardTapCounts() {
  if (typeof FOOD_REFERENCE_DATA === 'undefined') return;
  FOOD_REFERENCE_DATA.forEach(food => {
    const el = document.getElementById('tapcount-' + food.id);
    if (!el) return;
    const count = APP.nutritionLogItems.filter(i => i.food_id === food.id).length;
    if (count === 0) {
      el.textContent = '';
      el.classList.remove('has-taps');
    } else {
      const totalGrams = count * food.servingGrams;
      el.textContent = `${food.emoji} × ${count} = ${totalGrams}g logged`;
      el.classList.add('has-taps');
    }
  });
}

// Inserts one row for a logged food/tap. Called from applyFoodTap()
// instead of (well, alongside) just bumping the in-memory total — the
// in-memory total is still updated immediately for instant HUD feedback,
// but the row in nutrition_log_items is what actually persists and is
// reviewable/undoable.
async function recordNutritionLogItem(foodId, foodName, proteinAmt, zincAmt, calciumAmt, ironAmt, vitDAmt) {
  const childId = activeChildId();
  if (!childId) return;

  const { data, error } = await sb.from('nutrition_log_items').insert({
    child_id: childId,
    log_date: APP.logDate,
    meal_slot: APP.activeMealSlot || 'unspecified',
    food_id: foodId,
    food_name: foodName,
    protein_g: proteinAmt,
    zinc_mg: zincAmt,
    calcium_mg: calciumAmt,
    // Minor co-factors — auto-captured, surfaced only in Analytics.
    iron_mg: ironAmt != null ? ironAmt : null,
    vitamin_d_iu: vitDAmt != null ? vitDAmt : null,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) {
    showToast('⚠️', 'Logged locally but not saved: ' + error.message);
    return;
  }
  APP.nutritionLogItems.push(data);
  renderNutritionLogList();
}

// Removes a specific logged item (the × button) and subtracts its
// amounts back out of the running totals — this is the precise,
// per-item undo that a flat stepper can't give you.
async function deleteNutritionLogItem(itemId) {
  const item = APP.nutritionLogItems.find(i => i.item_id === itemId);
  if (!item) return;

  const { error } = await sb.from('nutrition_log_items').delete().eq('item_id', itemId);
  if (error) { showToast('⚠️', t('toast.error.remove_failed','Could not remove') + ': ' + error.message); return; }

  APP.nutritionLogItems = APP.nutritionLogItems.filter(i => i.item_id !== itemId);
  renderNutritionLogList();

  // Reverse this item's contribution from the running totals shown in
  // the steppers, matching exactly what was added when it was logged.
  applyFoodTap(null, Number(item.protein_g) || 0, item.zinc_mg != null ? Number(item.zinc_mg) : null, item.calcium_mg != null ? Number(item.calcium_mg) : null, -1, { skipLog: true });
}

// Used only by the long-press/right-click subtract path in applyFoodTap():
// that path already adjusted the running totals itself before calling
// here, so this function's job is strictly "delete this DB row and
// refresh the visible list" — it must NOT touch totals again, or a
// long-press would subtract twice (once from the totals math at the top
// of applyFoodTap, and a second time if this called back into
// deleteNutritionLogItem(), which also adjusts totals).
async function removeLoggedItemRowOnly(itemId) {
  const { error } = await sb.from('nutrition_log_items').delete().eq('item_id', itemId);
  if (error) { showToast('⚠️', t('toast.error.remove_failed','Could not remove') + ': ' + error.message); return; }
  APP.nutritionLogItems = APP.nutritionLogItems.filter(i => i.item_id !== itemId);
  renderNutritionLogList();
}

function loadChildIntoForm() {
  const s = currentState();
  document.querySelectorAll('#mealSlotSeg .seg-btn').forEach(b => {
    b.classList.toggle('active', b.dataset.meal === APP.activeMealSlot);
  });
  document.getElementById('valProtein').textContent = s.protein + ' g';
  document.getElementById('valCalcium').textContent = s.calcium + ' mg';
  document.getElementById('valZinc').textContent = s.zinc + ' mg';
  // valHanging and valJumps removed in activity library redesign — guard against null
  const elH = document.getElementById('valHanging'); if (elH) elH.textContent = s.hanging + ' sec';
  const elJ = document.getElementById('valJumps');   if (elJ) elJ.textContent = s.jumps + ' reps';
  document.getElementById('valNightWakes').textContent = s.nightWakes;
  document.getElementById('waterLbl').textContent = `(${s.water}/${activeChildNutritionTargets().waterGlasses} glasses)`;
  { const z = document.getElementById('zincSubLbl'); if (z) z.textContent = `Growth plate co-factor · target ${activeChildNutritionTargets().zincMg}mg/day (for age)`; }
  document.getElementById('sleepBed').value = s.bed;
  document.getElementById('sleepWake').value = s.wake;

  // yogaSeg removed in activity library redesign — guard against null
  document.querySelectorAll('#yogaSeg .seg-btn').forEach((b,i) => {
    b.classList.toggle('active', [0,10,20,30][i] === s.yogaMin);
  });
  document.querySelectorAll('.seg .seg-btn').forEach(b => {
    if (b.id && b.id.startsWith('st')) b.classList.remove('active');
  });
  const stMap = { 0:'stNone', 1:'stInhaled', 2:'stOral' };
  const stBtn = document.getElementById(stMap[s.steroid]);
  if (stBtn) stBtn.classList.add('active');

  // Favorites/custom foods are per-child — re-fetch whenever the
  // active child has actually changed, not on every call to this
  // function (loadChildIntoForm runs often, e.g. after every daily-log
  // edit, and re-fetching food_favorites on each of those would be
  // wasteful). buildFoodCardGrid() below renders synchronously from
  // whatever's already in memory; the async fetch updates and
  // re-renders again once it resolves, which is fine since the first
  // render (old or default data) is just a brief placeholder.
  if (APP._foodFavoritesLoadedForChild !== activeChildId()) {
    APP._foodFavoritesLoadedForChild = activeChildId();
    loadFoodFavoritesAndCustomFoods();
  }

  buildFoodCardGrid();
  buildWaterGrid();
  calcSleep();
  updateHUD();
  renderStreakRow();

  const btn = document.getElementById('saveBtn');
  btn.textContent = saveButtonLabel(s.savedToday);
}

// ══════════════════════════════════════════
// AUTH
// ══════════════════════════════════════════
function showAuthError(msg) {
  const el = document.getElementById('authError');
  el.textContent = msg;
  el.classList.remove('hidden');
}
function clearAuthError() {
  document.getElementById('authError').classList.add('hidden');
}

function showSignUpForm() {
  clearAuthError();
  document.getElementById('authSignInForm').classList.add('hidden');
  document.getElementById('authSignUpForm').classList.remove('hidden');
}
function showSignInForm() {
  clearAuthError();
  document.getElementById('authSignUpForm').classList.add('hidden');
  document.getElementById('authSignInForm').classList.remove('hidden');
}
function setSignupRole(role, btn) {
  APP.signupRole = role;
  document.querySelectorAll('#authSignUpForm .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
}

async function handleSignIn() {
  clearAuthError();
  const email = document.getElementById('authEmail').value.trim();
  const password = document.getElementById('authPassword').value;
  if (!email || !password) { showAuthError('Enter your email and password.'); return; }

  const btn = document.getElementById('signInBtn');
  btn.disabled = true; btn.textContent = 'Signing in…';
  const { data, error } = await sb.auth.signInWithPassword({ email, password });
  btn.disabled = false; btn.textContent = 'Sign in';

  if (error) { showAuthError(error.message); return; }
  await enterApp(data.session);
}

async function handleSignUp() {
  clearAuthError();
  const email = document.getElementById('suEmail').value.trim();
  const password = document.getElementById('suPassword').value;
  if (!email || !password) { showAuthError('Enter an email and password.'); return; }
  if (password.length < 8) { showAuthError('Password must be at least 8 characters.'); return; }

  const btn = document.getElementById('signUpBtn');
  btn.disabled = true; btn.textContent = 'Creating account…';

  const { data, error } = await sb.auth.signUp({ email, password });
  if (error) {
    btn.disabled = false; btn.textContent = 'Create account';
    showAuthError(error.message);
    return;
  }

  // If email confirmation is required, there's no session yet — tell the
  // person to check their inbox rather than silently doing nothing.
  if (!data.session) {
    btn.disabled = false; btn.textContent = 'Create account';
    showAuthError('Account created. Check your email to confirm, then sign in.');
    showSignInForm();
    return;
  }

  // Create the matching user_accounts row with the chosen role. If this
  // fails, the auth user still exists but has no profile — enterApp()
  // detects that case on next sign-in and surfaces it rather than
  // crashing silently.
  const { error: profileError } = await sb.from('user_accounts').insert({
    user_id: data.session.user.id,
    email: email,
    account_role: APP.signupRole
  });

  btn.disabled = false; btn.textContent = 'Create account';

  if (profileError) {
    showAuthError('Account created but profile setup failed: ' + profileError.message + '. Try signing in again.');
    return;
  }

  await enterApp(data.session);
}

async function handleSignOut() {
  await sb.auth.signOut();
  APP.session = null;
  APP.account = null;
  APP.children = [];
  APP.activeChild = 0;
  closeSetup();
  showAuthScreen();
}

// Archives the WHOLE account, not just one child — same "nothing
// vanishes immediately" guarantee as deleteChildProfile(), one level
// up. The account and every child under it are flipped to 'archived'
// as a single unit, so a parent doesn't have to separately delete each
// child first. Only the scheduled sweep performs real, irreversible
// deletion, and only after the full grace period (account_archive_
// retention_days for this account's tier) has elapsed. A system_admin
// can restore the account at any point before that.
async function requestAccountDeletion() {
  const retentionDays = await getAccountArchiveRetentionDays();
  const confirmed = confirm(
    `Delete your GrowSense account? Your account and all children's profiles will be archived for ${retentionDays} days, during which you can contact support to restore everything. After that period, your data will be permanently and irreversibly deleted. You will be signed out immediately.`
  );
  if (!confirmed) return;

  const archivedAt = new Date();
  const permanentDeleteAfter = new Date(archivedAt.getTime() + retentionDays * 86400000);
  const userId = APP.session ? APP.session.user.id : null;
  if (!userId) return;

  // Archive every child under this account first, then the account
  // itself — both as plain status updates, nothing cascades or
  // deletes here.
  const { error: childrenError } = await sb.from('children').update({
    status: 'archived', archived_at: archivedAt.toISOString(), archived_by: userId,
    permanent_delete_after: permanentDeleteAfter.toISOString()
  }).eq('parent_id', userId).eq('status', 'active');
  if (childrenError) { showToast('⚠️', 'Could not archive children: ' + childrenError.message); return; }

  const { error: accountError } = await sb.from('user_accounts').update({
    account_status: 'archived', archived_at: archivedAt.toISOString(),
    permanent_delete_after: permanentDeleteAfter.toISOString()
  }).eq('user_id', userId);
  if (accountError) { showToast('⚠️', 'Could not archive account: ' + accountError.message); return; }

  showToast('✅', t('toast.account_archived','Account archived. Signing out…'));
  setTimeout(() => handleSignOut(), 1200); // brief pause so the toast is actually visible before the auth screen replaces everything
}

// ══════════════════════════════════════════
// CHILD SWITCHER
// ══════════════════════════════════════════
// Pulls whichever children this account can see (RLS enforces the actual
// scoping — a parent sees their own kids, a doctor sees assigned patients,
// a scientist sees all). Called on boot, after adding a child, and after
// switching accounts.
async function loadChildren() {
  const { data, error } = await sb.from('children').select('*').eq('status', 'active').order('created_at');
  if (error) {
    showToast('⚠️', 'Could not load children: ' + error.message);
    APP.children = [];
  } else {
    APP.children = data || [];
  }
  if (APP.activeChild >= APP.children.length) APP.activeChild = 0;

  renderChildSwitcher();
  populateShareChildSelect();
  if (isClinicianRole()) {
    renderAssignedChildrenList();
  }
  if (APP.children.length > 0) {
    await loadDayIntoState();
    loadChildIntoForm();
    await refreshActiveChildHistory();
    await loadWeekStreak();
    // Render activity cards immediately with defaults (favourites load async after)
    renderActivityCards();
    loadActivitySectionForToday(); // fire-and-forget — updates cards once DB responds
  }
}

// Rebuilds the "logging consistency" row from what's actually in the
// database, rather than trusting only the in-memory flag set by saveDay()
// in this session — otherwise every fresh page load would show 0/7 even
// for a child logged every day this week.
async function loadWeekStreak() {
  const childId = activeChildId();
  if (!childId) return;

  const monday = new Date();
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
  const mondayStr = monday.toISOString().split('T')[0];

  // A day counts as "logged" if any of the three tables has a row for it —
  // querying just one (daily_activity) as the marker, since saveDay()
  // always writes to all three together or none.
  const { data, error } = await sb
    .from('daily_activity')
    .select('log_date')
    .eq('child_id', childId)
    .gte('log_date', mondayStr);

  const streak = [0,0,0,0,0,0,0];
  if (!error && data) {
    data.forEach(row => {
      const d = new Date(row.log_date);
      const idx = (d.getDay() + 6) % 7;
      streak[idx] = 1;
    });
  }
  APP.weekStreakByChild[APP.activeChild] = streak;
  renderStreakRow();
}

function ageFromDOB(dobStr) {
  if (!dobStr) return null;
  const dob = new Date(dobStr);
  const now = new Date();
  let age = now.getFullYear() - dob.getFullYear();
  const monthDiff = now.getMonth() - dob.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < dob.getDate())) age--;
  return age;
}

// ══════════════════════════════════════════
// PROTEIN TARGET — dynamic, evidence-based
//
// Source: Institute of Medicine (2005) Dietary Reference Intakes —
// Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Protein, and Amino
// Acids. National Academies Press. Table 10-21 (RDA for protein).
//
// Source: WHO/FAO/UNU (2007) Protein and Amino Acid Requirements in
// Human Nutrition. Technical Report Series 935. Table 9 (safe levels
// of protein intake, children).
//
// Source: Pediatric Society of Thailand / Thai Department of Health
// (กรมอนามัย) — follows WHO DRI framework; no separate Thai-specific
// per-kg rates published; weight-based calculation from DRI is used
// as the standard for Thai pediatric practice.
//
// METHOD: RDA = per-kg rate × body weight, floored by age group
// minimum. When body weight is unavailable, the age-group minimum is
// used as the best available estimate rather than returning nothing.
//
// WHY NOT A FIXED VALUE:
// A 5-year-old at 18kg needs ~17g/day (0.95 × 18).
// A 9-year-old at 29kg needs ~34g/day (max of 0.95×29=28g and the
// 9-13yo minimum of 34g).
// The same 44g figure that was hardcoded before is accurate only for
// a ~46kg child in the 9-13yo group — wrong for younger or lighter
// children, which is the majority of GrowSense users.
// ══════════════════════════════════════════
function calcProteinTargetG(dobStr, weightKg, biologicalSex) {
  // Age in months from DOB
  const ageMonths = dobStr
    ? (new Date() - new Date(dobStr)) / (1000 * 60 * 60 * 24 * 30.4375)
    : null;
  const ageYears = ageMonths ? ageMonths / 12 : null;
  const isMale = (biologicalSex || 'male').toLowerCase() !== 'female';

  // DRI per-kg rates and age-group minimum floors (IOM 2005, Table 10-21)
  let perKgRate, minimumG;

  if (ageYears === null || ageYears < 1) {
    perKgRate = 1.52; minimumG = 11;                // 7-12 months
  } else if (ageYears < 4) {
    perKgRate = 1.05; minimumG = 13;                // 1-3 years
  } else if (ageYears < 9) {
    perKgRate = 0.95; minimumG = 19;                // 4-8 years
  } else if (ageYears < 14) {
    perKgRate = 0.95; minimumG = 34;                // 9-13 years
  } else if (isMale) {
    perKgRate = 0.85; minimumG = 52;                // 14-18 years, male
  } else {
    perKgRate = 0.85; minimumG = 46;                // 14-18 years, female
  }

  const weightBased = weightKg ? Math.round(weightKg * perKgRate) : null;
  return weightBased !== null ? Math.max(weightBased, minimumG) : minimumG;
}

// ══════════════════════════════════════════
// Age-banded calcium + water targets (mirror of the Flutter client).
// Calcium RDA (IOM 2011): 700mg 1-3y, 1000mg 4-8y, 1300mg 9-18y —
// the old flat 1300 was only right for 9-18s and over-asked younger
// children, deflating their nutrition scores. Water beverage AI
// (IOM 2005), 1 glass = 250ml.
// ══════════════════════════════════════════
function calcCalciumTargetMg(dobStr) {
  const age = dobStr ? (new Date() - new Date(dobStr)) / (365.25 * 86400000) : null;
  if (age === null || age >= 9) return 1300;
  if (age >= 4) return 1000;
  return 700;
}

function calcWaterTargetGlasses(dobStr, biologicalSex) {
  const age = dobStr ? (new Date() - new Date(dobStr)) / (365.25 * 86400000) : null;
  const isMale = (biologicalSex || 'male').toLowerCase() !== 'female';
  let ml;
  if (age === null) ml = 1800;
  else if (age < 4) ml = 900;
  else if (age < 9) ml = 1200;
  else if (age < 14) ml = isMale ? 1800 : 1600;
  else ml = isMale ? 2600 : 1800;
  return Math.round(ml / 250);
}

// Zinc RDA (IOM 2001): 3mg 1-3y, 5mg 4-8y, 8mg 9-13y, 11/9mg 14-18y
// M/F. Display target only — zinc is not part of the readiness score.
function calcZincTargetMg(dobStr, biologicalSex) {
  const age = dobStr ? (new Date() - new Date(dobStr)) / (365.25 * 86400000) : null;
  const isMale = (biologicalSex || 'male').toLowerCase() !== 'female';
  if (age === null) return 8;
  if (age < 4) return 3;
  if (age < 9) return 5;
  if (age < 14) return 8;
  return isMale ? 11 : 9;
}

// Growth-oriented sleep target in minutes — keeps the long-standing
// 9.5h for the core 6-12y demographic, bands the edges (AASM ranges).
function calcSleepTargetMin(dobStr) {
  const age = dobStr ? (new Date() - new Date(dobStr)) / (365.25 * 86400000) : null;
  if (age === null) return 570;
  if (age < 3) return 12 * 60;
  if (age < 6) return 11 * 60;
  if (age < 13) return 570; // 9.5h
  return 510; // 8.5h
}

function activeChildNutritionTargets() {
  const child = APP.children[APP.activeChild] || {};
  return {
    calciumMg: calcCalciumTargetMg(child.date_of_birth),
    waterGlasses: calcWaterTargetGlasses(child.date_of_birth, child.biological_sex),
    zincMg: calcZincTargetMg(child.date_of_birth, child.biological_sex),
    sleepMin: calcSleepTargetMin(child.date_of_birth),
  };
}

// ══════════════════════════════════════════
// Nutrition subscore (mirror of Flutter's nutritionSubscore) — see
// FORMULAS.md. Evidence-weighted for LINEAR GROWTH: protein 40
// (IGF-1/height, carries the food matrix), calcium 30, zinc 15
// (meta-analytic linear-growth effect), water 15. A bounded balance
// penalty (×0.80..1.00) discounts single-nutrient days up to 20% but
// NEVER zeroes them, so a day with data still carries into analytics;
// ε-smoothing keeps one legitimately-missing nutrient from
// over-penalizing.
function nutritionSubscore(rProtein, rCalcium, rZinc, rWater) {
  const wP = 0.40, wCa = 0.30, wZn = 0.15, wW = 0.15;
  const base = rProtein*wP + rCalcium*wCa + rZinc*wZn + rWater*wW;
  const eps = 0.12, sm = r => (r + eps) / (1 + eps);
  const sP = sm(rProtein), sCa = sm(rCalcium), sZn = sm(rZinc), sW = sm(rWater);
  const geo = Math.pow(sP, wP) * Math.pow(sCa, wCa) * Math.pow(sZn, wZn) * Math.pow(sW, wW);
  const arith = sP*wP + sCa*wCa + sZn*wZn + sW*wW;
  const evenness = arith <= 0 ? 1 : Math.min(1, geo / arith);
  return base * (0.80 + 0.20 * evenness);
}

// ══════════════════════════════════════════
// Recall Engine estimation ladder (mirror of the Flutter client's
// manualEntryMeta in recall_engine.dart): manual entry always wins
// over an AI estimate, and its trust tier is inferred from how far
// back the day is — never asked. <=2 days: memory is reliable →
// measured 1.0. 3-7 days: items hold up, portions blur → recalled
// 0.85. Beyond: 0.7. Keeping the PWA's writes tiered means a day
// estimated in the Flutter app and then edited here is correctly
// promoted instead of staying gold forever.
// ══════════════════════════════════════════
function manualEntryMeta(logDateStr) {
  const [y, m, d] = String(logDateStr).split('-').map(Number);
  const today = new Date();
  const gap = Math.round(
    (new Date(today.getFullYear(), today.getMonth(), today.getDate()) -
      new Date(y, m - 1, d)) / 86400000
  );
  if (gap <= 2) return { method: 'measured', confidence: 1.0 };
  if (gap <= 7) return { method: 'recalled_manual', confidence: 0.85 };
  return { method: 'recalled_manual', confidence: 0.7 };
}

// Growth-optimized protein target — ~1.26× standard RDA.
// Evidence basis:
//   · IAAO stable isotope method (Hudson et al., Nutrients 2021, PMID 34063030)
//     suggests the true requirement for children 6-10yr is ~1.55 g/kg/day —
//     60% above the DRI nitrogen-balance estimate. 1.2 g/kg is conservative
//     and practical.
//   · Hoppe et al. (EJCN 2004, PMID 15220943): protein 20-30% above RDA
//     significantly elevated serum IGF-1 in prepubertal boys. IGF-1 correlates
//     with height velocity in prepubertal children (Michaelsen et al. 2012).
//   · Review: increases of 70-150% above PRI showed positive trend with IGF-1
//     in 8-15yr children (Nutrients 2023;15(7):1683, PMID 37049522).
//   · Safety ceiling: Pediatric sports nutrition guidelines place 2.5 g/kg as
//     the kidney-safety upper limit for healthy children; 1.2-1.5 g/kg is
//     routinely consumed by active children in observational data with no
//     adverse effects noted. ACSM/DC recommend 1.2-2.0 g/kg for physically
//     active individuals including adolescents.
function calcProteinBoostTargetG(dobStr, weightKg, biologicalSex) {
  const standard = calcProteinTargetG(dobStr, weightKg, biologicalSex);
  const ageMonths = dobStr
    ? (new Date() - new Date(dobStr)) / (1000 * 60 * 60 * 24 * 30.4375)
    : null;
  const ageYears = ageMonths ? ageMonths / 12 : null;

  // Safe upper ceiling per age (kidney solute load consideration for young
  // children; relaxed toward standard athletic guidance for older)
  let boostPerKg, safeMaxPerKg;
  if (ageYears === null || ageYears < 4) {
    boostPerKg = 1.2; safeMaxPerKg = 1.3;  // conservative for under-4
  } else if (ageYears < 14) {
    boostPerKg = 1.2; safeMaxPerKg = 1.5;  // 4-13yr: IAAO-informed, well within safe range
  } else {
    boostPerKg = 1.2; safeMaxPerKg = 1.6;  // 14-18yr: approaching athletic guidance
  }

  const boostWeightBased = weightKg ? Math.round(weightKg * boostPerKg) : null;
  const safeMax = weightKg ? Math.round(weightKg * safeMaxPerKg) : null;
  // Floor: boost must be at least the standard target
  const boost = boostWeightBased !== null
    ? Math.max(boostWeightBased, standard)
    : Math.round(standard * 1.26);
  return safeMax !== null ? Math.min(boost, safeMax) : boost;
}

// Helper: get the active child's protein targets using their profile.
// Returns { standard, boost } in grams — both displayed in the UI.
function activeChildProteinTargets() {
  const c = APP.children[APP.activeChild];
  if (!c) return { standard: 34, boost: 42 }; // 9-13yr fallback
  // Latest weight from the already-loaded measurements array (loaded by
  // refreshActiveChildHistory on tab switch — no extra query needed)
  const latestWeight = (APP.activeChildMeasurements || [])[0]?.mass_weight_kg || null;
  const std  = calcProteinTargetG(c.date_of_birth, latestWeight, c.biological_sex);
  const boost = calcProteinBoostTargetG(c.date_of_birth, latestWeight, c.biological_sex);
  return { standard: std, boost };
}

// Legacy single-value helper — returns the boost target as the "working
// target" used by the readiness ring (so 100% = growth-optimized intake).
function activeChildProteinTarget() {
  return activeChildProteinTargets().boost;
}


function renderChildSwitcher() {
  const sw = document.getElementById('childSwitcher');
  sw.innerHTML = '';
  if (APP.children.length === 0) {
    sw.innerHTML = `<div class="empty-state" style="padding:12px; text-align:left;"><p>${isClinicianRole() ? 'No children have been assigned to your account yet.' : 'Add your first child profile to get started.'}</p></div>`;
  }
  APP.children.forEach((c, i) => {
    const chip = document.createElement('button');
    chip.className = 'child-chip' + (i === APP.activeChild ? ' active' : '');
    chip.innerHTML = `<span class="child-chip-avatar">${(c.avatar || c.name.charAt(0)).toUpperCase()}</span><span class="child-chip-name">${c.name.split(' ')[0]}</span>`;
    chip.onclick = async () => {
      if (APP.activeChild === i) return;
      APP.activeChild = i;
      renderChildSwitcher();
      await loadDayIntoState();      // pulls this child's data for whatever date is currently selected
      loadChildIntoForm();
      await refreshActiveChildHistory();
      await loadWeekStreak();
      updateStats();
      drawGrowthChart();
      drawBMIChart();
      await loadFamilyHeightRecords();
      loadTargetHeightForm();
      resetAIChatForChildSwitch();
      // Reload activity section for newly selected child
      renderActivityCards(); // show defaults immediately
      loadActivitySectionForToday(); // then update with this child's favourites + logged items
    };
    sw.appendChild(chip);
  });
  if (!isClinicianRole()) {
    const addBtn = document.createElement('div');
    addBtn.className = 'add-child-btn';
    addBtn.textContent = '+';
    addBtn.onclick = openSetup;
    sw.appendChild(addBtn);
  }
}

async function addChild() {
  const name = document.getElementById('newChildName').value.trim();
  const dob = document.getElementById('newChildDOB').value;
  const sex = document.getElementById('newChildSex').value;
  if (!name) { showToast('⚠️', t('toast.error.enter_name','Enter a name')); return; }
  if (!dob) { showToast('⚠️', t('toast.error.enter_dob','Enter a date of birth')); return; }

  // ── Tier enforcement: max_children ───────────────────────────────
  // Check the limit before inserting — a client-side-only check is
  // trivially bypassed, so this reads the real limit from the
  // subscription_tier_limits table every time rather than caching it.
  // NULL max_children means unlimited (Pro tier). Only active
  // (non-archived) children count toward the cap.
  const tier = (APP.account && APP.account.subscription_tier) || 'free';
  const limitRes = await sb.from('subscription_tier_limits')
    .select('max_children')
    .eq('tier', tier)
    .maybeSingle();
  if (!limitRes.error && limitRes.data && limitRes.data.max_children !== null) {
    const activeCount = APP.children.filter(c => c.status !== 'archived').length;
    if (activeCount >= limitRes.data.max_children) {
      showToast('⚠️', `Your ${tier} plan supports up to ${limitRes.data.max_children} child profile${limitRes.data.max_children === 1 ? '' : 's'} — upgrade to add more`);
      return;
    }
  }
  // ─────────────────────────────────────────────────────────────────

  // Optional birth-status fields, for SGA/catch-up-growth tracking (see
  // migration_sga_tracking.sql for why is_sga is a confirmed flag, not
  // something this app computes itself).
  const gestWeeksRaw = document.getElementById('newChildGestWeeks').value;
  const birthWeightRaw = document.getElementById('newChildBirthWeight').value;
  const birthLengthRaw = document.getElementById('newChildBirthLength').value;
  const isSGA = document.getElementById('newChildIsSGA').checked;

  const insertPayload = {
    parent_id: APP.session.user.id,
    name, date_of_birth: dob, biological_sex: sex
  };
  if (gestWeeksRaw) insertPayload.gestational_age_weeks = parseInt(gestWeeksRaw);
  if (birthWeightRaw) insertPayload.birth_weight_kg = parseFloat(birthWeightRaw);
  if (birthLengthRaw) insertPayload.birth_length_cm = parseFloat(birthLengthRaw);
  if (isSGA) {
    insertPayload.is_sga = true;
    insertPayload.sga_confirmed_by = APP.session.user.id; // parent confirming what a doctor told them — see note below
  }

  const { data, error } = await sb.from('children').insert(insertPayload).select().single();

  if (error) { showToast('⚠️', 'Could not add child: ' + error.message); return; }

  APP.children.push(data);
  document.getElementById('newChildName').value = '';
  document.getElementById('newChildDOB').value = '';
  document.getElementById('newChildGestWeeks').value = '';
  document.getElementById('newChildBirthWeight').value = '';
  document.getElementById('newChildBirthLength').value = '';
  document.getElementById('newChildIsSGA').checked = false;
  renderChildSwitcher();
  renderChildList();
  populateShareChildSelect();
  showToast('✅', `${name} ${t('toast.child_added','added')}`);
}

// Shows/hides the optional birth-details fields on the child creation
// form — collapsed by default since most parents won't need this.
function toggleBirthDetails(btn) {
  const el = document.getElementById('birthDetailsFields');
  const isHidden = el.classList.contains('hidden');
  el.classList.toggle('hidden');
  btn.textContent = isHidden ? '− Hide birth details' : '+ Add birth details (for SGA / catch-up growth tracking)';
}

// Collapses the USDA-sourcing explanation behind a small (i) button by
// default, rather than always showing the full paragraph — on a phone
// screen that note took up real vertical space every time the
// Nutrition card was open, for text most people only need to read once.
function toggleFoodNote(btn) {
  const el = document.getElementById('foodNotePanel');
  const isHidden = el.classList.contains('hidden');
  el.classList.toggle('hidden');
  btn.classList.toggle('active', isHidden);
}

function renderChildList() {
  const el = document.getElementById('childList');
  if (!el) return;
  if (APP.children.length === 0) {
    el.innerHTML = '';
    return;
  }
  el.innerHTML = APP.children.map(c => {
    const age = ageFromDOB(c.date_of_birth) ?? '—';
    const avatar = (c.avatar || c.name.charAt(0)).toUpperCase();
    const wearableVal = c.wearable_account_email || '';
    return `
    <div class="child-profile-row" id="cpr-${c.child_id}">
      <div class="child-profile-header" onclick="toggleChildProfile('${c.child_id}')">
        <div class="child-profile-info">
          <span class="child-chip-avatar" style="width:30px;height:30px;font-size:13px;">${avatar}</span>
          <div>
            <div class="child-profile-name">${c.name}</div>
            <div class="child-profile-age">Age ${age} · ${c.biological_sex || ''}</div>
          </div>
        </div>
        <span class="child-profile-chevron" id="cpchev-${c.child_id}">›</span>
      </div>
      <div class="child-profile-body hidden" id="cpbody-${c.child_id}">
        <div class="form-row" style="margin-top:4px;">
          <div class="form-lbl">Name</div>
          <input type="text" id="cedit-name-${c.child_id}" class="text-input" value="${c.name}" style="max-width:160px;">
        </div>
        <div class="form-row">
          <div class="form-lbl">Date of birth</div>
          <input type="date" id="cedit-dob-${c.child_id}" class="date-input" value="${c.date_of_birth || ''}" style="max-width:160px;">
        </div>
        <div>
          <div class="form-row" style="margin-bottom:2px;">
            <div class="form-lbl">Fitbit / wearable account email</div>
            <input type="email" id="cedit-wearable-${c.child_id}" class="text-input"
              value="${wearableVal}" placeholder="Optional"
              style="max-width:200px;">
          </div>
          <div class="wearable-email-note">Email the child's Fitbit is registered to. Used to warn you if the wrong account is connected.</div>
        </div>
        <div class="child-profile-actions">
          <button class="btn-secondary" onclick="saveChildSettings('${c.child_id}')">Save</button>
          <button class="btn-link" style="color:var(--flag); font-size:12px;" onclick="deleteChildProfile('${c.child_id}')">Remove profile</button>
        </div>
      </div>
    </div>`;
  }).join('');
}

function toggleChildProfile(childId) {
  const body   = document.getElementById(`cpbody-${childId}`);
  const chevron = document.getElementById(`cpchev-${childId}`);
  if (!body) return;
  const opening = body.classList.contains('hidden');

  // Close all other open profiles
  document.querySelectorAll('.child-profile-body').forEach(b => b.classList.add('hidden'));
  document.querySelectorAll('.child-profile-chevron').forEach(c => c.classList.remove('open'));
  // Close add-child form
  document.getElementById('addChildBody')?.classList.add('hidden');
  document.getElementById('addChildChevron')?.classList.remove('open');

  if (opening) {
    body.classList.remove('hidden');
    chevron?.classList.add('open');
  }
}

function toggleAddChildForm() {
  const body    = document.getElementById('addChildBody');
  const chevron = document.getElementById('addChildChevron');
  if (!body) return;
  const opening = body.classList.contains('hidden');

  // Close all child profile cards
  document.querySelectorAll('.child-profile-body').forEach(b => b.classList.add('hidden'));
  document.querySelectorAll('.child-profile-chevron').forEach(c => c.classList.remove('open'));

  if (opening) {
    body.classList.remove('hidden');
    chevron?.classList.add('open');
  } else {
    body.classList.add('hidden');
    chevron?.classList.remove('open');
  }
}

async function saveChildSettings(childId) {
  const name          = document.getElementById(`cedit-name-${childId}`)?.value?.trim();
  const dob           = document.getElementById(`cedit-dob-${childId}`)?.value?.trim();
  const wearableEmail = document.getElementById(`cedit-wearable-${childId}`)?.value?.trim() || null;

  if (!name) { showToast('⚠️', 'Name cannot be empty'); return; }

  const { error } = await sb.from('children').update({
    name,
    date_of_birth: dob || undefined,
    wearable_account_email: wearableEmail,
  }).eq('child_id', childId);

  if (error) { showToast('⚠️', t('toast.error.save_failed','Save failed') + ': ' + error.message); return; }

  const child = APP.children.find(c => c.child_id === childId);
  if (child) {
    child.name = name;
    if (dob) child.date_of_birth = dob;
    child.wearable_account_email = wearableEmail;
  }

  renderChildSwitcher();
  renderChildList();
  showToast('✅', `${name} — ${t('toast.profile_saved','profile saved')}`);
}

// Named deleteChildProfile, NOT removeChild — every DOM Node has a
// native removeChild() method (Node.prototype.removeChild), and naming
// this function the same thing caused a real collision: the inline
// onclick="removeChild(...)" attribute was resolving to the native DOM
// method instead of this function in some execution contexts, throwing
// "Failed to execute 'removeChild' on 'Node': parameter 1 is not of
// type 'Node'" because the native method expects an actual DOM node
// argument, not a child_id string. Confirmed directly from a real
// browser console error, not assumed.
// Archives a child profile rather than permanently deleting it — per
// the retention policy, nothing a parent removes vanishes immediately.
// The child is hidden from this account's view and a 1-year countdown
// to permanent deletion starts (longer on Pro — see
// subscription_tier_limits.account_archive_retention_days), but every
// measurement, lab result, puberty milestone, and log tied to this
// child stays completely intact in the database. A system_admin can
// restore the profile at any point before the countdown ends. Only the
// scheduled sweep (run_archive_permanent_delete_sweep(), once daily)
// ever performs the real, irreversible delete, and only after the full
// grace period has elapsed.
async function deleteChildProfile(childId) {
  if (APP.children.filter(c => c.status !== 'archived').length <= 1) {
    showToast('⚠️', 'At least one active child profile is required');
    return;
  }
  if (!confirm(t('confirm.archive_child','Remove this child profile? It will be archived for 1 year and can be recovered during that time.'))) return;

  const retentionDays = await getAccountArchiveRetentionDays();
  const archivedAt = new Date();
  const permanentDeleteAfter = new Date(archivedAt.getTime() + retentionDays * 86400000);

  const { error } = await sb.from('children').update({
    status: 'archived',
    archived_at: archivedAt.toISOString(),
    archived_by: APP.session ? APP.session.user.id : null,
    permanent_delete_after: permanentDeleteAfter.toISOString()
  }).eq('child_id', childId);
  if (error) { showToast('⚠️', 'Could not archive: ' + error.message); return; }

  const idx = APP.children.findIndex(c => c.child_id === childId);
  if (idx >= 0) {
    APP.children.splice(idx, 1); // removed from the in-memory active list, not the database
    delete APP.dayStateByChild[idx];
    delete APP.weekStreakByChild[idx];
  }
  if (APP.activeChild >= APP.children.length) APP.activeChild = 0;
  renderChildList();
  renderChildSwitcher();
  populateShareChildSelect();
  await loadDayIntoState();
  loadChildIntoForm();
  await refreshActiveChildHistory();
  await loadWeekStreak();
  showToast('✅', t('toast.child_archived','Child profile archived') + ' — ' + retentionDays + ' ' + t('toast.days_recoverable','days recoverable'));
}

// Looks up this account's actual archive retention window from
// subscription_tier_limits rather than hardcoding 365 in the client —
// Pro gets a longer window (3 years), and a hardcoded client-side
// number would silently be wrong for that tier, or wrong the moment an
// admin changes the policy in the database.
async function getAccountArchiveRetentionDays() {
  const tier = (APP.account && APP.account.subscription_tier) || 'free';
  const { data, error } = await sb.from('subscription_tier_limits').select('account_archive_retention_days').eq('tier', tier).maybeSingle();
  return (!error && data) ? data.account_archive_retention_days : 365; // 365-day fallback if the lookup itself fails, never less protective than the documented default
}

// ══════════════════════════════════════════
// DOCTOR / RESEARCHER SHARING
// ══════════════════════════════════════════
function populateShareChildSelect() {
  const sel = document.getElementById('shareChildSelect');
  if (!sel) return;
  sel.innerHTML = APP.children.map(c => `<option value="${c.child_id}">${c.name}</option>`).join('');
}

async function shareChildWithDoctor() {
  const childId = document.getElementById('shareChildSelect').value;
  const email = document.getElementById('shareDoctorEmail').value.trim();
  if (!childId) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }
  if (!email) { showToast('⚠️', t('toast.error.enter_doctor_email',"Enter the doctor or researcher's email")); return; }

  // find_clinician_by_email is a SECURITY DEFINER Postgres function
  // (see migration_find_clinician_function.sql) — it's the correct fix
  // for the fact that a direct SELECT on user_accounts by email can
  // never work under that table's RLS policy (which only lets a user
  // read their own row, by design — that's not a bug to work around
  // with a looser policy, since loosening it would let any user browse
  // every other user's email and role). The function returns only
  // user_id + account_role, and only for doctor/scientist accounts —
  // never the email itself or any other field, and it can't be used to
  // enumerate which emails exist (a parent's email or an unregistered
  // email both return zero rows, same as a clinician's would if typed
  // wrong).
  const { data: matches, error: lookupError } = await sb.rpc('find_clinician_by_email', {
    lookup_email: email
  });

  if (lookupError) {
    showToast('⚠️', 'Could not look up that account: ' + lookupError.message);
    return;
  }
  const target = matches && matches.length > 0 ? matches[0] : null;

  if (!target) {
    showToast('⚠️', t('toast.error.no_clinician_account','No Doctor or Researcher account found with that email'));
    return;
  }

  const { error } = await sb.from('doctor_patient_assignments').insert({
    doctor_id: target.user_id, child_id: childId, is_active: true
  });

  if (error) {
    showToast('⚠️', error.code === '23505' ? 'Already shared with this account' : 'Could not grant access: ' + error.message);
    return;
  }
  document.getElementById('shareDoctorEmail').value = '';
  showToast('✅', t('toast.access_granted','Access granted'));
  await renderCurrentShares(childId);
}

async function renderCurrentShares(childId) {
  const el = document.getElementById('currentSharesList');
  if (!el) return;
  const { data, error } = await sb
    .from('doctor_patient_assignments')
    .select('assignment_id, doctor_id, is_active, user_accounts(email, account_role)')
    .eq('child_id', childId)
    .eq('is_active', true);

  if (error || !data || data.length === 0) { el.innerHTML = ''; return; }
  el.innerHTML = data.map(a => `
    <div style="display:flex; align-items:center; justify-content:space-between; background:var(--surface2); border-radius:8px; padding:8px 10px; font-size:12px;">
      <span>${a.user_accounts?.email || 'Unknown'} <span class="role-badge ${a.user_accounts?.account_role}" style="margin-left:4px;">${a.user_accounts?.account_role}</span></span>
      <button onclick="revokeShare('${a.assignment_id}', '${childId}')" style="background:none; border:none; color:var(--flag); font-size:11px; font-weight:600; cursor:pointer; padding:4px;">Revoke</button>
    </div>
  `).join('');
}

async function revokeShare(assignmentId, childId) {
  const { error } = await sb.from('doctor_patient_assignments').update({ is_active: false }).eq('assignment_id', assignmentId);
  if (error) { showToast('⚠️', 'Could not revoke: ' + error.message); return; }
  showToast('✅', t('toast.access_revoked','Access revoked'));
  await renderCurrentShares(childId);
}

// For doctor/researcher accounts: show which children are assigned, with
// the parent's contact left deliberately absent here — clinicians see the
// child's data, not the parent's account details, unless that's added later.
async function renderAssignedChildrenList() {
  const el = document.getElementById('assignedChildrenList');
  if (!el) return;
  if (APP.children.length === 0) {
    el.innerHTML = `<div class="empty-state" style="padding:12px;"><p>No assignments yet.</p></div>`;
    return;
  }
  el.innerHTML = APP.children.map(c => `
    <div style="display:flex; align-items:center; gap:8px; background:var(--surface2); border-radius:8px; padding:9px 11px;">
      <span class="child-chip-avatar" style="width:24px;height:24px;font-size:11px;">${(c.avatar || c.name.charAt(0)).toUpperCase()}</span>
      <div>
        <div style="font-size:12.5px; font-weight:600;">${c.name}</div>
        <div style="font-size:10.5px; color:var(--text2);">Age ${ageFromDOB(c.date_of_birth) ?? '—'}</div>
      </div>
    </div>
  `).join('');
}


// ══════════════════════════════════════════
// STATE ADJUSTERS
// ══════════════════════════════════════════
const LIMITS = {
  protein:[0,150], calcium:[0,3000], zinc:[0,30], water:[0,8],
  hanging:[0,180], jumps:[0,300], yogaMin:[0,60], nightWakes:[0,10]
};
const LABELS = {
  protein:' g', calcium:' mg', zinc:' mg', water:' / 8',
  hanging:' sec', jumps:' reps', yogaMin:' min', nightWakes:''
};
const ELIDS = {
  protein:'valProtein', calcium:'valCalcium', zinc:'valZinc', water:'valWater',
  hanging:'valHanging', jumps:'valJumps', yogaMin:'valYoga', nightWakes:'valNightWakes'
};

function adj(key, delta) {
  const s = currentState();
  const [min, max] = LIMITS[key];
  s[key] = Math.max(min, Math.min(max, s[key] + delta));
  const el = document.getElementById(ELIDS[key]);
  if (el) el.textContent = s[key] + LABELS[key];
  if (key === 'water') {
    updateWaterGrid();
    document.getElementById('waterLbl').textContent = `(${s.water}/${activeChildNutritionTargets().waterGlasses} glasses)`;
  { const z = document.getElementById('zincSubLbl'); if (z) z.textContent = `Growth plate co-factor · target ${activeChildNutritionTargets().zincMg}mg/day (for age)`; }
  }
  if (key === 'nightWakes') renderSleepTimeline();
  updateHUD();
}

function setYoga(min, btn) {
  currentState().yogaMin = min;
  document.querySelectorAll('#yogaSeg .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  updateHUD();
}

function setSteroid(val, btn) {
  currentState().steroid = val;
  document.querySelectorAll('.seg .seg-btn').forEach(b => {
    if (b.id && b.id.startsWith('st')) b.classList.remove('active');
  });
  btn.classList.add('active');
}

// Which meal new food-card taps get tagged with. Doesn't affect the
// daily totals shown in the HUD (those stay a flat daily sum, by
// design — see conversation notes on why the full per-meal HUD rewrite
// was deliberately not done) — it only tags each nutrition_log_items
// row, which saveDay() later sums per-meal for the
// protein_breakfast_g/lunch_g/dinner_g columns.
function setMealSlot(meal, btn) {
  APP.activeMealSlot = meal;
  document.querySelectorAll('#mealSlotSeg .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
}

// Switches which reference dataset the growth chart overlays — WHO
// (default, verified) or Thai (approximate, hand-read from a chart
// image — see thai-reference-data-approx.js for exactly why it's
// labeled that way and what that means for precision). Only the height
// chart switches; the BMI chart has no Thai data and stays WHO-only.
function setReferenceStandard(standard, btn) {
  APP.referenceStandard = standard;
  document.querySelectorAll('#referenceToggle .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  drawGrowthChart();
}

// Switches between the existing "zoomed to current age" view and a new
// "full timeline" view showing the entire 0-19y span at once — useful
// for a parent or doctor reviewing the whole growth trajectory from
// birth through puberty in one glance, rather than the day-to-day
// working view.
function setChartZoom(zoom, btn) {
  APP.chartZoom = zoom;
  document.querySelectorAll('#chartZoomToggle .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  drawGrowthChart();
}

// ══════════════════════════════════════════
// TARGET (MID-PARENTAL) HEIGHT — see target-height.js for the full
// method and citations. This function just reads the form, calls the
// calculation, and displays every value transparently — no hidden
// substitution of any entered height, per the design decision recorded
// in target-height.js's header.
// ══════════════════════════════════════════
// Generic collapsible-card-header toggle, used by the Target Height
// card (and reusable for any future card that wants this pattern).
// Toggle a hidden explanatory paragraph — used by the (ⓘ) buttons
// on Analytics stat cards and chart notes. The element starts hidden
// in the HTML; tapping (ⓘ) flips the class each time.
function toggleInfo(id) {
  const el = document.getElementById(id);
  if (el) el.classList.toggle('hidden');
}

function toggleCardCollapse(bodyId, headerEl) {
  const body = document.getElementById(bodyId);
  const chevron = document.getElementById(bodyId + '-chevron');
  const isHidden = body.classList.contains('hidden');
  body.classList.toggle('hidden');
  if (chevron) chevron.textContent = isHidden ? '▴' : '▾';
}

// Switches between the validated parents-only formula and the
// exploratory extended-family-weighted one. See target-height.js's
// calculateExploratoryExtendedTargetHeight() header for exactly why
// these two are NOT equal-confidence and must never be presented as
// such in the UI.
function setTargetHeightFormula(formula, btn) {
  APP.targetHeightFormula = formula;
  document.querySelectorAll('#targetHeightFormulaToggle .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');

  const noteEl = document.getElementById('extendedFormulaNote');
  if (formula === 'extended') {
    noteEl.classList.remove('hidden');
    noteEl.textContent = 'Exploratory — there is no peer-reviewed method for weighting partial extended-family data into a height prediction. This blends your validated parents-only estimate (70% weight) with a standard relatedness-weighted average of whatever extended-family heights you\'ve recorded below (30% weight, using real genetics math for the weighting itself, but an arbitrary blend ratio not derived from any study). Treat this as a "what if" exploration, not a more accurate number than the parents-only result.';
  } else {
    noteEl.classList.add('hidden');
  }

  // Recalculate immediately if heights are already on file, so
  // switching the toggle updates the displayed result right away.
  const child = APP.children[APP.activeChild];
  if (child && child.mother_height_cm != null && child.father_height_cm != null) {
    calculateAndShowTargetHeight();
  }
}

// Restores previously-saved parent heights/ages into the form (and
// shows the calculated result immediately) — fixes the bug where this
// data was never persisted and had to be retyped every visit.
function loadTargetHeightForm() {
  const child = APP.children[APP.activeChild];
  const motherHeightEl = document.getElementById('thMotherHeight');
  const motherAgeEl = document.getElementById('thMotherAge');
  const fatherHeightEl = document.getElementById('thFatherHeight');
  const fatherAgeEl = document.getElementById('thFatherAge');

  if (!child) {
    motherHeightEl.value = ''; motherAgeEl.value = '';
    fatherHeightEl.value = ''; fatherAgeEl.value = '';
    document.getElementById('targetHeightResult').classList.add('hidden');
    return;
  }

  motherHeightEl.value = child.mother_height_cm != null ? child.mother_height_cm : '';
  motherAgeEl.value = child.mother_current_age != null ? child.mother_current_age : '';
  fatherHeightEl.value = child.father_height_cm != null ? child.father_height_cm : '';
  fatherAgeEl.value = child.father_current_age != null ? child.father_current_age : '';

  // If both heights are already on file, show the result right away
  // rather than making the parent click "Calculate" again just to see
  // what they already entered last time.
  if (child.mother_height_cm != null && child.father_height_cm != null) {
    calculateAndShowTargetHeight();
  } else {
    document.getElementById('targetHeightResult').classList.add('hidden');
  }
}

async function calculateAndShowTargetHeight() {
  const child = APP.children[APP.activeChild];
  if (!child) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }

  const motherHeight = parseFloat(document.getElementById('thMotherHeight').value);
  const fatherHeight = parseFloat(document.getElementById('thFatherHeight').value);
  const motherAgeRaw = document.getElementById('thMotherAge').value;
  const fatherAgeRaw = document.getElementById('thFatherAge').value;

  if (!motherHeight || !fatherHeight) {
    showToast('⚠️', t('toast.error.enter_parent_heights',"Enter both parents' heights"));
    return;
  }

  const baseParams = {
    motherHeightCm: motherHeight,
    fatherHeightCm: fatherHeight,
    motherAge: motherAgeRaw ? parseFloat(motherAgeRaw) : null,
    fatherAge: fatherAgeRaw ? parseFloat(fatherAgeRaw) : null,
    childSex: child.biological_sex
  };

  // Always compute the validated parents-only result — this is never
  // skipped or replaced by the exploratory one. See note below on why
  // both are computed and shown together rather than the toggle
  // swapping which single result displays.
  const result = calculateTargetHeight(baseParams);
  if (!result) { showToast('⚠️', 'Could not calculate — check the entered heights'); return; }

  // Persist what was entered, so it's there next time this child/tab is
  // opened — previously this was read-only-from-form and lost on every
  // reload. See migration_parent_height_persistence.sql.
  const { error } = await sb.from('children').update({
    mother_height_cm: motherHeight,
    father_height_cm: fatherHeight,
    mother_current_age: motherAgeRaw ? parseInt(motherAgeRaw) : null,
    father_current_age: fatherAgeRaw ? parseInt(fatherAgeRaw) : null
  }).eq('child_id', child.child_id);

  if (error) {
    showToast('⚠️', 'Calculated, but could not save for next time: ' + error.message);
  } else {
    child.mother_height_cm = motherHeight;
    child.father_height_cm = fatherHeight;
    child.mother_current_age = motherAgeRaw ? parseInt(motherAgeRaw) : null;
    child.father_current_age = fatherAgeRaw ? parseInt(fatherAgeRaw) : null;
  }

  document.getElementById('targetHeightResult').classList.remove('hidden');
  document.getElementById('thResultValue').textContent = result.targetHeightCm;
  document.getElementById('thResultRange').textContent =
    `Likely adult height range: ${result.rangeLowCm}–${result.rangeHighCm}cm (using the real measured spread from the source study, ±${result.residualSD}cm — not a theoretical guess).`;

  const ageNote = (result.motherAgeShrinkageCm > 0 || result.fatherAgeShrinkageCm > 0)
    ? ` Age-correction added back ${result.motherAgeShrinkageCm}cm (mother) and ${result.fatherAgeShrinkageCm}cm (father) for natural height loss with age — see target-height.js for the source.`
    : '';
  document.getElementById('thResultDetail').innerHTML =
    `For comparison, the traditional method (flat ±13cm sex adjustment, no age or regression correction) gives <strong>${result.tannerMidParentalCm}cm</strong>.${ageNote} This is a population-based estimate with real uncertainty (the source study notes ~20% variability in the spread itself) — not a precise prediction, and not a substitute for your pediatrician's assessment, especially if bone age or growth velocity look unusual.`;

  // Exploratory result — shown ALONGSIDE the validated one above
  // (never replacing it) whenever extended-family records exist AND the
  // parent has opted into seeing it via the toggle. Previously this
  // function computed ONE OR THE OTHER depending on the toggle, which
  // meant the two numbers could never be compared without manually
  // re-toggling and re-clicking Calculate — fixed here.
  const exploratoryCard = document.getElementById('thExploratoryCard');
  const hasFamilyData = (APP.familyHeightRecords || []).length > 0;
  if (APP.targetHeightFormula === 'extended' && hasFamilyData) {
    const exploratoryResult = calculateExploratoryExtendedTargetHeight(
      Object.assign({}, baseParams, { familyRecords: APP.familyHeightRecords })
    );
    exploratoryCard.classList.remove('hidden');
    document.getElementById('thExploratoryValue').textContent = exploratoryResult.targetHeightCm;
    document.getElementById('thExploratoryRange').textContent =
      `Likely adult height range: ${exploratoryResult.rangeLowCm}–${exploratoryResult.rangeHighCm}cm.`;
    document.getElementById('thExploratoryDetail').innerHTML =
      `<strong>⚠️ Exploratory — not equal-confidence with the validated result above.</strong> Includes ${exploratoryResult.extendedFamilyUsedCount} extended-family record(s), blended with the validated parents-only estimate (70% weight) using standard relatedness weighting — but the 70/30 blend itself is an arbitrary choice, not a researched constant. See target-height.js for the full explanation.`;
  } else {
    exploratoryCard.classList.add('hidden');
  }
}

// ══════════════════════════════════════════
// EXTENDED FAMILY HEIGHTS (family_height_records table). Used for
// reference display ALWAYS; also read by
// calculateExploratoryExtendedTargetHeight() when a parent explicitly
// switches the formula toggle to "extended" — see
// setTargetHeightFormula() and target-height.js's header for exactly
// why that path is labeled exploratory/unvalidated, and is never the
// default.
// for why. If you're tempted to add these into the calculation later,
// re-read that file's header first: there's no validated method for
// it, and guessing would repeat the mistake the original "ancestral
// traceback" proposal was rejected for.
// ══════════════════════════════════════════
const FAMILY_RELATION_LABELS = {
  maternal_grandmother: 'Maternal grandmother', maternal_grandfather: 'Maternal grandfather',
  paternal_grandmother: 'Paternal grandmother', paternal_grandfather: 'Paternal grandfather',
  maternal_aunt: 'Maternal aunt', maternal_uncle: 'Maternal uncle',
  paternal_aunt: 'Paternal aunt', paternal_uncle: 'Paternal uncle',
  sibling: 'Sibling'
};

async function loadFamilyHeightRecords() {
  const childId = activeChildId();
  const listEl = document.getElementById('familyHeightList');
  if (!listEl) return;
  if (!childId) { listEl.innerHTML = ''; return; }

  const { data, error } = await sb
    .from('family_height_records')
    .select('*')
    .eq('child_id', childId)
    .order('created_at', { ascending: false });

  if (error) { listEl.innerHTML = ''; return; }
  APP.familyHeightRecords = data || [];
  renderFamilyHeightList();
}

function renderFamilyHeightList() {
  const listEl = document.getElementById('familyHeightList');
  if (!listEl) return;
  const items = APP.familyHeightRecords || [];
  if (items.length === 0) {
    listEl.innerHTML = '<div class="log-list-empty">No extended family heights recorded yet.</div>';
    return;
  }
  listEl.innerHTML = items.map(r => {
    const label = FAMILY_RELATION_LABELS[r.relation] || r.relation;
    const ageText = r.age_at_measurement ? ` · age ${r.age_at_measurement}` : '';
    return `
      <div class="log-item-row">
        <div class="log-item-left">
          <span class="log-item-emoji">👤</span>
          <div class="log-item-info">
            <span class="log-item-name">${label}</span>
            <span class="log-item-meta">${r.notes ? r.notes : ''}${ageText}</span>
          </div>
        </div>
        <div class="log-item-right">
          <span class="log-item-amount">${r.height_cm}cm</span>
          <button class="log-item-delete" onclick="deleteFamilyHeightRecord('${r.record_id}')" aria-label="Remove">×</button>
        </div>
      </div>
    `;
  }).join('');
}

async function addFamilyHeightRecord() {
  const childId = activeChildId();
  if (!childId) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }

  const relation = document.getElementById('newFamilyRelation').value;
  const height = document.getElementById('newFamilyHeight').value;
  const age = document.getElementById('newFamilyAge').value;
  const notes = document.getElementById('newFamilyNotes').value.trim();

  if (!height) { showToast('⚠️', t('toast.error.enter_height','Enter a height')); return; }

  const { data, error } = await sb.from('family_height_records').insert({
    child_id: childId,
    relation,
    height_cm: parseFloat(height),
    age_at_measurement: age ? parseInt(age) : null,
    notes: notes || null,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) { showToast('⚠️', t('toast.error.save_failed','Could not save') + ': ' + error.message); return; }

  APP.familyHeightRecords = APP.familyHeightRecords || [];
  APP.familyHeightRecords.unshift(data);
  renderFamilyHeightList();

  document.getElementById('newFamilyHeight').value = '';
  document.getElementById('newFamilyAge').value = '';
  document.getElementById('newFamilyNotes').value = '';
  showToast('✅', t('toast.family_record_added','Added to family record'));
}

async function deleteFamilyHeightRecord(id) {
  if (!confirm(t('confirm.remove_family_record','Remove this family height record? This cannot be undone.'))) return;
  const { error } = await sb.from('family_height_records').delete().eq('record_id', id);
  if (error) { showToast('⚠️', t('toast.error.remove_failed','Could not remove') + ': ' + error.message); return; }
  APP.familyHeightRecords = (APP.familyHeightRecords || []).filter(r => r.record_id !== id);
  renderFamilyHeightList();
}

// ══════════════════════════════════════════
// FOOD CARDS — real USDA-sourced quick-add buttons
// Tapping a card adds its protein/zinc/calcium (scaled to the card's
// typical serving) to today's running totals (currentState().protein,
// .zinc, .calcium) — same fields the manual steppers below edit, so
// either method reaches the same numbers. Long-press (mobile) or
// right-click (desktop) subtracts the same amount, for misclick
// correction, mirroring the original screenshot's interaction model.
// ══════════════════════════════════════════
const LONG_PRESS_MS = 550;

// Builds the main Nutrition grid from this child's food_favorites —
// previously this always rendered the same fixed FOOD_REFERENCE_DATA
// list for every user. Now it renders whichever foods (preset or
// custom) are in APP.foodFavorites, in their saved display_order. If a
// child has no favorites set yet (new child, or favorites haven't
// loaded), falls back to the original default set so the grid is never
// empty on first use.
function buildFoodCardGrid() {
  const grid = document.getElementById('foodCardGrid');
  if (!grid) return;
  grid.innerHTML = '';

  if (typeof FOOD_REFERENCE_DATA === 'undefined') {
    grid.innerHTML = '<div class="setup-note" style="font-size:11px;">Food reference data not loaded.</div>';
    return;
  }

  const foodsToShow = resolveFavoriteFoods();

  foodsToShow.forEach(food => {
    const scale = food.servingGrams / 100;
    const addProtein = food.isCustom
      ? food.proteinPerServing // custom foods store the value already for THIS serving, not per-100g
      : Math.round(food.per100g.protein_g * scale * 10) / 10;
    const addZinc = food.isCustom
      ? food.zincPerServing
      : (food.per100g.zinc_mg != null ? Math.round(food.per100g.zinc_mg * scale * 100) / 100 : null);
    const addCalcium = food.isCustom
      ? food.calciumPerServing
      : (food.per100g.calcium_mg != null ? Math.round(food.per100g.calcium_mg * scale) : null);

    const card = document.createElement('div');
    card.className = 'food-card' + (food.isCustom ? ' manual-entry' : '');
    card.dataset.foodId = food.id;
    card.title = food.isCustom ? 'Custom food — your own estimated values, not USDA-verified' : food.source;
    card.innerHTML = `
      <div class="food-card-top">
        <span class="food-card-name"><span class="food-card-emoji">${food.emoji}</span>${food.name}</span>
        <span class="food-card-add">+${addProtein}g</span>
      </div>
      <div class="food-card-portion">${food.servingGrams}g · ${food.portionVisual}</div>
      <div class="food-card-prep">${food.prepNote || ''}</div>
      <div class="food-card-tapcount" id="tapcount-${food.id}"></div>
    `;
    attachFoodCardHandlers(card, (direction) => applyFoodTap(food, addProtein, addZinc, addCalcium, direction));
    grid.appendChild(card);
  });

  // "Protein Boost" — flat manual +10g, not tied to any food record.
  // Always shown, not subject to the favorites system, since it's a
  // utility quick-add rather than a specific food.
  const boostCard = document.createElement('div');
  boostCard.className = 'food-card manual-entry';
  boostCard.title = 'Manual entry — read the protein amount off any product label and tap to log it';
  boostCard.innerHTML = `
    <div class="food-card-top">
      <span class="food-card-name"><span class="food-card-emoji">💪</span>Protein Boost</span>
      <span class="food-card-add">+10g</span>
    </div>
    <div class="food-card-prep">manual — match to package label</div>
  `;
  attachFoodCardHandlers(boostCard, (direction) => applyFoodTap(null, 10, null, null, direction));
  grid.appendChild(boostCard);

  updateFoodCardTapCounts();
}

// ══════════════════════════════════════════
// CUSTOMIZABLE FOOD CARDS — food_favorites + custom_foods
// Previously the Nutrition grid always showed the same fixed 9 USDA
// preset cards for every user, with no way to add a food not in that
// list or choose a different subset. Now: a parent can browse the
// full preset library plus their own custom foods in a popup (the
// "Food library" modal), star/unstar which ones show on the main
// grid, and add a new custom food with manually-entered protein/zinc/
// calcium (explicitly labeled as a self-reported estimate, not a USDA
// value — there's no auto-lookup yet, noted directly as a later
// improvement). Favorites and custom foods are both scoped per child.
// ══════════════════════════════════════════

// Combines this child's favorited preset + custom foods into the
// single list buildFoodCardGrid() renders, in saved display order.
// Falls back to the original default 9 presets if no favorites are
// set yet, so a new child's grid is never empty.
function resolveFavoriteFoods() {
  const favorites = APP.foodFavorites || [];
  if (favorites.length === 0) {
    // No favorites configured yet — show the original default set
    // (the first 9 presets, excluding the 2 newly-added ones, so
    // existing users see exactly what they're used to until they
    // actively choose to customize).
    return FOOD_REFERENCE_DATA.filter(f => f.id !== 'peanut_butter' && f.id !== 'tofu');
  }

  const resolved = [];
  for (const fav of favorites) {
    if (fav.food_source === 'preset') {
      const preset = FOOD_REFERENCE_DATA.find(f => f.id === fav.food_ref_id);
      if (preset) resolved.push(preset);
    } else {
      const custom = (APP.customFoods || []).find(c => c.custom_food_id === fav.food_ref_id);
      if (custom) {
        resolved.push({
          id: custom.custom_food_id,
          name: custom.name,
          emoji: custom.emoji || '🍽️',
          prepNote: '',
          portionVisual: custom.serving_description || '',
          servingGrams: custom.serving_grams,
          isCustom: true,
          proteinPerServing: custom.protein_g,
          zincPerServing: custom.zinc_mg,
          calciumPerServing: custom.calcium_mg
        });
      }
    }
  }
  return resolved;
}

async function loadFoodFavoritesAndCustomFoods() {
  const childId = activeChildId();
  if (!childId) { APP.foodFavorites = []; APP.customFoods = []; return; }

  const [favRes, customRes] = await Promise.all([
    sb.from('food_favorites').select('*').eq('child_id', childId).order('display_order'),
    sb.from('custom_foods').select('*').eq('child_id', childId).order('created_at', { ascending: false })
  ]);

  APP.foodFavorites = (!favRes.error && favRes.data) ? favRes.data : [];
  APP.customFoods = (!customRes.error && customRes.data) ? customRes.data : [];
  buildFoodCardGrid();
}

// ── Food library browse state ─────────────────────────────────────
// Group mode ('type' | 'region') persists across open/close within
// a session so the parent doesn't have to re-select each time.
let _foodLibGroupMode = 'type';
let _foodLibCategoryFilter = 'all'; // 'all' | 'chicken'|'beef'|'pork'|'fish'|'seafood'|'egg'|'dairy'|'plant'|'composite'

const FOOD_TYPE_GROUPS = [
  { key: 'chicken',   label: 'Chicken & Poultry' },
  { key: 'beef',      label: 'Beef' },
  { key: 'pork',      label: 'Pork' },
  { key: 'fish',      label: 'Fish' },
  { key: 'seafood',   label: 'Seafood' },
  { key: 'egg',       label: 'Eggs' },
  { key: 'dairy',     label: 'Dairy' },
  { key: 'plant',     label: 'Plant-based' },
  { key: 'composite', label: 'Mixed Dishes & Soups' },
  { key: 'deli',      label: 'Deli & Processed Meats' },
];

const FOOD_REGION_GROUPS = [
  { key: 'asia',          label: 'Asia',          regions: ['cn','kr','th','vn'] },
  { key: 'middleeast',    label: 'Middle East',    regions: ['ae'] },
  { key: 'europe',        label: 'Europe',         regions: ['eu'] },
  { key: 'international', label: 'International',  regions: ['global','us'] },
];

function openFoodLibraryModal() {
  if (!activeChildId()) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }
  // Reset search + category tabs to clean state on every open
  const searchEl = document.getElementById('foodLibrarySearch');
  if (searchEl) searchEl.value = '';
  _resetFoodLibraryBrowseUI();
  initFoodExplainer();
  renderFoodLibraryBrowseList('');
  renderFoodLibraryMineList();
  document.getElementById('foodLibraryModal').classList.remove('hidden');
}

// ── "Why protein, not everything" explainer — parity with the Flutter
// Food tab. New parents try to log potato and fruit; this card sets
// the protein/zinc/calcium focus once, then stays dismissed per device.
function initFoodExplainer() {
  const card = document.getElementById('foodExplainerCard');
  if (!card) return;
  if (localStorage.getItem('gs_food_explainer_dismissed') === '1') {
    card.classList.add('hidden');
    return;
  }
  document.getElementById('foodExplainerTitle').textContent =
    '🌱 ' + t('flutter.food.explainer_title', 'Why we track protein, not everything');
  document.getElementById('foodExplainerBody').textContent =
    t('flutter.food.explainer_body',
      "GrowSense isn't a calorie counter — it follows the nutrients that drive a child's height: protein, zinc and calcium. Log the protein part of a meal (the egg, chicken, milk, tofu) — you don't need to log every potato or piece of fruit.");
  document.getElementById('foodExplainerLink').textContent =
    t('flutter.food.explainer_link', 'Learn why →');
  card.classList.remove('hidden');
}

function dismissFoodExplainer() {
  localStorage.setItem('gs_food_explainer_dismissed', '1');
  const card = document.getElementById('foodExplainerCard');
  if (card) card.classList.add('hidden');
}

function closeFoodLibraryModal(e) {
  // If called from the overlay onclick, only close when clicking the
  // backdrop itself — not when clicking inside the sheet.
  if (e && e.target !== document.getElementById('foodLibraryModal')) return;
  document.getElementById('foodLibraryModal').classList.add('hidden');
}

// Resets category tab to "All" and clears search on every open so
// the parent always starts from a clean state.
function _resetFoodLibraryBrowseUI() {
  _foodLibCategoryFilter = 'all';
  document.querySelectorAll('.food-cat-tab').forEach((b, i) => {
    b.classList.toggle('active', i === 0);
  });
  const groupSeg = document.getElementById('foodGroupSeg');
  if (groupSeg) groupSeg.style.display = '';
}

function setFoodCategoryFilter(cat, btn) {
  _foodLibCategoryFilter = cat;
  document.querySelectorAll('.food-cat-tab').forEach(b => b.classList.remove('active'));
  if (btn) btn.classList.add('active');
  // Group-by toggle is only meaningful when showing all foods
  const groupSeg = document.getElementById('foodGroupSeg');
  if (groupSeg) groupSeg.style.display = cat === 'all' ? '' : 'none';
  renderFoodLibraryBrowseList();
}

function setFoodGroupMode(mode, btn) {
  _foodLibGroupMode = mode;
  document.querySelectorAll('#foodGroupSeg .seg-btn').forEach(b => b.classList.remove('active'));
  if (btn) btn.classList.add('active');
  renderFoodLibraryBrowseList();
}

function onFoodLibrarySearch(val) {
  renderFoodLibraryBrowseList(val);
}

// Logs one serving of a food directly from the library browse list,
// without requiring the parent to star it first. Identical math to
// the food-card tap on the Today grid — same applyFoodTap() call,
// same recordNutritionLogItem() path, same HUD update.
function logFoodFromLibrary(source, refId) {
  let protein, zinc, calcium, foodObj, name;

  if (source === 'preset') {
    const food = (typeof FOOD_REFERENCE_DATA !== 'undefined')
      ? FOOD_REFERENCE_DATA.find(f => f.id === refId) : null;
    if (!food) return;
    const scale = food.servingGrams / 100;
    protein  = Math.round(food.per100g.protein_g * scale * 10) / 10;
    zinc     = food.per100g.zinc_mg     != null ? Math.round(food.per100g.zinc_mg     * scale * 100) / 100 : null;
    calcium  = food.per100g.calcium_mg  != null ? Math.round(food.per100g.calcium_mg  * scale)             : null;
    foodObj  = food;
    name     = food.name;
  } else {
    // Custom food — values are already per-serving
    const custom = (APP.customFoods || []).find(c => c.custom_food_id === refId);
    if (!custom) return;
    protein  = Number(custom.protein_g) || 0;
    zinc     = custom.zinc_mg    != null ? Number(custom.zinc_mg)    : null;
    calcium  = custom.calcium_mg != null ? Number(custom.calcium_mg) : null;
    foodObj  = { id: null, name: custom.name };
    name     = custom.name;
  }

  applyFoodTap(foodObj, protein, zinc, calcium, 1);
  showToast('✅', `${name} · +${protein}g protein`);
}

function setFoodLibraryTab(tab, btn) {
  document.querySelectorAll('#foodLibraryTabs .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  document.getElementById('foodLibraryBrowsePane').classList.toggle('hidden', tab !== 'browse');
  document.getElementById('foodLibraryMinePane').classList.toggle('hidden', tab !== 'mine');
  document.getElementById('foodLibraryAddPane').classList.toggle('hidden', tab !== 'add');
}

function isFoodFavorited(source, refId) {
  return (APP.foodFavorites || []).some(f => f.food_source === source && f.food_ref_id === String(refId));
}

// Renders the food library browse list with:
//   • live search filtering (name + prepNote)
//   • grouping by protein type OR region (no flags — Asia / Middle East / Europe / International)
//   • ★ star button  — pins/unpins from the Today home grid
//   • + log button   — logs one serving immediately, no starring required
//
// searchQuery is read from the #foodLibrarySearch input if not passed
// (so callers that don't have the value handy can just call with no arg).
function renderFoodLibraryBrowseList(searchQuery) {
  const listEl = document.getElementById('foodLibraryBrowseList');
  if (!listEl) return;

  if (searchQuery === undefined) {
    const searchEl = document.getElementById('foodLibrarySearch');
    searchQuery = searchEl ? searchEl.value : '';
  }
  const q = (searchQuery || '').toLowerCase().trim();

  // ── Filtered data sets ────────────────────────────────────────────
  const presets = (typeof FOOD_REFERENCE_DATA !== 'undefined' ? FOOD_REFERENCE_DATA : [])
    .filter(f => !q || f.name.toLowerCase().includes(q) || (f.prepNote || '').toLowerCase().includes(q));

  const customs = (APP.customFoods || [])
    .filter(c => !q || c.name.toLowerCase().includes(q));

  // ── Row builders ──────────────────────────────────────────────────
  // Escape single-quotes in names used inside onclick attributes
  const esc = s => String(s).replace(/'/g, "\\'");

  function presetRow(f) {
    const fav  = isFoodFavorited('preset', f.id);
    const scale = f.servingGrams / 100;
    const prot = Math.round(f.per100g.protein_g * scale * 10) / 10;
    const sub  = `${f.servingGrams}g · +${prot}g protein`;
    // Salty flag: high-sodium foods in their own right (≥500 mg/100g)
    // — a property of the food, so the flag is stable per portion.
    // Gold (estimated) token, never the red clinical-flag colour.
    const salty = (f.per100g.sodium_mg || 0) >= 500
      ? ` <span style="font-size:9px; font-weight:700; color:var(--estimated); background:color-mix(in srgb, var(--estimated) 14%, transparent); border-radius:4px; padding:1px 5px; vertical-align:1px; white-space:nowrap;">⚠ ${t('flutter.food.salty','Salty')}</span>`
      : '';
    return `<div class="log-item-row" style="padding:9px 0; border-bottom:0.5px solid var(--border2); display:flex; align-items:center; justify-content:space-between; gap:6px;">
      <div style="display:flex; align-items:center; gap:10px; min-width:0;">
        <span style="font-size:20px; width:26px; text-align:center; flex-shrink:0;">${f.emoji}</span>
        <div style="min-width:0;">
          <div style="font-size:13px; font-weight:500; color:var(--text1); white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${f.name}${salty}</div>
          <div style="font-size:11px; color:var(--text3);">${sub}</div>
        </div>
      </div>
      <div style="display:flex; align-items:center; gap:5px; flex-shrink:0;">
        <button class="favorite-star ${fav ? 'active' : ''}"
          onclick="toggleFoodFavorite('preset','${esc(f.id)}',this)"
          aria-label="${fav ? 'Remove from grid' : 'Add to grid'}"
          style="background:none; border:none; cursor:pointer; font-size:17px; padding:4px 2px; color:${fav ? 'var(--estimated)' : 'var(--text3)'}; line-height:1;">${fav ? '★' : '☆'}</button>
        <button onclick="logFoodFromLibrary('preset','${esc(f.id)}')"
          aria-label="Log ${esc(f.name)}"
          style="background:var(--accent); color:#fff; border:none; border-radius:8px; width:30px; height:30px; font-size:19px; font-weight:600; cursor:pointer; display:flex; align-items:center; justify-content:center; flex-shrink:0; line-height:1;">+</button>
      </div>
    </div>`;
  }

  function customRow(c) {
    const fav = isFoodFavorited('custom', c.custom_food_id);
    const sub = `${c.serving_grams}g · +${c.protein_g}g protein (est.)`;
    return `<div class="log-item-row" style="padding:9px 0; border-bottom:0.5px solid var(--border2); display:flex; align-items:center; justify-content:space-between; gap:6px;">
      <div style="display:flex; align-items:center; gap:10px; min-width:0;">
        <span style="font-size:20px; width:26px; text-align:center; flex-shrink:0;">${c.emoji || '🍽️'}</span>
        <div style="min-width:0;">
          <div style="font-size:13px; font-weight:500; color:var(--text1); white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${c.name}</div>
          <div style="font-size:11px; color:var(--text3);">${sub}</div>
        </div>
      </div>
      <div style="display:flex; align-items:center; gap:5px; flex-shrink:0;">
        <button class="favorite-star ${fav ? 'active' : ''}"
          onclick="toggleFoodFavorite('custom','${esc(c.custom_food_id)}',this)"
          aria-label="${fav ? 'Remove from grid' : 'Add to grid'}"
          style="background:none; border:none; cursor:pointer; font-size:17px; padding:4px 2px; color:${fav ? 'var(--estimated)' : 'var(--text3)'}; line-height:1;">${fav ? '★' : '☆'}</button>
        <button onclick="logFoodFromLibrary('custom','${esc(c.custom_food_id)}')"
          aria-label="Log ${esc(c.name)}"
          style="background:var(--accent); color:#fff; border:none; border-radius:8px; width:30px; height:30px; font-size:19px; font-weight:600; cursor:pointer; display:flex; align-items:center; justify-content:center; flex-shrink:0; line-height:1;">+</button>
      </div>
    </div>`;
  }

  function groupHeader(label, count) {
    return `<div style="padding:10px 0 3px; font-size:10.5px; font-weight:600; color:var(--text2); letter-spacing:0.06em; text-transform:uppercase; border-bottom:1.5px solid var(--border); margin-top:8px; display:flex; justify-content:space-between;">
      <span>${label}</span>
      <span style="font-weight:400; opacity:0.6;">${count}</span>
    </div>`;
  }

  // ── Build HTML ────────────────────────────────────────────────────
  let html = '';
  let totalShown = 0;

  if (_foodLibCategoryFilter !== 'all') {
    // ── Category tab active: flat filtered list, no group headers ──
    const filtered = presets.filter(f => f.category === _foodLibCategoryFilter);
    if (filtered.length) {
      filtered.forEach(f => { html += presetRow(f); totalShown++; });
    }
    // Custom foods don't have a category — show them only if the
    // parent is actively searching (so their search results appear).
    if (q && customs.length) {
      html += groupHeader('My Custom Foods', customs.length);
      customs.forEach(c => { html += customRow(c); totalShown++; });
    }
  } else {
    // ── "All" tab: grouped by type or region ──────────────────────
    if (_foodLibGroupMode === 'type') {
      FOOD_TYPE_GROUPS.forEach(grp => {
        const items = presets.filter(f => f.category === grp.key);
        if (!items.length) return;
        html += groupHeader(grp.label, items.length);
        items.forEach(f => { html += presetRow(f); totalShown++; });
      });
      const uncat = presets.filter(f => !f.category);
      if (uncat.length) {
        html += groupHeader('Other', uncat.length);
        uncat.forEach(f => { html += presetRow(f); totalShown++; });
      }
    } else {
      // By region — text labels only, no flag icons
      FOOD_REGION_GROUPS.forEach(grp => {
        const items = presets.filter(f => grp.regions.includes(f.region || 'global'));
        if (!items.length) return;
        html += groupHeader(grp.label, items.length);
        items.forEach(f => { html += presetRow(f); totalShown++; });
      });
      const knownRegions = FOOD_REGION_GROUPS.flatMap(g => g.regions);
      const unknown = presets.filter(f => f.region && !knownRegions.includes(f.region));
      if (unknown.length) {
        html += groupHeader('Other', unknown.length);
        unknown.forEach(f => { html += presetRow(f); totalShown++; });
      }
    }
    // Custom foods always at the bottom in "All" mode
    if (customs.length) {
      html += groupHeader('My Custom Foods', customs.length);
      customs.forEach(c => { html += customRow(c); totalShown++; });
    }
  }

  if (totalShown === 0) {
    const msg = q
      ? `No foods match <em>"${q}"</em>`
      : 'No foods in this category yet.';
    html = `<div style="text-align:center; padding:28px 0; color:var(--text3); font-size:13px;">${msg}</div>`;
  }

  listEl.innerHTML = html;
}

function renderFoodLibraryMineList() {
  const listEl = document.getElementById('foodLibraryMineList');
  if (!listEl) return;
  const items = APP.customFoods || [];
  if (items.length === 0) {
    listEl.innerHTML = '<div class="log-list-empty">No custom foods added yet — use the "Add new" tab.</div>';
    return;
  }
  listEl.innerHTML = items.map(c => `
    <div class="log-item-row">
      <div class="log-item-left">
        <span class="log-item-emoji">${c.emoji || '🍽️'}</span>
        <div class="log-item-info">
          <span class="log-item-name">${c.name}</span>
          <span class="log-item-meta">${c.serving_grams}g${c.serving_description ? ' · ' + c.serving_description : ''} · ${c.protein_g}g protein (estimated)</span>
        </div>
      </div>
      <div class="log-item-right">
        <button class="log-item-delete" onclick="deleteCustomFood('${c.custom_food_id}')" aria-label="Remove">×</button>
      </div>
    </div>
  `).join('');
}

async function toggleFoodFavorite(source, refId, btn) {
  const childId = activeChildId();
  const alreadyFav = isFoodFavorited(source, refId);

  if (alreadyFav) {
    const existing = APP.foodFavorites.find(f => f.food_source === source && f.food_ref_id === String(refId));
    const { error } = await sb.from('food_favorites').delete().eq('favorite_id', existing.favorite_id);
    if (error) { showToast('⚠️', 'Could not update: ' + error.message); return; }
    APP.foodFavorites = APP.foodFavorites.filter(f => f.favorite_id !== existing.favorite_id);
  } else {
    const nextOrder = APP.foodFavorites.length;
    const { data, error } = await sb.from('food_favorites').insert({
      child_id: childId, food_source: source, food_ref_id: String(refId), display_order: nextOrder
    }).select().single();
    if (error) { showToast('⚠️', 'Could not update: ' + error.message); return; }
    // Reassigns rather than mutating in place — same defensive
    // pattern as addCustomFood(), avoiding any array-aliasing risk
    // regardless of what the data layer returns.
    APP.foodFavorites = [...APP.foodFavorites, data];
  }

  renderFoodLibraryBrowseList();
  buildFoodCardGrid();
}

async function addCustomFood() {
  const childId = activeChildId();
  const name = document.getElementById('newCustomFoodName').value.trim();
  const grams = parseFloat(document.getElementById('newCustomFoodGrams').value);
  const desc = document.getElementById('newCustomFoodDesc').value.trim();
  const protein = parseFloat(document.getElementById('newCustomFoodProtein').value);
  const zincRaw = document.getElementById('newCustomFoodZinc').value;
  const calciumRaw = document.getElementById('newCustomFoodCalcium').value;

  if (!name) { showToast('⚠️', t('toast.error.enter_food_name','Enter a food name')); return; }
  if (!grams || grams <= 0) { showToast('⚠️', t('toast.error.enter_serving_size','Enter a valid serving size')); return; }
  if (!protein || protein < 0) { showToast('⚠️', t('toast.error.enter_protein','Enter the protein amount for this serving')); return; }

  // Same 5 (free) / 50 (paid) per-child cap as the Flutter app — a
  // UX/abuse cap and upgrade boundary, not a storage concern.
  const customLimit = isPremium() ? 50 : 5;
  if ((APP.customFoods || []).length >= customLimit) {
    showToast('⚠️', t('toast.error.custom_food_limit',
      'Your plan supports up to {n} custom foods — remove one or upgrade')
      .replace('{n}', customLimit));
    return;
  }

  const { data, error } = await sb.from('custom_foods').insert({
    child_id: childId,
    name: name,
    serving_grams: grams,
    serving_description: desc || null,
    protein_g: protein,
    zinc_mg: zincRaw ? parseFloat(zincRaw) : null,
    calcium_mg: calciumRaw ? parseFloat(calciumRaw) : null,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) { showToast('⚠️', t('toast.error.save_failed','Could not save') + ': ' + error.message); return; }

  // Reassigns rather than mutating APP.customFoods in place — safer
  // regardless of whether the data layer happens to return a fresh
  // array or (as caught directly in testing, when the test stub
  // returned the same array reference it stored internally) the same
  // underlying array reference, which a naive .unshift() could double
  // up against.
  APP.customFoods = [data, ...(APP.customFoods || [])];

  document.getElementById('newCustomFoodName').value = '';
  document.getElementById('newCustomFoodGrams').value = '';
  document.getElementById('newCustomFoodDesc').value = '';
  document.getElementById('newCustomFoodProtein').value = '';
  document.getElementById('newCustomFoodZinc').value = '';
  document.getElementById('newCustomFoodCalcium').value = '';

  renderFoodLibraryMineList();
  renderFoodLibraryBrowseList();
  showToast('✅', t('toast.custom_food_added','Custom food added — star it in "Browse all" to show it on the grid'));
}

async function deleteCustomFood(id) {
  if (!confirm(t('confirm.remove_custom_food','Remove this custom food? This cannot be undone.'))) return;

  // Also remove any favorite pointing at this custom food, so a
  // deleted food can't leave a dangling, unresolvable favorite that
  // would silently vanish from the grid with no explanation.
  const favToRemove = (APP.foodFavorites || []).find(f => f.food_source === 'custom' && f.food_ref_id === id);
  if (favToRemove) {
    await sb.from('food_favorites').delete().eq('favorite_id', favToRemove.favorite_id);
    APP.foodFavorites = APP.foodFavorites.filter(f => f.favorite_id !== favToRemove.favorite_id);
  }

  const { error } = await sb.from('custom_foods').delete().eq('custom_food_id', id);
  if (error) { showToast('⚠️', t('toast.error.remove_failed','Could not remove') + ': ' + error.message); return; }

  APP.customFoods = (APP.customFoods || []).filter(c => c.custom_food_id !== id);
  renderFoodLibraryMineList();
  renderFoodLibraryBrowseList();
  buildFoodCardGrid();
}

// Wires both the tap/click (add) and long-press/right-click (subtract)
// behavior onto a single card element.
function attachFoodCardHandlers(card, onAdd) {
  let pressTimer = null;
  let didLongPress = false;

  const startPress = () => {
    didLongPress = false;
    pressTimer = setTimeout(() => {
      didLongPress = true;
      card.classList.add('flash-subtract');
      setTimeout(() => card.classList.remove('flash-subtract'), 200);
      onAdd(-1); // negative direction = subtract
    }, LONG_PRESS_MS);
  };
  const cancelPress = () => { if (pressTimer) clearTimeout(pressTimer); };

  // IMPORTANT: a real tap on a touchscreen fires touchstart -> touchend,
  // and then the browser ALSO synthesizes a click event afterward (for
  // compatibility with code that only listens for click). Without
  // preventDefault() here, a single tap would call onAdd(1) twice — once
  // from touchend, once from the synthetic click — which is exactly what
  // happened in production: real logged rows showed pairs of identical
  // entries 1-20ms apart. touchstart must NOT be passive for
  // preventDefault() to work in touchend.
  card.addEventListener('touchstart', startPress);
  card.addEventListener('touchend', (e) => {
    e.preventDefault(); // suppresses the browser's synthetic click that would otherwise double-fire onAdd
    cancelPress();
    if (!didLongPress) {
      card.classList.add('flash-add');
      setTimeout(() => card.classList.remove('flash-add'), 200);
      onAdd(1);
    }
  });
  card.addEventListener('touchmove', cancelPress);
  card.addEventListener('touchcancel', cancelPress);

  card.addEventListener('mousedown', startPress);
  card.addEventListener('mouseup', () => cancelPress());
  card.addEventListener('mouseleave', cancelPress);
  card.addEventListener('click', () => {
    // On a touch device this won't fire at all now (preventDefault above
    // suppresses it). On a real mouse/trackpad (desktop), there is no
    // touchend at all, so this remains the only path — still needed.
    if (!didLongPress) {
      card.classList.add('flash-add');
      setTimeout(() => card.classList.remove('flash-add'), 200);
      onAdd(1);
    }
  });
  card.addEventListener('contextmenu', (e) => {
    e.preventDefault(); // right-click = subtract, matches the original screenshot's "right-click (PC)" instruction
    card.classList.add('flash-subtract');
    setTimeout(() => card.classList.remove('flash-subtract'), 200);
    onAdd(-1);
  });
}

// direction: 1 to add, -1 to subtract (long-press/right-click correction)
// direction: 1 to add, -1 to subtract. `food` is the FOOD_REFERENCE_DATA
// entry (or null for manual entries like Protein Boost) — used to name
// the log row. opts.skipLog is set by deleteNutritionLogItem(), which
// already deleted its own row and only needs the totals adjusted here,
// not a second log-list mutation.
function applyFoodTap(food, proteinAmt, zincAmt, calciumAmt, direction, opts) {
  opts = opts || {};
  adjustNutritionTotals(proteinAmt, zincAmt, calciumAmt, direction);

  if (opts.skipLog) return; // caller (deleteNutritionLogItem) already handled the log row itself

  if (direction > 0) {
    // A tap: record a new row for this specific food event.
    const foodName = food ? food.name : 'Protein Boost (manual)';
    const foodId = food ? food.id : null;
    // Auto-capture the minor co-factors from the food's per-100g values
    // for this one serving. Analytics-only; absent on manual/custom taps.
    let ironAmt = null, vitDAmt = null;
    if (food && food.per100g && food.servingGrams) {
      const scale = food.servingGrams / 100;
      if (food.per100g.iron_mg != null) ironAmt = Math.round(food.per100g.iron_mg * scale * 100) / 100;
      if (food.per100g.vitamin_d_iu != null) vitDAmt = Math.round(food.per100g.vitamin_d_iu * scale * 10) / 10;
    }
    recordNutritionLogItem(foodId, foodName, proteinAmt, zincAmt, calciumAmt, ironAmt, vitDAmt);
  } else {
    // Long-press/right-click subtract with no specific item targeted —
    // remove the most recent matching log row so the list stays
    // consistent with the totals. deleteNutritionLogItem() only deletes
    // the row and updates the list here; it does NOT call back into
    // applyFoodTap(), since the totals were already adjusted above —
    // calling it again would double-subtract.
    const foodName = food ? food.name : 'Protein Boost (manual)';
    const match = [...APP.nutritionLogItems].reverse().find(i => i.food_name === foodName);
    if (match) removeLoggedItemRowOnly(match.item_id);
  }
}

// Pure totals math, used by both the tap/long-press path above and by
// the × button's delete path — the only place s.protein/zinc/calcium
// actually get mutated, so there is exactly one place to audit for
// correctness.
function adjustNutritionTotals(proteinAmt, zincAmt, calciumAmt, direction) {
  const s = currentState();
  const [pMin, pMax] = LIMITS.protein;
  s.protein = Math.max(pMin, Math.min(pMax, Math.round((s.protein + proteinAmt * direction) * 10) / 10));
  document.getElementById('valProtein').textContent = s.protein + ' g';

  if (zincAmt != null) {
    const [zMin, zMax] = LIMITS.zinc;
    s.zinc = Math.max(zMin, Math.min(zMax, Math.round((s.zinc + zincAmt * direction) * 100) / 100));
    document.getElementById('valZinc').textContent = s.zinc + ' mg';
  }
  if (calciumAmt != null) {
    const [cMin, cMax] = LIMITS.calcium;
    s.calcium = Math.max(cMin, Math.min(cMax, Math.round(s.calcium + calciumAmt * direction)));
    document.getElementById('valCalcium').textContent = s.calcium + ' mg';
  }
  updateHUD();
}

// ══════════════════════════════════════════
// WATER GRID
// ══════════════════════════════════════════
function buildWaterGrid() {
  const s = currentState();
  const g = document.getElementById('waterGrid');
  g.innerHTML = '';
  for (let i = 1; i <= 8; i++) {
    const d = document.createElement('div');
    d.className = 'water-drop' + (i <= s.water ? ' on' : '');
    d.id = 'wd'+i;
    d.textContent = i <= s.water ? '●' : '';
    d.onclick = () => {
      const st = currentState();
      st.water = (st.water === i) ? i-1 : i;
      updateWaterGrid();
      document.getElementById('waterLbl').textContent = `(${st.water}/${activeChildNutritionTargets().waterGlasses} glasses)`;
      { const z = document.getElementById('zincSubLbl'); if (z) z.textContent = `Growth plate co-factor · target ${activeChildNutritionTargets().zincMg}mg/day (for age)`; }
      updateHUD();
    };
    g.appendChild(d);
  }
}

function updateWaterGrid() {
  const s = currentState();
  for (let i = 1; i <= 8; i++) {
    const d = document.getElementById('wd'+i);
    if (d) { d.className = 'water-drop' + (i <= s.water ? ' on' : ''); d.textContent = i <= s.water ? '●' : ''; }
  }
}

// ══════════════════════════════════════════
// SLEEP CALC + GH-WINDOW TIMELINE
// ══════════════════════════════════════════
function calcSleep() {
  const s = currentState();
  s.bed = document.getElementById('sleepBed').value;
  s.wake = document.getElementById('sleepWake').value;
  const bed = s.bed.split(':').map(Number);
  const wake = s.wake.split(':').map(Number);
  if (bed.length < 2 || wake.length < 2 || isNaN(bed[0]) || isNaN(wake[0])) return;
  let bedMins = bed[0]*60+bed[1], wakeMins = wake[0]*60+wake[1];
  if (bedMins > wakeMins) wakeMins += 1440;
  const hrs = ((wakeMins - bedMins) / 60).toFixed(2);
  document.getElementById('totalSleepLbl').textContent = hrs + ' hrs';
  renderSleepTimeline();
  updateHUD();
}

// Visualizes bedtime -> first slow-wave-sleep episode -> wake.
// The first ~90 min after sleep onset is when most of the day's GH pulse fires,
// so the timeline highlights that window rather than just totalling minutes.
function renderSleepTimeline() {
  const s = currentState();
  const bed = s.bed.split(':').map(Number);
  const wake = s.wake.split(':').map(Number);
  if (bed.length < 2 || wake.length < 2 || isNaN(bed[0]) || isNaN(wake[0])) return;
  let bedMins = bed[0]*60+bed[1], wakeMins = wake[0]*60+wake[1];
  if (bedMins > wakeMins) wakeMins += 1440;
  const totalMins = wakeMins - bedMins;
  if (totalMins <= 0) return;

  const onsetLatency = 20; // typical minutes to fall asleep
  const ghWindowStart = onsetLatency;
  const ghWindowEnd = onsetLatency + 90; // first SWS episode window

  const track = document.getElementById('sleepTrack');
  const pPre = Math.min(100, (ghWindowStart / totalMins) * 100);
  const pWindow = Math.min(100 - pPre, (90 / totalMins) * 100);
  const pRest = Math.max(0, 100 - pPre - pWindow);

  track.innerHTML = `
    <div class="sleep-segment pre" style="left:0; width:${pPre}%;"></div>
    <div class="sleep-segment gh-window" style="left:${pPre}%; width:${pWindow}%;"></div>
    <div class="sleep-segment rest" style="left:${pPre+pWindow}%; width:${pRest}%;"></div>
  `;

  document.getElementById('sleepLblBed').textContent = s.bed;
  document.getElementById('sleepLblWake').textContent = s.wake;

  const note = document.getElementById('ghWindowNote');
  const lateBed = bed[0] > 21 || (bed[0] === 21 && bed[1] > 45);
  const frequentWakes = s.nightWakes >= 2;
  if (lateBed || frequentWakes) {
    note.className = 'gh-window-note warn';
    note.textContent = lateBed && frequentWakes
      ? 'Bedtime is later than the 21:30 target and there were several night wake-ups — both can shorten or fragment the early GH pulse window.'
      : lateBed
        ? 'Bedtime is later than the 21:30 target, which compresses the early-night window where most growth hormone is released.'
        : 'Frequent wake-ups before midnight can interrupt the first slow-wave-sleep episode, when most growth hormone is released.';
  } else {
    note.className = 'gh-window-note';
    note.textContent = 'Most of a child\'s daily growth hormone release happens in the first deep-sleep cycle, roughly 60–90 minutes after sleep onset. Going to bed on time matters more than total hours.';
  }
}

// ══════════════════════════════════════════
// HUD UPDATE
// ══════════════════════════════════════════
function updateHUD() {
  const s = currentState();
  const { standard: proteinStd, boost: proteinBoost } = activeChildProteinTargets();

  // Update the protein label to show both values
  const lbl = document.getElementById('proteinTargetLabel');
  if (lbl) lbl.innerHTML = `Standard (WHO/DRI): <b>${proteinStd}g</b> &nbsp;·&nbsp; Growth target: <b>${proteinBoost}g</b>`;

  // ── Growth-velocity optimized readiness scoring ───────────────────
  // Protein ring uses the growth target (boost) as 100% reference,
  // so the ring shows real progress toward the growth-optimized intake.
  const pR = Math.min(s.protein / proteinBoost, 1);

  // Calcium weight raised (50% of nutrition subscore) — rate-limiting
  // substrate for bone mineralization. Bonjour et al. (1991) established
  // calcium as the primary limiting nutrient for prepubertal bone accrual.
  const nutTargets = activeChildNutritionTargets();
  const cR = Math.min(s.calcium / nutTargets.calciumMg, 1);
  const znR = Math.min((s.zinc || 0) / nutTargets.zincMg, 1);
  const wR = Math.min(s.water / nutTargets.waterGlasses, 1);

  // Nutrition subscore: evidence-weighted (protein 40 / calcium 30 /
  // zinc 15 / water 15) with a bounded balance penalty — see
  // nutritionSubscore + FORMULAS.md.
  const nutPct = nutritionSubscore(pR, cR, znR, wR);

  // ── Activity score — library-based weighted sum ───────────────
  // Each logged activity contributes duration × tier_weight.
  // 60 min of high-impact = 100%. Cannot exceed 1.0.
  // Falls back to old state (hanging/jumps/yoga) if no items loaded
  // yet — ensures the HUD still works on a fresh load before the
  // async activity items arrive.
  const actPct = calcActivityScore();

  // Overall: Sleep 40%, Nutrition 30%, Activity 30%
  // Sleep raised to 40% (was 30%) — 70-80% of GH secretion occurs
  // during sleep (Van Cauter & Copinschi 2000, Sleep Med Rev).
  // GH drives IGF-1, which directly stimulates chondrocyte proliferation
  // in the growth plate — making sleep the single highest-leverage
  // variable for height velocity in prepubertal children.
  const bed = document.getElementById('sleepBed').value.split(':').map(Number);
  const wake = document.getElementById('sleepWake').value.split(':').map(Number);
  let bedM = bed[0]*60+bed[1], wakeM = wake[0]*60+wake[1];
  if (bedM > wakeM) wakeM += 1440;
  const durR = Math.min((wakeM-bedM)/(activeChildNutritionTargets().sleepMin/60)/60, 1);
  // Bedtime on/before 21:30 protects the early GH-pulse window; each night
  // wake-up before midnight is treated as a partial disruption to that window.
  const onTimeR = (bedM <= (21*60+30)) ? 1 : Math.max(0, 1 - (bedM - (21*60+30))/120);
  const wakeR = Math.max(0, 1 - s.nightWakes * 0.25);
  const slpPct = durR*0.35 + onTimeR*0.4 + wakeR*0.25;

  // Growth-velocity optimized overall weights:
  // Sleep 40% · Activity 30% · Nutrition 30%
  // (previous: 35/35/30 — sleep raised, activity/nutrition reduced)
  const grs = Math.round(nutPct*30 + actPct*30 + slpPct*40);

  // Rings (r=47→circumference=295, r=36→226, r=25→157)
  document.getElementById('ring1').style.strokeDashoffset = 295*(1-nutPct);
  document.getElementById('ring2').style.strokeDashoffset = 226*(1-actPct);
  document.getElementById('ring3').style.strokeDashoffset = 157*(1-slpPct);

  document.getElementById('grsScore').textContent = grs;
  document.getElementById('metNut').textContent = Math.round(nutPct*100)+'%';
  document.getElementById('metAct').textContent = Math.round(actPct*100)+'%';
  document.getElementById('metSlp').textContent = Math.round(slpPct*100)+'%';

  document.getElementById('barNut').style.width = Math.round(pR*100)+'%';
  document.getElementById('barCal').style.width = Math.round(cR*100)+'%';
  document.getElementById('barWat').style.width = Math.round(wR*100)+'%';
  document.getElementById('barEx').style.width = Math.round(actPct*100)+'%';
  document.getElementById('barSlp').style.width = Math.round(slpPct*100)+'%';
}

function setDateBadge() {
  const d = new Date();
  const opts = { weekday:'short', day:'numeric', month:'short' };
  document.getElementById('todayDateBadge').textContent = d.toLocaleDateString('en-GB', opts);
}

// ══════════════════════════════════════════
// LOGGING CONSISTENCY
// ══════════════════════════════════════════
function renderStreakRow() {
  const days = ['M','T','W','T','F','S','S'];
  const row = document.getElementById('streakRow');
  if (!row) return;
  const streakArr = currentStreak();
  const todayIdx = (new Date().getDay() + 6) % 7; // Mon=0
  row.innerHTML = days.map((d,i) => {
    const cls = i === todayIdx ? 'today' : streakArr[i] ? 'done' : 'miss';
    return `<div class="consist-day ${cls}">${d}</div>`;
  }).join('');
  const loggedCount = streakArr.reduce((a,b) => a+b, 0);
  document.getElementById('streakCount').textContent = loggedCount + ' / 7 days';
}

// ══════════════════════════════════════════
// SAVE DAY
// ══════════════════════════════════════════
async function saveDay() {
  const s = currentState();
  const childId = activeChildId();
  if (!childId) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }
  const saveDate = APP.logDate; // the date selected in the date selector — defaults to today, but may be backdated

  const btn = document.getElementById('saveBtn');
  btn.textContent = 'Saving…';
  btn.disabled = true;

  // Total sleep duration, computed the same way the on-screen "Total sleep
  // duration" label does.
  const [bh, bm] = s.bed.split(':').map(Number);
  const [wh, wm] = s.wake.split(':').map(Number);
  let bedMins = bh*60+bm, wakeMins = wh*60+wm;
  if (bedMins > wakeMins) wakeMins += 1440;
  const totalSleepMin = Math.round(wakeMins - bedMins);

  // sleep_efficiency_score now reflects actual sleep duration adequacy
  // only — night_wakes has its own real column (see migration), so this
  // no longer needs to double as a wake-up proxy.
  const sleepEfficiency = Math.max(0, Math.min(100, Math.round((totalSleepMin / activeChildNutritionTargets().sleepMin) * 100)));

  // Three independent writes — this app screen edits all three domains at
  // once, but each is its own table/concern (the split is deliberate, see
  // schema notes), so each upsert can succeed or fail on its own. If one
  // fails, the user is told specifically which domain didn't save rather
  // than getting one opaque "save failed" for the whole form.
  // Per-meal protein breakdown: sum nutrition_log_items by meal_slot for
  // today's logged foods. Manual stepper taps don't create log rows (only
  // food-card taps do), so any gap between the daily total (s.protein) and
  // what the log accounts for is attributed to the currently-selected meal
  // slot — this keeps protein_breakfast_g+lunch_g+dinner_g always equal to
  // the displayed daily total, rather than silently losing manually-typed
  // amounts.
  const mealSums = { breakfast: 0, lunch: 0, dinner: 0, snack: 0 };
  APP.nutritionLogItems.forEach(item => {
    const slot = mealSums.hasOwnProperty(item.meal_slot) ? item.meal_slot : 'breakfast';
    mealSums[slot] += Number(item.protein_g) || 0;
  });
  const loggedTotal = mealSums.breakfast + mealSums.lunch + mealSums.dinner + mealSums.snack;
  const unaccounted = Math.max(0, s.protein - loggedTotal);
  const fallbackSlot = mealSums.hasOwnProperty(APP.activeMealSlot) ? APP.activeMealSlot : 'breakfast';
  mealSums[fallbackSlot] += unaccounted;
  // daily_nutrition only has breakfast/lunch/dinner columns (no snack
  // column) — fold snack into dinner for storage, which is the schema's
  // existing 3-meal model; nutrition_log_items itself still keeps the
  // real 'snack' tag for the detailed history.
  mealSums.dinner += mealSums.snack;

  // Manual saves replace any recall-engine estimate for the day and
  // carry the time-tiered trust (see manualEntryMeta).
  const estMeta = manualEntryMeta(saveDate);
  const results = await Promise.allSettled([
    sb.from('daily_nutrition').upsert({
      child_id: childId,
      log_date: saveDate,
      protein_breakfast_g: Math.round(mealSums.breakfast * 10) / 10,
      protein_lunch_g: Math.round(mealSums.lunch * 10) / 10,
      protein_dinner_g: Math.round(mealSums.dinner * 10) / 10,
      calcium_mg: s.calcium,
      zinc_mg: s.zinc,
      fluids_ml: s.water * 250,  // 1 glass ≈ 250ml
      estimation_method: estMeta.method,
      confidence: estMeta.confidence
    }, { onConflict: 'child_id,log_date' }),

    sb.from('daily_sleep').upsert({
      child_id: childId,
      log_date: saveDate,
      total_sleep_min: totalSleepMin,
      sleep_efficiency_score: sleepEfficiency,
      night_wakes: s.nightWakes,
      bedtime: s.bed,
      wake_time: s.wake,
      data_source: 'manual',
      estimation_method: estMeta.method,
      confidence: estMeta.confidence
    }, { onConflict: 'child_id,log_date' })
    // Activity is now saved per-item in real-time via confirmLogActivity().
    // The daily_activity table (bar_hanging/box_jumps/yoga) is kept for
    // historical data only — new logs go into daily_activity_items.
  ]);

  btn.disabled = false;

  const labels = ['Nutrition', 'Sleep'];
  const failed = results
    .map((r, i) => ({ r, label: labels[i] }))
    .filter(x => x.r.status === 'rejected' || x.r.value?.error);

  if (failed.length > 0) {
    const msg = failed.map(f => f.label + ': ' + (f.r.reason?.message || f.r.value?.error?.message || 'unknown error')).join(' · ');
    showToast('⚠️', 'Some data did not save — ' + msg);
    btn.textContent = saveButtonLabel(false);
    return;
  }

  const savedDateObj = new Date(saveDate + 'T00:00:00');
  const savedIdx = (savedDateObj.getDay() + 6) % 7;
  // Only mark the streak if the saved date falls within the currently
  // displayed week — loadWeekStreak() already scopes its query to the
  // current week, so an entry further in the past wouldn't show here
  // anyway, but this avoids writing a stale index if it's ever extended.
  const weekStart = new Date();
  weekStart.setDate(weekStart.getDate() - ((weekStart.getDay() + 6) % 7));
  weekStart.setHours(0,0,0,0);
  if (savedDateObj >= weekStart) {
    currentStreak()[savedIdx] = 1;
    renderStreakRow();
  }
  s.savedToday = true;
  showToast('✅', t('toast.saved','Saved'));
  btn.textContent = saveButtonLabel(true);
}

// ══════════════════════════════════════════
// ANALYTICS
// ══════════════════════════════════════════

// Pulls this child's measurement history from Supabase and repaints the
// history table. Called on child switch, after adding a measurement, and
// on initial load. The growth chart and stats then read from
// APP.activeChildMeasurements rather than scraping table DOM text, which
// was fragile (locale date-string parsing) in the previous version.
async function refreshActiveChildHistory() {
  const childId = activeChildId();
  const tb = document.getElementById('histBody');
  if (!childId) { tb.innerHTML = ''; APP.activeChildMeasurements = []; return; }

  const { data, error } = await sb
    .from('measurements')
    .select('measurement_id, recorded_date, stature_height_cm, mass_weight_kg, calculated_bmi')
    .eq('child_id', childId)
    .order('recorded_date', { ascending: false });

  if (error) {
    showToast('⚠️', 'Could not load growth history: ' + error.message);
    APP.activeChildMeasurements = [];
    tb.innerHTML = '';
    return;
  }

  APP.activeChildMeasurements = data || [];

  if (!data || data.length === 0) {
    tb.innerHTML = `<tr><td colspan="5" style="padding:20px; text-align:center; color:var(--text3);">No measurements logged yet</td></tr>`;
    return;
  }

  const child = APP.children[APP.activeChild];

  tb.innerHTML = data.map(m => {
    const fmt = new Date(m.recorded_date).toLocaleDateString('en-GB', {day:'numeric', month:'short', year:'numeric'});

    // Real BMI-for-age percentile (WHO 2007 Reference, full LMS method —
    // see bmi-percentile.js) replaces the permanent "—" placeholder this
    // column previously showed, since real percentile math wasn't wired
    // up before now.
    let channelCell = '<span class="pct-pill badge-measured">—</span>';
    if (child && child.date_of_birth && m.calculated_bmi != null && typeof calculateBMIPercentile === 'function') {
      const ageYears = (new Date(m.recorded_date) - new Date(child.date_of_birth)) / (365.25 * 86400000);
      const result = calculateBMIPercentile(Number(m.calculated_bmi), ageYears, child.biological_sex);
      if (result && !result.outOfRange) {
        const pctLabel = result.percentile < 1 ? '<1st' : result.percentile > 99 ? '>99th' : Math.round(result.percentile) + 'th';
        const badgeClass = result.classification === 'obesity' || result.classification === 'severe_thinness' ? 'badge-flag'
          : result.classification === 'overweight' || result.classification === 'thinness' ? 'badge-estimated'
          : 'badge-measured';
        channelCell = `<span class="pct-pill ${badgeClass}" title="${result.classification.replace('_',' ')}">${pctLabel}</span>`;
      }
    }

    return `<tr class="hist-row" onclick="openMeasurementEditSheet('${m.measurement_id}')">
      <td>${fmt}</td>
      <td>${Number(m.stature_height_cm).toFixed(1)}</td>
      <td>${Number(m.mass_weight_kg).toFixed(1)}</td>
      <td>${m.calculated_bmi ?? '—'}</td>
      <td style="display:flex; align-items:center; justify-content:space-between; gap:4px;">${channelCell}<span class="hist-chevron">›</span></td>
    </tr>`;
  }).join('');
}

async function updateStats() {
  const streak = currentStreak().reduce((a,b) => a+b, 0);
  document.getElementById('streakStat').textContent = streak+' / 7';

  const childId = activeChildId();
  if (!childId) {
    document.getElementById('avgGRS').textContent = '—';
    document.getElementById('heightGain').textContent = '—';
    document.getElementById('avgSleep').textContent = '—';
    document.getElementById('velocityVal').textContent = '—';
    return;
  }

  // Last 7 days across the three logging tables. Pulled separately since
  // they're separate tables now (see schema notes on why nutrition/sleep/
  // activity were split out) — joined client-side by log_date below.
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
  const sinceDate = sevenDaysAgo.toISOString().split('T')[0];

  const [nutRes, sleepRes, actNewRes, actOldRes] = await Promise.all([
    sb.from('daily_nutrition').select('log_date, total_protein_g, calcium_mg, zinc_mg, fluids_ml').eq('child_id', childId).gte('log_date', sinceDate),
    sb.from('daily_sleep').select('log_date, total_sleep_min, sleep_efficiency_score').eq('child_id', childId).gte('log_date', sinceDate),
    // New activity items — group by date in JS
    sb.from('daily_activity_items').select('log_date, tier, duration_min').eq('child_id', childId).gte('log_date', sinceDate),
    // Old activity table — fallback for historical data
    sb.from('daily_activity').select('log_date, hanging_decompression_sec, box_jumps_reps, stretching_yoga_duration_min').eq('child_id', childId).gte('log_date', sinceDate)
  ]);

  const nutByDate = {}, sleepByDate = {}, actByDate = {};
  (nutRes.data || []).forEach(r => nutByDate[r.log_date] = r);
  (sleepRes.data || []).forEach(r => sleepByDate[r.log_date] = r);

  // Group new activity items by date → weighted minutes
  (actNewRes.data || []).forEach(r => {
    const w = (ACTIVITY_TIER_CONFIG[r.tier] || ACTIVITY_TIER_CONFIG.lifestyle).weight;
    actByDate[r.log_date] = (actByDate[r.log_date] || 0) + r.duration_min * w;
  });
  // Fill in old activity data where no new data exists (backward compat)
  (actOldRes.data || []).forEach(r => {
    if (actByDate[r.log_date] === undefined) {
      const hR = Math.min((r.hanging_decompression_sec||0)/30, 1) * 0.25;
      const jR = Math.min((r.box_jumps_reps||0)/40, 1) * 0.55;
      const yR = Math.min((r.stretching_yoga_duration_min||0)/20, 1) * 0.20;
      // Convert old score to weighted minutes equivalent
      actByDate[r.log_date] = (hR + jR + yR) * 60;
    }
  });

  const allDates = [...new Set([...Object.keys(nutByDate), ...Object.keys(sleepByDate), ...Object.keys(actByDate)])];

  if (allDates.length > 0) {
    // Same weighting as updateHUD()'s same-day score, applied per logged
    // day and averaged — this is the honest version of "avg readiness":
    // derived from what was actually logged, not a stored score column
    // (there isn't one in this schema; a single day's score was never
    // meant to be a durable clinical value anyway).
    const dailyScores = allDates.map(date => {
      const n = nutByDate[date], sl = sleepByDate[date];
      const child = APP.children[APP.activeChild];
      const analyticProteinTarget = child
        ? calcProteinTargetG(child.date_of_birth, n?.mass_weight_kg || null, child.biological_sex)
        : 34;
      const nt = activeChildNutritionTargets();
      const pR = n ? Math.min((n.total_protein_g||0) / analyticProteinTarget, 1) : 0;
      const cR = n ? Math.min((n.calcium_mg||0)/nt.calciumMg, 1) : 0;
      const znR = n ? Math.min((n.zinc_mg||0)/nt.zincMg, 1) : 0;
      const wR = n ? Math.min((n.fluids_ml||0)/(nt.waterGlasses*250), 1) : 0;
      // Evidence-weighted nutrition subscore (protein 40 / calcium 30 /
      // zinc 15 / water 15) with bounded balance penalty.
      const nutPct = nutritionSubscore(pR, cR, znR, wR);

      // Activity: new system uses weighted minutes (60 min high-impact = 100%)
      const actWeightedMin = actByDate[date] || 0;
      const actPct = Math.min(actWeightedMin / 60, 1.0);

      const durR = sl ? Math.min((sl.total_sleep_min||0)/activeChildNutritionTargets().sleepMin, 1) : 0;
      const effR = sl ? (sl.sleep_efficiency_score||0)/100 : 0;
      const slpPct = durR*0.6 + effR*0.4;

      // Growth-velocity overall weights: Sleep 40%, Activity 30%, Nutrition 30%
      return nutPct*30 + actPct*30 + slpPct*40;
    });
    const avgScore = dailyScores.reduce((a,b)=>a+b,0) / dailyScores.length;
    document.getElementById('avgGRS').textContent = Math.round(avgScore);

    const sleepMinutes = Object.values(sleepByDate).map(s => s.total_sleep_min).filter(m => m != null);
    if (sleepMinutes.length > 0) {
      const avgSleep = sleepMinutes.reduce((a,b)=>a+b,0) / sleepMinutes.length / 60;
      document.getElementById('avgSleep').textContent = avgSleep.toFixed(1) + 'h';
    } else {
      document.getElementById('avgSleep').textContent = '—';
    }
  } else {
    document.getElementById('avgGRS').textContent = '—';
    document.getElementById('avgSleep').textContent = '—';
  }

  // Height velocity from the growth analytics view (Postgres LAG() window
  // function — same computation used to live client-side, now done once,
  // correctly, in the database).
  const { data: ledger } = await sb
    .from('child_growth_analytics_ledger')
    .select('recorded_date, height_delta_cm, days_between_measurements')
    .eq('child_id', childId)
    .order('recorded_date', { ascending: false })
    .limit(1);

  let velocity = null, trendDir = 'flat', trendLabel = 'not enough data';
  if (ledger && ledger.length > 0 && ledger[0].height_delta_cm != null && ledger[0].days_between_measurements > 0) {
    velocity = (ledger[0].height_delta_cm / ledger[0].days_between_measurements) * 365.25;
    trendDir = velocity >= 5.3 ? 'up' : velocity < 4.2 ? 'down' : 'flat';
    trendLabel = velocity >= 5.3 ? 'on pace' : velocity < 4.2 ? 'below range' : 'stable';
  }
  document.getElementById('velocityVal').textContent = velocity != null ? velocity.toFixed(1) : '—';
  const trendEl = document.getElementById('velocityTrend');
  trendEl.className = 'velocity-trend ' + trendDir;
  trendEl.textContent = trendLabel;

  // Height gain over the last 30 days, from raw measurements (separate
  // from the single most-recent-pair velocity figure above).
  const measurements = APP.activeChildMeasurements || [];
  if (measurements.length >= 2) {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const inWindow = measurements.filter(m => new Date(m.recorded_date) >= thirtyDaysAgo);
    if (inWindow.length >= 2) {
      const newest = inWindow[0], oldest = inWindow[inWindow.length - 1];
      const gain = Number(newest.stature_height_cm) - Number(oldest.stature_height_cm);
      document.getElementById('heightGain').textContent = (gain >= 0 ? '+' : '') + gain.toFixed(1) + 'cm';
    } else {
      document.getElementById('heightGain').textContent = '—';
    }
  } else {
    document.getElementById('heightGain').textContent = '—';
  }

  // Percentile channel — computed from the WHO 2007 height-for-age
  // reference (5–19 years) using the child's most recent measurement,
  // exact decimal age, and recorded biological sex. See growth-percentile.js
  // for the method; see who-reference-data.js for the source data.
  const channelMarker = document.getElementById('channelMarker');
  const channelLbl = document.getElementById('channelPctLbl');
  const child = APP.children[APP.activeChild];
  const latestMeasurement = measurements[0];

  if (!child || !latestMeasurement || typeof calculateHeightPercentile !== 'function') {
    channelMarker.style.left = '50%';
    channelLbl.textContent = 'no measurement logged yet';
  } else {
    const ageYears = (new Date(latestMeasurement.recorded_date) - new Date(child.date_of_birth)) / (365.25 * 86400000);
    const result = calculateHeightPercentile(
      Number(latestMeasurement.stature_height_cm),
      ageYears,
      child.biological_sex
    );

    if (!result) {
      channelMarker.style.left = '50%';
      channelLbl.textContent = 'reference data unavailable';
    } else if (result.outOfRange) {
      channelMarker.style.left = '50%';
      channelLbl.textContent = `WHO 5–19y reference doesn't cover this age (${ageYears.toFixed(1)}y)`;
    } else {
      // Marker position: 3rd percentile = 0% of the bar, 97th = 100%,
      // using the same Z-score scale as the lookup itself so the dot's
      // position and the printed percentile always agree.
      const clampedZ = Math.max(PERCENTILE_Z.p3, Math.min(PERCENTILE_Z.p97, result.zScore));
      const pct = ((clampedZ - PERCENTILE_Z.p3) / (PERCENTILE_Z.p97 - PERCENTILE_Z.p3)) * 100;
      channelMarker.style.left = pct.toFixed(1) + '%';

      const displayPct = result.percentile < 1 ? '<1st'
        : result.percentile > 99 ? '>99th'
        : Math.round(result.percentile) + (result.percentile < 50 ? 'th' : result.percentile < 85 ? 'th' : 'th') + ' percentile';
      channelLbl.textContent = `${displayPct} for height-for-age (WHO 2007 reference, z=${result.zScore.toFixed(2)})`;
      APP.lastPercentileResult = result; // cached for drawGrowthChart()'s overlay
    }
  }

  // BMI-for-age — same pattern as the height percentile above, using
  // the WHO 2007 BMI-for-age reference and the full Box-Cox LMS method
  // (see bmi-percentile.js). Uses the database's own generated
  // calculated_bmi column rather than recomputing BMI client-side, so
  // there's exactly one place BMI is calculated (the Postgres generated
  // column), matching the principle already applied to total_protein_g.
  const bmiVal = document.getElementById('bmiVal');
  const bmiClassBadge = document.getElementById('bmiClassBadge');
  const bmiSub = document.getElementById('bmiSub');
  const bmiChannelMarker = document.getElementById('bmiChannelMarker');
  const bmiPctLbl = document.getElementById('bmiPctLbl');

  if (!child || !latestMeasurement || latestMeasurement.calculated_bmi == null || typeof calculateBMIPercentile !== 'function') {
    bmiVal.textContent = '—';
    bmiClassBadge.textContent = 'no data';
    bmiClassBadge.className = 'velocity-trend flat';
    bmiPctLbl.textContent = 'not available';
  } else {
    const ageYears = (new Date(latestMeasurement.recorded_date) - new Date(child.date_of_birth)) / (365.25 * 86400000);
    const bmiResult = calculateBMIPercentile(Number(latestMeasurement.calculated_bmi), ageYears, child.biological_sex);

    bmiVal.textContent = Number(latestMeasurement.calculated_bmi).toFixed(1);

    if (!bmiResult) {
      bmiClassBadge.textContent = 'unavailable';
      bmiClassBadge.className = 'velocity-trend flat';
      bmiPctLbl.textContent = 'reference data unavailable';
    } else if (bmiResult.outOfRange) {
      bmiClassBadge.textContent = 'out of range';
      bmiClassBadge.className = 'velocity-trend flat';
      bmiPctLbl.textContent = `WHO 5–19y reference doesn't cover this age (${ageYears.toFixed(1)}y)`;
    } else {
      // Marker position on the same 3rd-97th visual scale as the height
      // card, for consistent left-to-right reading across both cards.
      const clampedZ = Math.max(PERCENTILE_Z.p3, Math.min(PERCENTILE_Z.p97, bmiResult.zScore));
      const pct = ((clampedZ - PERCENTILE_Z.p3) / (PERCENTILE_Z.p97 - PERCENTILE_Z.p3)) * 100;
      bmiChannelMarker.style.left = pct.toFixed(1) + '%';

      const displayPct = bmiResult.percentile < 1 ? '<1st'
        : bmiResult.percentile > 99 ? '>99th'
        : Math.round(bmiResult.percentile) + 'th percentile';
      bmiPctLbl.textContent = `${displayPct} for BMI-for-age (WHO 2007 reference, z=${bmiResult.zScore.toFixed(2)})`;

      // WHO's own stated classification labels and color treatment —
      // amber for the single-threshold categories, red (flag) for the
      // double-threshold ones, matching the badge convention used
      // elsewhere in the app for measured-vs-flagged data.
      const classLabels = {
        obesity: 'obesity range', overweight: 'overweight range',
        healthy_range: 'healthy range', thinness: 'thinness range', severe_thinness: 'severe thinness'
      };
      const classTrend = {
        obesity: 'down', overweight: 'down', healthy_range: 'flat', thinness: 'down', severe_thinness: 'down'
      };
      bmiClassBadge.textContent = classLabels[bmiResult.classification] || bmiResult.classification;
      bmiClassBadge.className = 'velocity-trend ' + (classTrend[bmiResult.classification] || 'flat');
      if (bmiResult.classification === 'healthy_range') bmiClassBadge.className = 'velocity-trend up';
    }
  }

  // SGA catch-up growth tracking — only relevant for children flagged
  // is_sga, only meaningful under age 5 (the age range the clinical
  // catch-up-growth literature this is built from actually covers — see
  // FORMULAS.md). Hidden entirely otherwise, including when there
  // aren't yet two measurements to compute a velocity from.
  const sgaCard = document.getElementById('sgaCatchupCard');
  const ageNowYears = child ? (new Date() - new Date(child.date_of_birth)) / (365.25*86400000) : null;
  const showSGACard = !!(child && child.is_sga && ageNowYears != null && ageNowYears < 5);
  sgaCard.classList.toggle('hidden', !showSGACard);

  if (showSGACard) {
    const sgaVelocityEl = document.getElementById('sgaVelocitySDS');
    const sgaBadge = document.getElementById('sgaCatchupBadge');
    const sgaMonitoringNote = document.getElementById('sgaMonitoringNote');

    // Monitoring cadence reminder, per the SGA consensus guideline this
    // feature is built from: every 3 months in year 1, 6-monthly in
    // year 2, yearly after.
    const cadence = ageNowYears < 1 ? 'every 3 months (year 1)'
      : ageNowYears < 2 ? 'every 6 months (year 2)'
      : 'yearly';
    sgaMonitoringNote.textContent = `Recommended monitoring frequency at this age: ${cadence}. If catch-up growth (>0 SDS/year) hasn't been observed by age 2–4, guidelines recommend evaluation for growth hormone therapy — bring this chart to that conversation.`;

    if (measurements.length < 2 || typeof calculateHeightPercentile0to5 !== 'function') {
      sgaVelocityEl.textContent = '—';
      sgaBadge.textContent = 'need 2+ measurements';
      sgaBadge.className = 'velocity-trend flat';
    } else {
      // Real definition of catch-up growth: the CHANGE in height
      // Z-score over time, not raw cm/year — a child gaining height at
      // the population-median rate has a flat Z-score (not catching up,
      // just tracking the same curve); catch-up means gaining SDS,
      // i.e. moving up the percentile bands over time.
      const last = measurements[0], prev = measurements[1]; // measurements is newest-first
      const lastAgeMonths = (new Date(last.recorded_date) - new Date(child.date_of_birth)) / (30.4375*86400000);
      const prevAgeMonths = (new Date(prev.recorded_date) - new Date(child.date_of_birth)) / (30.4375*86400000);
      const yearsBetween = (lastAgeMonths - prevAgeMonths) / 12;

      if (yearsBetween <= 0 || lastAgeMonths > 60 || prevAgeMonths < 0) {
        sgaVelocityEl.textContent = '—';
        sgaBadge.textContent = 'out of 0-5y range';
        sgaBadge.className = 'velocity-trend flat';
      } else {
        const lastResult = calculateHeightPercentile0to5(Number(last.stature_height_cm), lastAgeMonths, child.biological_sex);
        const prevResult = calculateHeightPercentile0to5(Number(prev.stature_height_cm), prevAgeMonths, child.biological_sex);

        if (!lastResult || !prevResult || lastResult.outOfRange || prevResult.outOfRange) {
          sgaVelocityEl.textContent = '—';
          sgaBadge.textContent = 'unavailable';
          sgaBadge.className = 'velocity-trend flat';
        } else {
          const sdsPerYear = (lastResult.zScore - prevResult.zScore) / yearsBetween;
          sgaVelocityEl.textContent = (sdsPerYear >= 0 ? '+' : '') + sdsPerYear.toFixed(2);

          if (sdsPerYear > 0.1) {
            sgaBadge.textContent = 'catching up';
            sgaBadge.className = 'velocity-trend up';
          } else if (sdsPerYear < -0.1) {
            sgaBadge.textContent = 'falling further behind';
            sgaBadge.className = 'velocity-trend down';
          } else {
            sgaBadge.textContent = 'tracking, not catching up';
            sgaBadge.className = 'velocity-trend flat';
          }
        }
      }
    }
  }
}

async function addMeasurement() {
  const childId = activeChildId();
  if (!childId) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }
  if (!requireMeasurementQuota()) return; // free tier lifetime cap check
  const date = document.getElementById('logDate').value;
  const h = parseFloat(document.getElementById('logHeight').value);
  const w = parseFloat(document.getElementById('logWeight').value);
  if (!date) { showToast('⚠️', t('toast.error.select_date','Select a date')); return; }
  if (isNaN(h) || isNaN(w) || h <= 0 || w <= 0) { showToast('⚠️', t('toast.error.invalid_height_weight','Enter a valid height and weight')); return; }

  // calculated_bmi is a generated column in Postgres (computed from
  // stature_height_cm/mass_weight_kg automatically) — don't send it.
  const { error } = await sb.from('measurements').upsert({
    child_id: childId,
    recorded_date: date,
    stature_height_cm: h,
    mass_weight_kg: w,
    data_source: 'manual'
  }, { onConflict: 'child_id,recorded_date' });

  if (error) { showToast('⚠️', t('toast.error.save_failed','Could not save') + ': ' + error.message); return; }

  showToast('✅', t('toast.measurement_logged','Measurement logged'));
  await refreshActiveChildHistory();
  updateStats();
  drawGrowthChart();
  drawBMIChart();
}

// ══════════════════════════════════════════
// GROWTH CHART — real WHO 2007 height-for-age bands (5–19y), shaded
// percentile overlay, child's actual measurements plotted on top.
// Requires who-reference-data.js and growth-percentile.js to be loaded.
// ══════════════════════════════════════════
// ══════════════════════════════════════════
// SHARED CHART RENDERING HELPERS
// Both drawGrowthChart() and drawBMIChart() use these — extracted so
// the 0-5y/5-19y branching and the height/BMI branching don't each need
// their own copy of the same canvas-drawing mechanics.
// ══════════════════════════════════════════

// Sets up a canvas for crisp rendering at the current device pixel
// ratio and returns the context plus usable width/height after padding.
function setupChartCanvas(canvasId, padOverride) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return null;
  const ctx = canvas.getContext('2d');
  const W = canvas.parentElement.clientWidth;
  const H = canvas.parentElement.clientHeight;
  canvas.width = W * window.devicePixelRatio;
  canvas.height = H * window.devicePixelRatio;
  ctx.setTransform(1,0,0,1,0,0);
  ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
  ctx.clearRect(0, 0, W, H);
  const pad = padOverride || { t:12, r:12, b:28, l:32 };
  return { canvas, ctx, W, H, pad, w: W-pad.l-pad.r, h: H-pad.t-pad.b };
}

function drawEmptyChartMessage(ctx, W, H, message) {
  ctx.fillStyle = '#95A092'; ctx.font = '11px Inter,sans-serif'; ctx.textAlign = 'center';
  ctx.fillText(message, W/2, H/2);
}

function drawChartGridAndAxis(ctx, pad, w, h, ageMin, ageMax, pxForAge) {
  ctx.strokeStyle = '#F0F2F5'; ctx.lineWidth = 1;
  for (let i=1; i<5; i++) {
    const y = pad.t + (h/5)*i;
    ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(pad.l+w, y); ctx.stroke();
  }
  ctx.fillStyle = '#9BA3B4'; ctx.font = '9px Inter,sans-serif'; ctx.textAlign = 'center';
  // Below age 2, label every 3 months (real early growth changes fast
  // enough that whole-year labels would leave most of a 0-2y chart
  // unlabeled); from 2y up, whole-year labels same as the 5-19y chart.
  if (ageMax <= 2.1) {
    for (let m = 0; m <= ageMax*12; m += 3) {
      ctx.fillText(m + 'mo', pxForAge(m/12), pad.t + h + 18);
    }
  } else {
    const startYear = Math.ceil(ageMin), endYear = Math.floor(ageMax);
    for (let y = startYear; y <= endYear; y++) {
      ctx.fillText(y + 'y', pxForAge(y), pad.t + h + 18);
    }
  }
}

function fillChartBand(ctx, sampled, pxForAge, hy, lowKey, highKey, color) {
  ctx.fillStyle = color;
  ctx.beginPath();
  sampled.forEach((s, i) => {
    const x = pxForAge(s.ageYears), y = hy(s[highKey]);
    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  });
  for (let i = sampled.length - 1; i >= 0; i--) {
    const s = sampled[i];
    ctx.lineTo(pxForAge(s.ageYears), hy(s[lowKey]));
  }
  ctx.closePath();
  ctx.fill();
}

function drawChartBandLine(ctx, sampled, pxForAge, hy, key, color, width) {
  drawLine(ctx, sampled.map(s => [pxForAge(s.ageYears), hy(s[key])]), color, width);
}

// ══════════════════════════════════════════
// HEIGHT-FOR-AGE CHART — branches between the WHO 2007 Reference
// (5-19y, percentile-band interpolation) and the WHO Child Growth
// Standards (0-5y, real LMS — naturally renders the actual decelerating
// early-growth curve shape rather than a straight line, since the
// underlying median values themselves curve that way).
// ══════════════════════════════════════════
function drawGrowthChart() {
  const setup = setupChartCanvas('growthCanvas');
  if (!setup) return;
  const { ctx, W, H, pad, w, h } = setup;

  const child = APP.children[APP.activeChild];
  const measurements = (APP.activeChildMeasurements || []).slice().reverse(); // oldest first
  const titleEl = document.getElementById('growthChartTitle');
  const noteEl = document.getElementById('growthChartNote');

  if (!child || typeof WHO_HFA_BOYS_5_19 === 'undefined') {
    drawEmptyChartMessage(ctx, W, H, !child ? 'Add a child profile to see this chart' : 'Reference data not loaded');
    return;
  }

  const ageNowYears = (new Date() - new Date(child.date_of_birth)) / (365.25*86400000);
  const use0to5 = ageNowYears < 5 && typeof WHO_HFA_BOYS_0_2 !== 'undefined';

  // The Thai approximate toggle only makes sense where that data exists
  // (2-19y, per the source chart) and only for height (no Thai BMI data
  // was extracted). Hide it entirely outside that range rather than
  // showing a toggle that does nothing.
  const toggleEl = document.getElementById('referenceToggle');
  const thaiAvailable = !use0to5 && typeof THAI_HFA_BOYS_APPROX !== 'undefined' && ageNowYears >= 2;
  if (toggleEl) toggleEl.classList.toggle('hidden', !thaiAvailable);
  const showThai = thaiAvailable && APP.referenceStandard === 'thai';

  const isFullTimeline = APP.chartZoom === 'full';

  // Hide the zoom toggle entirely if the data doesn't support a
  // meaningful "full timeline" (e.g. reference data missing) — in
  // practice this should always be available once who-reference-data.js
  // and who-reference-data-0-5.js are both loaded, which they always are.
  const zoomToggleEl = document.getElementById('chartZoomToggle');
  if (zoomToggleEl) zoomToggleEl.classList.remove('hidden');

  if (titleEl) titleEl.textContent = isFullTimeline
    ? (showThai ? 'Height-for-age, birth–19y (WHO 0–2y + Thai 2–19y, approximate)' : 'Height-for-age, birth–19y (WHO reference)')
    : use0to5 ? 'Length/Height-for-age (WHO Child Growth Standards)'
    : showThai ? 'Height-for-age (Thai national reference — approximate)'
    : 'Height-for-age (WHO 2007 Reference)';
  if (noteEl) noteEl.textContent = isFullTimeline
    ? (showThai
        ? 'Full-timeline view, birth to 19 years: WHO Child Growth Standards (0–2y) stitched to the Thai approximate reference (2–19y, read by eye — see above). A small jump where the two sources meet at age 2 is expected, since they come from different studies.'
        : 'Full-timeline view, birth to 19 years: the WHO Child Growth Standards (0–5y) stitched to the WHO 2007 Reference (5–19y). A small jump where the two sources meet at age 5 is expected and real — these are two separate WHO studies, not one continuous dataset. Useful for an overall visual of the growth trajectory from birth through puberty; use the zoomed view for day-to-day tracking.')
    : use0to5
    ? 'Shaded bands are the official WHO Child Growth Standards (0–5 years), transcribed directly from who.int. Curve shape reflects real early-childhood growth deceleration, not a straight-line approximation. Measured 0–2y as recumbent length, 2–5y as standing height — bring this chart to your pediatrician.'
    : showThai
    ? 'These bands are read by eye from a printed Thai Society for Pediatric Endocrinology chart (citing 2020 Ministry of Public Health national data) — not transcribed from an official numeric table, since none was found published openly. Treat as a rough visual comparison only, not a clinically precise reference. Only 3rd/50th/97th percentiles are shown.'
    : 'Shaded bands are the official WHO 2007 Growth Reference for school-age children and adolescents (5–19 years), transcribed directly from who.int. This is a population reference, not a diagnosis — bring this chart to your pediatrician for clinical interpretation, especially near the band edges.';

  let ageMin, ageMax, sampleBandsAt, yPad;

  if (isFullTimeline) {
    // One continuous function spanning the entire 0-19y axis, switching
    // data source at the real seam (age 5 for WHO-only, age 2 for the
    // Thai branch where Thai data starts). Returns the same 5-value
    // [p3,p15,p50,p85,p97] shape every other branch uses, with p15/p85
    // collapsed to p50 in whichever segment only has 3 percentile lines
    // (the Thai segment), same convention as the existing Thai branch.
    ageMin = 0; ageMax = 19; yPad = 3;
    const sex = child.biological_sex;
    sampleBandsAt = (ageYears) => {
      if (showThai) {
        if (ageYears < 2) {
          const ageMonths = ageYears * 12;
          const table = GrowthPercentile0to5Math.heightTableFor(ageMonths, sex);
          return GrowthPercentile0to5Math.deriveBandsFromLMS(table, ageMonths);
        }
        const thaiTable = (sex === 'female') ? THAI_HFA_GIRLS_APPROX : THAI_HFA_BOYS_APPROX;
        let row0 = thaiTable[0], row1 = thaiTable[thaiTable.length-1];
        for (let i = 0; i < thaiTable.length - 1; i++) {
          if (ageYears >= thaiTable[i][0] && ageYears <= thaiTable[i+1][0]) { row0 = thaiTable[i]; row1 = thaiTable[i+1]; break; }
        }
        const frac = row1[0] === row0[0] ? 0 : (ageYears - row0[0]) / (row1[0] - row0[0]);
        const p3 = row0[1] + frac*(row1[1]-row0[1]);
        const p50 = row0[2] + frac*(row1[2]-row0[2]);
        const p97 = row0[3] + frac*(row1[3]-row0[3]);
        return [p3, p50, p50, p50, p97];
      }
      if (ageYears < 5) {
        const ageMonths = ageYears * 12;
        const table = GrowthPercentile0to5Math.heightTableFor(ageMonths, sex);
        return GrowthPercentile0to5Math.deriveBandsFromLMS(table, ageMonths);
      }
      const table519 = (sex === 'female') ? WHO_HFA_GIRLS_5_19 : WHO_HFA_BOYS_5_19;
      return GrowthPercentileMath.interpolateBands(table519, ageYears * 12);
    };
  } else if (use0to5) {
    // Always show the full 0-5y window — unlike the 5-19y chart's
    // rolling ±3y window, early-childhood growth changes shape so fast
    // that a partial window would hide the deceleration curve this
    // view exists to show.
    ageMin = 0; ageMax = 5; yPad = 2;
    sampleBandsAt = (ageYears) => {
      const ageMonths = ageYears * 12;
      const table = GrowthPercentile0to5Math.heightTableFor(ageMonths, child.biological_sex);
      return GrowthPercentile0to5Math.deriveBandsFromLMS(table, ageMonths);
    };
  } else if (showThai) {
    const thaiTable = (child.biological_sex === 'female') ? THAI_HFA_GIRLS_APPROX : THAI_HFA_BOYS_APPROX;
    const tableMinYears = thaiTable[0][0], tableMaxYears = thaiTable[thaiTable.length-1][0];
    ageMin = Math.max(tableMinYears, ageNowYears - 3);
    ageMax = Math.min(tableMaxYears, ageNowYears + 3);
    if (ageMax - ageMin < 2) {
      if (ageMin <= tableMinYears) ageMax = Math.min(tableMaxYears, ageMin + 2);
      else ageMin = Math.max(tableMinYears, ageMax - 2);
    }
    yPad = 3;
    // Simple linear interpolation between whole-year rows — the Thai
    // approximate data only has yearly resolution to begin with (read
    // off a chart with year gridlines), so anything fancier here would
    // be manufacturing false precision the source data doesn't have.
    sampleBandsAt = (ageYears) => {
      const rows = thaiTable;
      let row0 = rows[0], row1 = rows[rows.length-1];
      for (let i = 0; i < rows.length - 1; i++) {
        if (ageYears >= rows[i][0] && ageYears <= rows[i+1][0]) { row0 = rows[i]; row1 = rows[i+1]; break; }
      }
      const frac = row1[0] === row0[0] ? 0 : (ageYears - row0[0]) / (row1[0] - row0[0]);
      const p3 = row0[1] + frac*(row1[1]-row0[1]);
      const p50 = row0[2] + frac*(row1[2]-row0[2]);
      const p97 = row0[3] + frac*(row1[3]-row0[3]);
      // Only 3 lines exist for Thai data — return the same 5-value shape
      // the chart expects by reusing p50 for the missing p15/p85 slots,
      // so the inner shaded band simply doesn't render a meaningfully
      // different region (rendered visually thin/absent) rather than
      // guessing values that were never read off the chart.
      return [p3, p50, p50, p50, p97];
    };
  } else {
    const table = (child.biological_sex === 'female') ? WHO_HFA_GIRLS_5_19 : WHO_HFA_BOYS_5_19;
    const tableMinYears = table[0][0] / 12, tableMaxYears = table[table.length-1][0] / 12;
    ageMin = Math.max(tableMinYears, ageNowYears - 3);
    ageMax = Math.min(tableMaxYears, ageNowYears + 3);
    if (ageMax - ageMin < 2) {
      if (ageMin <= tableMinYears) ageMax = Math.min(tableMaxYears, ageMin + 2);
      else ageMin = Math.max(tableMinYears, ageMax - 2);
    }
    yPad = 3;
    sampleBandsAt = (ageYears) => GrowthPercentileMath.interpolateBands(table, ageYears * 12);
  }

  function pxForAge(ageYears) {
    const clamped = Math.max(ageMin, Math.min(ageMax, ageYears));
    return pad.l + ((clamped - ageMin) / (ageMax - ageMin)) * w;
  }

  // More samples for views that include the 0-5y region (use0to5, or
  // full-timeline which always includes it) — the curve genuinely bends
  // faster in early months, so more points keep that real curvature
  // visually smooth rather than visibly faceted. Full-timeline gets the
  // most samples since it covers the steep early region AND the long
  // flatter tail in one chart.
  const SAMPLES = isFullTimeline ? 76 : use0to5 ? 48 : 24;
  const sampled = [];
  for (let i = 0; i <= SAMPLES; i++) {
    const ageYears = ageMin + (ageMax - ageMin) * (i / SAMPLES);
    const [p3, p15, p50, p85, p97] = sampleBandsAt(ageYears);
    sampled.push({ ageYears, p3, p15, p50, p85, p97 });
  }

  const allBandValues = sampled.flatMap(s => [s.p3, s.p97]);
  const yMin = Math.min(...allBandValues) - yPad;
  const yMax = Math.max(...allBandValues) + yPad;
  function hy(cm) { return pad.t + h - ((cm - yMin) / (yMax - yMin)) * h; }

  drawChartGridAndAxis(ctx, pad, w, h, ageMin, ageMax, pxForAge);

  fillChartBand(ctx, sampled, pxForAge, hy, 'p3', 'p97', 'rgba(170,179,165,0.18)');
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p3', '#D7DCD2', 1.2);
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p50', '#7C877A', 1.6);
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p97', '#D7DCD2', 1.2);
  if (!showThai) {
    // 15th/85th bands only exist for WHO data — Thai approximate data
    // only has 3rd/50th/97th (see thai-reference-data-approx.js), so
    // drawing these here would just re-trace the same p50 line twice
    // with no new information.
    fillChartBand(ctx, sampled, pxForAge, hy, 'p15', 'p85', 'rgba(170,179,165,0.30)');
    drawChartBandLine(ctx, sampled, pxForAge, hy, 'p15', '#AAB3A5', 1.4);
    drawChartBandLine(ctx, sampled, pxForAge, hy, 'p85', '#AAB3A5', 1.4);
  }

  // Plot this child's actual measurements. Apply the recumbent/standing
  // 0.7cm convention PER MEASUREMENT based on that measurement's own
  // age — not a single chart-wide flag — since full-timeline mode can
  // show both <5y and 5y+ measurements on the same chart, each needing
  // whichever convention matches its own age. This matches exactly what
  // calculateHeightPercentile0to5() does per-measurement elsewhere, so
  // the chart and the numeric percentile reading never disagree.
  const ageAt = dateStr => (new Date(dateStr) - new Date(child.date_of_birth)) / (365.25*86400000);
  const actual = measurements.map(m => {
    const ageYears = ageAt(m.recorded_date);
    let heightCm = Number(m.stature_height_cm);
    const needsConversion = isFullTimeline ? ageYears < 5 : use0to5;
    if (needsConversion) {
      const ageMonths = ageYears * 12;
      const { value } = GrowthPercentile0to5Math.resolveHeightTableAndValue(heightCm, ageMonths, child.biological_sex, ageMonths < 24 ? 'recumbent' : 'standing');
      heightCm = value;
    }
    return [pxForAge(ageYears), hy(heightCm)];
  });

  if (actual.length > 0) {
    drawLine(ctx, actual, '#2A5C8A', 3);
    actual.forEach(([x,y], i) => {
      const isLatest = i === actual.length - 1;
      ctx.fillStyle = '#2A5C8A';
      ctx.beginPath(); ctx.arc(x, y, isLatest ? 5 : 4, 0, 2*Math.PI); ctx.fill();
      ctx.fillStyle = 'white'; ctx.beginPath(); ctx.arc(x, y, isLatest ? 2.5 : 2, 0, 2*Math.PI); ctx.fill();
    });

    if (actual.length >= 2) {
      const last = measurements[measurements.length - 1];
      const prev = measurements[measurements.length - 2];
      const daysBetween = (new Date(last.recorded_date) - new Date(prev.recorded_date)) / 86400000;
      const cmPerDay = daysBetween > 0 ? (Number(last.stature_height_cm) - Number(prev.stature_height_cm)) / daysBetween : 0;
      const lastAge = ageAt(last.recorded_date);
      const lastPt = actual[actual.length - 1];
      const forecast = [
        lastPt,
        [pxForAge(lastAge + 0.5), hy(Number(last.stature_height_cm) + cmPerDay*182)],
        [pxForAge(lastAge + 1), hy(Number(last.stature_height_cm) + cmPerDay*365)]
      ];
      ctx.strokeStyle = '#9C7A3D'; ctx.lineWidth = 2.5;
      ctx.setLineDash([5, 4]);
      ctx.beginPath();
      forecast.forEach(([x,y], i) => i===0 ? ctx.moveTo(x,y) : ctx.lineTo(x,y));
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = '#9C7A3D';
      ctx.beginPath(); ctx.arc(forecast[forecast.length-1][0], forecast[forecast.length-1][1], 4, 0, 2*Math.PI); ctx.fill();
    }
  } else {
    drawEmptyChartMessage(ctx, W, H, 'No measurements logged yet');
  }
}

// ══════════════════════════════════════════
// BMI-FOR-AGE CHART — same branching pattern as drawGrowthChart(), with
// added +1SD/+2SD threshold lines (WHO's overweight/obesity cutoffs)
// since that clinical context matters specifically for BMI, not height.
// ══════════════════════════════════════════
function drawBMIChart() {
  const setup = setupChartCanvas('bmiChartCanvas');
  if (!setup) return;
  const { ctx, W, H, pad, w, h } = setup;

  const child = APP.children[APP.activeChild];
  const measurements = (APP.activeChildMeasurements || []).slice().reverse();
  const noteEl = document.getElementById('bmiChartNote');

  if (!child || typeof WHO_BMI_BOYS_5_19 === 'undefined') {
    drawEmptyChartMessage(ctx, W, H, !child ? 'Add a child profile to see this chart' : 'Reference data not loaded');
    return;
  }

  const ageNowYears = (new Date() - new Date(child.date_of_birth)) / (365.25*86400000);
  const use0to5 = ageNowYears < 5 && typeof WHO_BMI_0_5_BOYS_0_2 !== 'undefined';

  if (noteEl) noteEl.textContent = use0to5
    ? "BMI-for-age, WHO Child Growth Standards (0–5 years). A screening signal, not a diagnosis — BMI can't distinguish muscle from fat. Bring this chart to your pediatrician."
    : "BMI-for-age, WHO 2007 Reference (5–19 years). A screening signal, not a diagnosis — BMI can't distinguish muscle from fat, which matters most for very active children.";

  let ageMin, ageMax, sampleAt, yPad;

  if (use0to5) {
    ageMin = 0; ageMax = 5; yPad = 1.5;
    sampleAt = (ageYears) => {
      const ageMonths = ageYears * 12;
      const table = GrowthPercentile0to5Math.bmiTableFor(ageMonths, child.biological_sex);
      const { L, M, S } = GrowthPercentile0to5Math.interpolateLMS(table, ageMonths);
      return { L, M, S, bands: GrowthPercentile0to5Math.deriveBandsFromLMS(table, ageMonths) };
    };
  } else {
    const table = (child.biological_sex === 'female') ? WHO_BMI_GIRLS_5_19 : WHO_BMI_BOYS_5_19;
    const tableMinYears = table[0][0] / 12, tableMaxYears = table[table.length-1][0] / 12;
    ageMin = Math.max(tableMinYears, ageNowYears - 3);
    ageMax = Math.min(tableMaxYears, ageNowYears + 3);
    if (ageMax - ageMin < 2) {
      if (ageMin <= tableMinYears) ageMax = Math.min(tableMaxYears, ageMin + 2);
      else ageMin = Math.max(tableMinYears, ageMax - 2);
    }
    yPad = 1.5;
    sampleAt = (ageYears) => {
      const ageMonths = ageYears * 12;
      const { L, M, S } = BMIPercentileMath.interpolateLMS(table, ageMonths);
      const z = PERCENTILE_Z;
      const lmsVal = (zz) => Math.abs(L) < 1e-9 ? M*Math.exp(S*zz) : M*Math.pow(1+L*S*zz, 1/L);
      return { L, M, S, bands: [lmsVal(z.p3), lmsVal(z.p15), lmsVal(z.p50), lmsVal(z.p85), lmsVal(z.p97)] };
    };
  }

  function pxForAge(ageYears) {
    const clamped = Math.max(ageMin, Math.min(ageMax, ageYears));
    return pad.l + ((clamped - ageMin) / (ageMax - ageMin)) * w;
  }

  const SAMPLES = use0to5 ? 48 : 24;
  const sampled = [];
  for (let i = 0; i <= SAMPLES; i++) {
    const ageYears = ageMin + (ageMax - ageMin) * (i / SAMPLES);
    const { L, M, S, bands } = sampleAt(ageYears);
    const lmsVal = (zz) => Math.abs(L) < 1e-9 ? M*Math.exp(S*zz) : M*Math.pow(1+L*S*zz, 1/L);
    sampled.push({
      ageYears, p3: bands[0], p15: bands[1], p50: bands[2], p85: bands[3], p97: bands[4],
      plus1SD: lmsVal(1), plus2SD: lmsVal(2) // WHO's overweight/obesity cutoffs at this exact age
    });
  }

  const allValues = sampled.flatMap(s => [s.p3, s.p97, s.plus2SD]);
  const yMin = Math.min(...allValues) - yPad;
  const yMax = Math.max(...allValues) + yPad;
  function hy(val) { return pad.t + h - ((val - yMin) / (yMax - yMin)) * h; }

  drawChartGridAndAxis(ctx, pad, w, h, ageMin, ageMax, pxForAge);

  fillChartBand(ctx, sampled, pxForAge, hy, 'p3', 'p97', 'rgba(170,179,165,0.18)');
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p50', '#7C877A', 1.6);

  // WHO's own clinical thresholds, drawn as dashed reference lines —
  // this is the part that makes it an "obesity chart," not just a
  // percentile chart: a parent can see at a glance whether the measured
  // trend is approaching either cutoff.
  ctx.setLineDash([4, 3]);
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'plus1SD', '#9C7A3D', 1.5);
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'plus2SD', '#C0392B', 1.5);
  ctx.setLineDash([]);

  const ageAt = dateStr => (new Date(dateStr) - new Date(child.date_of_birth)) / (365.25*86400000);
  const actual = measurements
    .filter(m => m.calculated_bmi != null)
    .map(m => [pxForAge(ageAt(m.recorded_date)), hy(Number(m.calculated_bmi))]);

  if (actual.length > 0) {
    drawLine(ctx, actual, '#2A5C8A', 3);
    actual.forEach(([x,y], i) => {
      const isLatest = i === actual.length - 1;
      ctx.fillStyle = '#2A5C8A';
      ctx.beginPath(); ctx.arc(x, y, isLatest ? 5 : 4, 0, 2*Math.PI); ctx.fill();
      ctx.fillStyle = 'white'; ctx.beginPath(); ctx.arc(x, y, isLatest ? 2.5 : 2, 0, 2*Math.PI); ctx.fill();
    });
  } else {
    drawEmptyChartMessage(ctx, W, H, 'No measurements logged yet');
  }
}

// Lab marker trend chart — IGF-1 and Vitamin D over time.
// Lab marker trend chart — reads from lab_results table (and the three
// fixed fields on medical_logs: IGF-1, VitD, Ferritin). Shows the last
// 12 entries for each distinct analyte as a sparkline overlay.
// ══════════════════════════════════════════════════════════════════
// ANALYTICS INSIGHT CARDS + DETAIL SHEETS
// Google Health–style: cards surface a 7-day headline, tap → bottom
// sheet with period tabs (W/M/3M), SVG line chart, goal zone band,
// colour-coded dots, per-day log rows.
// All data is stored in APP.nutritionHistory / sleepHistory /
// activityHistory (90-day window, loaded once per Analytics visit).
// ══════════════════════════════════════════════════════════════════

// ── State ─────────────────────────────────────────────────────────
// (added to APP object dynamically — no schema change needed)
// APP.nutritionHistory, APP.sleepHistory, APP.activityHistory
// APP._insightType, APP._insightPeriod, APP._insightSubTab

// ── Helpers ───────────────────────────────────────────────────────
function filterByPeriod(rows, period) {
  const days = period === 'W' ? 7 : period === 'M' ? 30 : 90;
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString().split('T')[0];
  return (rows || []).filter(r => (r.log_date || r.recorded_date || '') >= cutoffStr);
}

// ── Load 90 days of daily logs ────────────────────────────────────
async function loadAnalyticsTrends() {
  const childId = activeChildId();
  if (!childId) return;
  const since = new Date();
  since.setDate(since.getDate() - 90);
  const sinceISO = since.toISOString().split('T')[0];

  const [nutRes, slpRes, actRes] = await Promise.all([
    sb.from('daily_nutrition')
      .select('log_date,total_protein_g,calcium_mg,fluids_ml')
      .eq('child_id', childId).gte('log_date', sinceISO).order('log_date'),
    sb.from('daily_sleep')
      .select('log_date,total_sleep_min,bedtime')
      .eq('child_id', childId).gte('log_date', sinceISO).order('log_date'),
    sb.from('daily_activity')
      .select('log_date,hanging_decompression_sec,box_jumps_reps,stretching_yoga_duration_min')
      .eq('child_id', childId).gte('log_date', sinceISO).order('log_date'),
  ]);

  APP.nutritionHistory = nutRes.data || [];
  APP.sleepHistory     = slpRes.data || [];
  APP.activityHistory  = actRes.data || [];

  updateInsightCards();
}

// ── Update the 4 collapsed card surfaces ─────────────────────────
function updateInsightCards() {
  const nut7 = filterByPeriod(APP.nutritionHistory, 'W');
  const slp7 = filterByPeriod(APP.sleepHistory,     'W');
  const act7 = filterByPeriod(APP.activityHistory,  'W');
  const { boost } = activeChildProteinTargets();

  // Nutrition
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  if (nut7.length) {
    const avgP = Math.round(nut7.reduce((a,r)=>a+(r.total_protein_g||0),0)/nut7.length);
    const pct  = Math.round(avgP/boost*100);
    const metC = nut7.filter(r=>(r.calcium_mg||0)>=activeChildNutritionTargets().calciumMg).length;
    set('icNutValue', `${avgP}g protein avg / day`);
    set('icNutSub',   `${pct}% of growth target · Ca goal ${metC}/${nut7.length} days`);
  } else { set('icNutValue','—'); set('icNutSub','No data logged this week'); }

  // Sleep
  if (slp7.length) {
    const avgM = slp7.reduce((a,r)=>a+(r.total_sleep_min||0),0)/slp7.length;
    const sleepGoalMin = activeChildNutritionTargets().sleepMin;
    const met  = slp7.filter(r=>(r.total_sleep_min||0)>=sleepGoalMin).length;
    set('icSlpValue', `${Math.floor(avgM/60)}h ${Math.round(avgM%60)}m avg / night`);
    set('icSlpSub',   `${(sleepGoalMin/60).toFixed(1)}h goal met ${met} of ${slp7.length} nights`);
  } else { set('icSlpValue','—'); set('icSlpSub','No sleep data this week'); }

  // Activity
  const active = act7.filter(r=>(r.box_jumps_reps||0)+(r.hanging_decompression_sec||0)+(r.stretching_yoga_duration_min||0)>0).length;
  set('icActValue', act7.length ? `${active} of ${act7.length} days active` : '—');
  set('icActSub',   'Box jumps · Hanging · Yoga');

  // Height velocity
  const meas = (APP.activeChildMeasurements||[]).slice().sort((a,b)=>new Date(a.recorded_date)-new Date(b.recorded_date));
  if (meas.length >= 2) {
    const newest = meas[meas.length-1], oldest = meas[0];
    const days = (new Date(newest.recorded_date)-new Date(oldest.recorded_date))/(86400000);
    const vel  = days > 0 ? ((Number(newest.stature_height_cm)-Number(oldest.stature_height_cm))/days*365.25).toFixed(1) : '—';
    set('icHtValue', `${vel} cm / year`);
    set('icHtSub',   `${Number(newest.stature_height_cm).toFixed(1)} cm latest · ${meas.length} measurements`);
  } else { set('icHtValue','—'); set('icHtSub','Add 2+ measurements to see velocity'); }
}

// ── SVG chart generator ───────────────────────────────────────────
// Draws a responsive line chart with optional goal zone band.
// All colours are hardcoded hex equivalents of the design tokens so
// they work inside an SVG template literal (CSS vars don't apply to SVG
// fill/stroke attributes when set via HTML string injection).
function buildInsightSVG(rows, cfg) {
  // cfg: { valueKey, goalValue|null, lineColor, goalColor, unit }
  if (!rows || !rows.length) return '<div class="insight-empty">No data for this period.</div>';

  const VW = 320, VH = 150, PL = 4, PR = 4, PT = 10, PB = 26;
  const cW = VW-PL-PR, cH = VH-PT-PB;

  const vals  = rows.map(r => Number(r[cfg.valueKey]||0));
  const maxV  = Math.max(...vals, cfg.goalValue||0) * 1.05 || 1;
  const minV  = 0;
  const range = maxV - minV;

  const toX = i  => PL + (i/(Math.max(rows.length-1,1)))*cW;
  const toY = v  => PT + cH - ((v-minV)/range)*cH;

  // Goal zone band
  const goalY = cfg.goalValue != null ? toY(cfg.goalValue) : null;
  const goalZone = goalY != null ? `
    <rect x="${PL}" y="${PT}" width="${cW}" height="${Math.max(0,goalY-PT)}"
      fill="${cfg.goalColor}1A" rx="3"/>
    <line x1="${PL}" y1="${goalY.toFixed(1)}" x2="${VW-PR}" y2="${goalY.toFixed(1)}"
      stroke="${cfg.goalColor}" stroke-width="1.2" stroke-dasharray="4,3" opacity="0.6"/>
  ` : '';

  // Grid lines (3 horizontals)
  const grid = [0.25,0.5,0.75].map(f =>
    `<line x1="${PL}" y1="${(PT+cH*f).toFixed(1)}" x2="${VW-PR}" y2="${(PT+cH*f).toFixed(1)}"
      stroke="#E8EDE8" stroke-width="0.6"/>`).join('');

  // Data polyline
  const pts = rows.map((r,i)=>`${toX(i).toFixed(1)},${toY(Number(r[cfg.valueKey]||0)).toFixed(1)}`).join(' ');

  // Dots — green = met goal or no goal, amber = missed
  const dots = rows.map((r,i) => {
    const v   = Number(r[cfg.valueKey]||0);
    const met = cfg.goalValue == null || v >= cfg.goalValue;
    const cx  = toX(i).toFixed(1), cy = toY(v).toFixed(1);
    return `<circle cx="${cx}" cy="${cy}" r="4.5" fill="${met?'#2F6B4F':'#9C7A3D'}" stroke="#fff" stroke-width="1.5"/>`;
  }).join('');

  // X-axis date labels — first, mid, last only
  const fmtD = s => new Date(s+'T00:00:00').toLocaleDateString('en-GB',{day:'numeric',month:'short'});
  const xLbls = [];
  if (rows.length>0) xLbls.push({i:0,           align:'start', lbl:fmtD(rows[0].log_date||rows[0].recorded_date)});
  if (rows.length>2) xLbls.push({i:Math.floor(rows.length/2), align:'middle', lbl:fmtD(rows[Math.floor(rows.length/2)].log_date||rows[Math.floor(rows.length/2)].recorded_date)});
  if (rows.length>1) xLbls.push({i:rows.length-1, align:'end',   lbl:fmtD(rows[rows.length-1].log_date||rows[rows.length-1].recorded_date)});
  const xlabels = xLbls.map(({i,align,lbl})=>
    `<text x="${toX(i).toFixed(1)}" y="${VH-4}" text-anchor="${align}"
      fill="#95A092" font-size="9" font-family="monospace">${lbl}</text>`).join('');

  return `<svg viewBox="0 0 ${VW} ${VH}" class="insight-chart-svg" preserveAspectRatio="none">
    ${grid}${goalZone}
    <polyline points="${pts}" fill="none" stroke="${cfg.lineColor}" stroke-width="2.2"
      stroke-linejoin="round" stroke-linecap="round"/>
    ${dots}
    ${xlabels}
  </svg>`;
}

// ── Per-type sheet content builders ──────────────────────────────
function buildNutritionSheet(period) {
  const { standard: ps, boost: pb } = activeChildProteinTargets();
  const rows = filterByPeriod(APP.nutritionHistory, period);
  const sub  = APP._insightSubTab || 'protein';

  const nutT = activeChildNutritionTargets();
  const cfg = {
    protein: { key:'total_protein_g', goal:pb,   color:'#2F6B4F', unit:'g',      goalLabel:`${pb}g growth target` },
    calcium: { key:'calcium_mg',      goal:nutT.calciumMg, color:'#2A5C8A', unit:'mg', goalLabel:`${nutT.calciumMg}mg goal (for age)` },
    water:   { key:'fluids_ml',       goal:nutT.waterGlasses*250, color:'#2A5C8A', unit:'ml', goalLabel:`${nutT.waterGlasses*250}ml (${nutT.waterGlasses} glasses)` },
  }[sub];

  const subTabs = `<div class="insight-sub-tabs">
    ${['protein','calcium','water'].map(t=>`<button class="insight-sub-tab ${sub===t?'active':''}"
      onclick="setInsightSubTab('${t}')">${t.charAt(0).toUpperCase()+t.slice(1)}</button>`).join('')}
  </div>`;

  if (!rows.length) return subTabs + '<div class="insight-empty">No data for this period.<br>Start logging on the Today tab.</div>';

  const avg  = rows.reduce((a,r)=>a+(r[cfg.key]||0),0)/rows.length;
  const metC = rows.filter(r=>(r[cfg.key]||0)>=cfg.goal).length;
  const bigNum = sub==='water' ? (avg/250).toFixed(1) : Math.round(avg);
  const bigUnit= sub==='water' ? 'glasses avg/day' : `${cfg.unit} avg/day`;

  const chart = buildInsightSVG(rows, {valueKey:cfg.key, goalValue:cfg.goal, lineColor:cfg.color, goalColor:cfg.color});
  const legend = `<div class="insight-chart-legend">
    <span><span class="ileg-dot" style="background:#2F6B4F;"></span>Goal met</span>
    <span><span class="ileg-dot" style="background:#9C7A3D;"></span>Missed</span>
    <span style="opacity:.6">· ${cfg.goalLabel}</span>
  </div>`;

  const dayRows = [...rows].reverse().slice(0,14).map(r => {
    const v   = r[cfg.key]||0;
    const met = v >= cfg.goal;
    const disp = sub==='water' ? `${(v/250).toFixed(1)} gl` : `${Math.round(v)} ${cfg.unit}`;
    const date = new Date(r.log_date+'T00:00:00').toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short'});
    return `<div class="insight-day-row">
      <span class="insight-day-label">${date}</span>
      <div style="display:flex;align-items:center;gap:8px;">
        <span class="insight-day-value">${disp}</span>
        <span class="insight-day-badge ${met?'met':'missed'}">${met?'✓':'·'}</span>
      </div></div>`;
  }).join('');

  return `${subTabs}
    <div><span class="insight-big-num">${bigNum}</span><span class="insight-big-unit">${bigUnit}</span></div>
    <div class="insight-big-sub">Goal met ${metC} of ${rows.length} days</div>
    <div class="insight-chart-wrap">${chart}${legend}</div>
    <div style="margin-top:6px;">${dayRows}</div>`;
}

function buildSleepSheet(period) {
  const rows = filterByPeriod(APP.sleepHistory, period);
  if (!rows.length) return '<div class="insight-empty">No sleep data for this period.<br>Start logging on the Today tab.</div>';

  const GOAL = activeChildNutritionTargets().sleepMin; // age-banded, minutes
  const avg  = rows.reduce((a,r)=>a+(r.total_sleep_min||0),0)/rows.length;
  const met  = rows.filter(r=>(r.total_sleep_min||0)>=GOAL).length;
  const h = Math.floor(avg/60), m = Math.round(avg%60);

  const chart = buildInsightSVG(rows, {valueKey:'total_sleep_min', goalValue:GOAL, lineColor:'#2A5C8A', goalColor:'#2A5C8A'});
  const legend = `<div class="insight-chart-legend">
    <span><span class="ileg-dot" style="background:#2F6B4F;"></span>Goal met</span>
    <span><span class="ileg-dot" style="background:#9C7A3D;"></span>Missed</span>
    <span style="opacity:.6">· ${(GOAL/60).toFixed(1)}h goal zone</span>
  </div>`;

  const dayRows = [...rows].reverse().slice(0,14).map(r => {
    const totalMin = r.total_sleep_min||0;
    const isMet = totalMin >= GOAL;
    const disp  = totalMin ? `${Math.floor(totalMin/60)}h ${totalMin%60}m` : '—';
    const date  = new Date(r.log_date+'T00:00:00').toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short'});
    return `<div class="insight-day-row">
      <span class="insight-day-label">${date}</span>
      <div style="display:flex;align-items:center;gap:8px;">
        <span class="insight-day-value">${disp}</span>
        <span class="insight-day-badge ${isMet?'met':'missed'}">${isMet?'✓':'·'}</span>
      </div></div>`;
  }).join('');

  return `
    <div><span class="insight-big-num">${h}h ${m}m</span><span class="insight-big-unit">avg / night</span></div>
    <div class="insight-big-sub">${(GOAL/60).toFixed(1)}h goal met ${met} of ${rows.length} nights</div>
    <div class="insight-chart-wrap">${chart}${legend}</div>
    <div style="margin-top:6px;">${dayRows}</div>`;
}

function buildActivitySheet(period) {
  const rows = filterByPeriod(APP.activityHistory, period);
  const sub  = APP._insightSubTab || 'jumps';

  const cfg = {
    jumps:   { key:'box_jumps_reps',                goal:40,  unit:'reps', label:'Box jumps',  goalLabel:'40 reps goal' },
    hanging: { key:'hanging_decompression_sec',      goal:30,  unit:'s',   label:'Hanging',    goalLabel:'30s goal'     },
    yoga:    { key:'stretching_yoga_duration_min',   goal:20,  unit:'min', label:'Yoga',       goalLabel:'20 min goal'  },
  }[sub];

  const subTabs = `<div class="insight-sub-tabs">
    ${[['jumps','Box jumps'],['hanging','Hanging'],['yoga','Yoga']].map(([t,l])=>
      `<button class="insight-sub-tab ${sub===t?'active':''}" onclick="setInsightSubTab('${t}')">${l}</button>`).join('')}
  </div>`;

  if (!rows.length) return subTabs+'<div class="insight-empty">No activity data for this period.</div>';

  const activeDays = rows.filter(r=>(r.box_jumps_reps||0)+(r.hanging_decompression_sec||0)+(r.stretching_yoga_duration_min||0)>0).length;
  const avg    = rows.reduce((a,r)=>a+(r[cfg.key]||0),0)/rows.length;
  const metC   = rows.filter(r=>(r[cfg.key]||0)>=cfg.goal).length;

  const chart = buildInsightSVG(rows, {valueKey:cfg.key, goalValue:cfg.goal, lineColor:'#2F6B4F', goalColor:'#2F6B4F'});
  const legend = `<div class="insight-chart-legend">
    <span><span class="ileg-dot" style="background:#2F6B4F;"></span>Goal met</span>
    <span><span class="ileg-dot" style="background:#9C7A3D;"></span>Missed</span>
    <span style="opacity:.6">· ${cfg.goalLabel}</span>
  </div>`;

  const dayRows = [...rows].reverse().slice(0,14).map(r => {
    const v    = r[cfg.key]||0;
    const isMet = v >= cfg.goal;
    const date = new Date(r.log_date+'T00:00:00').toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short'});
    return `<div class="insight-day-row">
      <span class="insight-day-label">${date}</span>
      <div style="display:flex;align-items:center;gap:8px;">
        <span class="insight-day-value">${v} ${cfg.unit}</span>
        <span class="insight-day-badge ${isMet?'met':'missed'}">${isMet?'✓':'·'}</span>
      </div></div>`;
  }).join('');

  return `${subTabs}
    <div><span class="insight-big-num">${activeDays}</span><span class="insight-big-unit"> of ${rows.length} days active</span></div>
    <div class="insight-big-sub">${cfg.label} goal met ${metC}/${rows.length} days · avg ${Math.round(avg)} ${cfg.unit}</div>
    <div class="insight-chart-wrap">${chart}${legend}</div>
    <div style="margin-top:6px;">${dayRows}</div>`;
}

function buildHeightSheet() {
  const meas = (APP.activeChildMeasurements||[])
    .slice().sort((a,b)=>new Date(a.recorded_date)-new Date(b.recorded_date));
  if (meas.length < 2) return '<div class="insight-empty">Add at least 2 height measurements<br>to see velocity here.</div>';

  const newest = meas[meas.length-1], oldest = meas[0];
  const days   = (new Date(newest.recorded_date)-new Date(oldest.recorded_date))/86400000;
  const cmGain = Number(newest.stature_height_cm)-Number(oldest.stature_height_cm);
  const vel    = days > 0 ? (cmGain/days*365.25) : 0;

  const child = APP.children[APP.activeChild];
  const ageY  = child?.date_of_birth ? (Date.now()-new Date(child.date_of_birth))/(365.25*86400000) : null;
  let expLo = 4, expHi = 7;
  if (ageY < 4) { expLo=7; expHi=13; } else if (ageY < 7) { expLo=5; expHi=8; } else if (ageY < 10) { expLo=4; expHi=7; } else if (ageY < 13) { expLo=4; expHi=8; } else { expLo=3; expHi=10; }
  const status = vel < expLo ? 'missed' : vel > expHi ? 'met' : 'met';
  const statusText = vel < expLo ? `⚠ Below expected (${expLo}–${expHi} cm/yr)` : vel > expHi ? `↑ Above expected (${expLo}–${expHi} cm/yr)` : `✓ Within expected (${expLo}–${expHi} cm/yr)`;

  // Use measurements as time-series for the chart
  const measRows = meas.map(m=>({log_date:m.recorded_date, height_cm:Number(m.stature_height_cm)}));
  const chart = buildInsightSVG(measRows, {valueKey:'height_cm', goalValue:null, lineColor:'#9C7A3D', goalColor:'#9C7A3D'});

  const histRows = meas.slice().reverse().slice(0,10).map(m => {
    const date = new Date(m.recorded_date+'T00:00:00').toLocaleDateString('en-GB',{day:'numeric',month:'short',year:'2-digit'});
    return `<div class="insight-day-row">
      <span class="insight-day-label">${date}</span>
      <span class="insight-day-value">${Number(m.stature_height_cm).toFixed(1)} cm</span>
    </div>`;
  }).join('');

  return `
    <div><span class="insight-big-num">${vel.toFixed(1)}</span><span class="insight-big-unit"> cm / year</span></div>
    <div class="insight-big-sub"><span class="insight-day-badge ${status}" style="font-size:12px;">${statusText}</span></div>
    <div style="font-size:11px; color:#95A092; margin:10px 0 16px;">Over ${Math.round(days)} days · ${meas.length} measurements</div>
    <div class="insight-chart-wrap">${chart}</div>
    <div style="margin-top:8px;">${histRows}</div>`;
}

// ── Sheet open / close / switch ───────────────────────────────────
function openInsightSheet(type) {
  APP._insightType   = type;
  APP._insightPeriod = 'W';
  APP._insightSubTab = type==='nutrition' ? 'protein' : type==='activity' ? 'jumps' : null;
  const titles = {nutrition:'Nutrition', sleep:'Sleep', activity:'Activity', height:'Height velocity'};
  document.getElementById('insightSheetTitle').textContent = titles[type]||type;
  document.querySelectorAll('.period-btn').forEach(b=>b.classList.remove('active'));
  const wb = document.getElementById('iperiod-W');
  if (wb) wb.classList.add('active');
  // Height doesn't use a period (all measurements shown)
  document.querySelector('.insight-period-row').style.display = type==='height' ? 'none' : '';
  refreshInsightSheet();
  document.getElementById('insightSheetModal').classList.remove('hidden');
}

function closeInsightSheet() {
  document.getElementById('insightSheetModal').classList.add('hidden');
  APP._insightType = null;
}

function insightBackdropClick(e) {
  if (e.target === document.getElementById('insightSheetModal')) closeInsightSheet();
}

function switchInsightPeriod(period) {
  APP._insightPeriod = period;
  document.querySelectorAll('.period-btn').forEach(b=>b.classList.remove('active'));
  const btn = document.getElementById(`iperiod-${period}`);
  if (btn) btn.classList.add('active');
  refreshInsightSheet();
}

function setInsightSubTab(tab) {
  APP._insightSubTab = tab;
  refreshInsightSheet();
}

function refreshInsightSheet() {
  const body = document.getElementById('insightSheetBody');
  if (!body) return;
  const t = APP._insightType, p = APP._insightPeriod;
  if      (t==='nutrition') body.innerHTML = buildNutritionSheet(p);
  else if (t==='sleep')     body.innerHTML = buildSleepSheet(p);
  else if (t==='activity')  body.innerHTML = buildActivitySheet(p);
  else if (t==='height')    body.innerHTML = buildHeightSheet();
}

// ── end insight engine ────────────────────────────────────────────

async function drawLabChart() {
  const canvas = document.getElementById('labCanvas');
  if (!canvas) return;
  const childId = activeChildId();
  const ctx = canvas.getContext('2d');
  const W = canvas.parentElement.clientWidth;
  const H = canvas.parentElement.clientHeight;
  canvas.width = W * window.devicePixelRatio;
  canvas.height = H * window.devicePixelRatio;
  ctx.setTransform(1,0,0,1,0,0);
  ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
  ctx.clearRect(0, 0, W, H);

  // Use already-loaded APP.labResults if available, otherwise query
  const rows = APP.labResults && APP.labResults.length > 0
    ? APP.labResults
    : (() => { return []; })(); // will show empty state below

  if (!childId || rows.length === 0) {
    ctx.fillStyle = 'var(--text3)';
    ctx.font = `11px var(--sans, Inter, sans-serif)`;
    ctx.textAlign = 'center';
    ctx.fillStyle = '#95A092';
    ctx.fillText('No lab results recorded yet.', W / 2, H / 2 - 6);
    ctx.font = `10px var(--sans, Inter, sans-serif)`;
    ctx.fillStyle = '#6B7C6B';
    ctx.fillText('Add results in the Medical tab to see trends here.', W / 2, H / 2 + 12);
    return;
  }

  // Group by analyte name
  const byAnalyte = {};
  rows.forEach(r => {
    if (!byAnalyte[r.analyte_name]) byAnalyte[r.analyte_name] = [];
    byAnalyte[r.analyte_name].push({ date: new Date(r.lab_date), value: Number(r.result_value) });
  });

  // Sort each analyte's data chronologically
  Object.values(byAnalyte).forEach(arr => arr.sort((a, b) => a.date - b.date));

  // Color palette matching design tokens
  const COLORS = ['#2F6B4F', '#2A5C8A', '#9C7A3D', '#A23B3B', '#6B4F8A', '#3D8A7C'];

  const analytes = Object.entries(byAnalyte);
  const allDates = rows.map(r => new Date(r.lab_date));
  const minDate = new Date(Math.min(...allDates));
  const maxDate = new Date(Math.max(...allDates));
  const dateSpan = maxDate - minDate || 1;

  // Grid lines
  ctx.strokeStyle = '#E8EDE8';
  ctx.lineWidth = 0.5;
  for (let i = 1; i < 4; i++) {
    const y = H * 0.1 + (H * 0.7) * (i / 4);
    ctx.beginPath(); ctx.moveTo(32, y); ctx.lineTo(W - 8, y); ctx.stroke();
  }

  // Plot each analyte as its own normalised sparkline
  analytes.forEach(([name, points], idx) => {
    if (points.length < 1) return;
    const vals = points.map(p => p.value);
    const minV = Math.min(...vals);
    const maxV = Math.max(...vals);
    const span = maxV - minV || 1;
    const color = COLORS[idx % COLORS.length];

    ctx.strokeStyle = color;
    ctx.lineWidth = 1.8;
    ctx.lineJoin = 'round';
    ctx.beginPath();
    points.forEach((p, i) => {
      const x = 32 + ((p.date - minDate) / dateSpan) * (W - 40);
      const y = H * 0.1 + H * 0.7 * (1 - (p.value - minV) / span);
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
      // Dot
      ctx.fillStyle = color;
      ctx.beginPath(); ctx.arc(x, y, 2.5, 0, 2 * Math.PI); ctx.fill();
      ctx.beginPath();
      points.forEach((p2, i2) => {
        const x2 = 32 + ((p2.date - minDate) / dateSpan) * (W - 40);
        const y2 = H * 0.1 + H * 0.7 * (1 - (p2.value - minV) / span);
        i2 === 0 ? ctx.moveTo(x2, y2) : ctx.lineTo(x2, y2);
      });
      ctx.stroke();
    });

    // Legend label
    ctx.fillStyle = color;
    ctx.font = `bold 9px monospace`;
    ctx.textAlign = 'left';
    ctx.fillText(`${name} (${vals[vals.length - 1]} latest)`, 34, H * 0.92 - idx * 13);
  });

  // Date axis labels
  ctx.fillStyle = '#95A092';
  ctx.font = `8px monospace`;
  ctx.textAlign = 'center';
  const fmtDate = d => d.toLocaleDateString('en-GB', { month: 'short', year: '2-digit' });
  ctx.fillText(fmtDate(minDate), 32, H - 2);
  ctx.fillText(fmtDate(maxDate), W - 8, H - 2);
}

// Builds a plain-text clinical summary (height velocity, percentile channel,
// recent lab values, logging consistency) sized for a doctor visit, and
// triggers a share/copy flow. No file-system writes — this is a client-side
// text blob handed to the OS share sheet or clipboard.
// exportClinicalSummary — alias kept so old onclick attributes still work.
async function exportClinicalSummary() {
  return generateClinicPDF();
}

async function _exportClinicalSummaryOLD_UNUSED() {
  const child = APP.children[APP.activeChild];
  if (!child) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }
  const streakArr = currentStreak();
  const loggedDays = streakArr.reduce((a,b)=>a+b,0);

  const summary = `BioGrowth OS — Clinic Summary
Child: ${child.name}  |  Age: ${child.age}  |  Current height: ${child.height} cm  |  Weight: ${child.weight} kg
Generated: ${new Date().toLocaleDateString('en-GB', {day:'numeric', month:'long', year:'numeric'})}

HEIGHT VELOCITY
${document.getElementById('velocityVal').textContent} cm/year — tracking near the ${document.getElementById('channelPctLbl').textContent} for height-for-age.

RECENT MEASUREMENTS
${Array.from(document.querySelectorAll('#histBody tr')).slice(0,5).map(tr => {
  const c = tr.querySelectorAll('td');
  return `  ${c[0]?.textContent}: ${c[1]?.textContent} cm, ${c[2]?.textContent} kg, BMI ${c[3]?.textContent}`;
}).join('\n')}

LOGGING CONSISTENCY
${loggedDays} of the last 7 days logged.

NOTE: Reference percentile bands shown in-app are illustrative population curves for trend visualization, not a substitute for your clinic's official growth chart.`;

  try {
    if (navigator.share) {
      await navigator.share({ title: 'BioGrowth OS — Clinic Summary', text: summary });
    } else {
      await navigator.clipboard.writeText(summary);
      showToast('✅', 'Summary copied to clipboard');
    }
  } catch (e) {
    try {
      await navigator.clipboard.writeText(summary);
      showToast('✅', 'Summary copied to clipboard');
    } catch (e2) {
      showToast('⚠️', 'Could not share or copy — try again');
    }
  }
}

function drawLine(ctx, pts, color, w) {
  if (!pts.length) return;
  ctx.strokeStyle = color; ctx.lineWidth = w; ctx.setLineDash([]);
  ctx.beginPath();
  pts.forEach(([x,y],i) => i===0 ? ctx.moveTo(x,y) : ctx.lineTo(x,y));
  ctx.stroke();
}

// ══════════════════════════════════════════
// MEDICAL
// ══════════════════════════════════════════
// NOTE: there is no medical_logs table in the current schema — only
// bone_age_assessments exists for clinical data beyond the daily
// nutrition/sleep/activity tables. Illness days, medications, and lab
// values (IGF-1, Vitamin D, ferritin) aren't persisted anywhere yet.
// This intentionally does not pretend to save to a backend until that
// table is designed — see conversation note. Values stay in the form
// fields for the current session only and are lost on reload.
async function saveMedical() {
  const childId = activeChildId();
  if (!childId) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }

  const btn = document.getElementById('saveMedicalBtn');
  if (btn) { btn.textContent = 'Saving…'; btn.disabled = true; }

  const igf1     = document.getElementById('labIGF').value;
  const vitD     = document.getElementById('labVitD').value;
  const ferritin = document.getElementById('labFerritin').value;

  // Lab values (IGF-1, Vit D, Ferritin) are Premium features
  const hasLabValues = igf1 || vitD || ferritin;
  if (hasLabValues && !isPremium()) {
    if (btn) { btn.disabled = false; btn.textContent = 'Save clinical record'; }
    showUpgradeModal('lab_values');
    return;
  }

  const { error } = await sb.from('medical_logs').upsert({
    child_id:         childId,
    log_date:         APP.logDate,
    steroid_level:    currentState().steroid,
    medications:      document.getElementById('medMeds').value || null,
    notes:            document.getElementById('medNotes').value || null,
    igf1_ng_ml:       igf1     ? parseFloat(igf1)     : null,
    vitamin_d_nmol_l: vitD     ? parseFloat(vitD)     : null,
    ferritin_ng_ml:   ferritin ? parseFloat(ferritin) : null,
    created_by:       APP.session ? APP.session.user.id : null
  }, { onConflict: 'child_id,log_date' });

  if (btn) { btn.disabled = false; btn.textContent = 'Save clinical record'; }

  if (error) {
    showToast('⚠️', t('toast.error.save_failed','Could not save') + ': ' + error.message);
    return;
  }
  showToast('✅', t('toast.clinical_saved','Clinical record saved') + ' — ' + APP.logDate);
  await loadLabValuesHistory();
}

// Loads recent medical_logs entries that have any lab value and renders
// them as rows below the Save button. Simple fetch + JS filter avoids
// Supabase OR filter syntax pitfalls.
async function loadLabValuesHistory() {
  const childId = activeChildId();
  const listEl  = document.getElementById('labValuesList');
  if (!childId || !listEl) return;

  const { data, error } = await sb
    .from('medical_logs')
    .select('log_id, log_date, igf1_ng_ml, vitamin_d_nmol_l, ferritin_ng_ml')
    .eq('child_id', childId)
    .order('log_date', { ascending: false })
    .limit(20);

  if (error) { console.error('[Lab history]', error); return; }

  // Filter client-side — only show rows with at least one lab value
  const rows = (data || []).filter(r =>
    r.igf1_ng_ml != null || r.vitamin_d_nmol_l != null || r.ferritin_ng_ml != null
  );

  if (!rows.length) {
    listEl.innerHTML = '<div style="font-size:11px;color:var(--text3);padding:8px 0;">No lab values recorded yet.</div>';
    return;
  }

  listEl.innerHTML = rows.map(r => {
    const parts = [];
    if (r.igf1_ng_ml       != null) parts.push('IGF-1: <b>' + r.igf1_ng_ml + '</b> <span style="color:var(--text3);font-size:10px;">ng/mL</span>');
    if (r.vitamin_d_nmol_l != null) parts.push('Vit D: <b>' + r.vitamin_d_nmol_l + '</b> <span style="color:var(--text3);font-size:10px;">nmol/L</span>');
    if (r.ferritin_ng_ml   != null) parts.push('Ferritin: <b>' + r.ferritin_ng_ml + '</b> <span style="color:var(--text3);font-size:10px;">ng/mL</span>');
    if (!parts.length) return '';
    const [y, m, d] = r.log_date.split('-').map(Number);
    const label = new Date(y, m - 1, d).toLocaleDateString('en-GB', { day:'numeric', month:'short', year:'numeric' });
    return '<div style="padding:9px 12px;background:var(--surface2);border-radius:10px;margin-bottom:6px;">'
      + '<div style="font-size:10.5px;color:var(--text3);margin-bottom:3px;">' + label + '</div>'
      + '<div style="font-size:12px;color:var(--text);line-height:1.7;">' + parts.join(' &nbsp;·&nbsp; ') + '</div>'
      + '</div>';
  }).filter(Boolean).join('');
}

// Loads this child's medical_logs row for the currently-selected
// APP.logDate (if any) and populates the Medical screen's fields —
// called whenever the Medical tab is opened or the date/child changes,
// mirroring how loadDayIntoState() restores the Today screen.
async function loadMedicalLogForDate() {
  const childId = activeChildId();
  const medsEl = document.getElementById('medMeds');
  const notesEl = document.getElementById('medNotes');
  const igfEl = document.getElementById('labIGF');
  const vitDEl = document.getElementById('labVitD');
  const ferritinEl = document.getElementById('labFerritin');

  // Reset to blank defaults first, so switching to a date/child with no
  // record doesn't show stale values from whatever was viewed before.
  medsEl.value = '';
  notesEl.value = '';
  igfEl.value = '';
  vitDEl.value = '';
  ferritinEl.value = '';
  setSteroid(0, document.getElementById('stNone'));

  if (!childId) return;

  const { data, error } = await sb
    .from('medical_logs')
    .select('*')
    .eq('child_id', childId)
    .eq('log_date', APP.logDate)
    .maybeSingle();

  if (error || !data) return; // no record for this date — blank form is correct

  medsEl.value = data.medications || '';
  notesEl.value = data.notes || '';
  igfEl.value = data.igf1_ng_ml != null ? data.igf1_ng_ml : '';
  vitDEl.value = data.vitamin_d_nmol_l != null ? data.vitamin_d_nmol_l : '';
  ferritinEl.value = data.ferritin_ng_ml != null ? data.ferritin_ng_ml : '';

  const stMap = { 0: 'stNone', 1: 'stInhaled', 2: 'stOral' };
  const stBtn = document.getElementById(stMap[data.steroid_level] || 'stNone');
  if (stBtn) setSteroid(data.steroid_level || 0, stBtn);
}

// ══════════════════════════════════════════
// LAB RESULTS — generic analyte tracking (lab_results table). Separate
// from the 3 fixed fields above (IGF-1/VitD/Ferritin, on medical_logs)
// — this covers anything else. Unlike daily_nutrition/medical_logs,
// these are event-based, not date-keyed, so there's no upsert-by-date:
// each entry is its own permanent row, and multiple results on the
// same day (e.g. a full panel from one blood draw) are all kept.
// ══════════════════════════════════════════
async function loadLabResults() {
  const childId = activeChildId();
  const listEl = document.getElementById('labResultsList');
  if (!listEl) return;
  if (!childId) { listEl.innerHTML = ''; return; }

  const { data, error } = await sb
    .from('lab_results')
    .select('*')
    .eq('child_id', childId)
    .order('lab_date', { ascending: false })
    .limit(20);

  if (error) {
    console.error('[Lab Results] Load failed:', error);
    listEl.innerHTML = `<div class="log-list-empty" style="color:var(--flag);">Could not load lab results: ${error.message}</div>`;
    return;
  }
  APP.labResults = data || [];
  renderLabResultsList();
}

function renderLabResultsList() {
  const listEl = document.getElementById('labResultsList');
  if (!listEl) return;
  const items = APP.labResults || [];
  if (items.length === 0) {
    listEl.innerHTML = '<div class="log-list-empty">No other lab results logged yet.</div>';
    return;
  }
  listEl.innerHTML = items.map(r => {
    const fmt = new Date(r.lab_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    const range = (r.reference_low != null && r.reference_high != null) ? ` (ref ${r.reference_low}–${r.reference_high})` : '';
    return `
      <div class="log-item-row">
        <div class="log-item-left">
          <span class="log-item-emoji">🧪</span>
          <div class="log-item-info">
            <span class="log-item-name">${r.analyte_name}</span>
            <span class="log-item-meta">${fmt}${range}</span>
          </div>
        </div>
        <div class="log-item-right">
          <span class="log-item-amount">${r.result_value} ${r.unit}</span>
          <button class="log-item-delete" onclick="deleteLabResult('${r.lab_result_id}')" aria-label="Remove">×</button>
        </div>
      </div>
    `;
  }).join('');
}

async function addLabResult() {
  const childId = activeChildId();
  if (!childId) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }

  const analyte = document.getElementById('newLabAnalyte').value.trim();
  const value = document.getElementById('newLabValue').value;
  const unit = document.getElementById('newLabUnit').value.trim();
  const refLow = document.getElementById('newLabRefLow').value;
  const refHigh = document.getElementById('newLabRefHigh').value;

  if (!analyte) { showToast('⚠️', t('toast.error.enter_analyte','Enter the analyte name')); return; }
  if (!value) { showToast('⚠️', t('toast.error.enter_result','Enter the result value')); return; }
  if (!unit) { showToast('⚠️', t('toast.error.enter_unit','Enter the unit')); return; }

  const { data, error } = await sb.from('lab_results').insert({
    child_id: childId,
    lab_date: APP.logDate,
    analyte_name: analyte,
    result_value: parseFloat(value),
    unit: unit,
    reference_low: refLow ? parseFloat(refLow) : null,
    reference_high: refHigh ? parseFloat(refHigh) : null,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) { showToast('⚠️', t('toast.error.save_failed','Could not save') + ': ' + error.message); return; }

  APP.labResults = APP.labResults || [];
  APP.labResults.unshift(data);
  renderLabResultsList();

  document.getElementById('newLabAnalyte').value = '';
  document.getElementById('newLabValue').value = '';
  document.getElementById('newLabUnit').value = '';
  document.getElementById('newLabRefLow').value = '';
  document.getElementById('newLabRefHigh').value = '';
  showToast('✅', t('toast.lab_result_added','Lab result added'));
}

async function deleteLabResult(id) {
  if (!confirm(t('confirm.remove_lab','Remove this lab result? This cannot be undone.'))) return;
  const { error } = await sb.from('lab_results').delete().eq('lab_result_id', id);
  if (error) { showToast('⚠️', t('toast.error.remove_failed','Could not remove') + ': ' + error.message); return; }
  APP.labResults = (APP.labResults || []).filter(r => r.lab_result_id !== id);
  renderLabResultsList();
}

// ══════════════════════════════════════════
// PUBERTY EVENTS — Tanner staging and pubertal milestones
// (puberty_events table). Same event-based pattern as lab_results, not
// date-keyed — a child can have multiple staged observations over time
// for the same milestone type, which is exactly the point (tracking
// Tanner stage PROGRESSION, e.g. breast development II -> III -> IV).
// ══════════════════════════════════════════
const PUBERTY_TYPES_WITHOUT_STAGE = ['voice_change', 'body_odor', 'acne', 'growth_spurt_feeling', 'menarche'];

function togglePubertyStageVisibility() {
  const type = document.getElementById('newPubertyType').value;
  const row = document.getElementById('tannerStageRow');
  if (row) row.classList.toggle('hidden', PUBERTY_TYPES_WITHOUT_STAGE.includes(type));
}

async function loadPubertyEvents() {
  const childId = activeChildId();
  const listEl = document.getElementById('pubertyEventsList');
  if (!listEl) return;
  if (!childId) { listEl.innerHTML = ''; return; }

  const { data, error } = await sb
    .from('puberty_events')
    .select('*')
    .eq('child_id', childId)
    .order('event_date', { ascending: false })
    .limit(20);

  if (error) { listEl.innerHTML = ''; return; }
  APP.pubertyEvents = data || [];
  renderPubertyEventsList();
}

const PUBERTY_TYPE_LABELS = {
  breast_development: 'Breast development', genital_development: 'Genital development',
  pubic_hair: 'Pubic hair', axillary_hair: 'Axillary hair', facial_hair: 'Facial hair',
  voice_change: 'Voice change', body_odor: 'Body odor', acne: 'Acne',
  growth_spurt_feeling: 'Growth spurt (reported)', menarche: 'Menarche'
};
const TANNER_NUMERALS = { 1: 'I', 2: 'II', 3: 'III', 4: 'IV', 5: 'V' };

function renderPubertyEventsList() {
  const listEl = document.getElementById('pubertyEventsList');
  if (!listEl) return;
  const items = APP.pubertyEvents || [];
  if (items.length === 0) {
    listEl.innerHTML = '<div class="log-list-empty">No puberty milestones logged yet.</div>';
    return;
  }
  listEl.innerHTML = items.map(ev => {
    const fmt = new Date(ev.event_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    const label = PUBERTY_TYPE_LABELS[ev.event_type] || ev.event_type;
    const stageText = ev.tanner_stage ? `Tanner ${TANNER_NUMERALS[ev.tanner_stage]}` : 'observed';
    return `
      <div class="log-item-row">
        <div class="log-item-left">
          <span class="log-item-emoji">🌱</span>
          <div class="log-item-info">
            <span class="log-item-name">${label}</span>
            <span class="log-item-meta">${fmt}</span>
          </div>
        </div>
        <div class="log-item-right">
          <span class="log-item-amount">${stageText}</span>
          <button class="log-item-delete" onclick="deletePubertyEvent('${ev.event_id}')" aria-label="Remove">×</button>
        </div>
      </div>
    `;
  }).join('');
}

async function addPubertyEvent() {
  const childId = activeChildId();
  if (!childId) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }

  const type = document.getElementById('newPubertyType').value;
  const dateVal = document.getElementById('newPubertyDate').value;
  if (!dateVal) { showToast('⚠️', t('toast.error.enter_date_observed','Enter the date observed')); return; }

  const needsStage = !PUBERTY_TYPES_WITHOUT_STAGE.includes(type);
  const stage = needsStage ? parseInt(document.getElementById('newPubertyStage').value) : null;

  const { data, error } = await sb.from('puberty_events').insert({
    child_id: childId,
    event_date: dateVal,
    event_type: type,
    tanner_stage: stage,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) { showToast('⚠️', t('toast.error.save_failed','Could not save') + ': ' + error.message); return; }

  APP.pubertyEvents = APP.pubertyEvents || [];
  APP.pubertyEvents.unshift(data);
  renderPubertyEventsList();
  showToast('✅', t('toast.milestone_added','Milestone added'));
}

async function deletePubertyEvent(id) {
  if (!confirm(t('confirm.remove_puberty','Remove this puberty milestone? This cannot be undone.'))) return;
  const { error } = await sb.from('puberty_events').delete().eq('event_id', id);
  if (error) { showToast('⚠️', t('toast.error.remove_failed','Could not remove') + ': ' + error.message); return; }
  APP.pubertyEvents = (APP.pubertyEvents || []).filter(ev => ev.event_id !== id);
  renderPubertyEventsList();
}

// ══════════════════════════════════════════
// BONE AGE ASSESSMENTS
// X-ray upload + radiologist result entry + statistical interpretation.
//
// The statistical analysis follows the one-sample t-test framework from
// the Greulich-Pyle reference literature — the same methodology used by
// the Samitivej radiologists in Peem's Jan 2023 bone age report:
//
//   t = (bone_age_months - chrono_age_months) / sd_months
//
// Where sd_months is the population standard deviation for that
// specific method/age cohort (taken directly from the radiologist's
// report — we don't have to compute it, the report gives it to us).
//
// A |t| > 1.645 corresponds roughly to p < 0.10 (one-SD threshold);
// |t| > 2 corresponds to p < 0.05. The GP literature commonly uses
// ±1 SD as the "within normal limits" boundary and ±2 SD as clinically
// significant advanced/delayed maturation.
// ══════════════════════════════════════════

let _xrayFileSelected = null; // holds the File object before upload

function handleXrayFileSelect(input) {
  const file = input.files[0];
  if (!file) return;
  _xrayFileSelected = file;

  const zone = document.getElementById('xrayUploadZone');
  zone.classList.add('has-file');
  document.getElementById('xrayUploadLabel').textContent = file.name;

  // Show image preview for image files (not PDFs)
  if (file.type.startsWith('image/')) {
    const reader = new FileReader();
    reader.onload = e => {
      document.getElementById('xrayPreviewImg').src = e.target.result;
      document.getElementById('xrayPreviewContainer').classList.remove('hidden');
    };
    reader.readAsDataURL(file);
  }
}

function clearXraySelection() {
  _xrayFileSelected = null;
  document.getElementById('xrayFileInput').value = '';
  document.getElementById('xrayUploadZone').classList.remove('has-file');
  document.getElementById('xrayUploadLabel').textContent = 'Tap to upload X-ray image';
  document.getElementById('xrayPreviewContainer').classList.add('hidden');
}

async function saveBoneAgeAssessment() {
  const childId = activeChildId();
  if (!childId) { showToast('⚠️', 'No active child selected'); return; }

  const studyDate = document.getElementById('boneAgeStudyDate').value;
  const boneAgeYears = parseInt(document.getElementById('boneAgeYears').value) || 0;
  const boneAgeMonthsExtra = parseInt(document.getElementById('boneAgeMonths').value) || 0;
  const sdMonths = parseFloat(document.getElementById('boneAgeSd').value) || null;
  const method = document.getElementById('boneAgeMethod').value;
  const doctor = document.getElementById('boneAgeDoctor').value.trim();
  const notes = document.getElementById('boneAgeNotes').value.trim();

  if (!studyDate) { showToast('⚠️', t('toast.error.study_date_required','Study date is required')); return; }
  if (boneAgeYears === 0 && boneAgeMonthsExtra === 0) { showToast('⚠️', t('toast.error.enter_bone_age','Enter a bone age result')); return; }

  const boneAgeMonthsTotal = boneAgeYears * 12 + boneAgeMonthsExtra;

  // Compute chronological age at study date from the child's DOB
  const child = APP.children[APP.activeChild];
  let chronoAgeMonths = null;
  if (child && child.date_of_birth) {
    const dob = new Date(child.date_of_birth);
    const study = new Date(studyDate);
    chronoAgeMonths = parseFloat(((study - dob) / (1000 * 60 * 60 * 24 * 30.4375)).toFixed(1));
  }

  const saveBtn = document.getElementById('saveBoneAgeBtn');
  saveBtn.disabled = true;
  saveBtn.textContent = 'Saving…';

  try {
    // Upload X-ray to Supabase Storage if one was selected
    let xrayStoragePath = null;
    if (_xrayFileSelected) {
      const ext = _xrayFileSelected.name.split('.').pop().toLowerCase();
      const fileName = `${childId}/${Date.now()}.${ext}`;
      const { data: uploadData, error: uploadError } = await sb.storage
        .from('bone-xrays')
        .upload(fileName, _xrayFileSelected, { contentType: _xrayFileSelected.type, upsert: false });

      if (uploadError) {
        showToast('⚠️', 'Image upload failed: ' + uploadError.message);
        // Don't abort — save the record without the image
      } else {
        xrayStoragePath = uploadData.path;
      }
    }

    const { data: record, error } = await sb.from('bone_age_assessments').insert({
      child_id: childId,
      study_date: studyDate,
      bone_age_months: boneAgeMonthsTotal,
      sd_months: sdMonths,
      method,
      chronological_age_months: chronoAgeMonths,
      report_doctor: doctor || null,
      notes: notes || null,
      xray_storage_path: xrayStoragePath,
      created_by: APP.session ? APP.session.user.id : null
    }).select().single();

    if (error) throw error;

    APP.boneAgeAssessments = [record, ...(APP.boneAgeAssessments || [])];
    await renderBoneAgeList();

    // Clear the form
    document.getElementById('boneAgeStudyDate').value = '';
    document.getElementById('boneAgeYears').value = '';
    document.getElementById('boneAgeMonths').value = '';
    document.getElementById('boneAgeSd').value = '';
    document.getElementById('boneAgeDoctor').value = '';
    document.getElementById('boneAgeNotes').value = '';
    clearXraySelection();
    showToast('✅', t('toast.bone_age_saved','Bone age record saved'));
  } catch (e) {
    showToast('⚠️', 'Could not save: ' + e.message);
  } finally {
    saveBtn.disabled = false;
    saveBtn.textContent = 'Save bone age record';
  }
}

async function loadBoneAgeAssessments() {
  const childId = activeChildId();
  if (!childId) return;
  const { data, error } = await sb.from('bone_age_assessments')
    .select('*').eq('child_id', childId).order('study_date', { ascending: false });
  APP.boneAgeAssessments = (!error && data) ? data : [];
  await renderBoneAgeList();
}

async function renderBoneAgeList() {
  const el = document.getElementById('boneAgeList');
  if (!el) return;
  const records = APP.boneAgeAssessments || [];

  if (records.length === 0) {
    el.innerHTML = '<div class="log-list-empty" style="padding:14px 0;">No bone age assessments recorded yet.</div>';
    return;
  }

  // Build all cards — need signed URLs for any X-ray images
  const cardsHtml = await Promise.all(records.map(r => buildBoneAgeCard(r)));
  el.innerHTML = cardsHtml.join('');
}

async function buildBoneAgeCard(r) {
  const boneAgeYr = Math.floor(r.bone_age_months / 12);
  const boneAgeMo = Math.round(r.bone_age_months % 12);
  const boneAgeStr = `${boneAgeYr}y ${boneAgeMo}m`;

  // Compute delta and statistical interpretation
  let deltaHtml = '';
  let sigBadge = '';
  if (r.chronological_age_months) {
    const delta = r.bone_age_months - r.chronological_age_months;
    const deltaSign = delta >= 0 ? '+' : '';
    const deltaClass = Math.abs(delta) <= 6 ? 'normal' : (delta < 0 ? 'delayed' : 'advanced');
    const deltaLabel = Math.abs(delta) <= 6 ? 'Within normal range' : (delta < 0 ? 'Delayed' : 'Advanced');

    const chronoYr = Math.floor(r.chronological_age_months / 12);
    const chronoMo = Math.round(r.chronological_age_months % 12);

    // t-score: how many SDs the delta represents
    // Uses the SD from the report (which is the population SD for that age/method)
    let tScore = null;
    let sdLine = '';
    if (r.sd_months) {
      tScore = delta / r.sd_months;
      const absT = Math.abs(tScore);
      const significant = absT >= 2.0; // |t| >= 2 ≈ p < 0.05 with large n
      sigBadge = `<span class="sig-badge ${significant ? 'significant' : 'not-significant'}">${significant ? '⚠ Significant' : '✓ Within 2 SD'}</span>`;
      sdLine = `<div style="font-size:11px; color:var(--text2); margin-top:6px;">t-score: ${tScore.toFixed(2)} · SD from report: ${r.sd_months} months · ${Math.abs(delta).toFixed(1)} months ${delta < 0 ? 'behind' : 'ahead'}</div>`;
    } else {
      sigBadge = `<span class="sig-badge no-sd">No SD in report</span>`;
    }

    deltaHtml = `
      <div class="bone-age-delta-strip">
        <div class="bone-age-stat ${deltaClass}">
          <div class="bone-age-stat-val">${deltaSign}${delta.toFixed(1)}mo</div>
          <div class="bone-age-stat-lbl">Bone age delta</div>
        </div>
        <div class="bone-age-stat">
          <div class="bone-age-stat-val">${boneAgeStr}</div>
          <div class="bone-age-stat-lbl">Bone age</div>
        </div>
        <div class="bone-age-stat">
          <div class="bone-age-stat-val">${chronoYr}y ${chronoMo}m</div>
          <div class="bone-age-stat-lbl">Chronological age</div>
        </div>
      </div>
      <div style="display:flex; align-items:center; gap:8px; flex-wrap:wrap;">
        ${sigBadge}
        <span style="font-size:11px; color:var(--text2);">${deltaLabel} · ${r.method} method</span>
      </div>
      ${sdLine}`;
  }

  // X-ray image — get a signed URL (valid 60 min)
  let xrayImgHtml = '';
  let xraySignedUrl = null;
  if (r.xray_storage_path) {
    try {
      const { data: signed } = await sb.storage.from('bone-xrays').createSignedUrl(r.xray_storage_path, 3600);
      if (signed && signed.signedUrl) {
        xrayImgHtml = `<img class="xray-thumb" src="${signed.signedUrl}" alt="Bone age X-ray" onclick="window.open(this.src,'_blank')">`;
        xraySignedUrl = signed.signedUrl; // also used for the AI annotation overlay
      }
    } catch (e) { /* signed URL failure is non-fatal */ }
  }

  const displayDate = new Date(r.study_date).toLocaleDateString('en-GB', { day:'numeric', month:'short', year:'numeric' });

  // AI analysis button and panel
  const hasImage = !!r.xray_storage_path;
  const hasAIResult = !!r.ai_analysis_result;

  const aiButtonHtml = hasImage
    ? `<button class="btn-secondary" id="aiBtn-${r.assessment_id}" style="font-size:11px; padding:7px 12px; margin-top:10px;" onclick="runBoneAgeAIAnalysis('${r.assessment_id}')">
        🤖 ${hasAIResult ? 'Re-run AI Second Opinion' : 'Get AI Second Opinion'}
       </button>`
    : `<div style="font-size:10px; color:var(--text3); margin-top:8px;">Upload an X-ray image to enable AI second opinion</div>`;

  const aiPanelInitialContent = hasAIResult
    ? renderBoneAgeAIPanel(r.ai_analysis_result, r.bone_age_months, r.chronological_age_months, r.ai_analysis_date, xraySignedUrl)
    : '';

  return `
    <div class="bone-age-result-card">
      <div class="bone-age-result-header">
        <div>
          <div style="font-size:13px; font-weight:700; color:var(--text);">Bone age: ${boneAgeStr}</div>
          <div style="font-size:11px; color:var(--text2);">${displayDate}${r.report_doctor ? ' · ' + r.report_doctor : ''} · ${r.method || 'GP'}</div>
        </div>
        <button class="btn-link" style="font-size:11px; color:var(--flag);" onclick="deleteBoneAgeAssessment('${r.assessment_id}')">Remove</button>
      </div>
      <div class="bone-age-result-body">
        ${deltaHtml}
        ${r.notes ? `<div style="font-size:11px; color:var(--text2); margin-top:8px;">${r.notes}</div>` : ''}
        ${xrayImgHtml}
        ${aiButtonHtml}
        <div id="aiPanel-${r.assessment_id}" class="${hasAIResult ? '' : 'hidden'}" style="margin-top:10px;">
          ${aiPanelInitialContent}
        </div>
      </div>
    </div>`;
}

async function deleteBoneAgeAssessment(id) {
  if (!confirm(t('confirm.remove_bone_age','Remove this bone age record? The uploaded X-ray image will also be deleted. This cannot be undone.'))) return;

  const record = (APP.boneAgeAssessments || []).find(r => r.assessment_id === id);

  if (record && record.xray_storage_path) {
    await sb.storage.from('bone-xrays').remove([record.xray_storage_path]);
  }

  const { error } = await sb.from('bone_age_assessments').delete().eq('assessment_id', id);
  if (error) { showToast('⚠️', t('toast.error.remove_failed','Could not remove') + ': ' + error.message); return; }

  APP.boneAgeAssessments = (APP.boneAgeAssessments || []).filter(r => r.assessment_id !== id);
  await renderBoneAgeList();
  showToast('✅', t('toast.bone_age_removed','Bone age record removed'));
}

// ══════════════════════════════════════════
// BONE AGE AI ANALYSIS — second opinion via Claude Vision
//
// Algorithm v2 corrections (from real case study validation — Peem Mar 2019
// where v1 overestimated by 6 months and reversed the clinical conclusion):
//
//   v1 error 1: Counted a shadow as "triquetrum" → carpal overcounting
//               → bone age overestimated → "normal" when it was "delayed"
//   v1 error 2: Used TW3 pixel ratio calculations → systematic upward bias
//               from JPEG compression vs DICOM
//   v1 error 3: Reported single number (24.0mo) with false precision
//
//   v2 corrections in the Edge Function prompt:
//   - Carpal count is PRIMARY anchor at age <48 months; uncertain → count fewer
//   - GP holistic plate matching only, no pixel ratio measurements
//   - Always output a range (≥6 month minimum uncertainty)
//   - When uncertain between two readings → bias toward YOUNGER
// ══════════════════════════════════════════

async function runBoneAgeAIAnalysis(assessmentId) {
  const record = (APP.boneAgeAssessments || []).find(r => r.assessment_id === assessmentId);
  if (!record) { showToast('⚠️', t('toast.error.record_not_found','Record not found')); return; }
  if (!record.xray_storage_path) { showToast('⚠️', t('toast.error.no_xray','No X-ray image attached to this record')); return; }

  // Update UI to loading state
  const btn = document.getElementById(`aiBtn-${assessmentId}`);
  const panel = document.getElementById(`aiPanel-${assessmentId}`);
  if (btn) { btn.disabled = true; btn.textContent = 'Analysing…'; }
  if (panel) {
    panel.classList.remove('hidden');
    panel.innerHTML = `<div class="bone-age-ai-loading"><div class="spinner-sm"></div>Claude Vision is examining the X-ray using the GP framework…</div>`;
  }

  try {
    // Step 1: Get a signed URL and fetch the image
    const { data: signed } = await sb.storage.from('bone-xrays').createSignedUrl(record.xray_storage_path, 300);
    if (!signed?.signedUrl) throw new Error('Could not access X-ray image');

    const imgRes = await fetch(signed.signedUrl);
    if (!imgRes.ok) throw new Error('Could not fetch X-ray image');

    const blob = await imgRes.blob();
    const mediaType = blob.type || 'image/jpeg';

    // Step 2: Convert to base64 — downscale to 800px max first to keep
    // the payload to Anthropic under ~200KB. Vision analysis doesn't
    // need the full 832×888 resolution; bones are clearly readable at
    // 600-800px and the request completes much faster.
    const base64 = await new Promise((resolve, reject) => {
      const img = new Image();
      const url = URL.createObjectURL(blob);
      img.onload = () => {
        URL.revokeObjectURL(url);
        const MAX = 800;
        let w = img.naturalWidth, h = img.naturalHeight;
        if (w > MAX || h > MAX) {
          const ratio = Math.min(MAX / w, MAX / h);
          w = Math.round(w * ratio);
          h = Math.round(h * ratio);
        }
        const canvas = document.createElement('canvas');
        canvas.width = w; canvas.height = h;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, w, h);
        const dataUrl = canvas.toDataURL('image/jpeg', 0.85);
        resolve(dataUrl.split(',')[1]);
      };
      img.onerror = reject;
      img.src = url;
    });

    // Step 3: Send to Edge Function
    const res = await fetch(`${SUPABASE_URL}/functions/v1/bone-age-analysis`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${APP.session ? APP.session.access_token : ''}`
      },
      body: JSON.stringify({
        image_base64: base64,
        media_type: mediaType,
        chronological_age_months: record.chronological_age_months,
        sex: APP.children[APP.activeChild]?.sex || 'male',
        assessment_id: assessmentId
      })
    });

    const data = await res.json();
    if (!res.ok || data.error) {
      // Extract the real error — Anthropic errors come back in data.detail
      const anthropicMsg = data.detail?.error?.message
        || data.detail?.message
        || (typeof data.detail === 'string' ? data.detail : null)
        || data.error
        || 'Unknown error from AI service';
      console.error('[Bone Age AI] Full error response:', data);
      throw new Error(anthropicMsg);
    }

    // Step 4: Update in-memory record + re-render
    const idx = (APP.boneAgeAssessments || []).findIndex(r => r.assessment_id === assessmentId);
    if (idx >= 0) {
      APP.boneAgeAssessments[idx].ai_analysis_result = data.result;
      APP.boneAgeAssessments[idx].ai_analysis_date = new Date().toISOString();
    }

    if (panel) {
      panel.innerHTML = renderBoneAgeAIPanel(
        data.result,
        record.bone_age_months,
        record.chronological_age_months,
        record.ai_analysis_date,
        signed.signedUrl
      );
    }

    if (btn) { btn.disabled = false; btn.textContent = '🔄 Re-analyse'; }
    showToast('✅', t('toast.ai_complete','AI second opinion complete'));

  } catch (e) {
    console.error('[Bone Age AI]', e);
    if (panel) panel.innerHTML = `<div class="bone-age-ai-error">⚠️ Analysis failed: ${e.message}. Please try again.</div>`;
    if (btn) { btn.disabled = false; btn.textContent = '🤖 Get AI Second Opinion'; }
    showToast('⚠️', t('toast.error.ai_failed','AI analysis failed') + ': ' + e.message);
  }
}

function buildAnnotationOverlaySVG(aiResult) {
  if (!aiResult) return '';
  const carpals = aiResult.carpal_analysis || {};
  const epiObs = aiResult.epiphyseal_observations || [];

  // Color map aligned to the app's design tokens (from design-tokens.css).
  // These are the exact hex values of each token, used here as hex because
  // SVG inside a JS template literal can't reference CSS custom properties.
  //
  //   absent        → --text3       #95A092  (muted, de-emphasised)
  //   barely_visible→ --measured    #2A5C8A  (blue — just appearing)
  //   small_clear   → --accent      #2F6B4F  (green — normal for age)
  //   well_formed   → --estimated   #9C7A3D  (amber — maturing)
  //   wide_capping  → --flag        #A23B3B  (red — advanced maturation)
  //   carpals       → --estimated   #9C7A3D  (amber — primary reference)
  const C = {
    absent:         '#95A092',
    barely_visible: '#2A5C8A',
    small_clear:    '#2F6B4F',
    well_formed:    '#9C7A3D',
    wide_capping:   '#A23B3B'
  };
  const CARPAL_COLOR = '#9C7A3D'; // --estimated

  const getColor = (boneGroup) => {
    const obs = epiObs.find(o => o.bone_group === boneGroup);
    return C[obs?.appearance] || '#95A092';
  };
  const getLabel = (boneGroup) => {
    const obs = epiObs.find(o => o.bone_group === boneGroup);
    return (obs?.appearance || '').replace(/_/g, ' ');
  };

  const ids = (carpals.bones_identified || []).map(b => b.toLowerCase());
  const hasCap  = ids.some(b => b.includes('capitate'));
  const hasHam  = ids.some(b => b.includes('hamate'));
  const hasTrq  = ids.some(b => b.includes('triquetrum'));
  const hasLun  = ids.some(b => b.includes('lunate'));
  const hasScap = ids.some(b => b.includes('scaphoid'));

  const rC  = getColor('distal_radius');
  const mC  = getColor('metacarpals');
  const ppC = getColor('proximal_phalanges');
  const mpC = getColor('middle_phalanges');
  const dpC = getColor('distal_phalanges');

  // All coordinates are in a 0-100 viewBox matching the X-ray's
  // standard orientation (left hand PA: wrist at bottom, thumb right).
  // Positions are approximate anatomical percentages — accurate enough
  // to visually guide the user to the right region even though they're
  // not pixel-calibrated from DICOM.
  return `
<svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet"
  style="position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;">

  <!-- Distal radius band -->
  <rect x="33" y="79" width="23" height="5" rx="1"
    fill="${rC}18" stroke="${rC}" stroke-width="0.6" stroke-dasharray="2,1.5"/>
  <text x="32" y="81" fill="${rC}" font-size="3.2" font-family="monospace"
    text-anchor="end" font-weight="bold">Radius</text>
  <text x="32" y="84.5" fill="${rC}" font-size="2.5" font-family="monospace"
    text-anchor="end" opacity="0.85">${getLabel('distal_radius')}</text>
  <line x1="32.5" y1="81.5" x2="33" y2="81.5" stroke="${rC}" stroke-width="0.4"/>

  <!-- Carpal region ellipse -->
  <ellipse cx="46" cy="73" rx="16" ry="7.5"
    fill="${CARPAL_COLOR}10" stroke="${CARPAL_COLOR}" stroke-width="0.7" stroke-dasharray="2.5,2"/>
  <text x="64" y="70" fill="${CARPAL_COLOR}" font-size="3.2" font-family="monospace"
    font-weight="bold">Carpals</text>
  <text x="64" y="73.5" fill="${CARPAL_COLOR}" font-size="2.5" font-family="monospace"
    opacity="0.85">${carpals.count_visible || 0}/8 found</text>
  <line x1="62" y1="72" x2="63.5" y2="71.5" stroke="${CARPAL_COLOR}" stroke-width="0.4"/>

  <!-- Individual carpal circles -->
  ${hasCap  ? `<circle cx="51" cy="72" r="2.8" fill="${CARPAL_COLOR}28" stroke="${CARPAL_COLOR}" stroke-width="0.8"/>
    <text x="51" y="77.5" fill="${CARPAL_COLOR}" font-size="2.3" text-anchor="middle" font-family="monospace">Cap</text>` : ''}
  ${hasHam  ? `<circle cx="43" cy="74.5" r="2.3" fill="${CARPAL_COLOR}28" stroke="${CARPAL_COLOR}" stroke-width="0.8"/>
    <text x="43" y="79.5" fill="${CARPAL_COLOR}" font-size="2.3" text-anchor="middle" font-family="monospace">Ham</text>` : ''}
  ${hasTrq  ? `<circle cx="36" cy="76.5" r="2" fill="${CARPAL_COLOR}28" stroke="${CARPAL_COLOR}" stroke-width="0.7" stroke-dasharray="1.5,1"/>
    <text x="36" y="81" fill="${CARPAL_COLOR}" font-size="2.3" text-anchor="middle" font-family="monospace">Triq</text>` : ''}
  ${hasLun  ? `<circle cx="58" cy="71" r="2" fill="${CARPAL_COLOR}28" stroke="${CARPAL_COLOR}" stroke-width="0.7"/>
    <text x="58" y="75.5" fill="${CARPAL_COLOR}" font-size="2.3" text-anchor="middle" font-family="monospace">Lun</text>` : ''}
  ${hasScap ? `<circle cx="55" cy="68" r="2" fill="${CARPAL_COLOR}28" stroke="${CARPAL_COLOR}" stroke-width="0.7"/>
    <text x="55" y="72.5" fill="${CARPAL_COLOR}" font-size="2.3" text-anchor="middle" font-family="monospace">Scap</text>` : ''}

  <!-- Metacarpal distal epiphyses -->
  <ellipse cx="44" cy="57" rx="20" ry="5.5"
    fill="${mC}18" stroke="${mC}" stroke-width="0.6" stroke-dasharray="2,1.5"/>
  <text x="66" y="54.5" fill="${mC}" font-size="3.2" font-family="monospace"
    font-weight="bold">Metacarpals</text>
  <text x="66" y="58.5" fill="${mC}" font-size="2.5" font-family="monospace"
    opacity="0.85">${getLabel('metacarpals')}</text>
  <line x1="64" y1="57" x2="65.5" y2="56.5" stroke="${mC}" stroke-width="0.4"/>

  <!-- Proximal phalangeal epiphyses -->
  <ellipse cx="43" cy="43" rx="19" ry="5"
    fill="${ppC}18" stroke="${ppC}" stroke-width="0.6" stroke-dasharray="2,1.5"/>
  <text x="64" y="40.5" fill="${ppC}" font-size="3.2" font-family="monospace"
    font-weight="bold">Prox. phalan.</text>
  <text x="64" y="44.5" fill="${ppC}" font-size="2.5" font-family="monospace"
    opacity="0.85">${getLabel('proximal_phalanges')}</text>
  <line x1="62" y1="43" x2="63.5" y2="42.5" stroke="${ppC}" stroke-width="0.4"/>

  <!-- Middle phalangeal epiphyses -->
  <ellipse cx="43" cy="31" rx="17" ry="4.5"
    fill="${mpC}18" stroke="${mpC}" stroke-width="0.6" stroke-dasharray="2,1.5"/>
  <text x="62" y="28.5" fill="${mpC}" font-size="3.2" font-family="monospace"
    font-weight="bold">Mid. phalan.</text>
  <text x="62" y="32.5" fill="${mpC}" font-size="2.5" font-family="monospace"
    opacity="0.85">${getLabel('middle_phalanges')}</text>
  <line x1="60" y1="31" x2="61.5" y2="30.5" stroke="${mpC}" stroke-width="0.4"/>

  <!-- Distal phalangeal epiphyses -->
  <ellipse cx="43" cy="18" rx="14" ry="4"
    fill="${dpC}18" stroke="${dpC}" stroke-width="0.6" stroke-dasharray="2,1.5"/>
  <text x="59" y="15.5" fill="${dpC}" font-size="3.2" font-family="monospace"
    font-weight="bold">Dist. phalan.</text>
  <text x="59" y="19.5" fill="${dpC}" font-size="2.5" font-family="monospace"
    opacity="0.85">${getLabel('distal_phalanges')}</text>
  <line x1="57" y1="18" x2="58.5" y2="17.5" stroke="${dpC}" stroke-width="0.4"/>

  <!-- Legend panel bottom-left -->
  <rect x="1" y="88" width="40" height="11" rx="1.5" fill="#1F2B2299"/>
  <text x="2.5" y="91.5" fill="#95A092" font-size="2.4" font-family="monospace"
    font-weight="bold">APPEARANCE SCALE</text>
  <circle cx="4" cy="94.5" r="1.2" fill="#2A5C8A"/>
  <text x="6.5" y="95.5" fill="#EEF0EC" font-size="2.2" font-family="monospace">barely visible</text>
  <circle cx="21" cy="94.5" r="1.2" fill="#2F6B4F"/>
  <text x="23.5" y="95.5" fill="#EEF0EC" font-size="2.2" font-family="monospace">small, clear</text>
  <circle cx="4" cy="98" r="1.2" fill="#9C7A3D"/>
  <text x="6.5" y="99" fill="#EEF0EC" font-size="2.2" font-family="monospace">well formed</text>
  <circle cx="21" cy="98" r="1.2" fill="#A23B3B"/>
  <text x="23.5" y="99" fill="#EEF0EC" font-size="2.2" font-family="monospace">wide/capping</text>
</svg>`;
}

function renderBoneAgeAIPanel(result, doctorBoneAgeMonths, chronologicalAgeMonths, analysisDate, xraySignedUrl) {
  if (!result) return '';

  const est = result.bone_age_estimate || {};
  const stats = result.statistical_analysis || {};
  const carpals = result.carpal_analysis || {};
  const epiObs = result.epiphyseal_observations || [];

  // Format bone age range
  const rangeLow = Math.floor((est.range_low_months || 0) / 12);
  const rangeLowMo = Math.round((est.range_low_months || 0) % 12);
  const rangeHigh = Math.floor((est.range_high_months || 0) / 12);
  const rangeHighMo = Math.round((est.range_high_months || 0) % 12);
  const bestYr = Math.floor((est.best_estimate_months || 0) / 12);
  const bestMo = Math.round((est.best_estimate_months || 0) % 12);
  const rangeStr = `${rangeLow}y${rangeLowMo > 0 ? rangeLowMo + 'm' : ''} – ${rangeHigh}y${rangeHighMo > 0 ? rangeHighMo + 'm' : ''}`;
  const bestStr = `${bestYr}y ${bestMo}m`;

  // Confidence badge
  const confMap = { high: { cls: 'sig-badge not-significant', label: '✓ High confidence' }, medium: { cls: 'sig-badge no-sd', label: '~ Medium confidence' }, low: { cls: 'sig-badge significant', label: '⚠ Low confidence' } };
  const confBadge = confMap[est.confidence] || confMap.low;

  // Clinical significance badge
  const sigMap = { normal: 'not-significant', borderline: 'no-sd', significant: 'significant' };
  const sigCls = sigMap[stats.clinical_significance] || 'no-sd';
  const sigLabel = stats.clinical_significance === 'normal' ? '✓ Within normal range' : stats.clinical_significance === 'borderline' ? '~ Borderline' : '⚠ Significant delay';

  // Doctor vs AI comparison
  let comparisonHtml = '';
  if (doctorBoneAgeMonths && est.best_estimate_months) {
    const diff = Math.abs(est.best_estimate_months - doctorBoneAgeMonths);
    const diffSign = est.best_estimate_months >= doctorBoneAgeMonths ? '+' : '−';
    const diffCls = diff <= 6 ? 'normal' : diff <= 12 ? '' : 'delayed';
    const docYr = Math.floor(doctorBoneAgeMonths / 12);
    const docMo = Math.round(doctorBoneAgeMonths % 12);
    comparisonHtml = `
      <div class="bone-age-ai-comparison">
        <div class="comparison-title">AI vs Radiologist comparison</div>
        <div class="comparison-row">
          <span class="comparison-lbl">Radiologist (GP)</span>
          <span class="comparison-val">${docYr}y ${docMo}m</span>
        </div>
        <div class="comparison-row">
          <span class="comparison-lbl">AI best estimate</span>
          <span class="comparison-val">${bestStr}</span>
        </div>
        <div class="comparison-row">
          <span class="comparison-lbl">Difference</span>
          <span class="comparison-val bone-age-stat-val ${diffCls}">${diffSign}${diff} months</span>
        </div>
        <div style="font-size:10px; color:var(--text2); margin-top:4px;">
          ${diff <= 6 ? '✓ Within expected inter-rater variability (±6 months at this age)' : diff <= 12 ? '~ Outside typical variability — review carpal count and epiphyseal staging' : '⚠ Large discrepancy — AI may have miscounted carpals or misread JPEG artifacts'}
        </div>
      </div>`;
  }

  // Epiphyseal observations table
  const appearanceLabel = { absent: '—', barely_visible: 'Barely visible', small_clear: 'Small, clear', well_formed: 'Well formed', wide_capping: 'Wide / capping' };
  const appearanceClass = { absent: 'absent', barely_visible: 'barely-visible', small_clear: 'small-clear', well_formed: 'well-formed', wide_capping: 'wide-capping' };
  const obsRows = epiObs.map(o => `
    <tr>
      <td style="color:var(--text2);">${(o.bone_group || '').replace(/_/g, ' ')}</td>
      <td><span class="stage-lbl ${appearanceClass[o.appearance] || ''}">${appearanceLabel[o.appearance] || o.appearance}</span></td>
      <td style="color:var(--text2); font-size:10px;">${o.observation || ''}</td>
    </tr>`).join('');

  const dateLabel = analysisDate ? new Date(analysisDate).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '';

  return `
    <div class="bone-age-ai-result">
      <div class="bone-age-ai-header">
        <div style="font-size:11px; font-weight:700; color:var(--text);">🤖 AI Second Opinion</div>
        <div style="display:flex; align-items:center; gap:6px; flex-wrap:wrap;">
          <span class="sig-badge ${confBadge.cls}">${confBadge.label}</span>
          ${dateLabel ? `<span style="font-size:10px; color:var(--text3);">Run ${dateLabel}</span>` : ''}
        </div>
      </div>

      <!-- Annotated X-ray overlay (if image available) -->
      ${xraySignedUrl ? `
      <div class="xray-annotated-container">
        <img src="${xraySignedUrl}" class="xray-annotated-img" alt="Bone age X-ray with AI annotations">
        ${buildAnnotationOverlaySVG(result)}
        <div class="xray-annotated-label">AI annotation overlay · Regions are approximate anatomical positions</div>
      </div>` : ''}

      <!-- Bone age estimate -->
      <div class="bone-age-delta-strip">
        <div class="bone-age-stat">
          <div class="bone-age-stat-val" style="font-size:14px;">${bestStr}</div>
          <div class="bone-age-stat-lbl">AI best estimate</div>
        </div>
        <div class="bone-age-stat">
          <div class="bone-age-stat-val" style="font-size:12px; color:var(--text2);">${rangeStr}</div>
          <div class="bone-age-stat-lbl">Range (≥6mo uncertainty)</div>
        </div>
        <div class="bone-age-stat">
          <div class="bone-age-stat-val ${sigCls === 'not-significant' ? 'normal' : sigCls === 'significant' ? 'delayed' : ''}" style="font-size:12px;">${stats.sds_score != null ? (stats.sds_score >= 0 ? '+' : '') + stats.sds_score.toFixed(2) : '—'} SDS</div>
          <div class="bone-age-stat-lbl">Bone age SDS</div>
        </div>
      </div>

      <div style="display:flex; gap:6px; flex-wrap:wrap; margin-bottom:10px;">
        <span class="sig-badge ${sigCls}">${sigLabel}</span>
        ${stats.p_value_approx != null ? `<span style="font-size:10px; color:var(--text2);">p ≈ ${stats.p_value_approx.toFixed(3)} · SD ref: ${stats.population_sd_months}mo</span>` : ''}
      </div>

      <!-- Carpal count findings -->
      <div class="bone-age-ai-section-title">Carpal bone count (primary anchor)</div>
      <div class="bone-age-ai-carpal-row">
        <div class="bone-age-stat" style="flex:0 0 auto; min-width:70px;">
          <div class="bone-age-stat-val" style="font-size:20px;">${carpals.count_visible ?? '?'}/8</div>
          <div class="bone-age-stat-lbl">Visible</div>
        </div>
        <div style="flex:1; font-size:10.5px; color:var(--text2); line-height:1.5;">
          <div style="color:var(--text); font-weight:600; margin-bottom:2px;">Identified: ${(carpals.bones_identified || []).join(', ') || '—'}</div>
          <div>${carpals.count_note || ''}</div>
          <div style="margin-top:3px; color:var(--text3);">Confidence: ${carpals.count_confidence || '—'} · Age constraint from count: ${(carpals.age_range_constraint_months || []).join('–')} months</div>
        </div>
      </div>

      <!-- Epiphyseal observations -->
      ${obsRows ? `
      <div class="bone-age-ai-section-title">Epiphyseal appearance (qualitative, GP method)</div>
      <table style="width:100%; border-collapse:collapse; font-size:10px; margin-bottom:10px;">
        <thead><tr style="background:var(--surface2);">
          <th style="padding:4px 6px; text-align:left; color:var(--text2); font-weight:700;">Bone group</th>
          <th style="padding:4px 6px; text-align:left; color:var(--text2); font-weight:700;">Appearance</th>
          <th style="padding:4px 6px; text-align:left; color:var(--text2); font-weight:700;">Observation</th>
        </tr></thead>
        <tbody>${obsRows}</tbody>
      </table>` : ''}

      <!-- GP plate match -->
      ${result.gp_plate_match ? `<div style="font-size:10.5px; color:var(--text2); margin-bottom:10px; padding:8px; background:var(--surface2); border-radius:8px;"><span style="color:var(--text); font-weight:600;">GP plate match: </span>${result.gp_plate_match}</div>` : ''}

      <!-- AI vs Doctor comparison -->
      ${comparisonHtml}

      <!-- Reasoning -->
      ${est.reasoning ? `<div style="font-size:10.5px; color:var(--text2); margin-bottom:8px; line-height:1.5;"><span style="color:var(--text); font-weight:600;">Reasoning: </span>${est.reasoning}</div>` : ''}

      <!-- Image quality note -->
      <div class="bone-age-ai-caveat">${result.image_quality_assessment || ''}</div>

      <!-- DICOM note -->
      <div class="bone-age-ai-dicom-note">
        📡 <strong>DICOM support coming in next phase</strong> — uploading the original .dcm file will provide calibrated mm/pixel measurements, improving carpal boundary detection and epiphysis measurement precision by ~15–20%.
      </div>

      <!-- Disclaimer -->
      <div class="bone-age-ai-disclaimer">${result.clinical_caveat || 'Educational AI reference only. Not a clinical diagnosis.'}</div>
    </div>`;
}

// ══════════════════════════════════════════
// ILLNESS EVENTS (illness_events table) — replaces the old single
// "illness days this month" number that was actually saved per
// log_date despite the monthly label, a real UX mismatch a user
// flagged directly: there's no natural moment a parent thinks "let me
// update my running monthly tally typed into one box on one arbitrary
// day." Illness happens as discrete episodes with a real start and
// end — this captures that shape directly, same event-based pattern as
// lab_results/puberty_events, rather than forcing illness into the
// daily-log shape it doesn't fit. The old medical_logs.illness_days
// column is left untouched in the database (old data isn't lost), just
// no longer written to or read from this screen.
// ══════════════════════════════════════════
const ILLNESS_TYPE_LABELS = {
  fever: 'Fever', cold_respiratory: 'Cold / respiratory', ear_infection: 'Ear infection',
  stomach_gi: 'Stomach / GI', flu: 'Flu', skin_rash: 'Skin / rash', injury: 'Injury',
  hospitalization: 'Hospitalization', other: 'Other',
  // Flutter app's richer taxonomy (illness_reference.json) — the DB CHECK
  // accepts the union of both sets (migrations/2026-07-15_illness_type_
  // check_widen.sql); these labels keep Flutter-logged rows readable here.
  cold: 'Cold / respiratory', rsv: 'RSV', covid: 'COVID-19',
  gastroenteritis: 'Stomach / GI', hfmd: 'Hand, foot & mouth',
  strep: 'Strep throat', asthma_flare: 'Asthma flare', ear: 'Ear infection',
  skin: 'Skin / rash', hospital: 'Hospitalization'
};

async function loadIllnessEvents() {
  const childId = activeChildId();
  const listEl = document.getElementById('illnessEventsList');
  if (!listEl) return;
  if (!childId) { listEl.innerHTML = ''; return; }

  const { data, error } = await sb
    .from('illness_events')
    .select('*')
    .eq('child_id', childId)
    .order('start_date', { ascending: false })
    .limit(20);

  if (error) { listEl.innerHTML = ''; return; }
  APP.illnessEvents = data || [];
  renderIllnessEventsList();
}

function renderIllnessEventsList() {
  const listEl = document.getElementById('illnessEventsList');
  if (!listEl) return;
  const items = APP.illnessEvents || [];
  if (items.length === 0) {
    listEl.innerHTML = '<div class="log-list-empty">No illness episodes logged yet.</div>';
    return;
  }
  listEl.innerHTML = items.map(ev => {
    const label = ILLNESS_TYPE_LABELS[ev.illness_type] || ev.illness_type;
    const startFmt = new Date(ev.start_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
    const dateRange = ev.end_date
      ? `${startFmt} – ${new Date(ev.end_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}`
      : `${startFmt} – ongoing`;
    return `
      <div class="log-item-row">
        <div class="log-item-left">
          <span class="log-item-emoji">🤒</span>
          <div class="log-item-info">
            <span class="log-item-name">${label}</span>
            <span class="log-item-meta">${dateRange}${ev.notes ? ' · ' + ev.notes : ''}</span>
          </div>
        </div>
        <div class="log-item-right">
          <button class="log-item-delete" onclick="deleteIllnessEvent('${ev.event_id}')" aria-label="Remove">×</button>
        </div>
      </div>
    `;
  }).join('');
}

async function addIllnessEvent() {
  const childId = activeChildId();
  if (!childId) { showToast('⚠️', t('toast.error.no_child','Add a child profile first')); return; }

  const startDate = document.getElementById('newIllnessStart').value;
  const endDate = document.getElementById('newIllnessEnd').value;
  const type = document.getElementById('newIllnessType').value;
  const notes = document.getElementById('newIllnessNotes').value.trim();

  if (!startDate) { showToast('⚠️', t('toast.error.enter_start_date','Enter the start date')); return; }
  if (endDate && endDate < startDate) { showToast('⚠️', t('toast.error.end_before_start','End date is before start date')); return; }

  const { data, error } = await sb.from('illness_events').insert({
    child_id: childId,
    start_date: startDate,
    end_date: endDate || null,
    illness_type: type,
    notes: notes || null,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) { showToast('⚠️', t('toast.error.save_failed','Could not save') + ': ' + error.message); return; }

  APP.illnessEvents = APP.illnessEvents || [];
  APP.illnessEvents.unshift(data);
  renderIllnessEventsList();

  document.getElementById('newIllnessStart').value = '';
  document.getElementById('newIllnessEnd').value = '';
  document.getElementById('newIllnessNotes').value = '';
  showToast('✅', t('toast.illness_added','Illness episode added'));
}

async function deleteIllnessEvent(id) {
  if (!confirm(t('confirm.remove_illness','Remove this illness episode? This cannot be undone.'))) return;
  const { error } = await sb.from('illness_events').delete().eq('event_id', id);
  if (error) { showToast('⚠️', t('toast.error.remove_failed','Could not remove') + ': ' + error.message); return; }
  APP.illnessEvents = (APP.illnessEvents || []).filter(ev => ev.event_id !== id);
  renderIllnessEventsList();
}

// ══════════════════════════════════════════
// AI CHAT
// ══════════════════════════════════════════
// ══════════════════════════════════════════
// AI COACH QUESTION LIBRARY (ai_coach_questions table) — ~150
// categorized questions, each tagged with which data it depends on.
// Filtered per-child so a parent only sees questions their child
// actually has the underlying data for (e.g. target-height questions
// only appear once parent heights are on file).
// ══════════════════════════════════════════
// Hand-picked cross-category "leads to" pairs for the follow-up
// suggestions shown after an answer — same-category matching alone
// (suggestFollowUps() below) misses natural sequences that cross
// category lines, e.g. a percentile question naturally leading to a
// target-height comparison question. Every entry validated against
// the real question library at authoring time — see FORMULAS.md.
const CURATED_FOLLOWUPS = {
  'What does my child\'s current height percentile mean?': ['Is my child\'s height velocity normal for their age?', 'Is my child currently tracking toward their target height?'],
  'Is my child\'s height velocity normal for their age?': ['What does my child\'s current height percentile mean?', 'Why did my child\'s percentile shift between visits?'],
  'What does my child\'s BMI percentile mean?': ['Is my child\'s BMI in a healthy range?', 'Can BMI be misleading for an athletic child?'],
  'What does it mean that my child was born SGA?': ['Is my child showing real catch-up growth?', 'How often should an SGA child be measured?'],
  'Is my child showing real catch-up growth?': ['What happens if catch-up growth doesn\'t happen by age 2-4?', 'Should I ask my doctor about growth hormone evaluation?'],
  'How is my child\'s target height calculated?': ['Is my child currently tracking toward their target height?', 'How accurate is this target height estimate really?'],
  'Is my child currently tracking toward their target height?': ['What does my child\'s current height percentile mean?', 'Should I bring the target height estimate to a specialist visit?'],
  'What does this Tanner stage actually mean?': ['Is my child\'s puberty timing typical for their age?', 'How does puberty timing affect how much more height is left to gain?'],
  'Is my child\'s puberty timing typical for their age?': ['How does growth velocity typically change during puberty?', 'Should I be concerned if I haven\'t seen any puberty signs yet?'],
  'What does this IGF-1 result mean for growth?': ['Can one lab result alone tell us much about growth?', 'How do lab trends over time matter more than single results?'],
  'Is my child getting enough protein for growth?': ['What\'s a realistic daily protein target for my child?', 'What happens if my child consistently misses protein targets?'],
  'How does sleep timing affect growth hormone release?': ['What\'s a healthy amount of sleep for my child\'s age?', 'How can I tell if poor sleep is affecting my child\'s growth trend?'],
  'Can corticosteroid use actually slow growth?': ['Does inhaled steroid use carry the same growth risk as oral steroids?', 'What\'s the connection between chronic illness and growth velocity?'],
  'What questions should I bring to the next pediatrician visit?': ['What data from this app is most useful to print or show a doctor?', 'When is it actually time to ask for a specialist referral?'],
  'Should I be worried if my child is in a low percentile?': ['What does it mean if my child crosses two percentile lines?', 'Is my child currently tracking toward their target height?']
};

const AI_CATEGORY_LABELS = {
  growth_trend: 'Growth trend', bmi_weight: 'BMI & weight', nutrition: 'Nutrition',
  sleep: 'Sleep', activity: 'Activity', puberty: 'Puberty', target_height: 'Target height',
  sga_catchup: 'Catch-up growth', labs: 'Labs', medical: 'Medical', clinic_prep: 'Clinic visit prep',
  general_understanding: 'General'
};

// Hardcoded fallback — used only if the table hasn't loaded (migration
// not yet run, or a network hiccup) so the AI coach screen is never
// left completely empty of suggestions.
const AI_FALLBACK_QUESTIONS = [
  { category: 'general_understanding', question_text: "What does today's readiness reading suggest?", requires_data: ['none'] },
  { category: 'clinic_prep', question_text: 'What questions should I bring to the next pediatrician visit?', requires_data: ['none'] },
  { category: 'sleep', question_text: 'How does sleep timing affect growth hormone release?', requires_data: ['none'] },
  { category: 'growth_trend', question_text: 'Explain the height velocity number on Analytics', requires_data: ['measurements_2plus'] }
];

async function loadAICoachQuestions() {
  try {
    const { data, error } = await sb.from('ai_coach_questions').select('*').eq('is_active', true).order('display_priority');
    APP.aiCoachQuestions = (!error && data && data.length > 0) ? data : AI_FALLBACK_QUESTIONS;
  } catch (e) {
    APP.aiCoachQuestions = AI_FALLBACK_QUESTIONS;
  }
  renderAICategoryChips();
}

// Determines which requires_data tags are actually satisfied for the
// active child right now — reuses the same context object the AI
// prompt itself is built from, so "is this question answerable" and
// "what does the AI actually know" never disagree with each other.
function getAvailableDataTags() {
  const ctx = buildAICoachContext();
  const tags = new Set(['none']);
  if (ctx.latestHeightCm != null) tags.add('measurements_1plus');
  if (ctx.heightVelocityCmYr != null) tags.add('measurements_2plus');
  if (ctx.bmi != null) tags.add('bmi');
  if (ctx.targetHeightCm != null) tags.add('target_height');
  if (ctx.isSGA) tags.add('sga_status');
  if (ctx.recentLabs) tags.add('labs');
  if (ctx.recentPubertyEvents) tags.add('puberty_events');
  if ((APP.familyHeightRecords || []).length > 0) tags.add('family_height_records');
  return tags;
}

function questionIsAnswerable(q, availableTags, ageYears) {
  const tagsOk = (q.requires_data || ['none']).every(t => availableTags.has(t));
  if (!tagsOk) return false;
  if (q.min_age_years != null && ageYears != null && ageYears < q.min_age_years) return false;
  if (q.max_age_years != null && ageYears != null && ageYears > q.max_age_years) return false;
  return true;
}

function renderAICategoryChips() {
  const chipsEl = document.getElementById('aiCategoryChips');
  if (!chipsEl) return;
  const child = APP.children[APP.activeChild];
  const ageYears = child ? (new Date() - new Date(child.date_of_birth)) / (365.25*86400000) : null;
  const availableTags = getAvailableDataTags();

  // Only show category chips that have at least one currently-answerable
  // question — no point showing a "Labs" chip if this child has zero
  // lab results logged and every lab question requires that data.
  const answerableQuestions = (APP.aiCoachQuestions || []).filter(q => questionIsAnswerable(q, availableTags, ageYears));
  const categoriesPresent = [...new Set(answerableQuestions.map(q => q.category))];

  chipsEl.innerHTML = ['all', ...categoriesPresent].map(cat => {
    const label = cat === 'all' ? 'All' : (AI_CATEGORY_LABELS[cat] || cat);
    return `<button class="ai-chip ${cat === 'all' ? 'active' : ''}" data-cat="${cat}" onclick="filterAIQuestionsByCategory('${cat}', this)">${label}</button>`;
  }).join('');

  renderAIQuestionList('all');
}

function filterAIQuestionsByCategory(category, btn) {
  document.querySelectorAll('#aiCategoryChips .ai-chip').forEach(c => c.classList.remove('active'));
  btn.classList.add('active');
  renderAIQuestionList(category);
}

// Picks 2-3 follow-up questions to show after an answered question —
// curated cross-category chains first (see CURATED_FOLLOWUPS above),
// filled out with same-category questions if needed. Only suggests
// questions that are actually answerable right now for the active
// child (same data-availability check used for the main question
// list), so a follow-up button never leads to a dead end.
function suggestFollowUps(answeredQuestion) {
  const child = APP.children[APP.activeChild];
  const ageYears = child ? (new Date() - new Date(child.date_of_birth)) / (365.25*86400000) : null;
  const availableTags = getAvailableDataTags();
  const allQuestions = APP.aiCoachQuestions || [];

  const isAnswerable = q => questionIsAnswerable(q, availableTags, ageYears) && q.question_text !== answeredQuestion.question_text;

  const suggestions = [];
  const seen = new Set();

  // Curated chain first
  const curated = CURATED_FOLLOWUPS[answeredQuestion.question_text] || [];
  for (const text of curated) {
    const q = allQuestions.find(x => x.question_text === text);
    if (q && isAnswerable(q) && !seen.has(q.question_text)) {
      suggestions.push(q);
      seen.add(q.question_text);
    }
  }

  // Fill out with same-category questions, ordered by the library's
  // own display_priority, until we have up to 3 total suggestions.
  if (suggestions.length < 3) {
    const sameCategory = allQuestions
      .filter(q => q.category === answeredQuestion.category && isAnswerable(q) && !seen.has(q.question_text))
      .sort((a, b) => (a.display_priority || 50) - (b.display_priority || 50));
    for (const q of sameCategory) {
      if (suggestions.length >= 3) break;
      suggestions.push(q);
      seen.add(q.question_text);
    }
  }

  return suggestions.slice(0, 3);
}

// Renders the follow-up suggestion buttons under a just-answered
// message — visually distinct from the main quick-prompts list
// (smaller, inline with the chat) since these are contextual to the
// specific answer just given, not the general browse list.
function renderFollowUpSuggestions(answeredQuestion) {
  const suggestions = suggestFollowUps(answeredQuestion);
  if (suggestions.length === 0) return;

  const chat = document.getElementById('aiChat');
  const wrap = document.createElement('div');
  wrap.className = 'ai-followup-suggestions';
  wrap.innerHTML = '<div class="ai-followup-label">You might also ask:</div>' +
    suggestions.map(q => `<button class="quick-btn ai-followup-btn" onclick="sendQuick(this)">${q.question_text}</button>`).join('');
  chat.appendChild(wrap);
  chat.scrollTop = chat.scrollHeight;
}

function renderAIQuestionList(category) {
  const listEl = document.getElementById('quickPrompts');
  if (!listEl) return;
  const child = APP.children[APP.activeChild];
  const ageYears = child ? (new Date() - new Date(child.date_of_birth)) / (365.25*86400000) : null;
  const availableTags = getAvailableDataTags();

  let questions = (APP.aiCoachQuestions || []).filter(q => questionIsAnswerable(q, availableTags, ageYears));
  if (category !== 'all') questions = questions.filter(q => q.category === category);

  // Cap the visible list — a parent scanning a chat screen isn't going
  // to scroll through dozens of buttons; the category filter is there
  // for when they want more than this default slice.
  const MAX_SHOWN = 8;
  const shown = questions.slice(0, MAX_SHOWN);

  if (shown.length === 0) {
    listEl.innerHTML = '<div class="log-list-empty">No suggested questions for this category yet — try asking directly below.</div>';
    return;
  }
  listEl.innerHTML = shown.map(q =>
    `<button class="quick-btn" onclick="sendQuick(this)">${q.question_text}</button>`
  ).join('');
}

function sendQuick(btn) {
  const msg = btn.textContent.trim();
  document.getElementById('quickPrompts').style.display = 'none';
  addUserMsg(msg);
  // The button's text IS an exact library question_text, so pass it
  // through as an exact-match hint — no fuzzy matching needed for this path.
  routeAICoachMessage(msg, msg);
}

function sendAI() {
  const inp = document.getElementById('aiInput');
  const msg = inp.value.trim();
  if (!msg) return;
  if (!requireAIQuota()) return; // free tier monthly cap check
  inp.value = '';
  document.getElementById('quickPrompts').style.display = 'none';
  addUserMsg(msg);
  routeAICoachMessage(msg, null);
}

// ══════════════════════════════════════════
// AI COACH MODE ROUTING — option 1 (template matching, no Anthropic
// API call, zero cost) vs option 2 (live AI via the Edge Function
// proxy, real cost). The active mode is a single admin-controlled
// project-wide setting (system_settings.ai_coach_mode), not a per-user
// choice — see migration_ai_coach_mode_toggle.sql.
// ══════════════════════════════════════════
async function getAICoachMode() {
  // Cached after first load per session — this setting rarely changes
  // mid-session, and re-querying on every single message would be
  // wasteful. An admin toggling it takes effect on next page load.
  if (APP.aiCoachMode) return APP.aiCoachMode;
  try {
    const { data, error } = await sb.from('system_settings').select('setting_value').eq('setting_key', 'ai_coach_mode').maybeSingle();
    APP.aiCoachMode = (!error && data) ? data.setting_value : 'template';
  } catch (e) {
    APP.aiCoachMode = 'template'; // fail safe to the zero-cost mode, not the one that spends money, if this lookup itself fails
  }
  return APP.aiCoachMode;
}

// Fills {{placeholder}} tokens in an answer template using the same
// context object the live-AI system prompt is built from — one
// template author writes one sentence, it's correct for every child.
function fillAnswerTemplate(template, ctx) {
  return template.replace(/\{\{(\w+)\}\}/g, (match, field) => {
    const value = ctx[field];
    if (value == null) return '(not yet logged)';
    if (Array.isArray(value)) return value.join('; ');
    return String(value);
  });
}

// Finds the best-matching library question for free text input. Real
// semantic matching would need an embeddings model (itself an API
// call with its own cost) — this is intentionally simpler: normalized
// word-overlap scoring, which is a real, well-understood text-
// similarity technique (not "AI", just string analysis), good enough
// to catch close rephrasings of an existing question without any API
// cost. Returns null if nothing clears a minimum similarity bar, so a
// genuinely novel question doesn't get a wrong, confidently-wrong match.
function findBestMatchingQuestion(userText, exactHint) {
  const questions = APP.aiCoachQuestions || [];
  if (exactHint) {
    const exact = questions.find(q => q.question_text === exactHint);
    if (exact) return exact;
  }

  // Common words excluded from matching — without this, generic shared
  // words like "what"/"the"/"does"/"my" inflate the overlap score for
  // ANY two questions, causing false-positive matches on completely
  // unrelated input (caught directly: "what is the capital of France"
  // was matching a BMI question purely on shared "what"/"the").
  const STOPWORDS = new Set(['what','does','the','for','and','this','that','with','from','about',
    'how','why','when','where','who','which','can','could','should','would','will','are','is','was',
    'were','has','have','had','not','but','they','their','them','you','your','our','out','into','than',
    'then','there','here','his','her','its','also','just','more','most','some','any','all','each']);

  const normalize = s => s.toLowerCase().replace(/[^\w\s]/g, '').split(/\s+/)
    .filter(w => w.length > 2 && !STOPWORDS.has(w));
  const userWords = new Set(normalize(userText));
  if (userWords.size === 0) return null;

  let best = null, bestScore = 0;
  for (const q of questions) {
    const qWords = new Set(normalize(q.question_text)); // de-duplicated, so a repeated word in the question text can't inflate its own match score
    if (qWords.size === 0) continue;
    const overlap = [...qWords].filter(w => userWords.has(w)).length;
    const score = overlap / Math.min(userWords.size, qWords.size);
    if (score > bestScore) { bestScore = score; best = q; }
  }

  const MIN_MATCH_SCORE = 0.5; // requires genuine, substantial word overlap, not a stray shared word
  return bestScore >= MIN_MATCH_SCORE ? best : null;
}

async function routeAICoachMessage(userText, exactHint) {
  const mode = await getAICoachMode();

  if (mode === 'live_ai') {
    askClaude(userText); // unchanged path — real Anthropic call via the Edge Function proxy
    return;
  }

  // Template mode (default) — try to match and answer with zero API cost.
  showThinking();
  const matched = findBestMatchingQuestion(userText, exactHint);

  if (matched && matched.answer_template) {
    const ctx = buildAICoachContext();
    const filled = fillAnswerTemplate(matched.answer_template, ctx);
    hideThinking();
    // Citation shown as a distinct, smaller line below the answer —
    // only for questions that actually have a verified source attached
    // (citation_source column, added specifically because an earlier
    // supplied batch of 600 "citations" turned out to be fabricated on
    // verification; every citation that DOES appear here was
    // independently checked, see FORMULAS.md).
    const citationHtml = matched.citation_source
      ? `<div class="ai-citation">Source: ${matched.citation_source}</div>`
      : '';
    addBotMsg(filled.replace(/\n/g, '<br>') + citationHtml);
    renderFollowUpSuggestions(matched);
    return;
  }

  // No good match, or a matched question has no template written yet —
  // be honest about the limitation rather than fabricate an answer
  // from nothing, since this mode by design has no language model to
  // fall back on.
  hideThinking();
  if (matched && !matched.answer_template) {
    addBotMsg(`I recognize that question, but don't have a ready answer template for it yet in this mode. Try browsing the category list above for a related question, or ask your pediatrician directly.`);
  } else {
    addBotMsg(`I couldn't match that to one of my prepared answers. Try rephrasing, browse the category buttons above for a similar question, or ask your pediatrician directly. (This app is currently in template-answer mode — no live AI model is being used for this response.)`);
  }
}

// Clears AI conversation history and resets the visible chat back to
// the welcome message when switching children — a conversation about
// one child's growth data should never silently carry over as context
// for a different child. Also re-filters the question library, since
// which questions are answerable depends on the active child's data.
// User-triggered "Clear conversation" button — same effect as switching
// children (clears history, resets the visible chat), but explicitly
// invoked without an actual child switch, for a parent who wants to
// start a fresh topic without carrying over an unrelated earlier thread.
function clearAIConversation() {
  resetAIChatForChildSwitch();
}

function resetAIChatForChildSwitch() {
  APP.aiChatHistory = [];
  const chat = document.getElementById('aiChat');
  if (chat) {
    chat.innerHTML = `<div class="ai-msg bot">I can answer questions using this child's logged nutrition, sleep, activity, and clinical data. I'm not a doctor — for diagnosis or treatment decisions, bring the trend data on the Analytics tab to your pediatrician.<br><br>What would you like to know?</div>`;
  }
  if (APP.aiCoachQuestions) renderAICategoryChips();
}

function addUserMsg(text) {
  const chat = document.getElementById('aiChat');
  const d = document.createElement('div');
  d.className = 'ai-msg user';
  d.textContent = text;
  chat.appendChild(d);
  chat.scrollTop = chat.scrollHeight;
}

function addBotMsg(text) {
  const chat = document.getElementById('aiChat');
  const d = document.createElement('div');
  d.className = 'ai-msg bot';
  d.innerHTML = text;
  chat.appendChild(d);
  chat.scrollTop = chat.scrollHeight;
}

function showThinking() {
  const chat = document.getElementById('aiChat');
  const t = document.createElement('div');
  t.className = 'ai-thinking'; t.id = 'aiThinking';
  t.innerHTML = '<div class="ai-dot"></div><div class="ai-dot"></div><div class="ai-dot"></div>';
  chat.appendChild(t);
  chat.scrollTop = chat.scrollHeight;
}

function hideThinking() {
  const t = document.getElementById('aiThinking');
  if (t) t.remove();
}

// Builds the full data context for the AI coach — recomputes
// percentile/BMI/target-height results fresh from the same underlying
// functions the rest of the app uses, rather than reading DOM text
// (which can be stale, hidden, or not yet rendered). This was added
// because the AI coach previously only saw today's daily log (protein/
// sleep/activity) and had no access to growth percentile, BMI status,
// target height, lab results, puberty milestones, or SGA status — most
// of what a parent would naturally ask about.
function buildAICoachContext() {
  const child = APP.children[APP.activeChild];
  if (!child) return { hasChild: false };

  const ageYears = (new Date() - new Date(child.date_of_birth)) / (365.25 * 86400000);
  const measurements = APP.activeChildMeasurements || [];
  const latest = measurements[0]; // newest-first, per refreshActiveChildHistory()
  const ctx = { hasChild: true, name: child.name, ageYears: ageYears.toFixed(1), sex: child.biological_sex };

  // Height/BMI percentile — recomputed fresh, same functions the charts use.
  if (latest) {
    const use0to5 = ageYears < 5 && typeof calculateHeightPercentile0to5 === 'function';
    let heightResult = null;
    if (use0to5) {
      const ageMonths = ageYears * 12;
      const { value } = GrowthPercentile0to5Math.resolveHeightTableAndValue(
        Number(latest.stature_height_cm), ageMonths, child.biological_sex, ageMonths < 24 ? 'recumbent' : 'standing'
      );
      heightResult = calculateHeightPercentile0to5(value, ageMonths, child.biological_sex);
    } else if (typeof calculateHeightPercentile === 'function') {
      heightResult = calculateHeightPercentile(Number(latest.stature_height_cm), ageYears, child.biological_sex);
    }
    if (heightResult && !heightResult.outOfRange) {
      ctx.heightPercentile = Math.round(heightResult.percentile);
      ctx.heightZ = heightResult.zScore.toFixed(2);
    }

    if (latest.calculated_bmi != null) {
      const bmiResult = use0to5
        ? calculateBMIPercentile0to5(Number(latest.calculated_bmi), ageYears * 12, child.biological_sex)
        : (typeof calculateBMIPercentile === 'function' ? calculateBMIPercentile(Number(latest.calculated_bmi), ageYears, child.biological_sex) : null);
      if (bmiResult && !bmiResult.outOfRange) {
        ctx.bmi = Number(latest.calculated_bmi).toFixed(1);
        ctx.bmiPercentile = Math.round(bmiResult.percentile);
        ctx.bmiClassification = bmiResult.classification;
      }
    }
    ctx.latestHeightCm = latest.stature_height_cm;
    ctx.latestWeightKg = latest.mass_weight_kg;
    ctx.latestMeasurementDate = latest.recorded_date;
  }

  // Per-child protein targets for answer templates — computed from
  // this child's age, sex and latest weight, never a fixed figure
  // (the old hardcoded 44g was only right for a ~46kg 9-13yo).
  ctx.proteinTargetG = calcProteinTargetG(
    child.date_of_birth,
    latest ? Number(latest.mass_weight_kg) || null : null,
    child.biological_sex
  );
  ctx.proteinBoostTargetG = calcProteinBoostTargetG(
    child.date_of_birth,
    latest ? Number(latest.mass_weight_kg) || null : null,
    child.biological_sex
  );
  ctx.calciumTargetMg = calcCalciumTargetMg(child.date_of_birth);
  ctx.waterTargetGlasses = calcWaterTargetGlasses(child.date_of_birth, child.biological_sex);
  ctx.zincTargetMg = calcZincTargetMg(child.date_of_birth, child.biological_sex);
  ctx.sleepTargetH = (calcSleepTargetMin(child.date_of_birth) / 60).toFixed(1);

  // Height velocity, if 2+ measurements exist.
  if (measurements.length >= 2) {
    const prev = measurements[1];
    const days = (new Date(latest.recorded_date) - new Date(prev.recorded_date)) / 86400000;
    if (days > 0) {
      ctx.heightVelocityCmYr = (((Number(latest.stature_height_cm) - Number(prev.stature_height_cm)) / days) * 365.25).toFixed(1);
    }
  }

  // Target height, if both parents' heights are on file.
  if (child.mother_height_cm != null && child.father_height_cm != null && typeof calculateTargetHeight === 'function') {
    const th = calculateTargetHeight({
      motherHeightCm: child.mother_height_cm, fatherHeightCm: child.father_height_cm,
      motherAge: child.mother_current_age, fatherAge: child.father_current_age,
      childSex: child.biological_sex
    });
    if (th) {
      ctx.targetHeightCm = th.targetHeightCm;
      ctx.targetHeightRangeLow = th.rangeLowCm;
      ctx.targetHeightRangeHigh = th.rangeHighCm;
    }
  }

  // SGA status + catch-up velocity, if flagged and under 5.
  if (child.is_sga && ageYears < 5 && measurements.length >= 2 && typeof calculateHeightPercentile0to5 === 'function') {
    const lastAgeMonths = (new Date(latest.recorded_date) - new Date(child.date_of_birth)) / (30.4375*86400000);
    const prevAgeMonths = (new Date(measurements[1].recorded_date) - new Date(child.date_of_birth)) / (30.4375*86400000);
    const yearsBetween = (lastAgeMonths - prevAgeMonths) / 12;
    if (yearsBetween > 0) {
      const lastR = calculateHeightPercentile0to5(Number(latest.stature_height_cm), lastAgeMonths, child.biological_sex);
      const prevR = calculateHeightPercentile0to5(Number(measurements[1].stature_height_cm), prevAgeMonths, child.biological_sex);
      if (lastR && prevR && !lastR.outOfRange && !prevR.outOfRange) {
        ctx.isSGA = true;
        ctx.sgaCatchupSDSPerYear = ((lastR.zScore - prevR.zScore) / yearsBetween).toFixed(2);
      }
    }
  }

  // Recent lab results (most recent 5, name + value + unit only — keep token cost bounded).
  if ((APP.labResults || []).length > 0) {
    ctx.recentLabs = APP.labResults.slice(0, 5).map(r => `${r.analyte_name}: ${r.result_value}${r.unit} (${r.lab_date})`);
  }

  // Puberty milestones (most recent 5).
  if ((APP.pubertyEvents || []).length > 0) {
    ctx.recentPubertyEvents = APP.pubertyEvents.slice(0, 5).map(ev => {
      const label = PUBERTY_TYPE_LABELS[ev.event_type] || ev.event_type;
      const stage = ev.tanner_stage ? ` (Tanner ${TANNER_NUMERALS[ev.tanner_stage]})` : '';
      return `${label}${stage} on ${ev.event_date}`;
    });
  }

  return ctx;
}

// ── Live AI monthly cap enforcement (client-side UX layer) ──────────
// Reads this account's tier limit, then upserts the monthly usage row
// atomically. Returns true if the cap has been reached (and shows the
// user a clear message), false if the call should proceed.
//
// The year_month key is 'YYYY-MM' in the user's local time (not UTC)
// — this avoids the confusing situation where a user makes a call just
// before midnight UTC and it's counted in the "wrong" month from their
// perspective. The Edge Function uses the same local-month convention.
async function checkAndIncrementLiveAIUsage() {
  const tier = (APP.account && APP.account.subscription_tier) || 'free';
  const userId = APP.session ? APP.session.user.id : null;
  if (!userId) return true; // shouldn't happen, but block rather than crash

  // Get the cap for this tier
  const limitRes = await sb.from('subscription_tier_limits')
    .select('live_ai_monthly_cap')
    .eq('tier', tier)
    .maybeSingle();

  if (limitRes.error || !limitRes.data) return false; // if limit lookup fails, let the call through rather than silently block
  const cap = limitRes.data.live_ai_monthly_cap;
  if (cap === null) return false; // NULL = unlimited (Pro future tier)
  if (cap === 0) {
    addBotMsg('Live AI is not available on the Free plan. You\'re getting answers from the template library — upgrade to Premium or Pro for live AI responses.');
    return true;
  }

  // Build the year-month key in local time
  const now = new Date();
  const yearMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

  // Read current count first
  const usageRes = await sb.from('live_ai_usage_monthly')
    .select('call_count')
    .eq('user_id', userId)
    .eq('year_month', yearMonth)
    .maybeSingle();

  const currentCount = (!usageRes.error && usageRes.data) ? usageRes.data.call_count : 0;

  if (currentCount >= cap) {
    addBotMsg(`You've used all ${cap} live AI responses for this month (${tier} plan). Your limit resets on the 1st of next month. Template-mode answers are still available — or upgrade to Pro for a higher cap.`);
    return true;
  }

  // Increment — upsert so the row is created on first use
  await sb.from('live_ai_usage_monthly').upsert({
    user_id: userId,
    year_month: yearMonth,
    call_count: currentCount + 1
  }, { onConflict: 'user_id,year_month' });

  return false; // cap not exceeded, proceed with the call
}

async function askClaude(userMsg) {
  // ── Tier enforcement: live AI monthly cap ─────────────────────────
  // Checked and incremented here (client side) rather than only in the
  // Edge Function, so the user gets a clear, friendly message before
  // wasting a round trip to the server. The Edge Function enforces the
  // same cap server-side as a real hard gate — this is the UX layer.
  const capExceeded = await checkAndIncrementLiveAIUsage();
  if (capExceeded) return; // message already shown inside the function
  // ─────────────────────────────────────────────────────────────────

  showThinking();
  const ctx = buildAICoachContext();
  const grs = document.getElementById('grsScore').textContent;
  const s = currentState();
  const totalSleep = document.getElementById('totalSleepLbl').textContent;

  // Build the growth-data section conditionally — only include lines for
  // data that actually exists, rather than printing "undefined" or empty
  // fields for whatever this child doesn't have on file yet.
  const growthLines = [];
  if (ctx.hasChild) {
    growthLines.push(`- Name: ${ctx.name} | Age: ${ctx.ageYears} years | Sex: ${ctx.sex}`);
    if (ctx.latestHeightCm != null) growthLines.push(`- Latest measurement (${ctx.latestMeasurementDate}): Height ${ctx.latestHeightCm}cm, Weight ${ctx.latestWeightKg}kg`);
    if (ctx.heightPercentile != null) growthLines.push(`- Height-for-age: ${ctx.heightPercentile}th percentile (Z=${ctx.heightZ}), WHO reference`);
    if (ctx.bmi != null) growthLines.push(`- BMI: ${ctx.bmi} kg/m², ${ctx.bmiPercentile}th percentile, classification: ${ctx.bmiClassification.replace('_',' ')}`);
    if (ctx.heightVelocityCmYr != null) growthLines.push(`- Height velocity (from last 2 measurements): ${ctx.heightVelocityCmYr} cm/year`);
    if (ctx.targetHeightCm != null) growthLines.push(`- Target adult height estimate (mid-parental, Zeevi et al. 2024 method): ${ctx.targetHeightCm}cm (range ${ctx.targetHeightRangeLow}–${ctx.targetHeightRangeHigh}cm)`);
    if (ctx.isSGA) growthLines.push(`- Born SGA (small for gestational age). Current catch-up growth velocity: ${ctx.sgaCatchupSDSPerYear} SDS/year (>0 SDS/year = catching up; this is the real clinical definition, not raw cm/year)`);
    if (ctx.recentLabs) growthLines.push(`- Recent lab results: ${ctx.recentLabs.join('; ')}`);
    if (ctx.recentPubertyEvents) growthLines.push(`- Recent puberty milestones: ${ctx.recentPubertyEvents.join('; ')}`);

    // 7-day trend summaries — pulled from in-memory history arrays loaded
    // when the Analytics tab is open. If arrays are empty the lines are
    // omitted rather than showing misleading zeros.
    const nut7 = filterByPeriod(APP.nutritionHistory || [], 'W');
    if (nut7.length >= 3) {
      const { standard: ps, boost: pb } = activeChildProteinTargets();
      const avgProt = Math.round(nut7.reduce((a,r) => a+(r.total_protein_g||0),0) / nut7.length);
      const avgCalc = Math.round(nut7.reduce((a,r) => a+(r.calcium_mg||0),0) / nut7.length);
      const protDays = nut7.filter(r=>(r.total_protein_g||0)>=pb).length;
      const calcDays = nut7.filter(r=>(r.calcium_mg||0)>=activeChildNutritionTargets().calciumMg).length;
      growthLines.push(`- 7-day nutrition trend: protein avg ${avgProt}g/day (standard RDA ${ps}g, growth target ${pb}g, target met ${protDays}/${nut7.length} days); calcium avg ${avgCalc}mg/day (goal ${activeChildNutritionTargets().calciumMg}mg, met ${calcDays}/${nut7.length} days)`);
    }
    const slp7 = filterByPeriod(APP.sleepHistory || [], 'W');
    if (slp7.length >= 3) {
      const avgMin = Math.round(slp7.reduce((a,r) => a+(r.total_sleep_min||0),0) / slp7.length);
      const goalMet = slp7.filter(r=>(r.total_sleep_min||0)>=activeChildNutritionTargets().sleepMin).length;
      growthLines.push(`- 7-day sleep trend: avg ${Math.floor(avgMin/60)}h ${avgMin%60}m/night, ${(activeChildNutritionTargets().sleepMin/60).toFixed(1)}h goal met ${goalMet}/${slp7.length} nights`);
    }
    const act7 = filterByPeriod(APP.activityHistory || [], 'W');
    if (act7.length >= 3) {
      const activeDays = act7.filter(r=>(r.box_jumps_reps||0)+(r.hanging_decompression_sec||0)+(r.stretching_yoga_duration_min||0)>0).length;
      const avgJumps = Math.round(act7.reduce((a,r)=>a+(r.box_jumps_reps||0),0)/act7.length);
      const avgHang  = Math.round(act7.reduce((a,r)=>a+(r.hanging_decompression_sec||0),0)/act7.length);
      growthLines.push(`- 7-day activity trend: active ${activeDays}/${act7.length} days, avg ${avgJumps} box jumps/day, avg ${avgHang}s bar hanging/day`);
    }
  } else {
    growthLines.push('- No child profile is currently selected.');
  }

  const systemPrompt = `You are the GrowSense AI coach, built for a parent who tracks their child's growth data and consults with a pediatrician/endocrinologist. You are not a doctor and must not diagnose, prescribe, or contradict clinical guidance — your role is to help the parent understand their own logged data and prepare better questions for clinical visits.

Growth & clinical profile:
${growthLines.join('\n')}

Today's readiness reading: ${grs}/100 (a same-day input score, not a diagnostic measure — single days carry little signal on their own)

Today's logged inputs:
- Protein: ${s.protein}g | Standard (WHO/DRI): ~${activeChildProteinTargets().standard}g · Growth-optimized: ~${activeChildProteinTargets().boost}g (1.2 g/kg, IAAO-method evidence: Hudson et al. Nutrients 2021) | Calcium: ${s.calcium}mg (target ~${activeChildNutritionTargets().calciumMg}mg) | Water: ${s.water}/${activeChildNutritionTargets().waterGlasses} glasses
- Bar hanging: ${s.hanging}s | Box jumps: ${s.jumps} reps | Yoga/stretching: ${s.yogaMin} min
- Bedtime: ${s.bed} | Wake: ${s.wake} | Total sleep: ${totalSleep} | Night wake-ups: ${s.nightWakes}
- Corticosteroid use level: ${s.steroid} (0=none, 1=inhaled, 2=oral)

Guidelines:
- Ground every answer in the data above; don't invent numbers not given. If the parent asks about something with no data on file (e.g. target height with no parent heights entered, or labs with none logged), say so plainly and point them to where in the app they'd add it — don't guess or estimate on their behalf.
- Never state a diagnosis or tell the parent to change medication/treatment — defer those explicitly to their pediatrician.
- Growth is judged by velocity and trend over weeks/months, not single days — say so if the parent seems to be over-reading one day's numbers.
- If a percentile or Z-score number is shared, briefly note that population percentiles describe where a child sits relative to a reference group, not a target to hit — extreme percentiles (very high or very low) deserve a doctor's interpretation, not concern from the number alone.
- The "exploratory" extended-family target-height variant (if the parent mentions it) is explicitly unvalidated — don't present it with the same confidence as the parents-only target height.
- Keep responses concise (3–5 sentences unless asked for detail). Plain language, minimal jargon.`;

  try {
    // Send real conversation history, not just the current message —
    // previously every call sent only userMsg with no prior turns,
    // meaning a follow-up like "what about compared to last month?"
    // had nothing to refer back to. Capped to the last 10 exchanges
    // (20 messages) to keep token cost and latency bounded — a coaching
    // chat doesn't need unlimited history, and the system prompt already
    // re-supplies the current data snapshot fresh on every call anyway.
    const MAX_HISTORY_MESSAGES = 20;
    const historyToSend = APP.aiChatHistory.slice(-MAX_HISTORY_MESSAGES);
    const messages = [...historyToSend, { role: 'user', content: userMsg }];

    // Calls the ai-coach-proxy Edge Function, NOT api.anthropic.com
    // directly — a static site has nowhere safe to hold a real
    // Anthropic API key client-side, and Anthropic's API isn't meant
    // to be called directly from a browser on another origin anyway
    // (blocked by CORS for that exact reason). The Edge Function holds
    // the real key as a server-side secret; the browser only ever
    // talks to Supabase, never to Anthropic. See
    // supabase_setup/edge_functions/ai-coach-proxy/index.ts.
    const res = await fetch(`${SUPABASE_URL}/functions/v1/ai-coach-proxy`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // Send the real session JWT, not the publishable/anon key —
        // the Edge Function uses this to verify the caller's identity
        // and look up their monthly cap. Without a real session token,
        // the function can't know who's calling, so server-side cap
        // enforcement would be impossible.
        'Authorization': `Bearer ${APP.session ? APP.session.access_token : ''}`
      },
      body: JSON.stringify({
        max_tokens: 1000,
        system: systemPrompt,
        messages: messages
      })
    });
    const data = await res.json();
    hideThinking();

    if (data.error) {
      console.error('[AI coach] Proxy error:', data.error);
      // Different error codes from the Edge Function get different
      // user-facing messages — the server's message is already
      // written for a parent to read, so we can surface it directly.
      const code = data.error.code;
      if (code === 'LIVE_AI_NOT_IN_PLAN') {
        addBotMsg('Live AI isn\'t included in your current plan. Template mode is still available above — or upgrade to Premium or Pro to unlock live responses.');
      } else if (code === 'MONTHLY_CAP_EXCEEDED') {
        addBotMsg(`You've reached your monthly live AI limit (${data.error.cap} calls on your plan). It resets on the 1st of next month. Template mode is still available.`);
      } else if (res.status === 401) {
        addBotMsg('Your session has expired — please sign out and sign back in, then try again.');
      } else {
        addBotMsg('⚠️ The AI service returned an error. Please try again in a moment.');
      }
      return;
    }

    const txt = data.content && data.content[0] ? data.content[0].text : null;
    if (!txt) {
      console.error('[AI coach] Unexpected API response shape:', data);
      addBotMsg('Sorry, I had trouble responding. Please try again.');
      return;
    }

    addBotMsg(txt.replace(/\n/g, '<br>'));

    // Record this exchange for future turns in the same conversation.
    APP.aiChatHistory.push({ role: 'user', content: userMsg });
    APP.aiChatHistory.push({ role: 'assistant', content: txt });
  } catch (e) {
    hideThinking();
    addBotMsg('⚠️ Unable to connect to AI. Check your internet connection and try again.');
  }
}

function setSyncStatus(state, label) {
  const dot = document.getElementById('syncDot');
  dot.className = 'sync-dot ' + state;
  document.getElementById('syncTxt').textContent = label;
}

// ══════════════════════════════════════════
// NAVIGATION
// ══════════════════════════════════════════
const TABS = { Today:'screenToday', Analytics:'screenAnalytics', Medical:'screenMedical', AI:'screenAI' };

async function goTab(name) {
  Object.values(TABS).forEach(id => document.getElementById(id).classList.remove('active'));
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));

  document.getElementById(TABS[name]).classList.add('active');
  document.getElementById('tab'+name).classList.add('active');
  document.getElementById('scrollArea').scrollTop = 0;

  if (name === 'Analytics') {
    await updateStats();
    drawGrowthChart();
    drawBMIChart();
    await loadLabResults();
    drawLabChart();
    await loadFamilyHeightRecords();
    loadTargetHeightForm();
    await loadAnalyticsTrends(); // insight cards + detail sheet data
  }
  if (name === 'Today') {
    await loadGoogleHealthConnections(); // refresh Fitbit sync button
    await loadActivitySectionForToday(); // cards, favourites, logged items
  }
  if (name === 'Medical') {
    await loadMedicalLogForDate();
    await loadLabResults();
    await loadPubertyEvents();
    await loadIllnessEvents();
    await loadBoneAgeAssessments();
    await loadLabValuesHistory(); // populate IGF-1 history rows
  }
  if (name === 'AI') {
    if (!APP.aiCoachQuestions) {
      await loadAICoachQuestions();
    } else {
      renderAICategoryChips();
    }
  }
}

// ══════════════════════════════════════════
// SETUP MODAL
// ══════════════════════════════════════════
function openSetup() {
  renderChildList();
  populateShareChildSelect();
  if (isClinicianRole()) renderAssignedChildrenList();
  document.getElementById('setupModal').classList.remove('hidden');
}

function closeSetup() {
  document.getElementById('setupModal').classList.add('hidden');
}

document.getElementById('setupModal').addEventListener('click', function(e) {
  if (e.target === this) closeSetup();
});

// ══════════════════════════════════════════
// TOAST
// ══════════════════════════════════════════
let toastTimer;
function showToast(icon, msg) {
  clearTimeout(toastTimer);
  document.getElementById('toastIcon').textContent = icon;
  document.getElementById('toastMsg').textContent = msg;
  const t = document.getElementById('toast');
  t.classList.add('show');
  toastTimer = setTimeout(() => t.classList.remove('show'), 3000);
}

// Resize chart on orientation change
window.addEventListener('resize', () => {
  const sc = document.getElementById('screenAnalytics');
  if (sc.classList.contains('active')) { drawGrowthChart(); drawBMIChart(); drawLabChart(); }
});
