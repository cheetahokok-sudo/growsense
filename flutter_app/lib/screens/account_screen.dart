import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

/// Account & settings — pushed from the top-bar avatar. Uses the same
/// account.* locale keys as the PWA's account screen. Child editing
/// stays in the web app for now; this surfaces identity, language,
/// and sign-out.
class AccountScreen extends StatelessWidget {
  const AccountScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    final email = Supabase.instance.client.auth.currentUser?.email ?? '—';

    return Scaffold(
      appBar: AppBar(
        title: Text(t('account.title', 'Account & settings'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _Card(
                children: [
                  Text(t('account.signed_in_as', 'Signed in as'),
                      style: const TextStyle(
                          fontSize: 11, color: GsColors.text3)),
                  const SizedBox(height: 4),
                  Text(email,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                children: [
                  Text(t('account.children.title', 'Children profiles'),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: GsColors.accent)),
                  const SizedBox(height: 8),
                  if (appState.children.isEmpty)
                    Text(t('flutter.no_children'),
                        style: const TextStyle(
                            fontSize: 12, color: GsColors.text3))
                  else
                    for (final c in appState.children)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
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
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(c['name'] as String? ?? '',
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text(c['date_of_birth'] as String? ?? '',
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: GsColors.text3)),
                          ],
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                children: [
                  Text(t('account.language', 'Language'),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: GsColors.accent)),
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
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: i18n.code == entry.key
                                    ? GsColors.accent
                                    : GsColors.surface2,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(entry.value,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: i18n.code == entry.key
                                          ? Colors.white
                                          : GsColors.text2)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t('flutter.account.version', 'App version'),
                          style: const TextStyle(
                              fontSize: 12.5, color: GsColors.text2)),
                      const Text('1.0.0 (prototype)',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: GsColors.flag,
                  side: const BorderSide(color: GsColors.flag),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GsRadius.md)),
                ),
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  appState.reset();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(t('account.sign_out_btn', 'Sign out'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
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
          children: children),
    );
  }
}
