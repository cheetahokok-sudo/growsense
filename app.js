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
  signupRole: 'parent_subscriber'
};

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

  await loadChildren();

  document.getElementById('authScreen').classList.add('hidden');
  document.getElementById('appRoot').classList.remove('hidden');
  setSyncStatus('connected', account.email);
  setDateBadge();
  setTimeout(drawGrowthChart, 200);
}

// Repaint the entire Today form from the active child's stored state —
// called on boot and every time the child switcher changes selection.
function loadChildIntoForm() {
  const s = currentState();
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
  btn.textContent = s.savedToday ? 'Saved — tap to update' : "Save today's data";
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
      loadChildIntoForm();   // repaints the entire Today form from this child's draft state
      await refreshActiveChildHistory();
      await loadWeekStreak();
      updateStats();
      drawGrowthChart();
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

  const { data, error } = await sb.from('children').insert({
    parent_id: APP.session.user.id,
    name, date_of_birth: dob, biological_sex: sex
  }).select().single();

  if (error) { showToast('⚠️', 'Could not add child: ' + error.message); return; }

  APP.children.push(data);
  document.getElementById('newChildName').value = '';
  document.getElementById('newChildDOB').value = '';
  renderChildSwitcher();
  renderChildList();
  populateShareChildSelect();
  showToast('✅', `${name} added`);
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

  // Look up the target account by email. Note: with RLS as currently
  // configured (see schema), a plain parent account can only read their
  // own user_accounts row, so this lookup is expected to require a
  // dedicated RPC/edge function in a real deployment — this direct query
  // is a placeholder until that's built, and will likely return no rows.
  const { data: target, error: lookupError } = await sb
    .from('user_accounts')
    .select('user_id, account_role')
    .eq('email', email)
    .single();

  if (lookupError || !target) {
    showToast('⚠️', 'No account found with that email, or you don\'t have permission to look it up yet');
    return;
  }
  if (target.account_role !== 'doctor' && target.account_role !== 'scientist') {
    showToast('⚠️', 'That account is not registered as a Doctor or Researcher');
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
    card.title = food.source; // shows on hover (desktop) as a quick provenance check
    card.innerHTML = `
      <div class="food-card-top">
        <span class="food-card-name"><span class="food-card-emoji">${food.emoji}</span>${food.name}</span>
        <span class="food-card-add">+${addProtein}g</span>
      </div>
      <div class="food-card-prep">${food.prepNote}</div>
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

  card.addEventListener('touchstart', startPress, { passive: true });
  card.addEventListener('touchend', () => {
    cancelPress();
    if (!didLongPress) {
      card.classList.add('flash-add');
      setTimeout(() => card.classList.remove('flash-add'), 200);
      onAdd(1);
    }
  });
  card.addEventListener('touchmove', cancelPress);

  card.addEventListener('mousedown', startPress);
  card.addEventListener('mouseup', () => cancelPress());
  card.addEventListener('mouseleave', cancelPress);
  card.addEventListener('click', () => {
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
function applyFoodTap(food, proteinAmt, zincAmt, calciumAmt, direction) {
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
  const today = new Date().toISOString().split('T')[0];

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

  // Night wake-ups aren't a column on daily_sleep, but the schema does have
  // sleep_efficiency_score — used here as a 0-100 proxy that drops with
  // each recorded wake-up, so that signal isn't silently lost.
  const sleepEfficiency = Math.max(0, 100 - (s.nightWakes * 15));

  // Three independent writes — this app screen edits all three domains at
  // once, but each is its own table/concern (the split is deliberate, see
  // schema notes), so each upsert can succeed or fail on its own. If one
  // fails, the user is told specifically which domain didn't save rather
  // than getting one opaque "save failed" for the whole form.
  const results = await Promise.allSettled([
    sb.from('daily_nutrition').upsert({
      child_id: childId,
      log_date: today,
      protein_breakfast_g: s.protein,  // single stepper today; per-meal split is a future UI change
      protein_lunch_g: 0,
      protein_dinner_g: 0,
      calcium_mg: s.calcium,
      zinc_mg: s.zinc,
      fluids_ml: s.water * 250  // 1 glass ≈ 250ml
    }, { onConflict: 'child_id,log_date' }),

    sb.from('daily_sleep').upsert({
      child_id: childId,
      log_date: today,
      total_sleep_min: totalSleepMin,
      sleep_efficiency_score: sleepEfficiency,
      data_source: 'manual'
    }, { onConflict: 'child_id,log_date' }),

    sb.from('daily_activity').upsert({
      child_id: childId,
      log_date: today,
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
    btn.textContent = "Save today's data";
    return;
  }

  const todayIdx = (new Date().getDay() + 6) % 7;
  currentStreak()[todayIdx] = 1;
  s.savedToday = true;
  renderStreakRow();
  showToast('✅', 'Saved');
  btn.textContent = 'Saved — tap to update';
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

  tb.innerHTML = data.map(m => {
    const fmt = new Date(m.recorded_date).toLocaleDateString('en-GB', {day:'numeric', month:'short', year:'numeric'});
    return `<tr><td>${fmt}</td><td>${Number(m.stature_height_cm).toFixed(1)}</td><td>${Number(m.mass_weight_kg).toFixed(1)}</td><td>${m.calculated_bmi ?? '—'}</td><td><span class="pct-pill badge-measured">—</span></td></tr>`;
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
}

// ══════════════════════════════════════════
// GROWTH CHART — real WHO 2007 height-for-age bands (5–19y), shaded
// percentile overlay, child's actual measurements plotted on top.
// Requires who-reference-data.js and growth-percentile.js to be loaded.
// ══════════════════════════════════════════
function drawGrowthChart() {
  const canvas = document.getElementById('growthCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const W = canvas.parentElement.clientWidth;
  const H = canvas.parentElement.clientHeight;
  canvas.width = W * window.devicePixelRatio;
  canvas.height = H * window.devicePixelRatio;
  ctx.setTransform(1,0,0,1,0,0);
  ctx.scale(window.devicePixelRatio, window.devicePixelRatio);
  ctx.clearRect(0, 0, W, H);

  const pad = { t:12, r:12, b:28, l:32 };
  const w = W - pad.l - pad.r;
  const h = H - pad.t - pad.b;

  const child = APP.children[APP.activeChild];
  const measurements = (APP.activeChildMeasurements || []).slice().reverse(); // oldest first

  if (!child || typeof WHO_HFA_BOYS_5_19 === 'undefined') {
    ctx.fillStyle = '#95A092'; ctx.font = '11px Inter,sans-serif'; ctx.textAlign = 'center';
    ctx.fillText(!child ? 'Add a child profile to see this chart' : 'Reference data not loaded', W/2, H/2);
    return;
  }

  const table = (child.biological_sex === 'female') ? WHO_HFA_GIRLS_5_19 : WHO_HFA_BOYS_5_19;
  const tableMinYears = table[0][0] / 12, tableMaxYears = table[table.length-1][0] / 12;

  // Center the visible age window on the child's current age (±3 years),
  // clamped to what the WHO 5–19y table actually covers.
  const ageNowYears = (new Date() - new Date(child.date_of_birth)) / (365.25*86400000);
  let ageMin = Math.max(tableMinYears, ageNowYears - 3);
  let ageMax = Math.min(tableMaxYears, ageNowYears + 3);
  if (ageMax - ageMin < 2) { // keep a sane minimum window near the table edges
    if (ageMin <= tableMinYears) ageMax = Math.min(tableMaxYears, ageMin + 2);
    else ageMin = Math.max(tableMinYears, ageMax - 2);
  }

  function pxForAge(ageYears) {
    const clamped = Math.max(ageMin, Math.min(ageMax, ageYears));
    return pad.l + ((clamped - ageMin) / (ageMax - ageMin)) * w;
  }

  // Sample the real WHO bands at N points across the visible window —
  // this is what makes the shaded region and lines reflect actual
  // reference data rather than a few hand-picked illustrative numbers.
  const SAMPLES = 24;
  const sampled = [];
  for (let i = 0; i <= SAMPLES; i++) {
    const ageYears = ageMin + (ageMax - ageMin) * (i / SAMPLES);
    const bands = GrowthPercentileMath.interpolateBands(table, ageYears * 12);
    sampled.push({ ageYears, p3: bands[0], p15: bands[1], p50: bands[2], p85: bands[3], p97: bands[4] });
  }

  // Y-axis scale: fit to the full 3rd–97th band range across the visible
  // window (plus a little headroom), so the shaded area always fills
  // most of the chart regardless of the child's age.
  const allBandValues = sampled.flatMap(s => [s.p3, s.p97]);
  const yMin = Math.min(...allBandValues) - 3;
  const yMax = Math.max(...allBandValues) + 3;
  function hy(cm) { return pad.t + h - ((cm - yMin) / (yMax - yMin)) * h; }

  // Gridlines
  ctx.strokeStyle = '#F0F2F5'; ctx.lineWidth = 1;
  for (let i=1; i<5; i++) {
    const y = pad.t + (h/5)*i;
    ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(pad.l+w, y); ctx.stroke();
  }

  // Age axis labels — whole years across the visible window
  ctx.fillStyle = '#9BA3B4'; ctx.font = '9px Inter,sans-serif'; ctx.textAlign = 'center';
  const startYear = Math.ceil(ageMin), endYear = Math.floor(ageMax);
  for (let y = startYear; y <= endYear; y++) {
    ctx.fillText(y + 'y', pxForAge(y), pad.t + h + 18);
  }

  // Shaded 3rd–97th band (outer, lighter) and 15th–85th band (inner,
  // slightly darker) — this is the visual "highlight area" overlay.
  function fillBand(lowKey, highKey, color) {
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
  fillBand('p3', 'p97', 'rgba(170,179,165,0.18)');
  fillBand('p15', 'p85', 'rgba(170,179,165,0.30)');

  // Band edge lines (3rd, 15th, 50th, 85th, 97th) drawn from the same
  // real sampled data as the fill above.
  function lineFor(key, color, width) {
    drawLine(ctx, sampled.map(s => [pxForAge(s.ageYears), hy(s[key])]), color, width);
  }
  lineFor('p3', '#D7DCD2', 1.2);
  lineFor('p15', '#AAB3A5', 1.4);
  lineFor('p50', '#7C877A', 1.6);
  lineFor('p85', '#AAB3A5', 1.4);
  lineFor('p97', '#D7DCD2', 1.2);

  // Plot this child's actual measurements, positioned by true age-at-
  // measurement (from date_of_birth), on the exact same scale as the
  // reference bands above — so visual position directly reflects
  // standing relative to the real WHO curve, not an approximation.
  const ageAt = dateStr => (new Date(dateStr) - new Date(child.date_of_birth)) / (365.25*86400000);
  const actual = measurements.map(m => [pxForAge(ageAt(m.recorded_date)), hy(Number(m.stature_height_cm))]);

  if (actual.length > 0) {
    drawLine(ctx, actual, '#2A5C8A', 3);
    actual.forEach(([x,y], i) => {
      const isLatest = i === actual.length - 1;
      ctx.fillStyle = '#2A5C8A';
      ctx.beginPath(); ctx.arc(x, y, isLatest ? 5 : 4, 0, 2*Math.PI); ctx.fill();
      ctx.fillStyle = 'white'; ctx.beginPath(); ctx.arc(x, y, isLatest ? 2.5 : 2, 0, 2*Math.PI); ctx.fill();
    });

    // Forecast: simple linear extrapolation from the last two points, only
    // drawn when there are at least two real measurements to extrapolate
    // from — no fabricated trajectory when there's only one data point.
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
    ctx.fillStyle = '#95A092'; ctx.font = '11px Inter,sans-serif'; ctx.textAlign = 'center';
    ctx.fillText('No measurements logged yet', W/2, H/2);
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
function saveMedical() {
  showToast('⚠️', 'Medical records aren\'t saved to your account yet — this screen is still in development');
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
    drawLabChart();
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
  if (sc.classList.contains('active')) { drawGrowthChart(); drawLabChart(); }
});
