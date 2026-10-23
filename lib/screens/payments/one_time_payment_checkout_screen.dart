import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:moyasar/moyasar.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/gestures/app_keyboard_inset.dart';
import '../../core/gestures/app_keyboard_popups.dart';
import '../../core/navigation/payment_overlay_route.dart';
import '../../core/payment/moyasar_web_3ds.dart';
import '../../core/payment/checkout_journey.dart';
import '../../core/payment/invoice_document.dart';
import '../../core/payment/payment_platform_detector.dart';
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
import '../subscriptions/moyasar_subscription_payment_screen.dart';
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
  bool _billingChecking = true;
  String? _billingIssue;
  List<Map<String, dynamic>> _cards = [];
  String? _selectedCardId;
  String _mode = 'saved';
  String? _appliedPromoCode;
  late double _chargeSar;

  @override
  void initState() {
    super.initState();
    _chargeSar = widget.amountSar;
    unawaited(_checkBillingStatus());
    unawaited(_loadCards());
  }

  @override
  void dispose() {
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    var c = await _pay.getSavedCards();
    if (PaymentService.useMoyasarLiveFlow) {
      c = c
          .where((row) => !PaymentService.isMockCardToken(row['card_token']))
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _cards = c;
      _selectedCardId = c.isEmpty
          ? null
          : (c
              .firstWhere(
                (x) => x['is_default'] == true,
                orElse: () => c.first,
              )['id']
              ?.toString());
      _mode = c.isEmpty
          ? (PaymentService.useMoyasarLiveFlow ? 'new' : 'saved')
          : 'saved';
    });
  }

  Future<bool> _checkBillingStatus() async {
    String? issue;
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        issue = 'auth';
      } else {
        final row = await Supabase.instance.client
            .from('billing_transactions')
            .select('status,currency')
            .eq('id', widget.billingTransactionId.trim())
            .eq('user_id', userId)
            .maybeSingle();
        if (row == null) {
          issue = 'billing_not_found';
        } else if ('${row['status'] ?? ''}'.trim().toLowerCase() != 'pending') {
          issue = 'billing_not_pending';
        } else if ('${row['currency'] ?? ''}'.trim().toUpperCase() != 'SAR') {
          issue = 'currency_mismatch';
        }
      }
    } catch (e, st) {
      debugPrint('[OneTimePayment] billing status check failed: $e\n$st');
      issue = 'billing_check_failed';
    }

    if (mounted) {
      setState(() {
        _billingChecking = false;
        _billingIssue = issue;
      });
    }
    return issue == null;
  }

  String _moyasarSetupIssueLabel(String issue) {
    switch (issue) {
      case 'client_server_mode_mismatch':
        return widget.isAr
            ? 'يجب تطابق وضع المفتاحين: pk_test_ مع sk_test_ أو pk_live_ مع sk_live_'
            : 'Key modes must match: pk_test_ with sk_test_, or pk_live_ with sk_live_';
      case 'client_publishable_key_missing':
        return widget.isAr
            ? 'مفتاح النشر غير مهيأ'
            : 'Moyasar publishable key is missing';
      case 'server_secret_key_missing':
        return widget.isAr
            ? 'المفتاح السري غير مهيأ في Supabase'
            : 'Moyasar secret key is missing in Supabase';
      case 'callback_url_missing_on_server':
        return widget.isAr
            ? 'رابط العودة غير مهيأ في Supabase'
            : 'Server callback URL is missing';
      case 'webhook_secret_missing':
        return widget.isAr
            ? 'سر Webhook غير مهيأ في Supabase'
            : 'Webhook secret is missing in Supabase';
      case 'live_mode_requires_moyasar_account_activation_otherwise_http_405':
        return widget.isAr
            ? 'حساب ميسر للإنتاج يحتاج إلى التفعيل'
            : 'Moyasar live account needs activation';
      default:
        return widget.isAr
            ? 'إعداد دفع غير مكتمل'
            : 'Payment setup is incomplete';
    }
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

  MoyasarWalletMode _moyasarWalletMode() {
    switch (_mode) {
      case 'apple_pay':
        return MoyasarWalletMode.applePay;
      case 'samsung_pay':
        return MoyasarWalletMode.samsungPay;
      case 'stc_pay':
        return MoyasarWalletMode.stcPay;
      default:
        return MoyasarWalletMode.none;
    }
  }

  String _paymentMethodLabel() {
    switch (_mode) {
      case 'apple_pay':
        return 'Apple Pay';
      case 'samsung_pay':
        return 'Samsung Pay';
      case 'stc_pay':
        return 'STC Pay';
      case 'new':
        return widget.isAr ? 'بطاقة جديدة' : 'New card';
      default:
        return widget.isAr ? 'بطاقة محفوظة' : 'Saved card';
    }
  }

  Future<Map<String, dynamic>> _payWithMoyasar() async {
    if (!PaymentService.useMoyasarLiveFlow) {
      return {'ok': false, 'error': 'payment_gateway_not_configured'};
    }
    final billingId = widget.billingTransactionId.trim();
    if (billingId.isEmpty) return {'ok': false, 'error': 'billing_not_found'};

    ApplePayConfig? applePay;
    SamsungPayConfig? samsungPay;
    final walletMode = _moyasarWalletMode();
    if (walletMode == MoyasarWalletMode.applePay) {
      final merchantId = PaymentService.moyasarApplePayMerchantId;
      if (merchantId == null || merchantId.isEmpty) {
        return {'ok': false, 'error': 'apple_pay_merchant_missing'};
      }
      applePay = ApplePayConfig(
        merchantId: merchantId,
        label: widget.isAr ? 'موثوق لاين' : 'Aqar Reliable',
        manual: false,
        saveCard: true,
      );
    } else if (walletMode == MoyasarWalletMode.samsungPay) {
      final serviceId = PaymentService.moyasarSamsungPayServiceId;
      if (serviceId == null || serviceId.isEmpty) {
        return {'ok': false, 'error': 'samsung_pay_service_missing'};
      }
      samsungPay = SamsungPayConfig(
        serviceId: serviceId,
        merchantName: widget.isAr ? 'موثوق لاين' : 'Aqar Reliable',
        manual: false,
      );
    }

    final metadata = _pay.buildMoyasarSubscriptionMetadata(
      billingTransactionId: billingId,
      purpose: widget.purpose,
    );
    PaymentConfig config;
    try {
      config = _pay.buildMoyasarPaymentConfig(
        amountHalalas: PaymentService.amountToHalalas(_chargeSar),
        description: widget.titleEn.length > 128
            ? widget.titleEn.substring(0, 128)
            : widget.titleEn,
        metadata: metadata,
        madaPreferredNetworksOnly: false,
        applePay: applePay,
        samsungPay: samsungPay,
      );
    } catch (e, st) {
      debugPrint('[OneTimePayment] Moyasar config failed: $e\n$st');
      return {'ok': false, 'error': 'moyasar_config_error'};
    }

    if (!mounted) return {'ok': false, 'error': 'unmounted'};
    dynamic result;
    try {
      result = await PaymentOverlay.push<dynamic>(
        context,
        name: '/payments/moyasar-pay',
        page: MoyasarSubscriptionPaymentScreen(
          config: config,
          walletMode: walletMode,
          isAr: widget.isAr,
          planName: widget.isAr ? widget.titleAr : widget.titleEn,
          amountSar: _chargeSar,
          periodLabel: widget.isAr ? 'دفعة واحدة' : 'One-time payment',
        ),
      );
    } catch (e, st) {
      debugPrint('[OneTimePayment] Moyasar checkout failed: $e\n$st');
      return {'ok': false, 'error': 'moyasar_widget_error'};
    }
    if (!mounted) return {'ok': false, 'error': 'unmounted'};
    if (result is! PaymentResponse ||
        !PaymentService.moyasarPaymentSucceeded(result)) {
      return {
        'ok': false,
        'error': PaymentService.mapMoyasarResultToError(result) ??
            'moyasar_cancelled_or_failed',
      };
    }

    _showProcessingOverlay();
    try {
      return await _pay.pollUntilBillingTransactionPaid(
        billingTransactionId: billingId,
        expectedAmountSar: _chargeSar,
      );
    } finally {
      _hideProcessingOverlay();
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
      case 'billing_check_failed':
        return widget.isAr
            ? 'تعذّر التحقق من حالة الفاتورة. أعد المحاولة قبل الدفع.'
            : 'Could not verify the invoice. Retry before paying.';
      case 'currency_mismatch':
        return widget.isAr
            ? 'عملة فاتورة الدفع غير مدعومة.'
            : 'The invoice currency is not supported.';
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
    if (_billingChecking) return;
    if (_billingIssue != null || !await _checkBillingStatus()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_paymentErrorMessage(_billingIssue)),
        ),
      );
      return;
    }

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

    if (_mode == 'saved' &&
        (_selectedCardId == null || _selectedCardId!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_paymentErrorMessage('no_card')),
        ),
      );
      return;
    }

    if (_mode == 'new' && !PaymentService.useMoyasarLiveFlow) {
      await _openAddCard();
      return;
    }

    final cardId = _selectedCardId?.trim() ?? '';
    final cardRow = _mode == 'saved'
        ? _cards.cast<Map<String, dynamic>?>().firstWhere(
              (c) => '${c?['id']}' == cardId,
              orElse: () => null,
            )
        : null;
    if (cardRow != null && PaymentService.isCardExpired(cardRow)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_paymentErrorMessage('card_expired'))),
      );
      return;
    }

    if (PaymentService.useMoyasarLiveFlow) {
      final health = await _pay.checkMoyasarServerHealth();
      if (!mounted) return;
      final rawIssues = health['issues'];
      if (health['ok'] != true || (rawIssues is List && rawIssues.isNotEmpty)) {
        final issueLabels = rawIssues is List
            ? rawIssues
                .map((issue) => _moyasarSetupIssueLabel('$issue'))
                .toSet()
                .toList()
            : <String>[];
        if (issueLabels.isEmpty) {
          issueLabels.add(
            widget.isAr
                ? 'تعذّر التحقق من إعدادات ميسر'
                : 'Could not verify Moyasar configuration',
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              widget.isAr
                  ? 'تعذّر بدء الدفع: ${issueLabels.join('، ')}. لا ترسل المفاتيح أو الأسرار في المحادثة.'
                  : 'Payment cannot start: ${issueLabels.join(', ')}. Do not share keys or secrets in chat.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _paying = true);
    try {
      late final Map<String, dynamic> res;
      if (PaymentService.useMoyasarLiveFlow && _mode != 'saved') {
        res = await _payWithMoyasar();
      } else {
        final charge = await _pay.processPaymentAgainstExistingBilling(
          billingTransactionId: widget.billingTransactionId,
          amount: _chargeSar,
          cardId: cardId,
          titleAr: widget.titleAr,
          titleEn: widget.titleEn,
          purpose: widget.purpose,
        );
        final threeDs = '${charge['three_ds_url'] ?? ''}'.trim();
        if (PaymentService.useMoyasarLiveFlow &&
            (charge['ok'] == true || threeDs.isNotEmpty)) {
          if (threeDs.isNotEmpty) {
            if (kIsWeb) {
              await runMoyasarWeb3ds(threeDs);
            } else {
              final uri = Uri.tryParse(threeDs);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          }
          _showProcessingOverlay();
          try {
            res = await _pay.pollUntilBillingTransactionPaid(
              billingTransactionId: widget.billingTransactionId,
              expectedAmountSar: _chargeSar,
            );
          } finally {
            _hideProcessingOverlay();
          }
        } else {
          res = charge;
        }
      }

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
      final fulfillment = await _sub.fulfillPaidBilling(
        billingTransactionId: bid,
        expectedAmountSar: _chargeSar,
      );
      if (fulfillment['ok'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isAr
                  ? 'تم تأكيد الدفع لكن تعذّر تفعيل الطلب. تواصل مع الدعم.'
                  : 'Payment was confirmed, but the purchase could not be activated. Contact support.',
            ),
          ),
        );
        return;
      }
      final credit = await _instant.getAvailableCredit();
      final creditId = widget.creditId ?? credit['credit_id']?.toString() ?? '';

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
            paymentMethodLabel: _paymentMethodLabel(),
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
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
                      if (!PaymentPlatformDetector.paymentsUiEnabled)
                        Card(
                          color: cs.errorContainer.withValues(alpha: 0.55),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              widget.isAr
                                  ? 'الدفع غير مهيأ لهذه البيئة. فعّل إعدادات Moyasar أو بوابة الاختبار قبل المتابعة.'
                                  : 'Payments are not configured for this environment. Configure Moyasar or the test gateway before continuing.',
                              style: TextStyle(
                                color: cs.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (_billingChecking || _billingIssue != null)
                        Card(
                          color: _billingIssue == null
                              ? cs.surfaceContainerHighest
                                  .withValues(alpha: 0.45)
                              : cs.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _billingChecking
                                        ? (widget.isAr
                                            ? 'جارٍ التحقق من أن الفاتورة قيد الانتظار...'
                                            : 'Checking that the invoice is pending...')
                                        : _paymentErrorMessage(_billingIssue),
                                    style: TextStyle(
                                      color: _billingIssue == null
                                          ? cs.onSurface
                                          : cs.onErrorContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (!_billingChecking &&
                                    _billingIssue == 'billing_check_failed')
                                  IconButton(
                                    tooltip: widget.isAr
                                        ? 'إعادة المحاولة'
                                        : 'Retry',
                                    onPressed: _paying
                                        ? null
                                        : () =>
                                            unawaited(_checkBillingStatus()),
                                    icon: const Icon(Icons.refresh),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.isAr ? 'طريقة الدفع' : 'Payment method',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          if (PaymentPlatformDetector.paymentsUiEnabled &&
                              !PaymentService.useMoyasarLiveFlow)
                            TextButton.icon(
                              onPressed: _paying
                                  ? null
                                  : () => unawaited(_openAddCard()),
                              icon:
                                  const Icon(Icons.add_card_outlined, size: 20),
                              label: Text(
                                  widget.isAr ? 'إضافة بطاقة' : 'Add card'),
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
                                      ? !PaymentPlatformDetector
                                              .paymentsUiEnabled
                                          ? 'الدفع غير مهيأ حالياً.'
                                          : PaymentService.useMoyasarLiveFlow
                                              ? 'لا توجد بطاقة محفوظة. اختر بطاقة جديدة لإتمام الدفع.'
                                              : 'لا توجد بطاقات محفوظة. أضف بطاقة للمتابعة.'
                                      : !PaymentPlatformDetector
                                              .paymentsUiEnabled
                                          ? 'Payments are not configured.'
                                          : PaymentService.useMoyasarLiveFlow
                                              ? 'No saved cards. Choose a new card to continue.'
                                              : 'No saved cards. Add a card to continue.',
                                ),
                                const SizedBox(height: 12),
                                if (PaymentPlatformDetector.paymentsUiEnabled &&
                                    !PaymentService.useMoyasarLiveFlow)
                                  FilledButton.icon(
                                    onPressed: _paying
                                        ? null
                                        : () => unawaited(_openAddCard()),
                                    icon: const Icon(Icons.add_card_outlined),
                                    label: Text(widget.isAr
                                        ? 'إضافة بطاقة'
                                        : 'Add card'),
                                  ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._cards.map((c) {
                          final id = '${c['id']}';
                          final last4 = '${c['last_four'] ?? '****'}';
                          final scheme =
                              '${c['scheme'] ?? c['brand'] ?? ''}'.trim();
                          final expired = PaymentService.isCardExpired(c);
                          return RadioListTile<String>(
                            value: id,
                            groupValue: _selectedCardId,
                            onChanged: _paying || expired
                                ? null
                                : (v) => setState(() {
                                      _selectedCardId = v;
                                      _mode = 'saved';
                                    }),
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
                      if (PaymentService.useMoyasarLiveFlow) ...[
                        RadioListTile<String>(
                          value: 'new',
                          groupValue: _mode,
                          onChanged: _paying
                              ? null
                              : (value) =>
                                  setState(() => _mode = value ?? 'new'),
                          secondary: const Icon(Icons.add_card_outlined),
                          title: Text(widget.isAr
                              ? 'بطاقة جديدة / مدى'
                              : 'New card / mada'),
                        ),
                        if (PaymentPlatformDetector.supportsStcPay())
                          RadioListTile<String>(
                            value: 'stc_pay',
                            groupValue: _mode,
                            onChanged: _paying
                                ? null
                                : (value) =>
                                    setState(() => _mode = value ?? 'stc_pay'),
                            secondary: const Icon(Icons.phone_android_outlined),
                            title: const Text('STC Pay'),
                          ),
                        if (PaymentPlatformDetector.supportsApplePay())
                          RadioListTile<String>(
                            value: 'apple_pay',
                            groupValue: _mode,
                            onChanged: _paying
                                ? null
                                : (value) => setState(
                                    () => _mode = value ?? 'apple_pay'),
                            secondary: const Icon(Icons.apple),
                            title: const Text('Apple Pay'),
                          ),
                        if (PaymentPlatformDetector.supportsSamsungPay())
                          RadioListTile<String>(
                            value: 'samsung_pay',
                            groupValue: _mode,
                            onChanged: _paying
                                ? null
                                : (value) => setState(
                                    () => _mode = value ?? 'samsung_pay'),
                            secondary: const Icon(Icons.phone_android_outlined),
                            title: const Text('Samsung Pay'),
                          ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: !PaymentPlatformDetector.paymentsUiEnabled ||
                                _paying ||
                                _billingChecking ||
                                _billingIssue != null ||
                                (_mode == 'saved' &&
                                    (_selectedCardId == null ||
                                        _selectedCardId!.isEmpty))
                            ? null
                            : _completePayment,
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
