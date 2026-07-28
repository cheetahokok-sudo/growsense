// ══════════════════════════════════════════════════════════════════
// Platform gates.
//
// v1.0 shipped iOS as a FREE build with no paid surface at all, because
// Apple Guideline 3.1.1 forbids unlocking paid content by any mechanism
// other than In-App Purchase and there was no IAP yet. A single boolean
// (kShowPaidUi) hid everything.
//
// v1.1 adds StoreKit, so that one boolean no longer works: the concerns
// it conflated now point in different directions per platform. Paid UI
// must appear on iOS, activation codes must NOT, purchasing goes through
// StoreKit on iOS but not elsewhere, and "manage billing in the web app"
// copy must never be shown on iOS.
//
// Hence named predicates. Each says exactly one thing, so a future
// change cannot accidentally re-expose the wrong surface — which is what
// the v1.0(3) rejection was.
//
// `isPremium` is deliberately NOT affected by any of these: entitlement
// is decided server-side (recompute_user_entitlement) and re-verified in
// the paid Edge Functions. These flags only control what is rendered.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// True on a native Apple build (iPhone, iPad, or macOS running the iOS
/// app). Same predicate the native Sign-in-with-Apple path uses in
/// auth_screen.dart.
bool get kIsApplePhone =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Whether any paid surface exists at all — the subscription card,
/// premium feature entry points, upgrade prompts.
///
/// True everywhere since v1.1. Kept as a named predicate rather than
/// deleted so the call sites still read intentionally, and so re-hiding
/// the paid surface (if a future review ever demanded it) is one line.
bool get kShowPaidUi => true;

/// Whether activation-code redemption is reachable.
///
/// ⚠️ NEVER true on Apple. Redeeming a code for digital content outside
/// In-App Purchase is exactly what Guideline 3.1.1 forbids, and it was a
/// named reason in the v1.0(3) rejection. Codes remain a web/Android
/// mechanism. Guarded by test/platform_gate_test.dart.
bool get kShowActivationCodes => !kIsApplePhone;

/// Whether purchases go through StoreKit. Android gets the same
/// treatment via Google Play when that lands; until then it keeps the
/// web billing story.
bool get kUseIap => kIsApplePhone;

/// Whether to show copy pointing at the web app for billing
/// ("Upgrade & billing are managed in the web app"). On iOS that is
/// steering to an external purchase mechanism — also 3.1.1.
bool get kShowWebBillingCopy => !kIsApplePhone;
