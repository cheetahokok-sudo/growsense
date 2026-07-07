// ══════════════════════════════════════════════════════════════════
// GrowSense Flutter client — entry point.
// Connects to the SAME Supabase project as the PWA (see
// ../../supabase-client.js). URL + publishable key are project-level
// identifiers, not secrets; data access is gated by RLS.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'i18n.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

const supabaseUrl = 'https://ogpkmcqaulohexanucng.supabase.co';
const supabasePublishableKey = 'sb_publishable_tNs8cyaiOYn8Q21wZxIYOQ_y5XXLXnf';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: supabaseUrl, publishableKey: supabasePublishableKey);
  final i18n = await I18n.create();
  runApp(GrowSenseApp(i18n: i18n));
}

class GrowSenseApp extends StatefulWidget {
  const GrowSenseApp({super.key, required this.i18n});
  final I18n i18n;

  @override
  State<GrowSenseApp> createState() => _GrowSenseAppState();
}

class _GrowSenseAppState extends State<GrowSenseApp> {
  late final AppState appState = AppState(Supabase.instance.client);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.i18n,
      builder: (context, _) {
        return MaterialApp(
          title: 'GrowSense',
          debugShowCheckedModeBanner: false,
          theme: buildGrowSenseTheme(widget.i18n.code),
          locale: widget.i18n.locale,
          supportedLocales: [
            for (final code in supportedLanguages.keys) Locale(code),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AuthGate(appState: appState, i18n: widget.i18n),
        );
      },
    );
  }
}

/// Shows the sign-in screen until a Supabase session exists, then the
/// 5-tab app shell — the Flutter equivalent of the PWA's
/// #authScreen / #appRoot boot sequence.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.appState, required this.i18n});
  final AppState appState;
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return AuthScreen(i18n: i18n);
        }
        return HomeShell(appState: appState, i18n: i18n);
      },
    );
  }
}
