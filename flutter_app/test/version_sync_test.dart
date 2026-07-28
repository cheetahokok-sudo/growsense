// Guards the version drift that shipped in v1.0.
//
// pubspec's `version:` becomes CFBundleShortVersionString — the number the
// App Store shows. app_meta's kAppVersion is the number the app shows in
// Account, the "What's new" screen and every bug report. They drifted to
// 1.0.0 and 1.4.1 respectively, because codemagic.yaml overrides only
// --build-number, so every TestFlight build shipped stamped 1.0.0 while the
// app told users it was 1.4.1.
//
// Submitting an App Store version against a binary carrying a different
// short version fails at submission — and with no Mac, discovering that
// costs a full Codemagic cycle. Cheaper to fail here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/app_meta.dart';

void main() {
  test('pubspec version matches app_meta kAppVersion', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$', multiLine: true)
            .firstMatch(pubspec);

    expect(match, isNotNull,
        reason: 'pubspec.yaml needs a `version: X.Y.Z+N` line');

    expect(
      match!.group(1),
      kAppVersion,
      reason: 'pubspec version (${match.group(1)}) != app_meta kAppVersion '
          '($kAppVersion). The App Store would show one number and the app '
          'another. Bump both together — see the release process at the top '
          'of lib/app_meta.dart.',
    );
  });

  test('version stamp is well formed', () {
    expect(versionStamp, '$kAppVersion (build $kAppBuild) · $kBuildDate');
    expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(kBuildDate), isTrue,
        reason: 'kBuildDate must be YYYY-MM-DD, got "$kBuildDate"');
  });
}
