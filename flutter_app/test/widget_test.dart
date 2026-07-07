// Smoke test that stays clear of Supabase initialization — the auth
// screen renders standalone, so it's the natural boot check.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:growsense/i18n.dart';
import 'package:growsense/screens/auth_screen.dart';
import 'package:growsense/theme.dart';

void main() {
  testWidgets('auth screen renders sign-in form', (tester) async {
    // Plain I18n() has no locale maps loaded, so t() returns the
    // English fallbacks — which is what this smoke test asserts.
    await tester.pumpWidget(MaterialApp(
      theme: buildGrowSenseTheme(),
      home: AuthScreen(i18n: I18n()),
    ));
    expect(find.text('GrowSense'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
  });
}
