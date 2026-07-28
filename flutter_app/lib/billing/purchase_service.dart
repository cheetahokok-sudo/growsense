// ══════════════════════════════════════════════════════════════════
// StoreKit purchase plumbing.
//
// Owns the InAppPurchase stream and turns store events into calls to
// the apple-verify-purchase Edge Function. It never decides entitlement
// itself: the server asks Apple what is true, writes apple_subscriptions,
// and a database trigger recomputes the user's tier. This class only
// reports progress to the UI and then reloads the account.
//
// Three details here are load-bearing and easy to get wrong:
//
//   1. The purchase stream is subscribed at APP START, not when the
//      paywall opens. StoreKit delivers interrupted purchases and
//      Ask-to-Buy approvals on launch — a listener that only exists
//      while the paywall is on screen means a parent gets charged and
//      never entitled.
//
//   2. completePurchase() is called for EVERY terminal event, including
//      errors, in a finally. Skipping it leaves the transaction in the
//      payment queue: it is redelivered on every launch forever and the
//      queue can jam. A purchase is never held hostage to our backend
//      being reachable — the server also learns about it from Apple's
//      notification, so the receipt is not lost.
//
//   3. applicationUserName carries the Supabase user id. On StoreKit 2
//      that becomes appAccountToken in the signed transaction, so a
//      notification arriving before (or instead of) our verify call can
//      still be attributed to the right account.
// ══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_state.dart';
import '../platform.dart';
import 'store_products.dart';

enum PurchasePhase { idle, loading, pending, verifying, success, failed }

/// The app's single PurchaseService, set once from main().
///
/// Global on purpose. StoreKit is inherently process-wide — there is one
/// payment queue — and any screen can raise a paywall, so threading the
/// instance through every widget that might would be pure noise. Follows
/// the same pattern as rootMessengerKey in main.dart. Null on web and
/// Android, where it is never constructed.
PurchaseService? gPurchases;

class PurchaseService extends ChangeNotifier {
  PurchaseService(this._appState);

  final AppState _appState;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _available = false;
  bool get storeAvailable => _available;

  List<ProductDetails> _products = const [];
  List<ProductDetails> get products => _products;

  /// Ids App Store Connect did not return. Almost always propagation on
  /// a fresh setup rather than a bug, and the single most common cause
  /// of an empty paywall — surfaced so it is diagnosable without a Mac.
  List<String> _notFound = const [];
  List<String> get notFoundIds => _notFound;

  PurchasePhase _phase = PurchasePhase.idle;
  PurchasePhase get phase => _phase;

  String? _lastError;
  String? get lastError => _lastError;

  /// Last stream event, for the hidden diagnostics row.
  String _lastEvent = '-';
  String get lastEvent => _lastEvent;

  bool get busy =>
      _phase == PurchasePhase.pending || _phase == PurchasePhase.verifying;

  void _set(PurchasePhase p, {String? error}) {
    _phase = p;
    _lastError = error;
    notifyListeners();
  }

  /// Call once at app start. Safe on web and Android — it simply reports
  /// the store as unavailable and does nothing else.
  Future<void> init() async {
    if (!kUseIap) return;

    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        _lastEvent = 'stream error: $e';
        _set(PurchasePhase.failed, error: e.toString());
      },
    );

    try {
      _available = await _iap.isAvailable();
    } catch (e) {
      _available = false;
      _lastEvent = 'isAvailable threw: $e';
    }
    if (_available) await loadProducts();
    notifyListeners();
  }

  Future<void> loadProducts() async {
    if (!kUseIap || !_available) return;
    _set(PurchasePhase.loading);
    try {
      final res = await _iap.queryProductDetails(StoreProducts.all);
      _products = [...res.productDetails]..sort((a, b) {
          final ia = StoreProducts.displayOrder.indexOf(a.id);
          final ib = StoreProducts.displayOrder.indexOf(b.id);
          return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
        });
      _notFound = res.notFoundIDs;
      _lastEvent = 'products=${_products.length} notFound=${_notFound.length}';
      _set(PurchasePhase.idle, error: res.error?.message);
    } catch (e) {
      _set(PurchasePhase.failed, error: e.toString());
    }
  }

  Future<void> buy(ProductDetails product) async {
    if (!kUseIap) return;
    _set(PurchasePhase.pending);
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          // Becomes appAccountToken on StoreKit 2 — see header note 3.
          applicationUserName: _appState.sb.auth.currentUser?.id,
        ),
      );
    } catch (e) {
      _set(PurchasePhase.failed, error: e.toString());
    }
  }

  /// Apple requires a restore affordance, and it must work without
  /// purchasing. The plugin gives no completion callback and no
  /// "nothing to restore" signal, so we time out rather than leave the
  /// button spinning forever for someone who has nothing to restore.
  Future<void> restore() async {
    if (!kUseIap) return;
    _restoredAny = false;
    _set(PurchasePhase.verifying);
    try {
      await _iap.restorePurchases();
      await Future<void>.delayed(const Duration(seconds: 8));
      if (!_restoredAny && _phase == PurchasePhase.verifying) {
        _set(PurchasePhase.failed, error: 'nothing_to_restore');
      }
    } catch (e) {
      _set(PurchasePhase.failed, error: e.toString());
    }
  }

  bool _restoredAny = false;

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      _lastEvent = '${p.productID} ${p.status.name}';
      try {
        switch (p.status) {
          case PurchaseStatus.pending:
            // Includes Ask to Buy awaiting a parent's approval — a real
            // case for a parenting app. Not a failure.
            _set(PurchasePhase.pending);
            break;

          case PurchaseStatus.canceled:
            // The user chose not to buy. Silent.
            _set(PurchasePhase.idle);
            break;

          case PurchaseStatus.error:
            _set(PurchasePhase.failed,
                error: p.error?.message ?? 'Purchase failed');
            break;

          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            _restoredAny = true;
            _set(PurchasePhase.verifying);
            final err = await _appState.verifyApplePurchase(
              payload: p.verificationData.serverVerificationData,
              transactionId: p.purchaseID,
            );
            if (err == null) {
              _set(PurchasePhase.success);
            } else {
              _set(PurchasePhase.failed, error: err);
            }
            break;
        }
      } finally {
        // Header note 2 — unconditional, including on error.
        if (p.pendingCompletePurchase) {
          try {
            await _iap.completePurchase(p);
          } catch (e) {
            debugPrint('[purchases] completePurchase failed: $e');
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
