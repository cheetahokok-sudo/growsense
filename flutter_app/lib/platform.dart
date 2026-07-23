// ══════════════════════════════════════════════════════════════════
// Platform gates for App Store compliance.
//
// On native Apple platforms (iPhone / iPad — iPadOS reports as iOS),
// the app ships as a FREE build: no paid feature surface and no usage
// cap that would prompt "upgrade on the web". Apple Guideline 3.1.1
// forbids unlocking paid content by any mechanism other than In-App
// Purchase, so on iOS we simply (a) don't render the paid entry points
// and (b) treat the free-tier caps as generous. Web and Android keep
// the full paid UI. Monetization returns via StoreKit in a later
// version — see [[ios-app-store-prep]].
//
// `isPremium` is deliberately NOT changed by this flag: the server-side
// Edge Functions still enforce entitlements. iOS just never calls them
// because the entry points aren't shown.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// True on a native Apple mobile build (iPhone or iPad). Same predicate
/// the native Sign-in-with-Apple path uses in auth_screen.dart.
bool get kIsApplePhone =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Whether to render paid/subscription UI (subscription card, activation
/// codes, premium feature entry points, upgrade prompts). Hidden on iOS.
bool get kShowPaidUi => !kIsApplePhone;
