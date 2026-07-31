// Locks the semantics of AppState.isPremium.
//
// This getter is the single client-side entitlement check. It gates the
// bone-age AI second opinion, the lab AI card and the visit-summary PDF,
// and its behaviour has to agree with the server-side re-check in
// bone-age-analysis and lab-ai-analysis (both of which treat an expired
// tier as free).
//
// The visit-summary PDF matters most here: unlike the AI features it is
// generated entirely client-side and never calls an Edge Function, so
// there is no server-side re-check behind it. _VisitPdfTile used to
// re-implement the tier check and ignore tier_expires_at, which let a
// lapsed subscriber keep PDF export forever.

import 'package:flutter_test/flutter_test.dart';
import 'package:growsense/app_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

AppState _appWith(Map<String, dynamic>? account) {
  // No network happens here — the client is only held as a field.
  final app = AppState(SupabaseClient('https://example.supabase.co', 'test'));
  app.account = account;
  return app;
}

String _iso(Duration offset) =>
    DateTime.now().add(offset).toUtc().toIso8601String();

void main() {
  group('AppState.isPremium', () {
    test('no account row is not premium', () {
      expect(_appWith(null).isPremium, isFalse);
    });

    test('free tier is not premium', () {
      expect(
        _appWith({'subscription_tier': 'free', 'tier_expires_at': null})
            .isPremium,
        isFalse,
      );
    });

    test('null expiry means a lifetime grant, not an expired one', () {
      expect(
        _appWith({'subscription_tier': 'premium', 'tier_expires_at': null})
            .isPremium,
        isTrue,
      );
    });

    test('premium with a future expiry is premium', () {
      expect(
        _appWith({
          'subscription_tier': 'premium',
          'tier_expires_at': _iso(const Duration(days: 30)),
        }).isPremium,
        isTrue,
      );
    });

    test('EXPIRED premium is not premium', () {
      // The regression: an expired subscriber kept the visit PDF because
      // _VisitPdfTile checked only the tier string.
      expect(
        _appWith({
          'subscription_tier': 'premium',
          'tier_expires_at': _iso(const Duration(days: -1)),
        }).isPremium,
        isFalse,
      );
    });

    test('expired pro is not premium either', () {
      expect(
        _appWith({
          'subscription_tier': 'pro',
          'tier_expires_at': _iso(const Duration(days: -1)),
        }).isPremium,
        isFalse,
      );
    });

    test('unparseable expiry fails open rather than locking a payer out', () {
      // Deliberate: a malformed timestamp should not revoke access from
      // someone who has paid. The server-side check is the real guard.
      expect(
        _appWith({
          'subscription_tier': 'premium',
          'tier_expires_at': 'not-a-date',
        }).isPremium,
        isTrue,
      );
    });
  });

  group('AppState.canUseHeightScan', () {
    // Height Scan runs entirely on-device, so like the visit-summary PDF
    // there is no Edge Function re-check behind it. That makes this
    // getter the only gate, and it must not re-implement the tier logic.
    test('free tier cannot scan', () {
      expect(
        _appWith({'subscription_tier': 'free', 'tier_expires_at': null})
            .canUseHeightScan,
        isFalse,
      );
    });

    test('no account row cannot scan', () {
      expect(_appWith(null).canUseHeightScan, isFalse);
    });

    test('active premium can scan', () {
      expect(
        _appWith({
          'subscription_tier': 'premium',
          'tier_expires_at': _iso(const Duration(days: 30)),
        }).canUseHeightScan,
        isTrue,
      );
    });

    test('EXPIRED premium cannot scan', () {
      expect(
        _appWith({
          'subscription_tier': 'premium',
          'tier_expires_at': _iso(const Duration(days: -1)),
        }).canUseHeightScan,
        isFalse,
      );
    });

    test('tracks isPremium exactly, so expiry can never be forgotten', () {
      for (final account in <Map<String, dynamic>?>[
        null,
        {'subscription_tier': 'free', 'tier_expires_at': null},
        {'subscription_tier': 'premium', 'tier_expires_at': null},
        {
          'subscription_tier': 'pro',
          'tier_expires_at': _iso(const Duration(days: -1))
        },
      ]) {
        final app = _appWith(account);
        expect(app.canUseHeightScan, app.isPremium, reason: '$account');
      }
    });
  });
}
