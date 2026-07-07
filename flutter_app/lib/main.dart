// ══════════════════════════════════════════════════════════════════
// GrowSense Flutter client — entry point.
// Connects to the SAME Supabase project as the PWA (see
// ../../supabase-client.js). URL + publishable key are project-level
// identifiers, not secrets; data access is gated by RLS.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

const supabaseUrl = 'https://ogpkmcqaulohexanucng.supabase.co';
const supabasePublishableKey = 'sb_publishable_tNs8cyaiOYn8Q21wZxIYOQ_y5XXLXnf';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
      url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(const GrowSenseApp());
}

class GrowSenseApp extends StatefulWidget {
  const GrowSenseApp({super.key});

  @override
  State<GrowSenseApp> createState() => _GrowSenseAppState();
}

class _GrowSenseAppState extends State<GrowSenseApp> {
  late final AppState appState = AppState(Supabase.instance.client);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GrowSense',
      debugShowCheckedModeBanner: false,
      theme: buildGrowSenseTheme(),
      home: AuthGate(appState: appState),
    );
  }
}

/// Shows the sign-in screen until a Supabase session exists, then the
/// 5-tab app shell — the Flutter equivalent of the PWA's
/// #authScreen / #appRoot boot sequence.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return const AuthScreen();
        }
        return HomeShell(appState: appState);
      },
    );
  }
}
