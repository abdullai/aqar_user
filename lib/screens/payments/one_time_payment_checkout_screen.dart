import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/gestures/app_keyboard_inset.dart';
import '../../core/gestures/app_keyboard_popups.dart';
import '../../core/navigation/payment_overlay_route.dart';
import '../../core/payment/moyasar_web_3ds.dart';
import '../../core/payment/checkout_journey.dart';
import '../../core/payment/invoice_document.dart';
import '../../core/session/app_session.dart';
import '../../core/utils/app_money.dart';
import '../../l10n/app_localizations.dart';
import '../../services/billing_transaction_repository.dart';
import '../../services/instant_market_request_payment_service.dart';
import '../../services/payment_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/app_logo_loading.dart';
import '../../widgets/app_page_close_button.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import '../../widgets/aqar_text_field.dart';
import '../subscriptions/add_payment_card_screen.dart';
import '../subscriptions/payment_receipt_screen.dart';

/// دفع لمرة واحدة (طلب فوري، رسوم، …) — فاتورة + إيصال + طباعة.
class OneTimePaymentCheckoutScreen extends StatefulWidget {
  const OneTimePaymentCheckoutScreen({
    super.key,
    required this.lang,
    required this.amountSar,
    required this.billingTransactionId,
    this.creditId,
    required this.titleAr,
    required this.titleEn,
    this.purpose = 'instant_market_request',
    this.embedAppBar = true,
  });

  final String lang;
  final double amountSar;
  final String billingTransactionId;
  final String? creditId;
  final String titleAr;
  final String titleEn;
  final String purpose;
  final bool embedAppBar;

  bool get isAr => lang.toLowerCase() != 'en';

  @override
  State<OneTimePaymentCheckoutScreen> createState() =>
      _OneTimePaymentCheckoutScreenState();
}

class _OneTimePaymentCheckoutScreenState
    extends State<OneTimePaymentCheckoutScreen> {
  final _pay = PaymentService(Supabase.instance.client);
  final _instant = InstantMarketRequestPaymentService(
    Supabase.instance.client,
  );
  final _sub = SubscriptionService(Supabase.instance.client);
  final _promoCtrl = TextEditingController();

  bool _paying = false;
  bool _processingOverlay = false;
  bool _promoBusy = false;
  List<Map<String, dynamic>> _cards = [];
  String? _selectedCardId;
  String? _appliedPromoCode;
  late double _chargeSar;

  @override
  void initState() {
    super.initState();
    _chargeSar = widget.amountSar;
    unawaited(_loadCards());
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final c = await _pay.getSavedCards();
    if (!mounted) return;
    setState(() {
      _cards = c;
      _selectedCardId = c.isEmpty
          ? null
          : (c.firstWhere(
                (x) => x['is_default'] == true,
                orElse: () => c.first,
              )['id']
              ?.toString());
    });
  }

  String _promoErrorText(AppLocalizations t, String? err) {
    switch (err) {
      case 'already_used':
        return t.promoErrUsed;
      case 'expired':
        return t.promoErrExpired;
      case 'sold_out':
        return t.promoErrSoldOut;
      case 'wrong_audience':
        return t.promoErrAudience;
      case 'not_started':
        return t.promoErrNotStarted;
      case 'has_active_subscription':
        return t.promoErrActiveSub;
      case 'other_campaign_active':
        return t.promoErrOtherCampaign;
      default:
        return t.promoErrInvalid;
    }
  }

  Future<void> _applyPromo() async {
    final t = AppLocalizations.of(context)!;
    final code = _promoCtrl.text.trim();
    if (code.isEmpty || _appliedPromoCode != null) return;
    setState(() => _promoBusy = true);
    final q = await _sub.applyPromoToPendingBilling(
      billingTransactionId: widget.billingTransactionId,
      code: code,
    );
    if (!mounted) return;
    setState(() => _promoBusy = false);
    if (q['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_promoErrorText(t, '${q['error'] ?? ''}'))),
      );
      return;
    }
    final after = q['amount_after'];
    final afterN = after is num ? after.toDouble() : _chargeSar;
    if (afterN <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.checkoutPromoZero)),
      );
      return;
    }
    setState(() {
      _appliedPromoCode = code;
      _chargeSar = afterN;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.checkoutPromoApplied)),
    );
  }

  Future<void> _openAddCard() async {
    final added = await PaymentOverlay.push<bool>(
      context,
      name: '/subscriptions/add-card',
      page: AddPaymentCardScreen(lang: widget.lang),
    );
    if (added == true) {
      await _loadCards();
    }
  }

  void _showProcessingOverlay() {
    if (_processingOverlay || !mounted) return;
    _processingOverlay = true;
    unawaited(
      showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  widget.isAr ? 'جاري إكمال الدفع...' : 'Processing payment...',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideProcessingOverlay() {
    if (!_processingOverlay || !mounted) return;
    _processingOverlay = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  String _paymentErrorMessage(String? code, {String? detail}) {
    final c = (code ?? '').trim();
    switch (c) {
      case 'no_card':
        return widget.isAr
            ? 'اختر بطاقة أو أضف بطاقة جديدة.'
            : 'Select a card or add a new one.';
      case 'mock_token_use_new_card':
      case 'mock_token':
        return widget.isAr
            ? 'البطاقة المحفوظة قديمة — أضف بطاقة جديدة.'
            : 'Saved card is outdated — add a new card.';
      case 'card_expired':
        return widget.isAr ? 'انتهت صلاحية البطاقة.' : 'Card expired.';
      case 'billing_not_found':
        return widget.isAr
            ? 'لم يُعثر على فاتورة الدفع.'
            : 'Payment invoice not found.';
      case 'billing_not_pending':
        return widget.isAr
            ? 'فاتورة الدفع ليست قيد الانتظار.'
            : 'Payment invoice is not pending.';
      case 'webhook_timeout':
        return widget.isAr
            ? 'تأخر تأكيد الدفع — تحقق من سجل المدفوعات.'
            : 'Payment confirmation delayed — check payment history.';
      default:
        if ((detail ?? '').trim().isNotEmpty) return detail!.trim();
        return PaymentService.userFacingError(
          c.isEmpty ? 'payment_failed' : c,
          isAr: widget.isAr,
        );
    }
  }

  Future<void> _completePayment() async {
    if (_paying) return;
    final online = context.read<AppSession>().hasInternet;
    if (!online) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAr
                ? 'لا يوجد اتصال بالإنترنت — لن يُنفَّذ الدفع.'
                : 'No internet — payment cannot proceed.',
          ),
        ),
      );
      return;
    }

    final cardId = _selectedCardId?.trim() ?? '';
    if (cardId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_paymentErrorMessage('no_card')),
        ),
      );
      return;
    }

    final cardRow = _cards.cast<Map<String, dynamic>?>().firstWhere(
          (c) => '${c?['id']}' == cardId,
          orElse: () => null,
        );
    if (cardRow != null && PaymentService.isCardExpired(cardRow)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_paymentErrorMessage('card_expired'))),
      );
      return;
    }

    setState(() => _paying = true);
    try {
      final res = await _pay.processPaymentAgainstExistingBilling(
        billingTransactionId: widget.billingTransactionId,
        amount: _chargeSar,
        cardId: cardId,
        titleAr: widget.titleAr,
        titleEn: widget.titleEn,
        purpose: widget.purpose,
      );

      var paid = res['ok'] == true;
      if (!paid) {
        final err = res['error']?.toString();
        if (err == 'mock_token' || err == 'mock_token_use_new_card') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_paymentErrorMessage(err))),
          );
          return;
        }

        final threeDs = '${res['three_ds_url'] ?? ''}'.trim();
        if (threeDs.isNotEmpty) {
          if (kIsWeb) {
            await runMoyasarWeb3ds(threeDs);
          } else {
            final uri = Uri.tryParse(threeDs);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
          _showProcessingOverlay();
          try {
            final poll = await _pay.pollUntilBillingTransactionPaid(
              billingTransactionId: widget.billingTransactionId,
              expectedAmountSar: _chargeSar,
            );
            paid = poll['ok'] == true;
            if (!paid && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _paymentErrorMessage(poll['error']?.toString()),
                  ),
                ),
              );
              return;
            }
          } finally {
            _hideProcessingOverlay();
          }
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _paymentErrorMessage(
                  err,
                  detail: res['detail']?.toString() ??
                      res['moyasar_message']?.toString(),
                ),
              ),
            ),
          );
          return;
        }
      }

      if (!paid) return;

      final bid = widget.billingTransactionId;
      final promo = _appliedPromoCode;
      if (promo != null && promo.isNotEmpty) {
        await _sub.redeemPromoCode(code: promo, billingTransactionId: bid);
      }
      await _sub.fulfillPaidBilling(
        billingTransactionId: bid,
        expectedAmountSar: _chargeSar,
      );
      final credit = await _instant.getAvailableCredit();
      final creditId =
          widget.creditId ?? credit['credit_id']?.toString() ?? '';

      if (!mounted) return;
      Map<String, dynamic>? bill;
      if (bid.isNotEmpty) {
        bill = await BillingTransactionRepository(Supabase.instance.client)
            .getOwn(bid);
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PaymentReceiptScreen(
            lang: widget.lang,
            planName: widget.isAr ? widget.titleAr : widget.titleEn,
            period: 'one_time',
            amountSar: bill != null
                ? InvoiceDocument.fromRow(bill, isAr: widget.isAr).amount
                : _chargeSar,
            paymentMethodLabel: widget.isAr ? 'بطاقة محفوظة' : 'Saved card',
            transactionId:
                InvoiceDocument.fromRow(bill ?? const {}, isAr: widget.isAr)
                    .invoiceNumber,
            completedAt: InvoiceDocument.fromRow(
                  bill ?? const {},
                  isAr: widget.isAr,
                ).occurredAt ??
                DateTime.now().toUtc(),
            purpose: widget.purpose,
            billingRow: bill,
            invoiceNumber: InvoiceDocument.fromRow(
              bill ?? const {},
              isAr: widget.isAr,
            ).invoiceNumber,
            paymentReference: InvoiceDocument.fromRow(
              bill ?? const {},
              isAr: widget.isAr,
            ).paymentReference,
          ),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(
        OneTimePaymentResult(
          ok: true,
          billingTransactionId: bid,
          creditId: creditId.isEmpty ? null : creditId,
          amountSar: _chargeSar,
        ),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PaymentPopGuard(
      busy: _paying,
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: AppPageCloseButton(isArabic: widget.isAr),
              title: Text(widget.isAr ? 'الدفع' : 'Payment'),
            ),
      body: _paying
          ? const Center(child: AppLogoLoading())
          : AppKeyboardPad(
              extra: 16,
              child: AqarPrimaryScrollScope(
              child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: AppKeyboardInset.scrollViewPadding(
                context,
                base: const EdgeInsets.all(16),
              ),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.isAr ? widget.titleAr : widget.titleEn,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.isAr ? 'المبلغ المستحق' : 'Amount due',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        AppMoneyLine(
                          amount: _chargeSar,
                          currencyCode: 'SAR',
                          isAr: widget.isAr,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 12),
                        AqarTextField(
                          controller: _promoCtrl,
                          enabled: !_promoBusy &&
                              !_paying &&
                              _appliedPromoCode == null,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!
                                .checkoutPromoCode,
                            suffixIcon: _appliedPromoCode == null
                                ? TextButton(
                                    onPressed: _promoBusy
                                        ? null
                                        : () => unawaited(_applyPromo()),
                                    child: Text(
                                      AppLocalizations.of(context)!
                                          .checkoutPromoApply,
                                    ),
                                  )
                                : Icon(
                                    Icons.check_circle_outline,
                                    color: cs.primary,
                                  ),
                          ),
                          onSubmitted: (_) => unawaited(_applyPromo()),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  CheckoutJourney.surfaceHint(isAr: widget.isAr),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isAr ? 'طريقة الدفع' : 'Payment method',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _paying ? null : () => unawaited(_openAddCard()),
                      icon: const Icon(Icons.add_card_outlined, size: 20),
                      label: Text(widget.isAr ? 'إضافة بطاقة' : 'Add card'),
                    ),
                  ],
                ),
                if (_cards.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.isAr
                                ? 'لا توجد بطاقات محفوظة. أضف بطاقة للمتابعة.'
                                : 'No saved cards. Add a card to continue.',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _paying ? null : () => unawaited(_openAddCard()),
                            icon: const Icon(Icons.add_card_outlined),
                            label: Text(widget.isAr ? 'إضافة بطاقة' : 'Add card'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._cards.map((c) {
                    final id = '${c['id']}';
                    final last4 = '${c['last_four'] ?? '****'}';
                    final scheme = '${c['scheme'] ?? c['brand'] ?? ''}'.trim();
                    final expired = PaymentService.isCardExpired(c);
                    return RadioListTile<String>(
                      value: id,
                      groupValue: _selectedCardId,
                      onChanged: _paying || expired
                          ? null
                          : (v) => setState(() => _selectedCardId = v),
                      title: Text(
                        scheme.isEmpty
                            ? '•••• $last4'
                            : '$scheme •••• $last4',
                      ),
                      subtitle: expired
                          ? Text(
                              widget.isAr ? 'منتهية الصلاحية' : 'Expired',
                              style: TextStyle(color: cs.error),
                            )
                          : null,
                    );
                  }),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _cards.isEmpty || _paying ? null : _completePayment,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(
                    widget.isAr
                        ? 'ادفع ${AppMoney.formatWithCurrencyCode(_chargeSar, isAr: true, maxFractionDigits: 0)}'
                        : 'Pay ${AppMoney.formatWithCurrencyCode(_chargeSar, isAr: false, maxFractionDigits: 0)}',
                  ),
                ),
              ],
            ),
          ),
        ),
    ),
    );
  }
}
