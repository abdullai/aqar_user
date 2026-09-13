import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/navigation/payment_overlay_route.dart';
import '../../core/utils/app_money.dart';
import '../../screens/payments/one_time_payment_checkout_screen.dart';
import '../../services/instant_market_request_payment_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/market_offer_paywall_dialog.dart';
import '../../widgets/marketing_subscription_paywall_dialog.dart';
import '../../widgets/subscription_gate_alert_chip.dart';
import 'app_subscription_gate.dart';
import '../gestures/app_keyboard_popups.dart';
import 'marketing_subscription_resume_intent.dart';

/// بوابة اشتراك/دفع قابلة للاستدعاء من أي شاشة (Provider + [AppSubscriptionGate]).
class SubscriptionGateHelper {
  SubscriptionGateHelper._();

  static AppSubscriptionGate gateOf(BuildContext context) =>
      context.read<AppSubscriptionGate>();

  static Future<void> refresh(BuildContext context, {bool force = true}) =>
      gateOf(context).refresh(force: force);

  /// يُرجع `true` إذا مسموح — وإلا يعرض حوار/تنبيه حسب [action].
  static Future<bool> ensure(
    BuildContext context, {
    required bool isAr,
    required SubscriptionGateAction action,
    MarketingSubscriptionResumeIntent? resume,
    VoidCallback? onGoSubscribe,
  }) async {
    late final AppSubscriptionGate gate;
    try {
      gate = gateOf(context);
    } catch (_) {
      // بدون Provider في الشجرة كان يظهر Uncaught Error ويكسر الواجهة.
      debugPrint(
        '[SubscriptionGate] AppSubscriptionGate missing above this route',
      );
      return true;
    }
    await gate.refresh(force: false);
    if (gate.allows(action)) return true;

    if (action == SubscriptionGateAction.completeMarketDeal) {
      final allow = gate.marketOfferAllowance;
      if (allow != null) {
        final go = await showMarketOfferPaywallDialog(
          context: context,
          isAr: isAr,
          allowance: allow,
        );
        if (!context.mounted || !go) return false;
        onGoSubscribe?.call();
        return false;
      }
    }

    if (action == SubscriptionGateAction.marketingPaidWorkflow ||
        (action == SubscriptionGateAction.addPropertyListing &&
            gate.isMarketingAccount)) {
      final row = gate.subscriptionRow;
      if (!context.mounted) return false;
      await showMarketingSubscriptionPaywallDialog(
        context: context,
        isAr: isAr,
        subscriptionRow: row,
        onSubscribe: () => onGoSubscribe?.call(),
      );
      return false;
    }

    if (!context.mounted) return false;
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text(
          isAr ? gate.alertTitleAr(action) : gate.alertTitleEn(action),
        ),
        content: Text(
          isAr ? gate.alertBodyAr(action) : gate.alertBodyEn(action),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'لاحقاً' : 'Later'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onGoSubscribe?.call();
            },
            icon: const Icon(Icons.subscriptions_outlined),
            label: Text(isAr ? 'الذهاب للاشتراك' : 'Go to subscription'),
          ),
        ],
      ),
    );
    return false;
  }

  static Widget alertChip({
    required BuildContext context,
    required bool isAr,
    required SubscriptionGateAction action,
    required VoidCallback onSubscribe,
    bool compact = true,
  }) {
    return SubscriptionGateAlertChip(
      isAr: isAr,
      action: action,
      onSubscribe: onSubscribe,
      compact: compact,
    );
  }

  /// دفع طلب فوري — المبلغ من كتالوج الخادم.
  static Future<OneTimePaymentResult?> payInstantMarketRequest({
    required BuildContext context,
    required bool isAr,
    required String lang,
  }) async {
    final svc = InstantMarketRequestPaymentService(
      Supabase.instance.client,
    );
    final checkout = await svc.createCheckout();
    if (checkout['ok'] != true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAr
                  ? 'تعذّر تجهيز الدفع: ${checkout['error'] ?? ''}'
                  : 'Checkout failed: ${checkout['error'] ?? ''}',
            ),
          ),
        );
      }
      return OneTimePaymentResult(
        ok: false,
        error: checkout['error']?.toString() ?? 'checkout_failed',
      );
    }
    if (!context.mounted) {
      return const OneTimePaymentResult(ok: false, error: 'unmounted');
    }
    final bid = checkout['billing_transaction_id']?.toString() ?? '';
    final cid = checkout['credit_id']?.toString();
    final amount = InstantMarketRequestPaymentService.priceFromCheckout(checkout);
    if (bid.isEmpty) {
      return const OneTimePaymentResult(ok: false, error: 'no_billing_id');
    }

    final result = await PaymentOverlay.push<OneTimePaymentResult>(
      context,
      name: '/payments/one-time-checkout',
      page: OneTimePaymentCheckoutScreen(
          lang: lang,
          amountSar: amount,
          billingTransactionId: bid,
          creditId: cid,
          titleAr:
              'طلب عقاري فوري — ${AppMoney.formatWithCurrencyCode(amount, isAr: true, maxFractionDigits: amount == amount.roundToDouble() ? 0 : 2)}',
          titleEn:
              'Instant property request — ${AppMoney.formatWithCurrencyCode(amount, isAr: false, maxFractionDigits: amount == amount.roundToDouble() ? 0 : 2)}',
          purpose: 'instant_market_request',
      ),
    );
    SubscriptionService.invalidateSubscriptionCache();
    if (context.mounted) {
      await gateOf(context).refresh(force: true);
    }
    return result;
  }
}
