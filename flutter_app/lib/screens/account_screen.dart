import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_meta.dart';
import '../app_state.dart';
import '../export/download.dart';
import '../export/visit_pdf.dart';
import '../i18n.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/gs_icons.dart';
import 'bug_report_screen.dart';
import 'devices_screen.dart';
import 'medical_references_screen.dart';
import 'settings_modules.dart';
import 'welcome_screen.dart';
import 'whats_new_screen.dart';

/// Account & settings — pushed from the top-bar avatar. Uses the same
/// account.* locale keys as the PWA's account screen. Child editing
/// stays in the web app for now; this surfaces identity, language,
/// and sign-out.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '—';

    // Which sign-in method(s) this account uses — answers the common
    // "did I sign up with Google or Apple?" question.
    final providers = <String>{};
    final pm = user?.appMetadata['providers'];
    if (pm is List) providers.addAll(pm.map((e) => e.toString()));
    final pOne = user?.appMetadata['provider'];
    if (pOne is String) providers.add(pOne);
    for (final id in user?.identities ?? const []) {
      providers.add(id.provider);
    }
    String providerLabel(String p) => switch (p) {
      'google' => 'Google',
      'apple' => 'Apple',
      'email' => t('flutter.auth.email_pw', 'Email & password'),
      _ => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1),
    };
    final signInVia = providers.isEmpty
        ? null
        : providers.map(providerLabel).join(' · ');
    IconData providerIcon() {
      if (providers.contains('google')) return Icons.g_mobiledata;
      if (providers.contains('apple')) return Icons.apple;
      return Icons.mail_outline;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t('account.title', 'Account & settings'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _Card(
                children: [
                  Text(
                    t('account.signed_in_as', 'Signed in as'),
                    style: const TextStyle(fontSize: 11, color: GsColors.text3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (signInVia != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(providerIcon(), size: 15, color: GsColors.text2),
                        const SizedBox(width: 5),
                        Text(
                          t(
                            'flutter.account.signin_via',
                            'Signed in with {p}',
                            {'p': signInVia},
                          ),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: GsColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                children: [
                  Text(
                    t('account.children.title', 'Children profiles'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: GsColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (appState.children.isEmpty)
                    Text(
                      t('flutter.no_children'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: GsColors.text3,
                      ),
                    )
                  else
                    for (final c in appState.children)
                      InkWell(
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: GsColors.surface,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(GsRadius.lg),
                            ),
                          ),
                          builder: (_) => _ChildEditorSheet(
                            appState: appState,
                            i18n: i18n,
                            child: c,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: GsColors.accentLight,
                                child: Text(
                                  ((c['avatar'] as String?) ??
                                          (c['name'] as String? ?? '?'))
                                      .characters
                                      .first
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: GsColors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  c['name'] as String? ?? '',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                c['date_of_birth'] as String? ?? '',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: GsColors.text3,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: GsColors.text3,
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                  // Add another child (limit enforced in AppState: tier
                  // limit from subscription_tier_limits, hard cap 4)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AddChildScreen(appState: appState, i18n: i18n),
                      ),
                    ),
                    icon: const Icon(Icons.person_add_alt, size: 16),
                    label: Text(
                      t('flutter.child.add_btn', 'Add another child'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              // Subscription + activation-code UI is hidden on iOS (App
              // Store Guideline 3.1.1 — no paid surface outside IAP).
              if (kShowPaidUi) ...[
                const SizedBox(height: 12),
                _SubscriptionCard(appState: appState, i18n: i18n),
              ],
              const SizedBox(height: 12),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ShareChildScreen(appState: appState, i18n: i18n),
                  ),
                ),
                child: _Card(
                  children: [
                    Row(
                      children: [
                        const GsIcon('share', size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t('flutter.share.title', 'Share with a doctor'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: GsColors.accent,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: GsColors.text3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        DevicesScreen(appState: appState, i18n: i18n),
                  ),
                ),
                child: _Card(
                  children: [
                    Row(
                      children: [
                        const GsIcon('watch', size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t('flutter.dev.title', 'Devices & sensors'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: GsColors.accent,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: GsColors.text3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReminderSettingsScreen(i18n: i18n),
                  ),
                ),
                child: _Card(
                  children: [
                    Row(
                      children: [
                        const GsIcon('bell', size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t('flutter.rem.title', 'Reminders'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: GsColors.accent,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: GsColors.text3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // CSV export writes a file — only implemented on web (native
              // download shows a "web app" message), so hide the tile on iOS
              // to avoid a dead-end / web steering. Guideline 3.1.1 / 2.1.
              if (!kIsApplePhone) ...[
                const SizedBox(height: 12),
                _ExportTile(appState: appState, i18n: i18n),
              ],
              // Visit-summary PDF is a Premium feature — hidden on iOS for
              // v1 (returns as a free/IAP feature later). Guideline 3.1.1.
              if (kShowPaidUi) ...[
                const SizedBox(height: 12),
                _VisitPdfTile(appState: appState, i18n: i18n),
              ],
              const SizedBox(height: 12),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WelcomeScreen(i18n: i18n, aboutMode: true),
                  ),
                ),
                child: _Card(
                  children: [
                    Row(
                      children: [
                        const GsIcon('about', size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t('flutter.welcome.about', 'About GrowSense'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: GsColors.accent,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: GsColors.text3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Support & legal — the standard set every consumer health
              // app ships (WHOOP/Google Health parity): contact, privacy,
              // terms, and an account-deletion path.
              _Card(
                children: [
                  Text(
                    t('flutter.legal.title', 'Support & legal'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: GsColors.accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _LinkRow(
                    icon: Icons.support_agent,
                    label: t('flutter.legal.support', 'Contact support'),
                    onTap: () => launchUrl(
                      Uri.parse(
                        'mailto:contact@growsense.life?subject=GrowSense%20support',
                      ),
                    ),
                  ),
                  _LinkRow(
                    icon: Icons.privacy_tip_outlined,
                    label: t('flutter.legal.privacy', 'Privacy policy'),
                    onTap: () => launchUrl(
                      Uri.parse('https://www.growsense.life/privacy'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  _LinkRow(
                    icon: Icons.description_outlined,
                    label: t('flutter.legal.terms', 'Terms of use'),
                    onTap: () => launchUrl(
                      Uri.parse('https://www.growsense.life/terms'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  _LinkRow(
                    icon: Icons.bug_report_outlined,
                    label: t('flutter.legal.report_bug', 'Report a bug'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            BugReportScreen(appState: appState, i18n: i18n),
                      ),
                    ),
                  ),
                  _LinkRow(
                    icon: Icons.menu_book_outlined,
                    label: t('flutter.legal.references',
                        'Medical information & sources'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MedicalReferencesScreen(i18n: i18n),
                      ),
                    ),
                  ),
                  _LinkRow(
                    icon: Icons.delete_outline,
                    label: t('flutter.legal.delete', 'Delete account'),
                    color: GsColors.flag,
                    onTap: () =>
                        _confirmAndDeleteAccount(context, appState, i18n),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                children: [
                  Text(
                    t('flutter.units.title', 'Units'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: GsColors.accent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final u in const [
                        ('metric', 'cm · kg'),
                        ('imperial', 'in · lb'),
                      ])
                        GestureDetector(
                          onTap: () => appState.setUnits(u.$1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: appState.units == u.$1
                                  ? GsColors.accent
                                  : GsColors.surface2,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${t('flutter.units.${u.$1}', u.$1 == 'metric' ? 'Metric' : 'Imperial')} · ${u.$2}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: appState.units == u.$1
                                    ? Colors.white
                                    : GsColors.text2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t(
                      'flutter.units.note',
                      'Growth charts stay in WHO metric units.',
                    ),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: GsColors.text3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                children: [
                  Text(
                    t('account.language', 'Language'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: GsColors.accent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListenableBuilder(
                    listenable: i18n,
                    builder: (context, _) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in supportedLanguages.entries)
                          GestureDetector(
                            onTap: () => i18n.setLanguage(entry.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: i18n.code == entry.key
                                    ? GsColors.accent
                                    : GsColors.surface2,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                entry.value,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: i18n.code == entry.key
                                      ? Colors.white
                                      : GsColors.text2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WhatsNewScreen(i18n: i18n)),
                ),
                child: _Card(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('flutter.account.version', 'App version'),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: GsColors.text2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                versionStamp,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          t('flutter.whatsnew.link', "What's new"),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: GsColors.accent,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: GsColors.text3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: GsColors.flag,
                  side: const BorderSide(color: GsColors.flag),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GsRadius.md),
                  ),
                ),
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  appState.reset();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(
                  t('account.sign_out_btn', 'Sign out'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// In-app account deletion — required by App Store Guideline 5.1.1(v)
/// (a mailto: link is no longer accepted). Confirms, then calls the
/// `delete-account` Edge Function, which removes the user's data and
/// their auth user via the service role. On success we sign out and
/// pop back to the auth screen. Fails safe: a failed delete never signs
/// the user out as if it succeeded, and if the function isn't deployed yet
/// the user just sees a retry/email message.
Future<void> _confirmAndDeleteAccount(
    BuildContext context, AppState appState, I18n i18n) async {
  final t = i18n.t;
  final messenger = ScaffoldMessenger.of(context);
  final rootNav = Navigator.of(context, rootNavigator: true);
  final email = Supabase.instance.client.auth.currentUser?.email ?? '';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('flutter.delete.title', 'Delete your account?')),
      content: Text(t(
          'flutter.delete.body',
          'This permanently deletes your GrowSense account ({email}) and all of your children’s data. This cannot be undone.',
          {'email': email})),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel', 'Cancel'))),
        TextButton(
            style: TextButton.styleFrom(foregroundColor: GsColors.flag),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('flutter.delete.confirm', 'Delete everything'))),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final res =
        await Supabase.instance.client.functions.invoke('delete-account');
    if (res.status != 200) {
      throw Exception('delete-account returned ${res.status}');
    }
    await Supabase.instance.client.auth.signOut();
    appState.reset();
    rootNav.pop(); // dismiss the spinner
    rootNav.pop(); // close the account screen → AuthGate shows sign-in
    messenger.showSnackBar(SnackBar(
        content:
            Text(t('flutter.delete.done', 'Your account has been deleted.'))));
  } catch (_) {
    rootNav.pop(); // dismiss the spinner
    messenger.showSnackBar(SnackBar(
        backgroundColor: GsColors.flag,
        content: Text(t('flutter.delete.error',
            'Could not delete your account. Please try again, or email contact@growsense.life.'))));
  }
}

/// Subscription status — tier badge, expiry, and the free-tier usage
/// counters the PWA gates on (user_accounts row).
class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final acct = appState.account;
    final tier = (acct?['subscription_tier'] as String?) ?? 'free';
    final expires = acct?['tier_expires_at'] as String?;
    final isPaid = tier == 'premium' || tier == 'pro';
    final tierLabel = switch (tier) {
      'premium' => 'Premium',
      'pro' => 'Pro',
      _ => t('flutter.sub.free', 'Free'),
    };
    final measurementsUsed =
        (acct?['total_measurements_logged'] as num?)?.toInt() ?? 0;
    final aiUsed = (acct?['ai_questions_this_month'] as num?)?.toInt() ?? 0;

    return _Card(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              t('flutter.sub.title', 'Subscription'),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: GsColors.accent,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isPaid ? GsColors.estimatedLight : GsColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: isPaid
                    ? Border.all(
                        color: GsColors.estimated.withValues(alpha: 0.5),
                      )
                    : null,
              ),
              child: Text(
                tierLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isPaid ? GsColors.estimatedDark : GsColors.text2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (isPaid && expires != null)
          _InfoRow(
            label: t('flutter.sub.expires', 'Valid until'),
            value: expires.split('T').first,
          ),
        if (!isPaid) ...[
          _InfoRow(
            label: t(
              'flutter.sub.measurements_used',
              'Measurements used (lifetime)',
            ),
            value: '$measurementsUsed / 5',
          ),
          _InfoRow(
            label: t('flutter.sub.ai_used', 'AI questions this month'),
            value: '$aiUsed / 3',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t(
                'flutter.sub.history_30d',
                'History window: last 30 days on Free',
              ),
              style: const TextStyle(fontSize: 10.5, color: GsColors.text3),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          t(
            'flutter.sub.manage_web',
            'Upgrade & billing are managed in the web app.',
          ),
          style: const TextStyle(fontSize: 10.5, color: GsColors.text3),
        ),
        const SizedBox(height: 10),
        _RedeemRow(appState: appState, i18n: i18n),
      ],
    );
  }
}

/// Activation-code field — calls the redeem-code Edge Function and the
/// tier badge above updates immediately via AppState.notifyListeners.
class _RedeemRow extends StatefulWidget {
  const _RedeemRow({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<_RedeemRow> createState() => _RedeemRowState();
}

class _RedeemRowState extends State<_RedeemRow> {
  final _code = TextEditingController();
  bool _busy = false;

  // Collapsed by default — redeeming a code happens maybe once a year,
  // so it shouldn't take permanent space in the subscription card.
  bool _expanded = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    setState(() => _busy = true);
    final (msg, err) = await widget.appState.redeemActivationCode(_code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) {
        _code.clear();
        _expanded = false; // job done — tuck it away again
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err == null ? '🎉 $msg' : '⚠️ $err')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    if (!_expanded) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: InkWell(
          onTap: () => setState(() => _expanded = true),
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: GsColors.accentLight,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                  color: GsColors.accent.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GsIcon('ticket', size: 20),
                const SizedBox(width: 8),
                Text(
                  t('flutter.sub.redeem_toggle', 'Have an activation code?'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: GsColors.accentDark,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 16, color: GsColors.accent),
              ],
            ),
          ),
        ),
      );
    }
    // Stacked (not a Row): the theme's ElevatedButton has an
    // infinite-width minimumSize, which explodes inside a Row.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: t('flutter.sub.redeem_label', 'Activation code'),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _expanded = false),
              child: Text(
                t('common.cancel', 'Cancel'),
                style: const TextStyle(fontSize: 12, color: GsColors.text3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _redeem,
                child: Text(
                  _busy
                      ? t('flutter.sub.activating', 'Activating…')
                      : t('flutter.sub.activate', 'Activate'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Export the active child's data as CSV — assembled in AppState,
/// downloaded through the platform helper (browser Blob on web).
class _ExportTile extends StatefulWidget {
  const _ExportTile({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<_ExportTile> createState() => _ExportTileState();
}

class _ExportTileState extends State<_ExportTile> {
  bool _busy = false;

  Future<void> _export() async {
    final t = widget.i18n.t;
    setState(() => _busy = true);
    final (csv, err) = await widget.appState.buildExportCsv();
    String? dlErr = err;
    if (csv != null) {
      final name = (widget.appState.activeChildRow?['name'] as String? ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      dlErr = await downloadTextFile('growsense-$name-${todayISO()}.csv', csv);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dlErr == null
              ? '✅ ${t('flutter.export.done', 'Export downloaded')}'
              : '⚠️ $dlErr',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return InkWell(
      onTap: _busy ? null : _export,
      child: _Card(
        children: [
          Row(
            children: [
              const GsIcon('csv', size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _busy
                          ? t('flutter.export.working', 'Preparing…')
                          : t('flutter.export.title', 'Export data (CSV)'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: GsColors.accent,
                      ),
                    ),
                    Text(
                      t(
                        'flutter.export.sub',
                        'Growth, clinical records & 30-day logs for the active child',
                      ),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: GsColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.download_outlined,
                      size: 18,
                      color: GsColors.text3,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Premium: a branded pediatric-visit summary as a PDF. Free users
/// see the tile with a lock + upgrade hint (same place as CSV export).
class _VisitPdfTile extends StatefulWidget {
  const _VisitPdfTile({required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<_VisitPdfTile> createState() => _VisitPdfTileState();
}

class _VisitPdfTileState extends State<_VisitPdfTile> {
  bool _busy = false;

  bool get _isPaid {
    final tier =
        (widget.appState.account?['subscription_tier'] as String?) ?? 'free';
    return tier == 'premium' || tier == 'pro';
  }

  Future<void> _make() async {
    final t = widget.i18n.t;
    if (!_isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'flutter.pdf.premium_hint',
              'The visit summary PDF is a Premium feature — upgrade to unlock it.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final (bytes, err) = await buildVisitPdf(widget.appState, widget.i18n);
    String? dlErr = err;
    if (bytes != null) {
      final name = (widget.appState.activeChildRow?['name'] as String? ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      dlErr = await downloadBytesFile(
        'growsense-visit-$name-${todayISO()}.pdf',
        bytes,
        'application/pdf',
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dlErr == null
              ? '✅ ${t('flutter.pdf.done', 'Visit summary downloaded')}'
              : '⚠️ $dlErr',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final paid = _isPaid;
    return InkWell(
      onTap: _busy ? null : _make,
      child: _Card(
        children: [
          Row(
            children: [
              const GsIcon('pdf', size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _busy
                                ? t('flutter.pdf.working', 'Preparing…')
                                : t('flutter.pdf.tile', 'Visit summary (PDF)'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: GsColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: GsColors.estimatedLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            t('flutter.premium', 'Premium'),
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: GsColors.estimatedDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      t(
                        'flutter.pdf.sub',
                        'A clean, printable summary to hand your pediatrician',
                      ),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: GsColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      paid ? Icons.download_outlined : Icons.lock_outline,
                      size: 18,
                      color: GsColors.text3,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color ?? GsColors.text2),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color ?? GsColors.text,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: GsColors.text3),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: GsColors.text2),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Child profile editor sheet — name, DOB, and parent heights/ages
/// (the same children columns the PWA account screen writes). Parent
/// heights feed the mid-parental genetic target and the Medical tab's
/// trajectory.
class _ChildEditorSheet extends StatefulWidget {
  const _ChildEditorSheet({
    required this.appState,
    required this.i18n,
    required this.child,
  });
  final AppState appState;
  final I18n i18n;
  final Map<String, dynamic> child;

  @override
  State<_ChildEditorSheet> createState() => _ChildEditorSheetState();
}

class _ChildEditorSheetState extends State<_ChildEditorSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.child['name'] as String? ?? '',
  );
  late String? _dob = widget.child['date_of_birth'] as String?;
  late final TextEditingController _motherH = TextEditingController(
    text: _numText(widget.child['mother_height_cm']),
  );
  late final TextEditingController _fatherH = TextEditingController(
    text: _numText(widget.child['father_height_cm']),
  );
  late final TextEditingController _motherA = TextEditingController(
    text: _numText(widget.child['mother_current_age']),
  );
  late final TextEditingController _fatherA = TextEditingController(
    text: _numText(widget.child['father_current_age']),
  );
  bool _busy = false;

  static String _numText(dynamic v) => v == null ? '' : (v as num).toString();

  @override
  void dispose() {
    for (final c in [_name, _motherH, _fatherH, _motherA, _fatherA]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final t = widget.i18n.t;
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final err = await widget.appState.updateChild(widget.child['child_id'], {
      'name': name,
      if (_dob != null) 'date_of_birth': _dob,
      'mother_height_cm': double.tryParse(_motherH.text),
      'father_height_cm': double.tryParse(_fatherH.text),
      'mother_current_age': int.tryParse(_motherA.text),
      'father_current_age': int.tryParse(_fatherA.text),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: err == null ? GsColors.accentDark : GsColors.flag,
        content: Text(
          err == null
              ? '✅ ${t('flutter.saved_ok', 'Saved')}'
              : '${t('flutter.not_saved', 'Not saved')}: $err',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('flutter.edit_child', 'Edit child profile'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: t('flutter.child_name', "Child's name"),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  side: const BorderSide(color: GsColors.border2),
                  foregroundColor: GsColors.text,
                  alignment: AlignmentDirectional.centerStart,
                ),
                icon: const Icon(
                  Icons.cake_outlined,
                  size: 15,
                  color: GsColors.text2,
                ),
                label: Text(
                  '${t('flutter.dob', 'Date of birth')}: ${_dob ?? '—'}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dob != null ? DateTime.parse(_dob!) : now,
                    firstDate: now.subtract(const Duration(days: 365 * 19)),
                    lastDate: now,
                  );
                  if (picked != null) {
                    setState(() => _dob = localISO(picked));
                  }
                },
              ),
              const SizedBox(height: 16),
              Text(
                t(
                  'flutter.parent_heights',
                  'Parent heights — reveal the genetic target & trajectory',
                ),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: GsColors.estimatedDark,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _motherH,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: t(
                          'analytics.target_height.mother_height',
                          "Mother's height (cm)",
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _motherA,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t(
                          'analytics.target_height.mother_age',
                          "Mother's age",
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fatherH,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: t(
                          'analytics.target_height.father_height',
                          "Father's height (cm)",
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _fatherA,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: t(
                          'analytics.target_height.father_age',
                          "Father's age",
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _busy ? null : _save,
                child: Text(
                  _busy
                      ? t('flutter.saving', 'Saving…')
                      : t('flutter.save', 'Save'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : _remove,
                icon: const Icon(
                  Icons.archive_outlined,
                  size: 16,
                  color: GsColors.flag,
                ),
                label: Text(
                  t('flutter.child.remove', 'Remove profile'),
                  style: const TextStyle(fontSize: 12.5, color: GsColors.flag),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remove() async {
    final t = widget.i18n.t;
    // Read the real retention window up front so the confirm can name it.
    final days = await widget.appState.archiveRetentionDays();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GsColors.surface,
        title: Text(
          t('flutter.child.remove_q', 'Remove this child profile?'),
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        content: Text(
          t(
            'flutter.child.remove_note',
            'This child\'s profile will be removed from the app.',
            {'n': '$days'},
          ),
          style: const TextStyle(fontSize: 12.5, color: GsColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              t('flutter.child.remove', 'Remove profile'),
              style: const TextStyle(color: GsColors.flag),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await widget.appState.archiveChild(widget.child['child_id']);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.error == 'last_active') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: GsColors.flag,
          content: Text(
            t(
              'flutter.child.remove_last',
              'Keep at least one active child profile.',
            ),
          ),
        ),
      );
      return;
    }
    if (res.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: GsColors.flag,
          content: Text('${t('flutter.not_saved', 'Not saved')}: ${res.error}'),
        ),
      );
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: GsColors.accentDark,
        content: Text(
          t(
            'flutter.child.removed',
            'Profile removed',
            {'n': '${res.retentionDays}'},
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
        boxShadow: gsShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
