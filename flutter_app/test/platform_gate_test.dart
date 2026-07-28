// Locks down the platform predicates that decide what renders where.
//
// v1.0(3) was rejected under Guideline 3.1.1 for two things reachable on
// iOS: activation-code redemption (unlocking paid content outside In-App
// Purchase) and copy steering users to the web app for billing. Both
// live INSIDE the subscription card, so un-gating that card for StoreKit
// re-exposes them unless each is separately guarded.
//
// This test is the guard. If any of these invert, the app ships the
// rejection again.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Apple (iOS / iPadOS / macOS)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('is recognised as an Apple build', () {
      expect(kIsApplePhone, isTrue);
    });

    test('activation codes are NEVER reachable — Guideline 3.1.1', () {
      expect(kShowActivationCodes, isFalse);
    });

    test('web-billing copy is NEVER shown — Guideline 3.1.1 steering', () {
      expect(kShowWebBillingCopy, isFalse);
    });

    test('purchasing goes through StoreKit', () {
      expect(kUseIap, isTrue);
    });

    test('paid surface IS shown (it has IAP as of v1.1)', () {
      expect(kShowPaidUi, isTrue);
    });

    test('macOS is treated as Apple too', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(kIsApplePhone, isTrue);
      expect(kShowActivationCodes, isFalse);
      expect(kUseIap, isTrue);
    });
  });

  group('Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('is not an Apple build', () {
      expect(kIsApplePhone, isFalse);
    });

    test('keeps activation codes and the web billing story', () {
      expect(kShowActivationCodes, isTrue);
      expect(kShowWebBillingCopy, isTrue);
    });

    test('does not use StoreKit', () {
      expect(kUseIap, isFalse);
    });

    test('shows the paid surface', () {
      expect(kShowPaidUi, isTrue);
    });
  });

  test('activation codes and StoreKit are mutually exclusive', () {
    // The invariant behind the rejection, stated directly: a platform
    // must never offer both a code path and an IAP path, because that is
    // precisely "unlocking paid content by another mechanism".
    for (final p in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.android,
    ]) {
      debugDefaultTargetPlatformOverride = p;
      expect(kShowActivationCodes && kUseIap, isFalse,
          reason: '$p offers both codes and IAP');
    }
  });
}
