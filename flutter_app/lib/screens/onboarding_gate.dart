// ══════════════════════════════════════════════════════════════════
// Onboarding gate. Sits between AuthGate (signed-in) and HomeShell.
// A freshly-created account has no children, so landing straight on an
// empty Today page is confusing. Instead we load the children once and:
//   • loading (and none yet known) → brand-colored splash
//   • zero active children         → FirstChildScreen (create-first-child)
//   • ≥1 active child              → HomeShell
// The gate listens to AppState, so the moment addChild() lands the first
// profile the tree rebuilds into HomeShell automatically — the pushed
// AddChildScreen simply pops to reveal it.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/gs_logo.dart';
import 'home_shell.dart';
import 'settings_modules.dart';

class RootGate extends StatefulWidget {
  const RootGate({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  void initState() {
    super.initState();
    // Owns the children load now (removed from HomeShell.initState so we
    // don't fetch twice) — HomeShell renders only once this resolves.
    widget.appState.loadChildren();
  }

  int get _activeChildren => widget.appState.children
      .where((c) => c['status'] != 'archived')
      .length;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        // First load in flight and nothing cached yet: quiet brand splash
        // rather than a flash of the onboarding screen.
        if (widget.appState.loadingChildren && widget.appState.children.isEmpty) {
          return const Scaffold(
            backgroundColor: GsColors.deepGreen,
            body: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white70),
              ),
            ),
          );
        }
        if (_activeChildren == 0) {
          return FirstChildScreen(
              appState: widget.appState, i18n: widget.i18n);
        }
        return HomeShell(appState: widget.appState, i18n: widget.i18n);
      },
    );
  }
}

/// Warm first-run screen shown when the account has no child profile yet.
/// Reuses the existing AddChildScreen form; on success the child lands in
/// AppState, RootGate rebuilds into HomeShell, and this screen is gone.
class FirstChildScreen extends StatelessWidget {
  const FirstChildScreen(
      {super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    final t = i18n.t;
    return Scaffold(
      backgroundColor: GsColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              // Logo mark on a soft accent halo.
              Center(
                child: Container(
                  width: 108,
                  height: 108,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: GsColors.accentLight,
                    shape: BoxShape.circle,
                  ),
                  child: const GsLogoMark(size: 60),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                t('flutter.onboarding.title', 'Welcome to GrowSense'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: GsColors.text),
              ),
              const SizedBox(height: 12),
              Text(
                t(
                    'flutter.onboarding.subtitle',
                    "Let's set up your first child's profile. "
                        'It takes less than a minute, and everything you '
                        'track from here on grows with them.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: GsColors.text2),
              ),
              const Spacer(flex: 4),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AddChildScreen(appState: appState, i18n: i18n),
                  ),
                ),
                icon: const Icon(Icons.child_care_outlined, size: 18),
                label: Text(
                    t('flutter.onboarding.cta', 'Add your first child')),
              ),
              const SizedBox(height: 10),
              // Escape hatch: signed into the wrong account, or want to
              // switch — mirrors AccountScreen's sign-out (auth stream then
              // routes back to the auth screen).
              TextButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  appState.reset();
                },
                child: Text(
                  t('flutter.onboarding.signout', 'Sign out'),
                  style: const TextStyle(
                      fontSize: 13, color: GsColors.text3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
