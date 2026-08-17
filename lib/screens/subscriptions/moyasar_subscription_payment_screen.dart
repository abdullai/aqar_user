import 'package:flutter/material.dart';
import 'package:moyasar/moyasar.dart';

import '../../core/navigation/dashboard_embedded_route.dart';
import '../../core/payment/aqar_moyasar_credit_card.dart';
import '../../core/utils/app_money.dart';
import '../../services/payment_service.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';

enum MoyasarWalletMode { none, applePay, samsungPay }

/// Full-screen Moyasar card / wallet flow; pops with [PaymentResponse] or an error object from the SDK.
class MoyasarSubscriptionPaymentScreen extends StatelessWidget {
  const MoyasarSubscriptionPaymentScreen({
    super.key,
    required this.config,
    required this.walletMode,
    required this.isAr,
    this.planName,
    this.amountSar,
    this.periodLabel,
  });

  final PaymentConfig config;
  final MoyasarWalletMode walletMode;
  final bool isAr;
  final String? planName;
  final double? amountSar;
  final String? periodLabel;

  bool get useApplePay => walletMode == MoyasarWalletMode.applePay;
  bool get useSamsungPay => walletMode == MoyasarWalletMode.samsungPay;

  @override
  Widget build(BuildContext context) {
    PaymentService.configureMoyasarCallbackUrlFromEnv();
    final loc = isAr ? const Localization.ar() : const Localization.en();
    final embedded = DashboardEmbeddedRoute.isEmbedded(context);
    final cs = Theme.of(context).colorScheme;
    final displayAmount = amountSar ?? (config.amount / 100);
    final callback = PaymentConfig.callbackUrl.trim();
    final configError = _configError(isAr, callback);

    final body = AqarPrimaryScrollScope(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: cs.primaryContainer.withValues(alpha: 0.45),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isAr ? 'ملخص الدفع' : 'Payment summary',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (planName != null && planName!.trim().isNotEmpty)
                        Text(
                          planName!,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      if (periodLabel != null && periodLabel!.trim().isNotEmpty)
                        Text(
                          periodLabel!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            isAr ? 'المبلغ المستحق' : 'Amount due',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          AppMoneyLine(
                            amount: displayAmount,
                            currencyCode: 'SAR',
                            isAr: isAr,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.primary,
                                ),
                            maxFractionDigits:
                                displayAmount == displayAmount.roundToDouble()
                                    ? 0
                                    : 2,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (configError != null)
                Card(
                  color: cs.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      configError,
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ),
                )
              else if (useApplePay)
                ApplePay(
                  config: config,
                  onPaymentResult: (dynamic r) {
                    if (context.mounted) Navigator.of(context).pop(r);
                  },
                )
              else if (useSamsungPay)
                SamsungPay(
                  config: config,
                  onPaymentResult: (dynamic r) {
                    if (context.mounted) Navigator.of(context).pop(r);
                  },
                )
              else
                AqarMoyasarCreditCard(
                  config: config,
                  locale: loc,
                  onPaymentResult: (dynamic r) {
                    if (context.mounted) Navigator.of(context).pop(r);
                  },
                ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: embedded
          ? null
          : AppBar(title: Text(isAr ? 'دفع ميسّر' : 'Moyasar payment')),
      body: body,
    );
  }

  String? _configError(bool ar, String callback) {
    if ((config.publishableApiKey).trim().isEmpty) {
      return ar
          ? 'مفتاح ميسّر غير مضبوط. راجع supabase_config.json.'
          : 'Moyasar key missing. Check supabase_config.json.';
    }
    if (callback.isEmpty || callback.contains('example.com')) {
      return ar
          ? 'رابط إكمال الدفع (3DS) غير مضبوط. راجع MOYASAR_CALLBACK_URL.'
          : '3DS callback URL missing. Set MOYASAR_CALLBACK_URL.';
    }
    if (useApplePay && config.applePay == null) {
      return ar
          ? 'Apple Pay غير مضبوط — أضف MOYASAR_APPLE_PAY_MERCHANT_ID.'
          : 'Apple Pay not configured — set MOYASAR_APPLE_PAY_MERCHANT_ID.';
    }
    if (useSamsungPay && config.samsungPay == null) {
      return ar
          ? 'Samsung Pay غير مضبوط — أضف MOYASAR_SAMSUNG_PAY_SERVICE_ID.'
          : 'Samsung Pay not configured — set MOYASAR_SAMSUNG_PAY_SERVICE_ID.';
    }
    return null;
  }
}
