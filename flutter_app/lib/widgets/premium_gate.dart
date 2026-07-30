// ══════════════════════════════════════════════════════════════════
// Shared premium paywall sheet. One look for every gated feature
// (bone-age AI, lab AI interpretation, future credit-based tools):
// emoji badge, what you unlock, a "what stays free" reassurance line,
// CTA to the subscription screen, quiet dismiss. Server-side guards in
// the Edge Functions are the real enforcement — this sheet is the UX.
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../billing/purchase_service.dart';
import '../i18n.dart';
import '../platform.dart';
import '../theme.dart';
import '../screens/account_screen.dart';
import '../screens/paywall_screen.dart';

void showPremiumSheet(
  BuildContext context, {
  required AppState appState,
  required I18n i18n,
  required String emoji,
  required String title,
  required String body,
  required String freeNote,
  String? highlightBenefitKey,
}) {
  final t = i18n.t;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: GsColors.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: GsColors.estimatedLight,
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: GsColors.text),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.5, color: GsColors.text2),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: GsColors.accentLight,
                  borderRadius: BorderRadius.circular(GsRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 18, color: GsColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        freeNote,
                        style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: GsColors.accentDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  // On iOS this MUST reach the StoreKit paywall. Pushing
                  // AccountScreen there was a dead end while the
                  // subscription card was hidden, and would be again if
                  // the CTA ever drifted back.
                  final purchases = gPurchases;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => kUseIap && purchases != null
                        ? PaywallScreen(
                            appState: appState,
                            i18n: i18n,
                            purchases: purchases,
                            highlightBenefit: highlightBenefitKey,
                          )
                        : AccountScreen(appState: appState, i18n: i18n),
                  ));
                },
                child: Text(
                    t('flutter.premium.cta', 'See subscription options')),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(
                  t('flutter.premium.dismiss', 'Maybe later'),
                  style:
                      const TextStyle(fontSize: 13, color: GsColors.text3),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The small gold "Premium" chip shown next to locked feature labels.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key, required this.i18n});
  final I18n i18n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: GsColors.estimatedLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(i18n.t('flutter.premium', 'Premium'),
          style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: GsColors.estimatedDark)),
    );
  }
}
