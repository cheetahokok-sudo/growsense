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
async function bootAdminSession() {
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
}

window.addEventListener('DOMContentLoaded', bootAdminSession);

// Direct sign-in on the admin page itself. The page URL was never the
// security boundary (public repo) — the system_admin role gate + RLS
// are; a non-admin who signs in here just lands on Gate 2.
async function handleAdminSignIn(ev) {
  ev.preventDefault();
  const btn = document.getElementById('adminLoginBtn');
  const errEl = document.getElementById('adminLoginError');
  errEl.textContent = '';
  btn.disabled = true; btn.textContent = 'Signing in…';
  const { error } = await sb.auth.signInWithPassword({
    email: document.getElementById('adminLoginEmail').value.trim(),
    password: document.getElementById('adminLoginPassword').value
  });
  btn.disabled = false; btn.textContent = 'Sign in';
  if (error) { errEl.textContent = error.message; return; }
  document.getElementById('adminLoginPassword').value = '';
  await bootAdminSession();
}

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
  // Purge-overdue control: the countdown the UI promises is enforced
  // manually from here (no cron) — button appears only when something
  // is actually overdue.
  const overdue = rows.filter(r => Number(r.days_until_permanent_delete) <= 0).length;
  const purgeBtn = document.getElementById('purgeOverdueBtn');
  if (purgeBtn) {
    purgeBtn.style.display = overdue > 0 ? '' : 'none';
    purgeBtn.textContent = `Purge overdue (${overdue})`;
  }
  if (rows.length === 0) { el.innerHTML = '<div class="log-list-empty">None archived.</div>'; return; }
  el.innerHTML = rows.map(r => {
    const days = Number(r.days_until_permanent_delete);
    const meta = days <= 0
      ? '<span style="color:var(--flag); font-weight:700;">overdue — past its deletion date</span>'
      : `${days} days until permanent deletion`;
    const safeName = escHtml(r.name).replace(/'/g, '&#39;');
    return `
    <div class="log-item-row">
      <div class="log-item-left">
        <div class="log-item-info">
          <span class="log-item-name">${escHtml(r.name)}</span>
          <span class="log-item-meta">${meta}</span>
        </div>
      </div>
      <div class="log-item-right" style="display:flex; gap:10px;">
        <button class="btn-link" onclick="restoreArchivedChild('${r.child_id}', this)">Restore</button>
        <button class="btn-link" style="color:var(--flag);" onclick="deleteArchivedChildNow('${r.child_id}', '${safeName}', this)">Delete now</button>
      </div>
    </div>`;
  }).join('');
}

function renderArchivedAccountsList(rows) {
  const el = document.getElementById('archivedAccountsList');
  if (rows.length === 0) { el.innerHTML = '<div class="log-list-empty">None archived.</div>'; return; }
  el.innerHTML = rows.map(r => {
    const safeEmail = escHtml(r.email).replace(/'/g, '&#39;');
    return `
    <div class="log-item-row">
      <div class="log-item-left">
        <div class="log-item-info">
          <span class="log-item-name">${escHtml(r.email)}</span>
          <span class="log-item-meta">${r.days_until_permanent_delete} days until permanent deletion</span>
        </div>
      </div>
      <div class="log-item-right" style="display:flex; gap:10px;">
        <button class="btn-link" onclick="restoreArchivedAccount('${r.user_id}', this)">Restore</button>
        <button class="btn-link" style="color:var(--flag);" onclick="deleteArchivedAccountNow('${r.user_id}', '${safeEmail}', this)">Delete now</button>
      </div>
    </div>`;
  }).join('');
}

// Hard delete of an ARCHIVED account: SECURITY DEFINER RPC (refuses
// active accounts and system_admins), audits first, then deletes the
// auth user — FK hygiene (2026-07-15 migration) cascades the whole
// tree: user_accounts -> children -> all child data.
async function deleteArchivedAccountNow(userId, email, btn) {
  const typed = prompt(
    `PERMANENT deletion of the account ${email}, its login, ALL its ` +
    `children and ALL their data.\n\nThis cannot be undone.\n\n` +
    `Type DELETE to confirm:`);
  if (typed !== 'DELETE') { if (typed !== null) showToast('⚠️', 'Not confirmed — nothing deleted'); return; }
  if (btn) btn.disabled = true;
  const { error } = await sb.rpc('admin_delete_account_permanently', { p_user_id: userId });
  if (error) { showToast('⚠️', 'Could not delete: ' + error.message); if (btn) btn.disabled = false; return; }
  showToast('✅', `${email} permanently deleted`);
  loadAndRenderAdminArchivePanel();
}

// Child lifecycle goes through SECURITY DEFINER RPCs (see
// migrations/2026-07-15_admin_child_lifecycle.sql): children RLS has no
// admin arm, so the old direct UPDATE here was a silent no-op (0 rows,
// no error). The RPCs also write admin_audit_log.
async function restoreArchivedChild(childId, btn) {
  const { error } = await sb.rpc('admin_restore_child', { p_child_id: childId });
  if (error) { showToast('⚠️', 'Could not restore: ' + error.message); return; }
  showToast('✅', 'Child profile restored');
  btn.closest('.log-item-row').remove();
}

// Hard delete of an ARCHIVED child (the RPC refuses active profiles).
// Typed confirmation — this is irreversible and cascades through every
// data table for the child.
async function deleteArchivedChildNow(childId, name, btn) {
  const typed = prompt(
    `PERMANENT deletion of "${name}" and ALL their data (measurements, ` +
    `nutrition, activity, sleep, medical records).\n\nThis cannot be undone.\n\n` +
    `Type DELETE to confirm:`);
  if (typed !== 'DELETE') { if (typed !== null) showToast('⚠️', 'Not confirmed — nothing deleted'); return; }
  if (btn) btn.disabled = true;
  const { error } = await sb.rpc('admin_delete_child_permanently', { p_child_id: childId });
  if (error) { showToast('⚠️', 'Could not delete: ' + error.message); if (btn) btn.disabled = false; return; }
  showToast('✅', `"${name}" permanently deleted`);
  loadAndRenderAdminArchivePanel();
}

// Enforce the promised retention countdown (no cron yet — manual).
async function purgeOverdueChildren() {
  if (!confirm('Permanently delete every archived child whose retention countdown has expired?')) return;
  const { data, error } = await sb.rpc('admin_purge_overdue_children');
  if (error) { showToast('⚠️', 'Purge failed: ' + error.message); return; }
  showToast('✅', `Purged ${data ?? 0} overdue child profile${data === 1 ? '' : 's'}`);
  loadAndRenderAdminArchivePanel();
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
  if (usersRes.error) showToast('⚠️', 'Could not load families: ' + usersRes.error.message);

  const auditRows = (!logRes.error && logRes.data) ? logRes.data : [];

  renderAdminUserList();
  renderAdminAuditLog(auditRows);
  renderAdminAuditLog(auditRows.slice(0, 5), 'adminAuditLogPreview');
  await renderAdminOverviewStats();

  await loadAndRenderAdminAIModePanel();
  await loadAndRenderAdminArchivePanel();
}

function setAdminGreeting() {
  const hour = new Date().getHours();
  const timeOfDay = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  const name = (ADMIN.account && ADMIN.account.email) ? ADMIN.account.email.split('@')[0] : 'admin';
  document.getElementById('adminGreeting').textContent = `${timeOfDay}, ${name}`;
}

// Overview answers "what needs me today?", so it carries the things that imply
// an action. The subscription-tier split is NOT repeated here — renderTierChart()
// under Metrics already owns that breakdown.
async function renderAdminOverviewStats() {
  const users = ADMIN.adminUsers || [];
  document.getElementById('statFamilies').textContent = users.length;

  // head:true asks PostgREST for the count only — no rows cross the wire.
  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const [newRes, bugRes] = await Promise.all([
    sb.from('user_accounts').select('*', { count: 'exact', head: true }).gte('created_at', since),
    sb.from('bug_reports').select('*', { count: 'exact', head: true }).in('status', ['new', 'triaged'])
  ]);
  document.getElementById('statNew7d').textContent = newRes.error ? '—' : (newRes.count || 0);
  document.getElementById('statOpenIssues').textContent = bugRes.error ? '—' : (bugRes.count || 0);
}

function setAdminSection(section, btn) {
  document.querySelectorAll('.admin-nav-item').forEach(b => b.classList.remove('active'));
  if (btn) btn.classList.add('active');
  document.querySelectorAll('.admin-section').forEach(s => s.classList.remove('active'));
  document.getElementById('adminSection' + section.charAt(0).toUpperCase() + section.slice(1)).classList.add('active');
  const sidebar = document.getElementById('adminSidebar');
  if (sidebar.classList.contains('mobile-open')) toggleMobileSidebar();
  if (section === 'metrics') loadMetrics();
  if (section === 'codes')   loadCodesSection();
  if (section === 'bugs')    loadBugReports();
  if (section === 'support') loadSupportArticles();
}

// ══════════════════════════════════════════
// BUG REPORTS — user-filed reports (bug_reports table). Readable here
// only under a system_admin session via RLS. Descriptions are user
// input, so everything rendered is HTML-escaped to prevent a report
// from running script in the admin's browser (stored XSS).
// ══════════════════════════════════════════
function escHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

let _bugRows = [];
let _bugFilter = 'open';
let _bugEmails = {};

async function loadBugReports() {
  const { data, error } = await sb.from('bug_reports')
    .select('*').order('created_at', { ascending: false }).limit(200);
  _bugRows = (!error && data) ? data : [];
  // Reporter emails — bug_reports.user_id references auth.users (not
  // user_accounts), so PostgREST can't embed it; batch-map the ids to
  // emails under the admin session instead. This is what lets CS follow
  // up with the person who filed the report.
  const ids = [...new Set(_bugRows.map(r => r.user_id).filter(Boolean))];
  _bugEmails = {};
  if (ids.length) {
    const { data: accs } = await sb.from('user_accounts')
      .select('user_id, email').in('user_id', ids);
    (accs || []).forEach(a => { _bugEmails[a.user_id] = a.email; });
  }
  const nNew = _bugRows.filter(r => r.status === 'new').length;
  const nTri = _bugRows.filter(r => r.status === 'triaged').length;
  const nHigh = _bugRows.filter(r => r.severity === 'high' &&
    (r.status === 'new' || r.status === 'triaged')).length;
  document.getElementById('bugStatNew').textContent = nNew;
  document.getElementById('bugStatTriaged').textContent = nTri;
  document.getElementById('bugStatHigh').textContent = nHigh;
  document.getElementById('bugStatTotal').textContent = _bugRows.length;
  renderBugReports();
}

function setBugFilter(f, btn) {
  _bugFilter = f;
  document.querySelectorAll('#bugFilterSeg .seg-btn').forEach(b => b.classList.remove('active'));
  if (btn) btn.classList.add('active');
  renderBugReports();
}

function renderBugReports() {
  const el = document.getElementById('bugReportsList');
  const rows = _bugFilter === 'open'
    ? _bugRows.filter(r => r.status === 'new' || r.status === 'triaged')
    : _bugRows;
  if (rows.length === 0) {
    el.innerHTML = '<div class="log-list-empty">No reports.</div>';
    return;
  }
  const catLbl = { bug: 'Bug', data_wrong: 'Wrong number', confusing: 'Confusing', idea: 'Idea' };
  const sevColor = { high: 'var(--flag)', medium: 'var(--accent)', low: 'var(--text3)' };
  el.innerHTML = rows.map(r => {
    const when = (r.created_at || '').replace('T', ' ').slice(0, 16);
    const childCtx = r.child_age_years != null
      ? ` · child ${escHtml(r.child_age_years)}y ${escHtml(r.child_sex || '')}` : '';
    const screen = r.context && r.context.active_screen
      ? ` · ${escHtml(r.context.active_screen)}` : '';
    const done = r.status === 'fixed' || r.status === 'wontfix';
    // Reporter identity: email when the account still exists, otherwise
    // a stub — user_id is SET NULL on account deletion by design.
    const repEmail = r.user_id ? _bugEmails[r.user_id] : null;
    const reporter = repEmail || (r.user_id ? 'unknown user' : 'deleted account');
    const followUp = repEmail
      ? ` <a class="btn-link" style="font-size:inherit;" href="mailto:${escHtml(repEmail)}?subject=${encodeURIComponent('GrowSense — about the issue you reported')}">Email reporter</a>`
      : '';
    // Saved fix note — clamped to 10 lines on screen; the 1000-char cap
    // is enforced by the DB CHECK, this is just the display guard.
    const noteBlock = r.admin_note ? `
      <div style="margin-top:8px; padding:8px 10px; background:var(--surface2); border-radius:8px;">
        <div style="font-size:10px; font-weight:700; color:var(--accent); margin-bottom:3px;">FIX NOTE · ${escHtml((r.admin_note_at || '').slice(0, 10))}</div>
        <div style="font-size:12px; line-height:1.45; white-space:pre-wrap; display:-webkit-box; -webkit-line-clamp:10; -webkit-box-orient:vertical; overflow:hidden;">${escHtml(r.admin_note)}</div>
      </div>` : '';
    return `
    <div class="card" style="padding:12px 14px; ${done ? 'opacity:.6;' : ''}">
      <div style="display:flex; justify-content:space-between; gap:10px; align-items:center; margin-bottom:6px;">
        <div style="display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
          <span style="font-weight:700; font-size:12px;">${escHtml(catLbl[r.category] || r.category)}</span>
          <span style="font-size:10.5px; font-weight:700; color:${sevColor[r.severity] || 'var(--text3)'};">${escHtml((r.severity || '').toUpperCase())}</span>
          <span style="font-size:10.5px; color:var(--text3);">v${escHtml(r.app_version)}+${escHtml(r.app_build)} · ${escHtml(r.channel || '')} · ${escHtml(r.locale || '')}</span>
        </div>
        <span style="font-size:10px; color:var(--text3); white-space:nowrap;">${escHtml(when)}</span>
      </div>
      <div style="font-size:12.5px; line-height:1.5; white-space:pre-wrap;">${escHtml(r.description)}</div>
      <div style="font-size:10px; color:var(--text3); margin-top:6px;">status: ${escHtml(r.status)} · by ${escHtml(reporter)}${childCtx}${screen}</div>
      ${noteBlock}
      <div style="display:flex; gap:8px; margin-top:8px; flex-wrap:wrap;">
        <button class="btn-link" onclick="updateBugStatus('${r.report_id}','triaged',this)">Triaged</button>
        <button class="btn-link" onclick="updateBugStatus('${r.report_id}','fixed',this)">Fixed</button>
        <button class="btn-link" style="color:var(--text3);" onclick="updateBugStatus('${r.report_id}','wontfix',this)">Won't fix</button>
        <button class="btn-link" onclick="toggleBugNote('${r.report_id}', true)">${r.admin_note ? 'Edit note' : '+ Fix note'}</button>${followUp}
      </div>
      <div id="bugNoteEd_${r.report_id}" style="display:none; margin-top:8px;">
        <textarea id="bugNoteTa_${r.report_id}" maxlength="1000" rows="4"
          placeholder="Cause + fix, short. Reference the commit for detail. (max 1000 chars)"
          style="width:100%; box-sizing:border-box; background:var(--surface2); color:inherit; border:1px solid var(--surface2); border-radius:8px; padding:8px 10px; font:inherit; font-size:12px; line-height:1.45; resize:vertical;"></textarea>
        <div style="display:flex; justify-content:space-between; align-items:center; margin-top:4px;">
          <span id="bugNoteCt_${r.report_id}" style="font-size:10px; color:var(--text3);"></span>
          <div style="display:flex; gap:10px;">
            <button class="btn-link" style="color:var(--text3);" onclick="toggleBugNote('${r.report_id}', false)">Cancel</button>
            <button class="btn-link" onclick="saveBugNote('${r.report_id}', this)">Save note</button>
          </div>
        </div>
      </div>
    </div>`;
  }).join('');
}

// Inline fix-note editor. The note is the "what caused it / what fixed
// it" record written at close time — capped at 1000 chars by a DB CHECK
// so it stays a summary (long detail belongs in the referenced commit).
function toggleBugNote(id, show) {
  const ed = document.getElementById('bugNoteEd_' + id);
  if (!ed) return;
  if (!show) { ed.style.display = 'none'; return; }
  const r = _bugRows.find(x => x.report_id === id);
  const ta = document.getElementById('bugNoteTa_' + id);
  const ct = document.getElementById('bugNoteCt_' + id);
  ta.value = (r && r.admin_note) || '';
  const upd = () => { ct.textContent = ta.value.length + ' / 1000'; };
  ta.oninput = upd; upd();
  ed.style.display = 'block';
  ta.focus();
}

async function saveBugNote(id, btn) {
  const ta = document.getElementById('bugNoteTa_' + id);
  const text = (ta.value || '').trim().slice(0, 1000);
  if (btn) btn.disabled = true;
  const { error } = await sb.from('bug_reports').update({
    admin_note: text || null,
    admin_note_by: text && ADMIN.account ? ADMIN.account.user_id : null,
    admin_note_at: text ? new Date().toISOString() : null
  }).eq('report_id', id);
  if (error) { showToast('⚠️', 'Could not save note: ' + error.message); if (btn) btn.disabled = false; return; }
  showToast('✅', text ? 'Fix note saved' : 'Fix note cleared');
  await loadBugReports();
}

async function updateBugStatus(id, status, btn) {
  if (btn) btn.disabled = true;
  const { error } = await sb.from('bug_reports').update({ status }).eq('report_id', id);
  if (error) { showToast('⚠️', 'Could not update: ' + error.message); if (btn) btn.disabled = false; return; }
  await loadBugReports();
}

// ══════════════════════════════════════════
// TROUBLESHOOTING LIBRARY (support_articles) — admin-internal knowledge
// base of symptom → fix-ladder articles (Apple-support editorial model:
// one problem per article, steps in escalating order, explicit
// escalation hand-off). Articles are DATA with a status column:
// 'internal' shows only here; flipping to 'public' is the future user-
// menu door (RLS read policy for it already exists in the migration).
// steps is plain text, ONE STEP PER LINE — rendered as an <ol>.
// ══════════════════════════════════════════
let _supportRows = [];
let _supportOpen = null;   // slug of the expanded article

// Browse taxonomy in user-journey order (mirrors the section CHECK in
// 2026-07-22_support_articles_journey.sql). Rows with an unknown/older
// section value fall back to 'technical' at render time.
const SUPPORT_SECTIONS = [
  ['account',   'Account & sign-in'],
  ['children',  'Child profiles & family'],
  ['logging',   'Daily logging'],
  ['estimates', 'Estimates & the calendar'],
  ['growth',    'Growth charts & analytics'],
  ['medical',   'Medical records'],
  ['premium',   'Premium & codes'],
  ['devices',   'Wearables & sync'],
  ['technical', 'App & technical'],
  // 'dev' is the operator runbook — CONFIDENTIAL-internal. A DB CHECK
  // (support_articles_dev_never_public) makes status='public' impossible
  // for it; the save guard below is just the friendly front door.
  ['dev',       'Dev & internal ops — never public']
];

async function loadSupportArticles() {
  const { data, error } = await sb.from('support_articles').select('*').order('title');
  if (error) {
    showToast('⚠️', 'Could not load articles: ' + error.message);
    _supportRows = [];
  } else {
    _supportRows = data || [];
  }
  renderSupportList();
}

function renderSupportList() {
  const el = document.getElementById('supportList');
  const q = (document.getElementById('supportSearch').value || '').trim().toLowerCase();
  const rows = _supportRows.filter(r =>
    !q || [r.title, r.symptom, r.steps, r.slug].join('\n').toLowerCase().includes(q));
  if (rows.length === 0) {
    el.innerHTML = '<div class="log-list-empty">' + (q
      ? 'No articles match.'
      : 'No articles yet — run migrations/2026-07-22_support_articles.sql in the Supabase SQL editor, then reload.') + '</div>';
    return;
  }
  const known = SUPPORT_SECTIONS.map(s => s[0]);
  el.innerHTML = SUPPORT_SECTIONS.map(([sec, label]) => {
    const group = rows.filter(r =>
      (known.includes(r.section) ? r.section : 'technical') === sec);
    if (group.length === 0) return '';   // hide empty sections (incl. under search)
    return `
    <div style="font-size:10.5px; font-weight:700; letter-spacing:0.06em; text-transform:uppercase; color:var(--text2); margin:6px 2px 0;">${label}</div>`
      + group.map(r => renderSupportCard(r)).join('');
  }).join('');
}

function renderSupportCard(r) {
    const open = _supportOpen === r.slug;
    const statusChip = r.status === 'public'
      ? '<span style="font-size:10px; font-weight:700; color:var(--accent);">PUBLIC</span>'
      : '<span style="font-size:10px; font-weight:700; color:var(--text3);">INTERNAL</span>';
    const platChip = r.platform !== 'all'
      ? `<span style="font-size:10px; font-weight:700; color:var(--measured);">${escHtml(r.platform.toUpperCase())}</span>` : '';
    let body = '';
    if (open) {
      const steps = (r.steps || '').split('\n').map(s => s.trim()).filter(Boolean)
        .map(s => `<li style="margin-bottom:6px;">${escHtml(s)}</li>`).join('');
      const esc = r.escalation ? `
        <div style="margin-top:8px; padding:8px 10px; background:var(--surface2); border-radius:8px; font-size:12px; line-height:1.5;">
          <span style="font-weight:700; font-size:10.5px; color:var(--text2);">IF THAT DIDN'T WORK</span><br>${escHtml(r.escalation)}
        </div>` : '';
      body = `
      <ol style="margin:10px 0 0; padding-left:20px; font-size:12.5px; line-height:1.55;">${steps}</ol>${esc}
      <div style="display:flex; gap:10px; margin-top:8px; align-items:center;">
        <button class="btn-link" onclick="editSupportArticle('${escHtml(r.slug)}')">Edit</button>
        <span style="font-size:10px; color:var(--text3);">updated ${escHtml((r.updated_at || '').slice(0, 10))}</span>
      </div>`;
    }
    return `
    <div style="background:var(--surface2); border-radius:12px; padding:12px 14px;">
      <div style="cursor:pointer;" onclick="toggleSupportArticle('${escHtml(r.slug)}')">
        <div style="display:flex; justify-content:space-between; gap:10px; align-items:baseline;">
          <span style="font-weight:700; font-size:13px;">${escHtml(r.title)}</span>
          <span style="display:flex; gap:8px; white-space:nowrap;">${platChip}${statusChip}</span>
        </div>
        <div style="font-size:11.5px; color:var(--text2); margin-top:3px;">${escHtml(r.symptom)}</div>
      </div>${body}
    </div>`;
}

function toggleSupportArticle(slug) {
  _supportOpen = _supportOpen === slug ? null : slug;
  renderSupportList();
}

function editSupportArticle(slug) {
  const r = slug ? _supportRows.find(x => x.slug === slug) : null;
  const wrap = document.getElementById('supportEditorWrap');
  const taStyle = 'width:100%; box-sizing:border-box; background:var(--surface2); color:inherit; border:1px solid var(--border2); border-radius:8px; padding:8px 10px; font:inherit; font-size:12px; line-height:1.45; resize:vertical;';
  wrap.innerHTML = `
    <div style="background:var(--surface2); border-radius:12px; padding:14px; display:flex; flex-direction:column; gap:10px;">
      <div style="font-weight:700; font-size:12px;">${r ? 'Edit article' : 'New article'}</div>
      <input class="text-input" id="supTitle" maxlength="160" placeholder="Title — the symptom as a user would say it" value="${r ? escHtml(r.title) : ''}">
      <input class="text-input" id="supSlug" maxlength="80" placeholder="slug-like-this (lowercase, hyphens)" value="${r ? escHtml(r.slug) : ''}">
      <input class="text-input" id="supSymptom" maxlength="400" placeholder="One line: what the user sees" value="${r ? escHtml(r.symptom) : ''}">
      <div style="display:flex; gap:10px;">
        <select class="text-input" id="supSection" style="flex:1.4;">
          ${SUPPORT_SECTIONS.map(([sec, label]) => `<option value="${sec}"${(r ? r.section : 'technical') === sec ? ' selected' : ''}>${label}</option>`).join('')}
        </select>
        <select class="text-input" id="supPlatform" style="flex:1;">
          ${['all', 'web', 'ios', 'android'].map(p => `<option value="${p}"${r && r.platform === p ? ' selected' : ''}>${p}</option>`).join('')}
        </select>
        <select class="text-input" id="supStatus" style="flex:1;">
          <option value="internal"${!r || r.status === 'internal' ? ' selected' : ''}>internal (admin only)</option>
          <option value="public"${r && r.status === 'public' ? ' selected' : ''}>public (user menu, later)</option>
        </select>
      </div>
      <textarea id="supSteps" rows="8" maxlength="4000" placeholder="Fix ladder — ONE STEP PER LINE, easiest first" style="${taStyle}">${r ? escHtml(r.steps) : ''}</textarea>
      <textarea id="supEscalation" rows="2" maxlength="1000" placeholder="If that didn't work — what to collect / where it goes (optional)" style="${taStyle}">${r && r.escalation ? escHtml(r.escalation) : ''}</textarea>
      <div style="display:flex; justify-content:space-between; align-items:center;">
        <span>${r ? `<button class="btn-link" style="color:var(--flag);" onclick="deleteSupportArticle('${escHtml(r.id)}')">Delete</button>` : ''}</span>
        <div style="display:flex; gap:12px;">
          <button class="btn-link" style="color:var(--text3);" onclick="closeSupportEditor()">Cancel</button>
          <button class="btn-link" onclick="saveSupportArticle(${r ? `'${escHtml(r.id)}'` : 'null'})">Save article</button>
        </div>
      </div>
    </div>`;
  wrap.classList.remove('hidden');
  document.getElementById('supTitle').focus();
}

function closeSupportEditor() {
  const wrap = document.getElementById('supportEditorWrap');
  wrap.classList.add('hidden');
  wrap.innerHTML = '';
}

async function saveSupportArticle(id) {
  const val = x => (document.getElementById(x).value || '').trim();
  const row = {
    slug: val('supSlug'), title: val('supTitle'), symptom: val('supSymptom'),
    section: val('supSection'), platform: val('supPlatform'), status: val('supStatus'),
    steps: val('supSteps'), escalation: val('supEscalation') || null,
    updated_at: new Date().toISOString(),
    updated_by: ADMIN.account ? ADMIN.account.user_id : null
  };
  if (!row.title || !row.symptom || !row.steps) { showToast('⚠️', 'Title, symptom, and steps are required'); return; }
  if (!/^[a-z0-9][a-z0-9-]{1,79}$/.test(row.slug)) { showToast('⚠️', 'Slug must be lowercase letters, digits, and hyphens'); return; }
  if (row.section === 'dev' && row.status === 'public') { showToast('⚠️', 'Dev articles are internal-only and can never be public'); return; }
  const { error } = id
    ? await sb.from('support_articles').update(row).eq('id', id)
    : await sb.from('support_articles').insert(row);
  if (error) { showToast('⚠️', 'Could not save: ' + error.message); return; }
  showToast('✅', 'Article saved');
  closeSupportEditor();
  _supportOpen = row.slug;
  await loadSupportArticles();
}

async function deleteSupportArticle(id) {
  if (!confirm('Delete this article? This cannot be undone.')) return;
  const { error } = await sb.from('support_articles').delete().eq('id', id);
  if (error) { showToast('⚠️', 'Could not delete: ' + error.message); return; }
  showToast('✅', 'Article deleted');
  closeSupportEditor();
  await loadSupportArticles();
}

// ══════════════════════════════════════════
// METRICS — signup trends, AI usage, tier distribution
// All queries run client-side against Supabase directly (data is
// already loaded for users; AI usage is a new query). Charts are
// pure HTML/CSS bar charts — no external charting library needed.
// ══════════════════════════════════════════

let _metricsLoaded = false;

async function loadMetrics() {
  if (_metricsLoaded) return;
  _metricsLoaded = true;

  // Run all three in parallel
  const [signupRes, aiRes] = await Promise.all([
    sb.from('user_accounts')
      .select('created_at, subscription_tier')
      .order('created_at', { ascending: false })
      .limit(500),
    sb.from('live_ai_usage_monthly')
      .select('year_month, call_count')
      .order('year_month', { ascending: false })
      .limit(100)
  ]);

  renderSignupChart(signupRes.data || []);
  renderAIUsageChart(aiRes.data || []);
  renderTierChart(ADMIN.adminUsers || []);
}

function renderSignupChart(users) {
  const el = document.getElementById('metricsSignupChart');
  if (!el) return;

  // Group signups by ISO week (Mon–Sun) for last 8 weeks
  const now = new Date();
  const weeks = [];
  for (let i = 7; i >= 0; i--) {
    const d = new Date(now);
    d.setDate(now.getDate() - i * 7);
    const weekStart = new Date(d);
    weekStart.setDate(d.getDate() - ((d.getDay() + 6) % 7)); // Monday
    weekStart.setHours(0,0,0,0);
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekStart.getDate() + 7);
    const label = weekStart.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
    const count = users.filter(u => {
      const t = new Date(u.created_at);
      return t >= weekStart && t < weekEnd;
    }).length;
    weeks.push({ label, count });
  }

  const max = Math.max(...weeks.map(w => w.count), 1);
  const bars = weeks.map(w => {
    const pct = Math.round((w.count / max) * 96);
    return `<div class="metrics-bar-col">
      <span class="metrics-bar-val">${w.count || ''}</span>
      <div class="metrics-bar" style="height:${pct}px;"></div>
      <span class="metrics-bar-lbl">${w.label}</span>
    </div>`;
  }).join('');

  el.innerHTML = users.length === 0
    ? '<div class="metrics-empty">No signup data yet.</div>'
    : `<div class="metrics-bar-chart">${bars}</div>`;
}

function renderAIUsageChart(rows) {
  const el = document.getElementById('metricsAIChart');
  if (!el) return;

  if (rows.length === 0) {
    el.innerHTML = '<div class="metrics-empty">No live AI usage recorded yet.</div>';
    return;
  }

  // Aggregate by month
  const byMonth = {};
  rows.forEach(r => {
    byMonth[r.year_month] = (byMonth[r.year_month] || 0) + r.call_count;
  });

  // Last 6 months
  const months = Object.entries(byMonth)
    .sort((a, b) => a[0].localeCompare(b[0]))
    .slice(-6);

  const max = Math.max(...months.map(m => m[1]), 1);
  const bars = months.map(([ym, count]) => {
    const [y, m] = ym.split('-');
    const label = new Date(+y, +m - 1, 1).toLocaleDateString('en-GB', { month: 'short', year: '2-digit' });
    const pct = Math.round((count / max) * 96);
    return `<div class="metrics-bar-col">
      <span class="metrics-bar-val">${count}</span>
      <div class="metrics-bar ai-bar" style="height:${pct}px;"></div>
      <span class="metrics-bar-lbl">${label}</span>
    </div>`;
  }).join('');

  el.innerHTML = `<div class="metrics-bar-chart">${bars}</div>`;
}

function renderTierChart(users) {
  const el = document.getElementById('metricsTierChart');
  if (!el) return;

  const tiers = ['free', 'premium', 'pro'];
  const counts = { free: 0, premium: 0, pro: 0 };
  (users || []).forEach(u => { if (counts[u.subscription_tier] !== undefined) counts[u.subscription_tier]++; });

  const total = Object.values(counts).reduce((a, b) => a + b, 0) || 1;
  const max = Math.max(...Object.values(counts), 1);

  const bars = tiers.map(t => {
    const pct = Math.round((counts[t] / max) * 96);
    const share = Math.round((counts[t] / total) * 100);
    return `<div class="metrics-bar-col">
      <span class="metrics-bar-val">${counts[t]}</span>
      <div class="metrics-bar tier-${t}" style="height:${pct}px;" title="${share}%"></div>
      <span class="metrics-bar-lbl">${t} (${share}%)</span>
    </div>`;
  }).join('');

  el.innerHTML = total === 0
    ? '<div class="metrics-empty">No user data.</div>'
    : `<div class="metrics-bar-chart" style="max-width:240px;">${bars}</div>`;
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

// ══════════════════════════════════════════════════════════════════
// CODES — Activation code management
// ══════════════════════════════════════════════════════════════════

let _allCodes      = [];   // full list fetched from DB
let _codesLoaded   = false;
let _appConfig     = {};   // app_config key→value map

// ── Load everything needed for the Codes section ──────────────────
async function loadCodesSection() {
  if (_codesLoaded) { renderCodesTable(); return; }
  await Promise.all([loadAllCodes(), loadAppConfig()]);
  _codesLoaded = true;
}

async function loadAllCodes() {
  const { data, error } = await sb
    .from('activation_codes')
    .select('*, redeemer:redeemed_by(email)')
    .order('created_at', { ascending: false });

  if (error) { console.error('[Codes]', error); return; }
  _allCodes = data || [];
  updateCodeStats();
  populateBatchFilter();
  renderCodesTable();
}

async function loadAppConfig() {
  const { data } = await sb.from('app_config').select('key, value');
  _appConfig = {};
  (data || []).forEach(r => { _appConfig[r.key] = r.value; });

  // Redemption enabled toggle
  const enabled = _appConfig['redemption_enabled'] === 'true';
  const seg = document.getElementById('redemptionEnabledSeg');
  if (seg) {
    seg.querySelectorAll('.seg-btn').forEach((b, i) => {
      b.classList.toggle('active', i === (enabled ? 0 : 1));
    });
  }

  // Free measurement limit
  const limitEl = document.getElementById('freeMeasurementLimit');
  if (limitEl) limitEl.value = _appConfig['free_measurement_limit'] || '5';
}

// ── Stats strip ───────────────────────────────────────────────────
function updateCodeStats() {
  const total     = _allCodes.length;
  const redeemed  = _allCodes.filter(c => c.redeemed_by).length;
  const available = _allCodes.filter(c => !c.redeemed_by && codeStatus(c) === 'available').length;
  const batches   = new Set(_allCodes.map(c => c.batch_name).filter(Boolean)).size;

  document.getElementById('codeStatTotal').textContent     = total;
  document.getElementById('codeStatAvailable').textContent = available;
  document.getElementById('codeStatRedeemed').textContent  = redeemed;
  document.getElementById('codeStatBatches').textContent   = batches;
}

function codeStatus(c) {
  if (c.redeemed_by) return 'redeemed';
  if (c.code_expires_at && new Date(c.code_expires_at) < new Date()) return 'expired';
  return 'available';
}

// ── Batch filter dropdown ─────────────────────────────────────────
function populateBatchFilter() {
  const sel = document.getElementById('codeFilterBatch');
  if (!sel) return;
  const batches = [...new Set(_allCodes.map(c => c.batch_name).filter(Boolean))].sort();
  sel.innerHTML = '<option value="">All batches</option>' +
    batches.map(b => `<option value="${b}">${b}</option>`).join('');
}

// ── Render table ──────────────────────────────────────────────────
function renderCodesTable() {
  const search      = (document.getElementById('codeSearch')?.value || '').toLowerCase();
  const batchFilter = document.getElementById('codeFilterBatch')?.value || '';
  const statFilter  = document.getElementById('codeFilterStatus')?.value || '';

  let filtered = _allCodes.filter(c => {
    const st = codeStatus(c);
    if (batchFilter && c.batch_name !== batchFilter) return false;
    if (statFilter  && st !== statFilter)            return false;
    if (search) {
      const hay = (c.code + ' ' + (c.batch_name||'') + ' ' + (c.redeemer?.email||'')).toLowerCase();
      if (!hay.includes(search)) return false;
    }
    return true;
  });

  const tbody = document.getElementById('codesTableBody');
  if (!tbody) return;

  if (!filtered.length) {
    tbody.innerHTML = '<tr><td colspan="8" style="text-align:center; color:var(--text3); padding:20px;">No codes match the current filter.</td></tr>';
    document.getElementById('codesTableMeta').textContent = '';
    return;
  }

  tbody.innerHTML = filtered.map(c => {
    const st     = codeStatus(c);
    const stPill = `<span class="status-pill status-${st}">${st}</span>`;
    const redAt  = c.redeemed_at
      ? new Date(c.redeemed_at).toLocaleDateString('en-GB', { day:'numeric', month:'short', year:'numeric' })
      : '—';
    const redBy  = c.redeemer?.email
      ? `<span style="font-size:11px;">${c.redeemer.email}</span>` : '—';
    const tierBadge = c.tier === 'pro'
      ? '👑 Pro' : '⭐ Premium';
    const actions = st === 'available'
      ? `<button class="code-action-btn danger" onclick="revokeCode('${c.code_id}')">Revoke</button>`
      : st === 'redeemed'
      ? `<button class="code-action-btn" onclick="viewCodeDetail('${c.code_id}')">Detail</button>`
      : '—';

    return `<tr>
      <td><span class="code-badge" onclick="copyCode('${c.code}')" title="Click to copy">${c.code}</span></td>
      <td style="font-size:11px; color:var(--text3);">${c.batch_name || '—'}</td>
      <td style="font-size:12px;">${tierBadge}</td>
      <td style="font-size:12px;">${c.duration_days}d</td>
      <td>${stPill}</td>
      <td>${redBy}</td>
      <td style="font-size:11px; color:var(--text3);">${redAt}</td>
      <td>${actions}</td>
    </tr>`;
  }).join('');

  document.getElementById('codesTableMeta').textContent =
    `Showing ${filtered.length} of ${_allCodes.length} codes`;
}

// ── Copy code to clipboard ────────────────────────────────────────
function copyCode(code) {
  navigator.clipboard.writeText(code).then(() => {
    showAdminToast('✓', `${code} copied`);
  });
}

// ── Revoke an available code ──────────────────────────────────────
async function revokeCode(codeId) {
  if (!confirm('Revoke this code? It will no longer be redeemable.')) return;
  // Set code_expires_at to now — the Edge Function will reject it as expired
  const { error } = await sb
    .from('activation_codes')
    .update({ code_expires_at: new Date().toISOString() })
    .eq('code_id', codeId);
  if (error) { showAdminToast('⚠️', 'Revoke failed: ' + error.message); return; }
  showAdminToast('✓', 'Code revoked');
  _codesLoaded = false;
  await loadAllCodes();
}

// ── View detail of a redeemed code ───────────────────────────────
function viewCodeDetail(codeId) {
  const c = _allCodes.find(x => x.code_id === codeId);
  if (!c) return;
  const redAt = c.redeemed_at
    ? new Date(c.redeemed_at).toLocaleString('en-GB') : 'unknown';
  alert(
    `Code: ${c.code}\n` +
    `Batch: ${c.batch_name || '—'}\n` +
    `Tier: ${c.tier} · ${c.duration_days} days\n` +
    `Redeemed by: ${c.redeemer?.email || 'unknown'}\n` +
    `Redeemed at: ${redAt}\n` +
    `IP: ${c.redeemed_ip || 'not logged'}`
  );
}

// ── Generate new batch ────────────────────────────────────────────
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function genCode() {
  let p1 = '', p2 = '';
  for (let i = 0; i < 4; i++) p1 += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  for (let i = 0; i < 4; i++) p2 += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  return `GROW-${p1}-${p2}`;
}

async function generateCodeBatch() {
  const name     = (document.getElementById('newBatchName')?.value || '').trim();
  const tier     = document.getElementById('newBatchTier')?.value || 'premium';
  const duration = parseInt(document.getElementById('newBatchDuration')?.value || '365');
  const count    = parseInt(document.getElementById('newBatchCount')?.value || '50');
  const btn      = document.getElementById('generateBatchBtn');
  const result   = document.getElementById('generateBatchResult');

  if (!name) { showAdminToast('⚠️', 'Enter a batch name'); return; }
  if (count < 1 || count > 1000) { showAdminToast('⚠️', 'Count must be 1–1000'); return; }

  btn.textContent = 'Generating…'; btn.disabled = true;
  result.textContent = '';

  // Generate unique codes (check against existing)
  const existingCodes = new Set(_allCodes.map(c => c.code));
  const newCodes = [];
  let attempts = 0;
  while (newCodes.length < count && attempts < count * 10) {
    const code = genCode();
    if (!existingCodes.has(code)) { newCodes.push(code); existingCodes.add(code); }
    attempts++;
  }

  if (newCodes.length < count) {
    showAdminToast('⚠️', 'Could not generate enough unique codes — try a smaller count');
    btn.textContent = 'Generate codes'; btn.disabled = false;
    return;
  }

  // Insert in batches of 100
  const rows = newCodes.map(code => ({ code, tier, duration_days: duration, batch_name: name }));
  let inserted = 0;
  for (let i = 0; i < rows.length; i += 100) {
    const { error } = await sb.from('activation_codes').insert(rows.slice(i, i + 100));
    if (error) { showAdminToast('⚠️', 'Insert error: ' + error.message); break; }
    inserted += Math.min(100, rows.length - i);
  }

  btn.textContent = 'Generate codes'; btn.disabled = false;
  result.textContent = `✓ ${inserted} codes generated for batch "${name}"`;
  showAdminToast('✅', `${inserted} ${tier} codes generated`);

  // Refresh list
  _codesLoaded = false;
  await loadAllCodes();
  document.getElementById('newBatchName').value = '';
}

// ── App config updates ────────────────────────────────────────────
async function updateAppConfig(key, value) {
  const { error } = await sb
    .from('app_config')
    .upsert({ key, value: String(value), updated_at: new Date().toISOString() });
  if (error) { showAdminToast('⚠️', 'Config update failed'); return; }
  _appConfig[key] = String(value);
  showAdminToast('✅', `${key} updated`);
}

async function setRedemptionEnabled(enabled, btn) {
  document.querySelectorAll('#redemptionEnabledSeg .seg-btn').forEach((b, i) => {
    b.classList.toggle('active', i === (enabled ? 0 : 1));
  });
  await updateAppConfig('redemption_enabled', enabled ? 'true' : 'false');
}

// ── Export CSV ────────────────────────────────────────────────────
function exportCodesToCSV() {
  const search      = (document.getElementById('codeSearch')?.value || '').toLowerCase();
  const batchFilter = document.getElementById('codeFilterBatch')?.value || '';
  const statFilter  = document.getElementById('codeFilterStatus')?.value || '';

  const filtered = _allCodes.filter(c => {
    const st = codeStatus(c);
    if (batchFilter && c.batch_name !== batchFilter) return false;
    if (statFilter  && st !== statFilter)            return false;
    if (search) {
      const hay = (c.code + ' ' + (c.batch_name||'') + ' ' + (c.redeemer?.email||'')).toLowerCase();
      if (!hay.includes(search)) return false;
    }
    return true;
  });

  const header = ['Code', 'Batch', 'Tier', 'Duration (days)', 'Status', 'Redeemed by', 'Redeemed at', 'IP'];
  const rows   = filtered.map(c => [
    c.code,
    c.batch_name || '',
    c.tier,
    c.duration_days,
    codeStatus(c),
    c.redeemer?.email || '',
    c.redeemed_at ? new Date(c.redeemed_at).toISOString().split('T')[0] : '',
    c.redeemed_ip || '',
  ]);

  const csv = [header, ...rows].map(r => r.map(v => `"${v}"`).join(',')).join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url  = URL.createObjectURL(blob);
  const a    = Object.assign(document.createElement('a'), {
    href: url,
    download: `growsense_codes_${new Date().toISOString().split('T')[0]}.csv`,
  });
  a.click();
  URL.revokeObjectURL(url);
  showAdminToast('✅', `${filtered.length} codes exported`);
}

// ── Toast (admin version — uses existing toast element) ───────────
function showAdminToast(icon, msg) {
  const t = document.getElementById('toast');
  if (!t) return;
  document.getElementById('toastIcon').textContent = icon;
  document.getElementById('toastMsg').textContent  = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 3000);
}
