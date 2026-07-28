// ══════════════════════════════════════════════════════════════════
// App Store product identifiers.
//
// These MUST match App Store Connect exactly — product ids are
// permanent there and can never be renamed or reused. They must also
// match PRODUCT_TIERS in supabase/functions/_shared/apple.ts: a mismatch
// means a paying customer is written to the database as 'free'.
// ══════════════════════════════════════════════════════════════════

class StoreProducts {
  StoreProducts._();

  static const String premiumMonthly = 'life.growsense.premium.monthly';
  static const String premiumYearly = 'life.growsense.premium.yearly';

  /// Query set for InAppPurchase.queryProductDetails.
  static const Set<String> all = {premiumMonthly, premiumYearly};

  /// Longest period first — annual is the better value and should lead.
  static const List<String> displayOrder = [premiumYearly, premiumMonthly];

  static bool isYearly(String id) => id == premiumYearly;
}
