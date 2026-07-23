import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/platform.dart';

// The App Store free-MVP gate: on native Apple mobile the paid UI is
// hidden (kShowPaidUi == false). Everywhere else it shows. This is the
// single predicate that every premium/cap guard in the app reads, so
// locking it down here protects against an accidental re-rejection.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('iOS hides paid UI', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(kIsApplePhone, isTrue);
    expect(kShowPaidUi, isFalse);
  });

  test('Android shows paid UI', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(kIsApplePhone, isFalse);
    expect(kShowPaidUi, isTrue);
  });
}
