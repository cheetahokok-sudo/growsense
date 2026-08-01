// ══════════════════════════════════════════════════════════════════
// GrowSense Premium paywall (StoreKit).
//
// A FULL SCREEN, not a bottom sheet. Apple's required disclosure set
// does not fit comfortably in a sheet, and cramming it produces the
// "subscription terms are hard to find" rejection. The existing
// showPremiumSheet stays as the teaser that leads here.
//
// Everything Apple mandates on a purchase screen (Guideline 3.1.2 and
// Schedule 2) is present:
//   · what the subscription is and what it unlocks
//   · the length of each period, and its price
//   · price read from ProductDetails.price — NEVER hardcoded, so the
//     Thai baht figure and its formatting come from App Store Connect
//   · auto-renewal, when the charge happens, and how to turn it off
//   · free-trial forfeiture, when a trial is offered
//   · working links to Terms of Use and Privacy Policy
//   · Restore Purchases, reachable WITHOUT buying anything
//   · Manage Subscription for someone who already pays
// ══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../billing/purchase_service.dart';
import '../billing/store_products.dart';
import '../i18n.dart';
import '../theme.dart';

const _termsUrl = 'https://www.growsense.life/terms.html';
const _privacyUrl = 'https://www.growsense.life/privacy.html';
const _manageUrl = 'https://apps.apple.com/account/subscriptions';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.appState,
    required this.i18n,
    required this.purchases,
    this.highlightBenefit,
  });

  final AppState appState;
  final I18n i18n;
  final PurchaseService purchases;

  /// When the parent arrived from a specific locked feature, that
  /// benefit's key ('history', 'bone', 'labs', 'pdf', 'wearable',
  /// 'meas') — its row moves to the top and reads as the reason they
  /// came, with the rest of premium beneath as a bonus.
  final String? highlightBenefit;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    widget.purchases.addListener(_onChange);
    // Refresh in case the screen is opened before init() finished, or
    // after a failed first query (products often take hours to
    // propagate on a fresh App Store Connect setup).
    if (widget.purchases.products.isEmpty) widget.purchases.loadProducts();
  }

  @override
  void dispose() {
    widget.purchases.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (widget.purchases.phase == PurchasePhase.success) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t(
            'flutter.paywall.link_failed', 'Could not open the link.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    final p = widget.purchases;
    final alreadyPaid = widget.appState.isPremium;

    return Scaffold(
      backgroundColor: GsColors.bg,
      appBar: AppBar(
        title: Text(t('flutter.paywall.title', 'GrowSense Premium')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Text(
              t('flutter.paywall.headline',
                  'See how your child is really growing'),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: GsColors.text),
            ),
            const SizedBox(height: 8),
            Text(
              t('flutter.paywall.sub',
                  'Free keeps your daily logging. Premium unlocks the long view — the multi-year picture a single measurement cannot show.'),
              style: const TextStyle(
                  fontSize: 13, height: 1.45, color: GsColors.text2),
            ),
            const SizedBox(height: 16),
            _benefits(t),
            const SizedBox(height: 18),

            if (alreadyPaid) _alreadySubscribed(t) else ..._buyArea(t, p),

            const SizedBox(height: 18),
            _renewalTerms(t),
            const SizedBox(height: 14),
            _links(t),
          ],
        ),
      ),
    );
  }

  Widget _benefits(String Function(String, [String?]) t) {
    final items = <(String, String, String)>[
      ('history', '📈', t('flutter.paywall.b_history',
          'Your child\'s full growth history and height-velocity trend, not just the last 30 days')),
      ('scan', '📷', t('flutter.paywall.b_scan',
          'Measure height with the camera — no stadiometer, no tape, no wall marks')),
      ('foodscan', '📸', t('flutter.paywall.b_foodscan',
          'Snap a photo of the plate or a nutrition label — AI finds the foods and portions, you confirm')),
      ('bone', '🦴', t('flutter.paywall.b_bone',
          'AI second opinion on bone-age X-rays, alongside your multi-hospital timeline')),
      ('labs', '🧪', t('flutter.paywall.b_labs',
          'Plain-language interpretation of growth labs, with the evidence behind it')),
      ('pdf', '📄', t('flutter.paywall.b_pdf',
          'Visit-summary PDF to hand your pediatrician')),
      ('wearable', '⌚', t('flutter.paywall.b_wearable',
          'Wearable sync for sleep and activity')),
      ('meas', '♾️', t('flutter.paywall.b_meas', 'Unlimited measurements')),
    ];
    // The benefit the parent tapped through from leads the list.
    final hl = widget.highlightBenefit;
    if (hl != null) {
      final i = items.indexWhere((it) => it.$1 == hl);
      if (i > 0) items.insert(0, items.removeAt(i));
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.surface,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.border),
      ),
      child: Column(
        children: [
          for (final (key, emoji, text) in items)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding:
                  const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
              decoration: key == hl
                  ? BoxDecoration(
                      color: GsColors.estimatedLight,
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: key == hl
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: key == hl
                                ? GsColors.text
                                : GsColors.text2)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buyArea(
      String Function(String, [String?]) t, PurchaseService p) {
    if (!p.storeAvailable) {
      return [
        _notice(t('flutter.paywall.unavailable',
            'In-app purchases are unavailable on this device. This can happen if purchases are restricted in Screen Time settings.')),
      ];
    }
    if (p.products.isEmpty) {
      return [
        _notice(p.phase == PurchasePhase.loading
            ? t('flutter.paywall.loading', 'Loading subscription options…')
            : t('flutter.paywall.no_products',
                'Subscription options are not available right now. Please try again shortly.')),
      ];
    }

    return [
      for (final prod in p.products) _productCard(t, p, prod),
      const SizedBox(height: 6),
      if (p.lastError != null && p.lastError != 'nothing_to_restore')
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(p.lastError!,
              style: const TextStyle(fontSize: 11.5, color: GsColors.flag)),
        ),
      if (p.lastError == 'nothing_to_restore')
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              t('flutter.paywall.nothing_restore',
                  'No previous purchase found on this Apple ID.'),
              style: const TextStyle(fontSize: 11.5, color: GsColors.text3)),
        ),
      // Apple requires restore to be reachable without buying.
      TextButton(
        onPressed: p.busy ? null : p.restore,
        child: Text(t('flutter.paywall.restore', 'Restore purchases')),
      ),
    ];
  }

  Widget _productCard(String Function(String, [String?]) t, PurchaseService p,
      ProductDetails prod) {
    final yearly = StoreProducts.isYearly(prod.id);
    final period = yearly
        ? t('flutter.paywall.per_year', '12 months')
        : t('flutter.paywall.per_month', '1 month');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: yearly ? GsColors.accentLight : GsColors.surface,
          borderRadius: BorderRadius.circular(GsRadius.md),
          border: Border.all(
              color: yearly ? GsColors.accent : GsColors.border,
              width: yearly ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    yearly
                        ? t('flutter.paywall.yearly', 'Annual')
                        : t('flutter.paywall.monthly', 'Monthly'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: GsColors.text),
                  ),
                  const SizedBox(height: 2),
                  // prod.price is localized and currency-formatted by
                  // StoreKit for the user's storefront. Never hardcode.
                  Text('${prod.price} / $period',
                      style: const TextStyle(
                          fontSize: 12.5, color: GsColors.text2)),
                ],
              ),
            ),
            // ⚠️ The app theme sets minimumSize: Size.fromHeight(48),
            // which is Size(double.infinity, 48) — every ElevatedButton
            // demands INFINITE width. Inside a Row that starves the
            // Expanded beside it, and the price renders one character
            // per line. Override with a real bounded size here.
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(104, 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: p.busy ? null : () => p.buy(prod),
              child: Text(p.busy
                  ? t('flutter.paywall.working', 'Working…')
                  : t('flutter.paywall.subscribe', 'Subscribe')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alreadySubscribed(String Function(String, [String?]) t) {
    final until = widget.appState.account?['tier_expires_at'];
    final when = until == null
        ? null
        : DateTime.tryParse(until.toString())?.toLocal();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GsColors.accentLight,
        borderRadius: BorderRadius.circular(GsRadius.md),
        border: Border.all(color: GsColors.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('flutter.paywall.active', 'Premium is active'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: GsColors.accentDark)),
          if (when != null) ...[
            const SizedBox(height: 3),
            Text(
              '${t('flutter.paywall.renews_on', 'Next renewal')}: '
              '${when.toIso8601String().split('T').first}',
              style: const TextStyle(fontSize: 12, color: GsColors.text2),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _open(_manageUrl),
            child: Text(t('flutter.paywall.manage', 'Manage subscription')),
          ),
        ],
      ),
    );
  }

  /// Apple-mandated renewal disclosure. Wording deliberately mirrors
  /// Schedule 2 so review has nothing to query.
  Widget _renewalTerms(String Function(String, [String?]) t) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: GsColors.surface2,
        borderRadius: BorderRadius.circular(GsRadius.sm),
      ),
      child: Text(
        t(
          'flutter.paywall.renewal_terms',
          'Payment is charged to your Apple ID at confirmation of purchase. '
              'The subscription renews automatically unless auto-renew is turned off at least 24 hours before the end of the current period. '
              'Your account is charged for renewal within 24 hours before the period ends. '
              'You can manage your subscription and turn off auto-renewal in your Account Settings after purchase. '
              'Any unused portion of a free trial, where offered, is forfeited when you buy a subscription.',
        ),
        style: const TextStyle(
            fontSize: 11, height: 1.5, color: GsColors.text2),
      ),
    );
  }

  Widget _links(String Function(String, [String?]) t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () => _open(_termsUrl),
          child: Text(t('flutter.paywall.terms', 'Terms of Use'),
              style: const TextStyle(fontSize: 12)),
        ),
        const Text('·', style: TextStyle(color: GsColors.text3)),
        TextButton(
          onPressed: () => _open(_privacyUrl),
          child: Text(t('flutter.paywall.privacy', 'Privacy Policy'),
              style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _notice(String text) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: GsColors.surface2,
          borderRadius: BorderRadius.circular(GsRadius.sm),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12.5, color: GsColors.text2)),
      );
}
