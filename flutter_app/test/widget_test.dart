// Smoke test that stays clear of Supabase initialization — the auth
// screen renders standalone, so it's the natural boot check.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:growsense/screens/auth_screen.dart';
import 'package:growsense/theme.dart';

void main() {
  testWidgets('auth screen renders sign-in form', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildGrowSenseTheme(),
      home: const AuthScreen(),
    ));
    expect(find.text('GrowSense'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
  });
}
