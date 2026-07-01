// ══════════════════════════════════════════════════════════════════
// GrowSense Admin Dashboard — standalone application logic
//
// This is a genuinely separate bundle from the parent app's app.js —
// not a lazy-loaded module, not sharing the parent app's global APP
// state. It has its own small state object (ADMIN, below), its own
// boot sequence, and its own copies of the handful of admin functions
// that used to live inside app.js (ported, not duplicated-and-left-
// behind — see FORMULAS.md for the plan to remove them from app.js
// once this page is fully verified working).
//
// Reuses only two things from the parent app, both loaded via <script>
// tags before this file: the Supabase SDK + createGrowSenseClient()
// (supabase-client.js) and the CSS design tokens (design-tokens.css).
// Everything else here is self-contained, by design — see admin.css's
// header comment for the reasoning.
// ══════════════════════════════════════════════════════════════════

const sb = createGrowSenseClient();

// Minimal admin-specific state — NOT a copy of the parent app's much
// larger APP object, which carries dozens of fields (daily logs, food
// favorites, growth charts, etc.) that have no meaning on this page.
const ADMIN = {
  session: null,
  account: null,
  adminUsers: [],
  aiCoachMode: null
};

function isSystemAdmin() {
  return ADMIN.account && ADMIN.account.account_role === 'system_admin';
}

// ══════════════════════════════════════════
// BOOT — this page's own session/role check, independent of the
// parent app's enterApp(). Three possible outcomes: no session at all
// (point back to the main app to sign in), a session that isn't a
// system_admin (clear "not authorized" message, no dashboard shown),
// or a confirmed system_admin (reveal the dashboard and load it).
//
// Sessions are shared automatically: the Supabase client persists its
// session to this browser's localStorage, scoped to the origin
// (scheme+host), not the path — so a session created by signing in on
// the main app at /growsense/ is already visible here at
// /growsense/admin.html with no extra work needed.
// ══════════════════════════════════════════
window.addEventListener('DOMContentLoaded', async () => {
  const { data } = await sb.auth.getSession();

  if (!data.session) {
    showAdminGate('noSession');
    return;
  }

  ADMIN.session = data.session;

  const { data: account, error } = await sb
    .from('user_accounts')
    .select('*')
    .eq('user_id', data.session.user.id)
    .single();

  if (error || !account) {
    showAdminGate('noSession');
    return;
  }

  document.getElementById('adminTopbarEmail').textContent = account.email;
  document.getElementById('adminTopbarEmail').classList.remove('hidden');
  document.getElementById('adminSignOutBtn').classList.remove('hidden');

  if (account.account_role !== 'system_admin') {
    document.getElementById('adminGateNotAuthorizedMsg').textContent =
      `Signed in as ${account.email}, but this account doesn't have admin access.`;
    showAdminGate('notAuthorized');
    return;
  }

  ADMIN.account = account;
  showAdminGate('dashboard');
  restoreSidebarState();
  await initAdminDashboard();
});

function showAdminGate(which) {
  document.getElementById('adminGateNoSession').classList.toggle('hidden', which !== 'noSession');
  document.getElementById('adminGateNotAuthorized').classList.toggle('hidden', which !== 'notAuthorized');
  document.getElementById('adminDashboardRoot').classList.toggle('hidden', which !== 'dashboard');
}

async function handleAdminSignOut() {
  await sb.auth.signOut();
  ADMIN.session = null;
  ADMIN.account = null;
  document.getElementById('adminTopbarEmail').classList.add('hidden');
  document.getElementById('adminSignOutBtn').classList.add('hidden');
  showAdminGate('noSession');
}

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

// ══════════════════════════════════════════
// AI COACH MODE (project-wide setting)
// ══════════════════════════════════════════
async function getAICoachMode() {
  if (ADMIN.aiCoachMode) return ADMIN.aiCoachMode;
  try {
    const { data, error } = await sb.from('system_settings').select('setting_value').eq('setting_key', 'ai_coach_mode').maybeSingle();
    ADMIN.aiCoachMode = (!error && data) ? data.setting_value : 'template';
  } catch (e) {
    ADMIN.aiCoachMode = 'template';
  }
  return ADMIN.aiCoachMode;
}

async function loadAndRenderAdminAIModePanel() {
  const mode = await getAICoachMode();
  document.querySelectorAll('#aiModeToggle .seg-btn').forEach(b => {
    b.classList.toggle('active', b.dataset.mode === mode);
  });
}

async function setAICoachModeAdmin(mode, btn) {
  const { error } = await sb.from('system_settings').upsert({
    setting_key: 'ai_coach_mode',
    setting_value: mode,
    updated_by: ADMIN.session ? ADMIN.session.user.id : null,
    updated_at: new Date().toISOString()
  });

  if (error) {
    showToast('⚠️', 'Could not update AI mode: ' + error.message);
    return;
  }

  ADMIN.aiCoachMode = mode;
  document.querySelectorAll('#aiModeToggle .seg-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  showToast('✅', `AI coach mode set to ${mode === 'live_ai' ? 'Live AI' : 'Template'}`);
}

// ══════════════════════════════════════════
// ARCHIVED DATA — reads through SECURITY DEFINER functions, same as
// the original (see migration_fix_children_rls_recursion.sql for why
// plain views don't work here).
// ══════════════════════════════════════════
async function loadAndRenderAdminArchivePanel() {
  const [childrenRes, accountsRes] = await Promise.all([
    sb.rpc('get_archived_children'),
    sb.rpc('get_archived_accounts')
  ]);

  renderArchivedChildrenList((!childrenRes.error && childrenRes.data) ? childrenRes.data : []);
  renderArchivedAccountsList((!accountsRes.error && accountsRes.data) ? accountsRes.data : []);
}

function renderArchivedChildrenList(rows) {
  const el = document.getElementById('archivedChildrenList');
  if (rows.length === 0) { el.innerHTML = '<div class="log-list-empty">None archived.</div>'; return; }
  el.innerHTML = rows.map(r => `
    <div class="log-item-row">
      <div class="log-item-left">
        <div class="log-item-info">
          <span class="log-item-name">${r.name}</span>
          <span class="log-item-meta">${r.days_until_permanent_delete} days until permanent deletion</span>
        </div>
      </div>
      <div class="log-item-right">
        <button class="btn-link" onclick="restoreArchivedChild('${r.child_id}', this)">Restore</button>
      </div>
    </div>
  `).join('');
}

function renderArchivedAccountsList(rows) {
  const el = document.getElementById('archivedAccountsList');
  if (rows.length === 0) { el.innerHTML = '<div class="log-list-empty">None archived.</div>'; return; }
  el.innerHTML = rows.map(r => `
    <div class="log-item-row">
      <div class="log-item-left">
        <div class="log-item-info">
          <span class="log-item-name">${r.email}</span>
          <span class="log-item-meta">${r.days_until_permanent_delete} days until permanent deletion</span>
        </div>
      </div>
      <div class="log-item-right">
        <button class="btn-link" onclick="restoreArchivedAccount('${r.user_id}', this)">Restore</button>
      </div>
    </div>
  `).join('');
}

async function restoreArchivedChild(childId, btn) {
  const { error } = await sb.from('children').update({
    status: 'active', archived_at: null, archived_by: null, permanent_delete_after: null
  }).eq('child_id', childId);
  if (error) { showToast('⚠️', 'Could not restore: ' + error.message); return; }
  showToast('✅', 'Child profile restored');
  btn.closest('.log-item-row').remove();
}

async function restoreArchivedAccount(userId, btn) {
  const { error } = await sb.from('user_accounts').update({
    account_status: 'active', archived_at: null, permanent_delete_after: null
  }).eq('user_id', userId);
  if (error) { showToast('⚠️', 'Could not restore: ' + error.message); return; }
  showToast('✅', 'Account restored');
  btn.closest('.log-item-row').remove();
}

// ══════════════════════════════════════════
// MAIN DASHBOARD — overview stats, user list, tier changes, audit log.
// Reads go through get_all_users_for_admin() (SECURITY DEFINER, bypasses
// normal RLS — a regular user can only see their own row). Tier changes
// go through change_user_subscription_tier(), which performs the
// update AND writes the audit log entry atomically.
// ══════════════════════════════════════════

// ══════════════════════════════════════════
// SIDEBAR CONTROLS
// ══════════════════════════════════════════

// Desktop: toggle between full sidebar (220px) and icon-only rail
// (56px). State saved to localStorage so the preference persists
// across page visits and reloads — an admin who collapses the sidebar
// to see more of the user list shouldn't have to do it again every
// visit.
function toggleSidebarCollapse() {
  const sidebar = document.getElementById('adminSidebar');
  const isCollapsed = sidebar.classList.toggle('collapsed');
  try { localStorage.setItem('adminSidebarCollapsed', isCollapsed ? '1' : '0'); } catch (e) {}
}

// Mobile: slide the sidebar drawer in/out as a full overlay,
// with a semi-transparent backdrop. The backdrop click also
// calls this to dismiss, matching standard mobile drawer behaviour.
function toggleMobileSidebar() {
  const sidebar = document.getElementById('adminSidebar');
  const backdrop = document.getElementById('sidebarBackdrop');
  const isOpen = sidebar.classList.toggle('mobile-open');
  backdrop.classList.toggle('hidden', !isOpen);
}

// Restore the saved collapse state on load — called once at the
// end of the boot sequence, after the dashboard is revealed.
function restoreSidebarState() {
  try {
    const saved = localStorage.getItem('adminSidebarCollapsed');
    if (saved === '1') {
      document.getElementById('adminSidebar').classList.add('collapsed');
    }
  } catch (e) {}
}

async function initAdminDashboard() {
  setAdminGreeting();

  const [usersRes, logRes] = await Promise.all([
    sb.rpc('get_all_users_for_admin'),
    sb.from('admin_audit_log').select('*').order('created_at', { ascending: false }).limit(30)
  ]);

  ADMIN.adminUsers = (!usersRes.error && usersRes.data) ? usersRes.data : [];
  if (usersRes.error) showToast('⚠️', 'Could not load users: ' + usersRes.error.message);

  const auditRows = (!logRes.error && logRes.data) ? logRes.data : [];

  renderAdminUserList();
  renderAdminAuditLog(auditRows);
  renderAdminAuditLog(auditRows.slice(0, 5), 'adminAuditLogPreview');
  renderAdminOverviewStats();

  await loadAndRenderAdminAIModePanel();
  await loadAndRenderAdminArchivePanel();
}

function setAdminGreeting() {
  const hour = new Date().getHours();
  const timeOfDay = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  const name = (ADMIN.account && ADMIN.account.email) ? ADMIN.account.email.split('@')[0] : 'admin';
  document.getElementById('adminGreeting').textContent = `${timeOfDay}, ${name}`;
}

function renderAdminOverviewStats() {
  const users = ADMIN.adminUsers || [];
  document.getElementById('statTotalUsers').textContent = users.length;
  document.getElementById('statFree').textContent = users.filter(u => u.subscription_tier === 'free').length;
  document.getElementById('statPremium').textContent = users.filter(u => u.subscription_tier === 'premium').length;
  document.getElementById('statPro').textContent = users.filter(u => u.subscription_tier === 'pro').length;
}

function setAdminSection(section, btn) {
  document.querySelectorAll('.admin-nav-item').forEach(b => b.classList.remove('active'));
  if (btn) btn.classList.add('active');
  document.querySelectorAll('.admin-section').forEach(s => s.classList.remove('active'));
  document.getElementById('adminSection' + section.charAt(0).toUpperCase() + section.slice(1)).classList.add('active');
  // Auto-close the mobile drawer when the user taps a nav item —
  // the content is now visible, the drawer is no longer needed.
  const sidebar = document.getElementById('adminSidebar');
  if (sidebar.classList.contains('mobile-open')) toggleMobileSidebar();
}

function renderAdminUserList() {
  const listEl = document.getElementById('adminUserList');
  const metaEl = document.getElementById('adminUserListMeta');
  const searchTerm = (document.getElementById('adminUserSearch').value || '').trim().toLowerCase();
  const allUsers = ADMIN.adminUsers || [];

  const filtered = searchTerm
    ? allUsers.filter(u => u.email.toLowerCase().includes(searchTerm))
    : allUsers;

  metaEl.textContent = `${filtered.length} of ${allUsers.length} accounts shown`;

  if (filtered.length === 0) {
    listEl.innerHTML = '<div class="log-list-empty">No matching accounts.</div>';
    return;
  }

  const tierOptions = ['free', 'premium', 'pro'];

  listEl.innerHTML = filtered.map(u => {
    const tierSelectOptions = tierOptions.map(t =>
      `<option value="${t}" ${u.subscription_tier === t ? 'selected' : ''}>${t}</option>`
    ).join('');
    const statusNote = u.account_status === 'archived' ? ' · <span style="color:var(--flag);">archived</span>' : '';
    return `
      <div class="log-item-row" style="flex-wrap:wrap; gap:8px;">
        <div class="log-item-left" style="flex:1; min-width:200px;">
          <div class="log-item-info">
            <span class="log-item-name">${u.email}</span>
            <span class="log-item-meta">${u.account_role.replace('_',' ')} · ${u.child_count} child${u.child_count === 1 ? '' : 'ren'}${statusNote}</span>
          </div>
        </div>
        <div class="log-item-right" style="display:flex; align-items:center; gap:6px;">
          <select class="num-input" style="width:110px;" id="tierSelect-${u.user_id}">${tierSelectOptions}</select>
          <button class="btn-link" onclick="applyTierChange('${u.user_id}', '${u.email}', '${u.subscription_tier}')">Apply</button>
        </div>
      </div>
    `;
  }).join('');
}

async function applyTierChange(userId, email, currentTier) {
  const select = document.getElementById('tierSelect-' + userId);
  const newTier = select.value;

  if (newTier === currentTier) { showToast('⚠️', 'Already on that tier'); return; }
  if (!confirm(`Change ${email}'s subscription tier from ${currentTier} to ${newTier}?`)) return;

  const { error } = await sb.rpc('change_user_subscription_tier', {
    p_target_user_id: userId,
    p_new_tier: newTier,
    p_notes: null
  });

  if (error) { showToast('⚠️', 'Could not change tier: ' + error.message); return; }

  showToast('✅', `${email} moved to ${newTier}`);
  const userRecord = (ADMIN.adminUsers || []).find(u => u.user_id === userId);
  if (userRecord) userRecord.subscription_tier = newTier;
  renderAdminUserList();
  renderAdminOverviewStats();
  const logRes = await sb.from('admin_audit_log').select('*').order('created_at', { ascending: false }).limit(30);
  if (!logRes.error) {
    renderAdminAuditLog(logRes.data);
    renderAdminAuditLog(logRes.data.slice(0, 5), 'adminAuditLogPreview');
  }
}

function renderAdminAuditLog(rows, targetElId) {
  const listEl = document.getElementById(targetElId || 'adminAuditLogList');
  if (!rows || rows.length === 0) {
    listEl.innerHTML = '<div class="log-list-empty">No admin actions recorded yet.</div>';
    return;
  }
  listEl.innerHTML = rows.map(r => {
    const when = new Date(r.created_at).toLocaleString('en-GB', { day:'numeric', month:'short', year:'numeric', hour:'2-digit', minute:'2-digit' });
    const changeDesc = (r.before_value && r.after_value)
      ? `${r.before_value} → ${r.after_value}`
      : (r.after_value || '');
    return `
      <div class="log-item-row">
        <div class="log-item-left">
          <div class="log-item-info">
            <span class="log-item-name">${r.action_type.replace(/_/g,' ')}${r.target_email ? ' — ' + r.target_email : ''}</span>
            <span class="log-item-meta">${changeDesc ? changeDesc + ' · ' : ''}by ${r.admin_email} · ${when}</span>
          </div>
        </div>
      </div>
    `;
  }).join('');
}
