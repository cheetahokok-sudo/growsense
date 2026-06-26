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
// These are project-level credentials (URL + publishable key), not a
// per-user secret — they identify which GrowSense database to talk to,
// the same way an API base URL would. Actual data access is gated by
// Postgres Row Level Security policies tied to the signed-in user, not
// by hiding this key. Never put a secret/service_role key here.
// ══════════════════════════════════════════
const SUPABASE_URL = 'https://ogpkmcqaulohexanucng.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_tNs8cyaiOYn8Q21wZxIYOQ_y5XXLXnf';
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);

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
  pubertyEvents: [], // puberty_events rows for the active child, loaded when the Medical tab opens
  illnessEvents: [], // illness_events rows for the active child, loaded when the Medical tab opens
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

// Loads the current project-wide AI mode and renders the admin toggle
// panel to match it — only ever called for system_admin accounts (see
// openSetup()), since the panel itself is also hidden by default.
async function loadAndRenderAdminAIModePanel() {
  const panel = document.getElementById('adminAIModePanel');
  panel.classList.remove('hidden');

  const mode = await getAICoachMode();
  document.querySelectorAll('#aiModeToggle .seg-btn').forEach(b => {
    b.classList.toggle('active', b.dataset.mode === mode);
  });
}

// Admin-only: flips the project-wide AI coach mode. Writes directly to
// system_settings — protected by that table's RLS policy (system_admin
// only), so even if this function were somehow called by a non-admin
// account, the database itself would reject the write.
async function setAICoachModeAdmin(mode, btn) {
  const { error } = await sb.from('system_settings').upsert({
    setting_key: 'ai_coach_mode',
    setting_value: mode,
    updated_by: APP.session ? APP.session.user.id : null,
    updated_at: new Date().toISOString()
  });

  if (error) {
    showToast('⚠️', 'Could not update AI mode: ' + error.message);
    return;
  }

  APP.aiCoachMode = mode; // update the cached value immediately for this session too
  document.querySelectorAll('#aiModeToggle .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  showToast('✅', `AI coach mode set to ${mode === 'live_ai' ? 'Live AI' : 'Template'}`);
}

// ══════════════════════════════════════════
// BOOT — gated on auth session
// ══════════════════════════════════════════
window.addEventListener('DOMContentLoaded', async () => {
  const { data } = await sb.auth.getSession();
  if (data.session) {
    await enterApp(data.session);
  } else {
    showAuthScreen();
  }

  // Keep the app in sync if the session changes elsewhere (e.g. token
  // refresh, or sign-out triggered from another tab).
  sb.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT') {
      showAuthScreen();
    }
  });

  document.getElementById('logDate').valueAsDate = new Date();
  document.getElementById('newPubertyDate').valueAsDate = new Date();
});

function showAuthScreen() {
  document.getElementById('authScreen').classList.remove('hidden');
  document.getElementById('appRoot').classList.add('hidden');
  setSyncStatus('disconnected', 'Not signed in');
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

  document.getElementById('clinicianPanel').classList.toggle('hidden', !isClinicianRole());
  document.getElementById('parentPanel').classList.toggle('hidden', isClinicianRole());

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
  input.max = todayISO(); // backdating is the point; future-dating isn't meaningful here
  updateDateSelectorUI();
}

function updateDateSelectorUI() {
  const bar = document.querySelector('.date-selector-bar');
  const todayBtn = document.getElementById('jumpToTodayBtn');
  const isToday = APP.logDate === todayISO();
  bar.classList.toggle('backdated', !isToday);
  todayBtn.classList.toggle('is-today', isToday);
  document.getElementById('logEntryDate').value = APP.logDate;
}

function shiftLogDate(deltaDays) {
  const d = new Date(APP.logDate + 'T00:00:00');
  d.setDate(d.getDate() + deltaDays);
  const newDate = d.toISOString().split('T')[0];
  if (newDate > todayISO()) return; // no future dates
  setLogDate(newDate);
}

function jumpToToday() {
  setLogDate(todayISO());
}

function onLogDateChanged() {
  const val = document.getElementById('logEntryDate').value;
  if (val) setLogDate(val);
}

// Switching dates means the whole Today form now represents a different
// day — reload that day's logged food items and daily totals, rather
// than carrying over whatever was on screen for the previous date.
async function setLogDate(newDate) {
  APP.logDate = newDate;
  updateDateSelectorUI();
  await loadDayIntoState();
  loadChildIntoForm();
}

// Pulls this child's daily_nutrition/sleep/activity rows AND
// nutrition_log_items for APP.logDate, and populates currentState()
// from them — so revisiting a past date shows what was actually
// logged that day, not leftover numbers from today.
async function loadDayIntoState() {
  const childId = activeChildId();
  const s = currentState();
  if (!childId) { resetStateToDefaults(s); await loadNutritionLogItems(); return; }

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
async function recordNutritionLogItem(foodId, foodName, proteinAmt, zincAmt, calciumAmt) {
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
  if (error) { showToast('⚠️', 'Could not remove: ' + error.message); return; }

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
  if (error) { showToast('⚠️', 'Could not remove: ' + error.message); return; }
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
  document.getElementById('valHanging').textContent = s.hanging + ' sec';
  document.getElementById('valJumps').textContent = s.jumps + ' reps';
  document.getElementById('valNightWakes').textContent = s.nightWakes;
  document.getElementById('waterLbl').textContent = `(${s.water}/8 glasses)`;
  document.getElementById('sleepBed').value = s.bed;
  document.getElementById('sleepWake').value = s.wake;

  document.querySelectorAll('#yogaSeg .seg-btn').forEach((b,i) => {
    b.classList.toggle('active', [0,10,20,30][i] === s.yogaMin);
  });
  document.querySelectorAll('.seg .seg-btn').forEach(b => {
    if (b.id && b.id.startsWith('st')) b.classList.remove('active');
  });
  const stMap = { 0:'stNone', 1:'stInhaled', 2:'stOral' };
  const stBtn = document.getElementById(stMap[s.steroid]);
  if (stBtn) stBtn.classList.add('active');

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

// ══════════════════════════════════════════
// CHILD SWITCHER
// ══════════════════════════════════════════
// Pulls whichever children this account can see (RLS enforces the actual
// scoping — a parent sees their own kids, a doctor sees assigned patients,
// a scientist sees all). Called on boot, after adding a child, and after
// switching accounts.
async function loadChildren() {
  const { data, error } = await sb.from('children').select('*').order('created_at');
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
  if (!name) { showToast('⚠️', 'Enter a name'); return; }
  if (!dob) { showToast('⚠️', 'Enter a date of birth'); return; }

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
  showToast('✅', `${name} added`);
}

// Shows/hides the optional birth-details fields on the child creation
// form — collapsed by default since most parents won't need this.
function toggleBirthDetails(btn) {
  const el = document.getElementById('birthDetailsFields');
  const isHidden = el.classList.contains('hidden');
  el.classList.toggle('hidden');
  btn.textContent = isHidden ? '− Hide birth details' : '+ Add birth details (for SGA / catch-up growth tracking)';
}

function renderChildList() {
  const el = document.getElementById('childList');
  if (APP.children.length === 0) {
    el.innerHTML = `<div class="empty-state" style="padding:16px;"><p>No children added yet.</p></div>`;
    return;
  }
  el.innerHTML = APP.children.map((c,i) => `
    <div style="display:flex; align-items:center; justify-content:space-between; background:var(--surface2); border-radius:10px; padding:10px 12px;">
      <div style="display:flex; align-items:center; gap:8px;">
        <span class="child-chip-avatar" style="width:26px;height:26px;font-size:12px;">${(c.avatar || c.name.charAt(0)).toUpperCase()}</span>
        <div>
          <div style="font-size:13px; font-weight:600;">${c.name}</div>
          <div style="font-size:11px; color:var(--text2);">Age ${ageFromDOB(c.date_of_birth) ?? '—'} · born ${c.date_of_birth}</div>
        </div>
      </div>
      <button onclick="removeChild('${c.child_id}')" style="background:none; border:none; color:var(--flag); font-size:18px; cursor:pointer; padding:4px; min-width:32px; min-height:32px;">×</button>
    </div>
  `).join('');
}

async function removeChild(childId) {
  if (APP.children.length <= 1) { showToast('⚠️', 'At least one child profile is required'); return; }
  if (!confirm('Remove this child profile? This permanently deletes all their logged data, including growth history and medical records. This cannot be undone.')) return;

  const { error } = await sb.from('children').delete().eq('child_id', childId);
  if (error) { showToast('⚠️', 'Could not remove: ' + error.message); return; }

  const idx = APP.children.findIndex(c => c.child_id === childId);
  if (idx >= 0) {
    APP.children.splice(idx, 1);
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
  if (!childId) { showToast('⚠️', 'Add a child profile first'); return; }
  if (!email) { showToast('⚠️', "Enter the doctor or researcher's email"); return; }

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
    showToast('⚠️', 'No Doctor or Researcher account found with that email');
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
  showToast('✅', 'Access granted');
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
  showToast('✅', 'Access revoked');
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
    document.getElementById('waterLbl').textContent = `(${s.water}/8 glasses)`;
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
  if (!child) { showToast('⚠️', 'Add a child profile first'); return; }

  const motherHeight = parseFloat(document.getElementById('thMotherHeight').value);
  const fatherHeight = parseFloat(document.getElementById('thFatherHeight').value);
  const motherAgeRaw = document.getElementById('thMotherAge').value;
  const fatherAgeRaw = document.getElementById('thFatherAge').value;

  if (!motherHeight || !fatherHeight) {
    showToast('⚠️', "Enter both parents' heights");
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
  if (!childId) { showToast('⚠️', 'Add a child profile first'); return; }

  const relation = document.getElementById('newFamilyRelation').value;
  const height = document.getElementById('newFamilyHeight').value;
  const age = document.getElementById('newFamilyAge').value;
  const notes = document.getElementById('newFamilyNotes').value.trim();

  if (!height) { showToast('⚠️', 'Enter a height'); return; }

  const { data, error } = await sb.from('family_height_records').insert({
    child_id: childId,
    relation,
    height_cm: parseFloat(height),
    age_at_measurement: age ? parseInt(age) : null,
    notes: notes || null,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) { showToast('⚠️', 'Could not save: ' + error.message); return; }

  APP.familyHeightRecords = APP.familyHeightRecords || [];
  APP.familyHeightRecords.unshift(data);
  renderFamilyHeightList();

  document.getElementById('newFamilyHeight').value = '';
  document.getElementById('newFamilyAge').value = '';
  document.getElementById('newFamilyNotes').value = '';
  showToast('✅', 'Added to family record');
}

async function deleteFamilyHeightRecord(id) {
  const { error } = await sb.from('family_height_records').delete().eq('record_id', id);
  if (error) { showToast('⚠️', 'Could not remove: ' + error.message); return; }
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

function buildFoodCardGrid() {
  const grid = document.getElementById('foodCardGrid');
  if (!grid) return;
  grid.innerHTML = '';

  if (typeof FOOD_REFERENCE_DATA === 'undefined') {
    grid.innerHTML = '<div class="setup-note" style="font-size:11px;">Food reference data not loaded.</div>';
    return;
  }

  FOOD_REFERENCE_DATA.forEach(food => {
    const scale = food.servingGrams / 100;
    const addProtein = Math.round(food.per100g.protein_g * scale * 10) / 10;
    const addZinc = food.per100g.zinc_mg != null ? Math.round(food.per100g.zinc_mg * scale * 100) / 100 : null;
    const addCalcium = food.per100g.calcium_mg != null ? Math.round(food.per100g.calcium_mg * scale) : null;

    const card = document.createElement('div');
    card.className = 'food-card';
    card.dataset.foodId = food.id;
    card.title = food.source; // shows on hover (desktop) as a quick provenance check
    card.innerHTML = `
      <div class="food-card-top">
        <span class="food-card-name"><span class="food-card-emoji">${food.emoji}</span>${food.name}</span>
        <span class="food-card-add">+${addProtein}g</span>
      </div>
      <div class="food-card-portion">${food.servingGrams}g · ${food.portionVisual}</div>
      <div class="food-card-prep">${food.prepNote}</div>
      <div class="food-card-tapcount" id="tapcount-${food.id}"></div>
    `;
    attachFoodCardHandlers(card, (direction) => applyFoodTap(food, addProtein, addZinc, addCalcium, direction));
    grid.appendChild(card);
  });

  // "Protein Boost" — flat manual +10g, not tied to any food record.
  // Visually distinguished (estimated-color accent) so it isn't mistaken
  // for a sourced USDA value the way the food cards above are.
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
    recordNutritionLogItem(foodId, foodName, proteinAmt, zincAmt, calciumAmt);
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
      document.getElementById('waterLbl').textContent = `(${st.water}/8 glasses)`;
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
  const pR = Math.min(s.protein/44, 1);
  const cR = Math.min(s.calcium/1300, 1);
  const wR = Math.min(s.water/8, 1);
  const nutPct = pR*0.4 + cR*0.4 + wR*0.2;

  const hR = Math.min(s.hanging/30, 1);
  const jR = Math.min(s.jumps/40, 1);
  const yR = Math.min(s.yogaMin/20, 1);
  const actPct = hR*0.4 + jR*0.4 + yR*0.2;

  const bed = document.getElementById('sleepBed').value.split(':').map(Number);
  const wake = document.getElementById('sleepWake').value.split(':').map(Number);
  let bedM = bed[0]*60+bed[1], wakeM = wake[0]*60+wake[1];
  if (bedM > wakeM) wakeM += 1440;
  const durR = Math.min((wakeM-bedM)/60/9.5, 1);
  // Bedtime on/before 21:30 protects the early GH-pulse window; each night
  // wake-up before midnight is treated as a partial disruption to that window.
  const onTimeR = (bedM <= (21*60+30)) ? 1 : Math.max(0, 1 - (bedM - (21*60+30))/120);
  const wakeR = Math.max(0, 1 - s.nightWakes * 0.25);
  const slpPct = durR*0.35 + onTimeR*0.4 + wakeR*0.25;

  const grs = Math.round(nutPct*35 + actPct*35 + slpPct*30);

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
  if (!childId) { showToast('⚠️', 'Add a child profile first'); return; }
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
  const sleepEfficiency = Math.max(0, Math.min(100, Math.round((totalSleepMin / (9.5*60)) * 100)));

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

  const results = await Promise.allSettled([
    sb.from('daily_nutrition').upsert({
      child_id: childId,
      log_date: saveDate,
      protein_breakfast_g: Math.round(mealSums.breakfast * 10) / 10,
      protein_lunch_g: Math.round(mealSums.lunch * 10) / 10,
      protein_dinner_g: Math.round(mealSums.dinner * 10) / 10,
      calcium_mg: s.calcium,
      zinc_mg: s.zinc,
      fluids_ml: s.water * 250  // 1 glass ≈ 250ml
    }, { onConflict: 'child_id,log_date' }),

    sb.from('daily_sleep').upsert({
      child_id: childId,
      log_date: saveDate,
      total_sleep_min: totalSleepMin,
      sleep_efficiency_score: sleepEfficiency,
      night_wakes: s.nightWakes,
      bedtime: s.bed,
      wake_time: s.wake,
      data_source: 'manual'
    }, { onConflict: 'child_id,log_date' }),

    sb.from('daily_activity').upsert({
      child_id: childId,
      log_date: saveDate,
      hanging_decompression_sec: s.hanging,
      box_jumps_reps: s.jumps,
      stretching_yoga_duration_min: s.yogaMin,
      data_source: 'manual'
    }, { onConflict: 'child_id,log_date' })
  ]);

  btn.disabled = false;

  const labels = ['Nutrition', 'Sleep', 'Activity'];
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
  showToast('✅', 'Saved');
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
    .select('recorded_date, stature_height_cm, mass_weight_kg, calculated_bmi')
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

    return `<tr><td>${fmt}</td><td>${Number(m.stature_height_cm).toFixed(1)}</td><td>${Number(m.mass_weight_kg).toFixed(1)}</td><td>${m.calculated_bmi ?? '—'}</td><td>${channelCell}</td></tr>`;
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

  const [nutRes, sleepRes, actRes] = await Promise.all([
    sb.from('daily_nutrition').select('log_date, total_protein_g, calcium_mg, fluids_ml').eq('child_id', childId).gte('log_date', sinceDate),
    sb.from('daily_sleep').select('log_date, total_sleep_min, sleep_efficiency_score').eq('child_id', childId).gte('log_date', sinceDate),
    sb.from('daily_activity').select('log_date, hanging_decompression_sec, box_jumps_reps, stretching_yoga_duration_min').eq('child_id', childId).gte('log_date', sinceDate)
  ]);

  const nutByDate = {}, sleepByDate = {}, actByDate = {};
  (nutRes.data || []).forEach(r => nutByDate[r.log_date] = r);
  (sleepRes.data || []).forEach(r => sleepByDate[r.log_date] = r);
  (actRes.data || []).forEach(r => actByDate[r.log_date] = r);
  const allDates = [...new Set([...Object.keys(nutByDate), ...Object.keys(sleepByDate), ...Object.keys(actByDate)])];

  if (allDates.length > 0) {
    // Same weighting as updateHUD()'s same-day score, applied per logged
    // day and averaged — this is the honest version of "avg readiness":
    // derived from what was actually logged, not a stored score column
    // (there isn't one in this schema; a single day's score was never
    // meant to be a durable clinical value anyway).
    const dailyScores = allDates.map(date => {
      const n = nutByDate[date], sl = sleepByDate[date], a = actByDate[date];
      const pR = n ? Math.min((n.total_protein_g||0)/44, 1) : 0;
      const cR = n ? Math.min((n.calcium_mg||0)/1300, 1) : 0;
      const wR = n ? Math.min((n.fluids_ml||0)/2000, 1) : 0;
      const nutPct = pR*0.4 + cR*0.4 + wR*0.2;

      const hR = a ? Math.min((a.hanging_decompression_sec||0)/30, 1) : 0;
      const jR = a ? Math.min((a.box_jumps_reps||0)/40, 1) : 0;
      const yR = a ? Math.min((a.stretching_yoga_duration_min||0)/20, 1) : 0;
      const actPct = hR*0.4 + jR*0.4 + yR*0.2;

      const durR = sl ? Math.min((sl.total_sleep_min||0)/(9.5*60), 1) : 0;
      const effR = sl ? (sl.sleep_efficiency_score||0)/100 : 0;
      const slpPct = durR*0.6 + effR*0.4;

      return nutPct*35 + actPct*35 + slpPct*30;
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
  if (!childId) { showToast('⚠️', 'Add a child profile first'); return; }
  const date = document.getElementById('logDate').value;
  const h = parseFloat(document.getElementById('logHeight').value);
  const w = parseFloat(document.getElementById('logWeight').value);
  if (!date) { showToast('⚠️', 'Select a date'); return; }
  if (isNaN(h) || isNaN(w) || h <= 0 || w <= 0) { showToast('⚠️', 'Enter a valid height and weight'); return; }

  // calculated_bmi is a generated column in Postgres (computed from
  // stature_height_cm/mass_weight_kg automatically) — don't send it.
  const { error } = await sb.from('measurements').upsert({
    child_id: childId,
    recorded_date: date,
    stature_height_cm: h,
    mass_weight_kg: w,
    data_source: 'manual'
  }, { onConflict: 'child_id,recorded_date' });

  if (error) { showToast('⚠️', 'Could not save: ' + error.message); return; }

  showToast('✅', 'Measurement logged');
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
// Currently plots illustrative/placeholder points since no lab history
// store exists yet; once Sheets sync round-trips data this should read
// real logged values via fetchFromSheets('Medical') rather than mock points.
// Lab marker trend chart (IGF-1, Vitamin D, etc.) — there is currently no
// table backing lab values (see Medical screen note: illness/medication/
// lab fields aren't persisted anywhere yet), so this renders an honest
// empty state rather than mock data that could be mistaken for real
// clinical trend lines.
function drawLabChart() {
  const canvas = document.getElementById('labCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const W = canvas.parentElement.clientWidth;
  const H = canvas.parentElement.clientHeight;
  canvas.width = W * window.devicePixelRatio;
  canvas.height = H * window.devicePixelRatio;
  ctx.setTransform(1,0,0,1,0,0);
  ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
  ctx.clearRect(0, 0, W, H);

  ctx.fillStyle = '#95A092';
  ctx.font = '11px Inter,sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('Lab tracking is not connected yet', W/2, H/2 - 6);
  ctx.font = '10px Inter,sans-serif';
  ctx.fillText('No table exists for lab values in this build', W/2, H/2 + 12);
}

// Builds a plain-text clinical summary (height velocity, percentile channel,
// recent lab values, logging consistency) sized for a doctor visit, and
// triggers a share/copy flow. No file-system writes — this is a client-side
// text blob handed to the OS share sheet or clipboard.
async function exportClinicalSummary() {
  const child = APP.children[APP.activeChild];
  if (!child) { showToast('⚠️', 'Add a child profile first'); return; }
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
  if (!childId) { showToast('⚠️', 'Add a child profile first'); return; }

  const btn = document.querySelector('#screenMedical .btn-secondary');
  const originalLabel = btn ? btn.textContent : '';
  if (btn) { btn.textContent = 'Saving…'; btn.disabled = true; }

  const igf1 = document.getElementById('labIGF').value;
  const vitD = document.getElementById('labVitD').value;
  const ferritin = document.getElementById('labFerritin').value;

  const { error } = await sb.from('medical_logs').upsert({
    child_id: childId,
    log_date: APP.logDate,
    steroid_level: currentState().steroid,
    medications: document.getElementById('medMeds').value || null,
    notes: document.getElementById('medNotes').value || null,
    igf1_ng_ml: igf1 ? parseFloat(igf1) : null,
    vitamin_d_nmol_l: vitD ? parseFloat(vitD) : null,
    ferritin_ng_ml: ferritin ? parseFloat(ferritin) : null,
    created_by: APP.session ? APP.session.user.id : null
  }, { onConflict: 'child_id,log_date' });

  if (btn) { btn.disabled = false; btn.textContent = originalLabel; }

  if (error) {
    showToast('⚠️', 'Could not save: ' + error.message);
    return;
  }
  showToast('✅', 'Clinical record saved for ' + APP.logDate);
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
    .limit(20); // most-recent-first, capped so the Medical screen doesn't grow unbounded for a child with years of history

  if (error) { listEl.innerHTML = ''; return; }
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
  if (!childId) { showToast('⚠️', 'Add a child profile first'); return; }

  const analyte = document.getElementById('newLabAnalyte').value.trim();
  const value = document.getElementById('newLabValue').value;
  const unit = document.getElementById('newLabUnit').value.trim();
  const refLow = document.getElementById('newLabRefLow').value;
  const refHigh = document.getElementById('newLabRefHigh').value;

  if (!analyte) { showToast('⚠️', 'Enter the analyte name'); return; }
  if (!value) { showToast('⚠️', 'Enter the result value'); return; }
  if (!unit) { showToast('⚠️', 'Enter the unit'); return; }

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

  if (error) { showToast('⚠️', 'Could not save: ' + error.message); return; }

  APP.labResults = APP.labResults || [];
  APP.labResults.unshift(data);
  renderLabResultsList();

  document.getElementById('newLabAnalyte').value = '';
  document.getElementById('newLabValue').value = '';
  document.getElementById('newLabUnit').value = '';
  document.getElementById('newLabRefLow').value = '';
  document.getElementById('newLabRefHigh').value = '';
  showToast('✅', 'Lab result added');
}

async function deleteLabResult(id) {
  const { error } = await sb.from('lab_results').delete().eq('lab_result_id', id);
  if (error) { showToast('⚠️', 'Could not remove: ' + error.message); return; }
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
  if (!childId) { showToast('⚠️', 'Add a child profile first'); return; }

  const type = document.getElementById('newPubertyType').value;
  const dateVal = document.getElementById('newPubertyDate').value;
  if (!dateVal) { showToast('⚠️', 'Enter the date observed'); return; }

  const needsStage = !PUBERTY_TYPES_WITHOUT_STAGE.includes(type);
  const stage = needsStage ? parseInt(document.getElementById('newPubertyStage').value) : null;

  const { data, error } = await sb.from('puberty_events').insert({
    child_id: childId,
    event_date: dateVal,
    event_type: type,
    tanner_stage: stage,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) { showToast('⚠️', 'Could not save: ' + error.message); return; }

  APP.pubertyEvents = APP.pubertyEvents || [];
  APP.pubertyEvents.unshift(data);
  renderPubertyEventsList();
  showToast('✅', 'Milestone added');
}

async function deletePubertyEvent(id) {
  const { error } = await sb.from('puberty_events').delete().eq('event_id', id);
  if (error) { showToast('⚠️', 'Could not remove: ' + error.message); return; }
  APP.pubertyEvents = (APP.pubertyEvents || []).filter(ev => ev.event_id !== id);
  renderPubertyEventsList();
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
  hospitalization: 'Hospitalization', other: 'Other'
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
  if (!childId) { showToast('⚠️', 'Add a child profile first'); return; }

  const startDate = document.getElementById('newIllnessStart').value;
  const endDate = document.getElementById('newIllnessEnd').value;
  const type = document.getElementById('newIllnessType').value;
  const notes = document.getElementById('newIllnessNotes').value.trim();

  if (!startDate) { showToast('⚠️', 'Enter the start date'); return; }
  if (endDate && endDate < startDate) { showToast('⚠️', 'End date is before start date'); return; }

  const { data, error } = await sb.from('illness_events').insert({
    child_id: childId,
    start_date: startDate,
    end_date: endDate || null,
    illness_type: type,
    notes: notes || null,
    created_by: APP.session ? APP.session.user.id : null
  }).select().single();

  if (error) { showToast('⚠️', 'Could not save: ' + error.message); return; }

  APP.illnessEvents = APP.illnessEvents || [];
  APP.illnessEvents.unshift(data);
  renderIllnessEventsList();

  document.getElementById('newIllnessStart').value = '';
  document.getElementById('newIllnessEnd').value = '';
  document.getElementById('newIllnessNotes').value = '';
  showToast('✅', 'Illness episode added');
}

async function deleteIllnessEvent(id) {
  const { error } = await sb.from('illness_events').delete().eq('event_id', id);
  if (error) { showToast('⚠️', 'Could not remove: ' + error.message); return; }
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
  inp.value = '';
  document.getElementById('quickPrompts').style.display = 'none';
  addUserMsg(msg);
  routeAICoachMessage(msg, null); // free text — needs real matching, not an exact hint
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

async function askClaude(userMsg) {
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
  } else {
    growthLines.push('- No child profile is currently selected.');
  }

  const systemPrompt = `You are the GrowSense AI coach, built for a parent who tracks their child's growth data and consults with a pediatrician/endocrinologist. You are not a doctor and must not diagnose, prescribe, or contradict clinical guidance — your role is to help the parent understand their own logged data and prepare better questions for clinical visits.

Growth & clinical profile:
${growthLines.join('\n')}

Today's readiness reading: ${grs}/100 (a same-day input score, not a diagnostic measure — single days carry little signal on their own)

Today's logged inputs:
- Protein: ${s.protein}g (target ~44g) | Calcium: ${s.calcium}mg (target ~1300mg) | Water: ${s.water}/8 glasses
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
        'Authorization': `Bearer ${SUPABASE_PUBLISHABLE_KEY}` // Supabase Edge Functions expect this even for public/anon calls
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
      // The API responded but with an error object (rate limit, bad
      // request, etc.) rather than a network failure — previously this
      // fell through to the generic "trouble responding" text with no
      // way to tell the two cases apart while debugging.
      console.error('[AI coach] API error:', data.error);
      addBotMsg('⚠️ The AI service returned an error. Please try again in a moment.');
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
    drawLabChart();
    await loadFamilyHeightRecords();
    loadTargetHeightForm();
  }
  if (name === 'Medical') {
    await loadMedicalLogForDate();
    await loadLabResults();
    await loadPubertyEvents();
    await loadIllnessEvents();
  }
  if (name === 'AI') {
    if (!APP.aiCoachQuestions) {
      await loadAICoachQuestions();
    } else {
      renderAICategoryChips(); // re-filter in case the active child or its data changed since last load
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
  if (isSystemAdmin()) loadAndRenderAdminAIModePanel();
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
