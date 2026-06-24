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
  activeMealSlot: 'breakfast' // which meal new food-card taps get tagged with; defaults to breakfast each load (see setMealSlot)
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

  if (titleEl) titleEl.textContent = use0to5 ? 'Length/Height-for-age (WHO Child Growth Standards)' : 'Height-for-age (WHO 2007 Reference)';
  if (noteEl) noteEl.textContent = use0to5
    ? 'Shaded bands are the official WHO Child Growth Standards (0–5 years), transcribed directly from who.int. Curve shape reflects real early-childhood growth deceleration, not a straight-line approximation. Measured 0–2y as recumbent length, 2–5y as standing height — bring this chart to your pediatrician.'
    : 'Shaded bands are the official WHO 2007 Growth Reference for school-age children and adolescents (5–19 years), transcribed directly from who.int. This is a population reference, not a diagnosis — bring this chart to your pediatrician for clinical interpretation, especially near the band edges.';

  let ageMin, ageMax, sampleBandsAt, yPad;

  if (use0to5) {
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

  // More samples for the 0-5y chart than the 5-19y one (48 vs 24) since
  // the curve genuinely bends faster in early months — more points keep
  // that real curvature visually smooth rather than visibly faceted.
  const SAMPLES = use0to5 ? 48 : 24;
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
  fillChartBand(ctx, sampled, pxForAge, hy, 'p15', 'p85', 'rgba(170,179,165,0.30)');
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p3', '#D7DCD2', 1.2);
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p15', '#AAB3A5', 1.4);
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p50', '#7C877A', 1.6);
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p85', '#AAB3A5', 1.4);
  drawChartBandLine(ctx, sampled, pxForAge, hy, 'p97', '#D7DCD2', 1.2);

  // Plot this child's actual measurements. Under the 0-5y branch, apply
  // the same recumbent/standing 0.7cm convention used by the percentile
  // calc itself — height shown on the chart should be on whichever
  // measurement basis matches the age it's plotted at, exactly the same
  // logic calculateHeightPercentile0to5() applies, so the chart and the
  // numeric percentile reading never disagree with each other.
  const ageAt = dateStr => (new Date(dateStr) - new Date(child.date_of_birth)) / (365.25*86400000);
  const actual = measurements.map(m => {
    const ageYears = ageAt(m.recorded_date);
    let heightCm = Number(m.stature_height_cm);
    if (use0to5) {
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
    illness_days: parseInt(document.getElementById('medIllness').value) || 0,
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
  const illnessEl = document.getElementById('medIllness');
  const medsEl = document.getElementById('medMeds');
  const notesEl = document.getElementById('medNotes');
  const igfEl = document.getElementById('labIGF');
  const vitDEl = document.getElementById('labVitD');
  const ferritinEl = document.getElementById('labFerritin');

  // Reset to blank defaults first, so switching to a date/child with no
  // record doesn't show stale values from whatever was viewed before.
  illnessEl.value = 0;
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

  illnessEl.value = data.illness_days || 0;
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
// AI CHAT
// ══════════════════════════════════════════
function sendQuick(btn) {
  const msg = btn.textContent.trim();
  document.getElementById('quickPrompts').style.display = 'none';
  addUserMsg(msg);
  askClaude(msg);
}

function sendAI() {
  const inp = document.getElementById('aiInput');
  const msg = inp.value.trim();
  if (!msg) return;
  inp.value = '';
  document.getElementById('quickPrompts').style.display = 'none';
  addUserMsg(msg);
  askClaude(msg);
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

async function askClaude(userMsg) {
  showThinking();
  const child = APP.children[APP.activeChild] || { name:'Child', age:9, weight:29, height:127 };
  const grs = document.getElementById('grsScore').textContent;
  const s = currentState();
  const totalSleep = document.getElementById('totalSleepLbl').textContent;

  const systemPrompt = `You are the BioGrowth OS AI coach, built for a parent who tracks their child's growth data and consults with a pediatrician/endocrinologist. You are not a doctor and must not diagnose, prescribe, or contradict clinical guidance — your role is to help the parent understand their own logged data and prepare better questions for clinical visits.

Current child profile:
- Name: ${child.name}
- Age: ${child.age} years
- Height: ${child.height} cm | Weight: ${child.weight} kg
- Today's readiness reading: ${grs}/100 (a same-day input score, not a diagnostic measure — single days carry little signal on their own)

Today's logged inputs:
- Protein: ${s.protein}g (target ~44g) | Calcium: ${s.calcium}mg (target ~1300mg) | Water: ${s.water}/8 glasses
- Bar hanging: ${s.hanging}s | Box jumps: ${s.jumps} reps | Yoga/stretching: ${s.yogaMin} min
- Bedtime: ${s.bed} | Wake: ${s.wake} | Total sleep: ${totalSleep} | Night wake-ups: ${s.nightWakes}
- Corticosteroid use level: ${s.steroid} (0=none, 1=inhaled, 2=oral)

Guidelines:
- Ground every answer in the data above; don't invent numbers not given.
- Never state a diagnosis or tell the parent to change medication/treatment — defer those explicitly to their pediatrician.
- Growth is judged by velocity and trend over weeks/months, not single days — say so if the parent seems to be over-reading one day's numbers.
- Keep responses concise (3–5 sentences unless asked for detail). Plain language, minimal jargon.`;

  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'claude-sonnet-4-6',
        max_tokens: 1000,
        system: systemPrompt,
        messages: [{ role: 'user', content: userMsg }]
      })
    });
    const data = await res.json();
    hideThinking();
    const txt = data.content && data.content[0] ? data.content[0].text : 'Sorry, I had trouble responding. Please try again.';
    addBotMsg(txt.replace(/\n/g, '<br>'));
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
  }
  if (name === 'Medical') {
    await loadMedicalLogForDate();
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
