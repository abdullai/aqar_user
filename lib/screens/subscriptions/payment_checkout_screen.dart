import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:moyasar/moyasar.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/branding/app_branding.dart';
import '../../core/navigation/dashboard_embedded_route.dart';
import '../../core/payment/payment_checkout_platform.dart';
import '../../core/payment/payment_recovery_coordinator.dart';
import '../../core/payment/plan_price_resolver.dart';
import '../../core/payment/payment_method_manager.dart';
import '../../core/payment/payment_platform_detector.dart';
import '../../core/payment/smart_payment_flow.dart';
import '../../core/payment/moyasar_web_3ds.dart';
import '../../core/session/app_session.dart';
import '../../core/subscription/subscription_billing_context.dart';
import '../../core/utils/app_money.dart';
import '../../l10n/app_localizations.dart';
import '../../services/payment_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/app_logo_loading.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import '../../widgets/fal_support_whatsapp_row.dart';
import '../../widgets/subscription/subscription_ui_helpers.dart';
import 'add_payment_card_screen.dart';
import 'moyasar_subscription_payment_screen.dart';
import 'payment_receipt_screen.dart';

class PaymentCheckoutScreen extends StatefulWidget {
  const PaymentCheckoutScreen({
    super.key,
    required this.lang,
    required this.accountType,
    required this.plan,
    required this.period,
    this.organizationId,
    this.renewSubscriptionId,
    this.upgradeSubscriptionId,
    this.periodSwitchSubscriptionId,
    this.chargeAmountOverride,
    this.billingContext,
  });

  final String lang;
  final String accountType;
  final Map<String, dynamic> plan;
  final String period;
  final String? organizationId;
  final String? renewSubscriptionId;
  final String? upgradeSubscriptionId;
  /// تحويل شهري → سنوي لنفس الباقة بعد احتساب الفرق.
  final String? periodSwitchSubscriptionId;
  /// مبلغ التحصيل (ترقية باقة / تحويل فترة / إلخ). إن لم يُمرَّر يُستخدم سعر الباقة للفترة المختارة.
  final double? chargeAmountOverride;
  final SubscriptionBillingContext? billingContext;

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  final _pay = PaymentService(Supabase.instance.client);
  final _sub = SubscriptionService(Supabase.instance.client);
  final _auth = LocalAuthentication();

  bool _loading = true;
  bool _paying = false;
  bool _processingOverlayShown = false;
  bool _recoveringPending = false;
  AppSession? _session;
  bool _savedCardsExpanded = false;
  List<Map<String, dynamic>> _cards = [];
  String _mode = 'saved';
  String? _selectedCardId;
  bool _autoRenew = true;
  double? _serverExpectedChargeSar;
  late final PlanPriceResolver _prices;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  bool get _isExistingSubscriptionPayment =>
      widget.renewSubscriptionId != null ||
      widget.upgradeSubscriptionId != null ||
      widget.periodSwitchSubscriptionId != null;

  bool _cardRowIsMoyasarReady(Map<String, dynamic> row) =>
      PaymentService.canChargeSavedCard(row);

  Future<void> _selectSavedCardAndMaybePay(Map<String, dynamic> c) async {
    if (_paying) return;
    if (PaymentService.isCardExpired(c)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr ? 'انتهت صلاحية هذه البطاقة' : 'This card has expired',
          ),
        ),
      );
      return;
    }
    setState(() {
      _mode = 'saved';
      _selectedCardId = '${c['id']}';
    });
    if (PaymentService.canChargeSavedCard(c) &&
        PaymentService.useMoyasarLiveFlow) {
      await _complete();
    }
  }

  Map<String, dynamic>? _cardRowById(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    for (final c in _cards) {
      if ('${c['id']}' == id) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (!_isOneTimePeriod && widget.period == 'monthly') {
      _autoRenew = true;
    } else {
      _autoRenew = false;
    }
    _prices = PlanPriceResolver(widget.plan);
    _prices.debugLog(widget.period);
    PaymentService.configureMoyasarCallbackUrlFromEnv();
    _loadCards();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prefetchServerCharge());
      if (!mounted) return;
      _session = context.read<AppSession>();
      _session!.addListener(_onConnectivityRestored);
      unawaited(_tryRecoverPendingPayment());
    });
  }

  @override
  void dispose() {
    _session?.removeListener(_onConnectivityRestored);
    super.dispose();
  }

  void _onConnectivityRestored() {
    if (_session?.hasInternet == true && !_paying && !_recoveringPending) {
      unawaited(_tryRecoverPendingPayment());
    }
  }

  Future<void> _tryRecoverPendingPayment() async {
    if (_recoveringPending || _paying || !mounted) return;
    final pending = await PaymentRecoveryCoordinator.loadPending();
    if (pending == null) return;
    final bid = '${pending['billing_transaction_id'] ?? ''}'.trim();
    if (bid.isEmpty) return;
    final expected = pending['expected_amount_sar'];
    final amount = expected is num ? expected.toDouble() : _chargeAmount;
    if (!_session!.hasInternet) return;

    _recoveringPending = true;
    final poll = await _pollBillingWithOverlay(
      billingTransactionId: bid,
      expectedAmountSar: amount,
      trackPending: false,
    );
    _recoveringPending = false;
    if (!mounted) return;
    if (poll['ok'] == true) {
      await PaymentRecoveryCoordinator.clearPending();
      final name = AppBranding.planNameFromRow(widget.plan, isAr: _isAr);
      final fin = await _finalizeSubscriptionAfterMoyasar(
        billingTransactionId: bid,
        titleAr: 'اشتراك $name',
        titleEn: '$name subscription',
      );
      if (fin['ok'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isAr
                  ? 'تم تأكيد الاشتراك بعد عودة الاتصال.'
                  : 'Subscription confirmed after reconnect.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    }
  }

  bool _ensureOnlineBeforePay() {
    final online = _session?.hasInternet ?? true;
    if (online) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isAr
              ? 'لا يوجد اتصال بالإنترنت — لن يُنفَّذ الدفع حتى عودة الشبكة.'
              : 'No internet — payment will not proceed until you are back online.',
        ),
      ),
    );
    return false;
  }

  /// جلب المبلغ الكانوني من السيرفر عند فتح الشاشة (يُصلح عرض 0.00).
  Future<void> _prefetchServerCharge() async {
    if (widget.chargeAmountOverride != null &&
        widget.chargeAmountOverride! >= 1.0) {
      if (mounted) {
        setState(() => _serverExpectedChargeSar = widget.chargeAmountOverride);
      }
      return;
    }
    final local = _chargeAmount;
    if (local < 1.0 && _prices.priceForPeriod(widget.period) < 1.0) {
      if (kDebugMode) {
        debugPrint(
          '[PaymentCheckout] local charge still 0 — plan keys: '
          'monthly=${widget.plan['price_monthly']} '
          'yearly=${widget.plan['price_yearly']}',
        );
      }
    }
    try {
      final intent = await _sub.validatePaymentIntent(
        planId: '${widget.plan['id']}',
        period: widget.period,
        amountSar: local > 0 ? local : _prices.priceForPeriod(widget.period),
        withAutoPay: _autoRenew && !_isExistingSubscriptionPayment,
        upgradeSubscriptionId: widget.upgradeSubscriptionId,
      );
      if (!mounted) return;
      if (intent['ok'] == true) {
        final exp = intent['expected_amount'] ?? intent['expected'];
        if (exp is num && exp.toDouble() >= 1.0) {
          setState(() => _serverExpectedChargeSar = exp.toDouble());
          if (kDebugMode) {
            debugPrint(
              '[PaymentCheckout] server expected_amount=${exp.toDouble()}',
            );
          }
        }
      } else if (kDebugMode) {
        debugPrint('[PaymentCheckout] prefetch intent error: $intent');
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[PaymentCheckout] prefetch failed: $e\n$st');
    }
  }

  Future<void> _loadCards() async {
    setState(() => _loading = true);
    if (PaymentService.useMoyasarLiveFlow) {
      await _pay.purgeMockSavedCards();
    }
    var c = await _pay.getSavedCards();
    c = c
        .where((row) => !PaymentService.isMockCardToken(row['card_token']))
        .toList();
    if (!mounted) return;
    String? sel;
    for (final row in c) {
      if (row['is_default'] == true &&
          PaymentService.canChargeSavedCard(row)) {
        sel = '${row['id']}';
        break;
      }
    }
    sel ??= () {
      for (final row in c) {
        if (PaymentService.canChargeSavedCard(row)) return '${row['id']}';
      }
      return null;
    }();
    var mode = c.any(PaymentService.canChargeSavedCard) ? 'saved' : 'new';
    if (mounted) {
      final flow = SmartPaymentFlow(
        context: context,
        isAr: _isAr,
        hasSavedCards: c.isNotEmpty,
        savedCardReady: c.any(PaymentService.canChargeSavedCard),
      );
      mode = flow.resolveDefaultMode();
      mode = PaymentCheckoutPlatform.normalizeMode(context, mode);
    }
    setState(() {
      _cards = c;
      _selectedCardId = sel;
      _mode = mode;
      _loading = false;
    });
  }

  double get _monthly => _prices.monthly;

  double get _yearly => _prices.yearly;

  double get _originalAnnual => _monthly * 12;

  double get _discount => (_originalAnnual - _yearly).clamp(0, 1e12);

  double get _total => _prices.priceForPeriod(widget.period);

  double get _autoPayPct => _prices.autoPayDiscountPercent();

  double get _autoPayDiscount {
    if (!_autoRenew || _isExistingSubscriptionPayment) return 0.0;
    final factor = (_autoPayPct / 100.0).clamp(0.0, 1.0);
    return double.parse((_total * factor).toStringAsFixed(2));
  }

  double get _chargeAmount => _prices.chargeAmount(
        period: widget.period,
        withAutoPay: _autoRenew,
        isExistingSubscription: _isExistingSubscriptionPayment,
        override: widget.chargeAmountOverride,
      );

  /// المبلغ النهائي للدفع — يفضّل القيمة المُتحقق منها من السيرفر ثم الإجمالي.
  double _effectiveChargeForPayment() {
    final server = _serverExpectedChargeSar;
    if (server != null && server >= 1.0) return server;

    final local = _chargeAmount;
    if (local >= 1.0) return local;

    if (widget.chargeAmountOverride != null &&
        widget.chargeAmountOverride! >= 1.0) {
      return widget.chargeAmountOverride!;
    }

    if (_total >= 1.0) return _total;

    return local;
  }

  String _moyasarPurpose() {
    if (widget.periodSwitchSubscriptionId != null) return 'period_switch';
    if (widget.renewSubscriptionId != null) return 'renew';
    if (widget.upgradeSubscriptionId != null) return 'upgrade';
    return 'subscribe_new';
  }

  String _paymentModeKey() {
    if (_mode == 'apple_pay') return 'apple_pay';
    if (_mode == 'google_pay') return 'google_pay';
    if (_mode == 'stc_pay') return 'stc_pay';
    if (_mode == 'mada_pay') return 'mada_pay';
    return 'card';
  }

  /// الدفع من بطاقة محفوظة — مدى/جوجل/بطاقة جديدة تمر عبر نموذج ميسّر مباشرة.
  bool _shouldUseSavedCardForPayment() {
    if (_mode == 'new') return false;
    if (PaymentService.useMoyasarLiveFlow &&
        (_mode == 'mada_pay' ||
            _mode == 'google_pay' ||
            _mode == 'apple_pay' ||
            _mode == 'stc_pay')) {
      return false;
    }
    if (_cards.isEmpty) return false;
    if (!PaymentService.useMoyasarLiveFlow) {
      if (_mode == 'saved') {
        return _selectedCardId != null && _selectedCardId!.trim().isNotEmpty;
      }
      if (_mode == 'mada_pay') return true;
      return false;
    }
    if (_mode == 'saved') {
      final row = _cardRowById(_selectedCardId);
      return row != null && _cardRowIsMoyasarReady(row);
    }
    if (_mode == 'mada_pay') {
      final madaCards = _cards
          .where(
            (c) =>
                '${c['card_scheme']}'.toLowerCase() == 'mada' &&
                _cardRowIsMoyasarReady(c),
          )
          .toList();
      return madaCards.isNotEmpty;
    }
    return false;
  }

  String? _resolvedSavedCardId() {
    if (_cards.isEmpty) return null;
    if (_mode == 'mada_pay') {
      final madaCards = _cards
          .where((c) => '${c['card_scheme']}'.toLowerCase() == 'mada')
          .toList();
      if (madaCards.isNotEmpty) {
        if (_selectedCardId != null &&
            madaCards.any((c) => '${c['id']}' == _selectedCardId)) {
          return _selectedCardId;
        }
        return '${madaCards.first['id']}';
      }
    }
    if (_selectedCardId != null && _selectedCardId!.trim().isNotEmpty) {
      return _selectedCardId;
    }
    return '${_cards.first['id']}';
  }

  Future<Map<String, dynamic>> _payWithSavedCardMock({
    required String titleAr,
    required String titleEn,
  }) async {
    final cardId = _resolvedSavedCardId();
    if (cardId == null || cardId.isEmpty) {
      return {'ok': false, 'error': 'no_card'};
    }
    final pm0 = 'card';
    if (widget.renewSubscriptionId != null) {
      return _sub.renewSubscription(
        subscriptionId: widget.renewSubscriptionId!,
        paymentMode: pm0,
        cardId: cardId,
        autoRenewAfterPayment: _autoRenew,
      );
    }
    if (widget.upgradeSubscriptionId != null) {
      return _sub.upgradePlan(
        subscriptionId: widget.upgradeSubscriptionId!,
        newPlanId: '${widget.plan['id']}',
        paymentMode: pm0,
        cardId: cardId,
        billedAmountSar: widget.chargeAmountOverride,
      );
    }
    return _sub.subscribeToPlan(
      planId: '${widget.plan['id']}',
      period: widget.period,
      paymentMode: pm0,
      cardId: cardId,
      organizationId: widget.organizationId,
      titleAr: titleAr,
      titleEn: titleEn,
      autoRenew: _autoRenew,
    );
  }

  Future<Map<String, dynamic>> _payWithSavedCardMoyasar({
    required double charge,
    required String titleAr,
    required String titleEn,
    required String pm,
  }) async {
    final cardId = _resolvedSavedCardId();
    if (cardId == null || cardId.isEmpty) {
      return {'ok': false, 'error': 'no_card'};
    }
    final cardRow = _cardRowById(cardId);
    if (cardRow != null && PaymentService.isCardExpired(cardRow)) {
      return {'ok': false, 'error': 'card_expired'};
    }
    if (cardRow != null && !_cardRowIsMoyasarReady(cardRow)) {
      return {'ok': false, 'error': 'mock_token_use_new_card'};
    }
    final pend = await _pay.createPendingBillingTransaction(
      amount: charge,
      subscriptionId: widget.periodSwitchSubscriptionId ??
          widget.renewSubscriptionId ??
          widget.upgradeSubscriptionId,
      titleAr: titleAr,
      titleEn: titleEn,
      paymentMethod: pm == 'mada_pay' ? 'mada_pay' : 'card',
      cardId: cardId,
    );
    if (pend['ok'] != true) {
      return {'ok': false, 'error': pend['error'] ?? 'pending_tx'};
    }
    final bid = '${pend['transaction_id'] ?? ''}'.trim();
    final chargeRes = await _pay.chargeSavedCardViaMoyasar(
      billingTransactionId: bid,
      cardId: cardId,
      purpose: _moyasarPurpose(),
    );
    if (chargeRes['error'] == 'mock_token') {
      return {
        'ok': false,
        'error': 'mock_token_use_new_card',
      };
    }
    if (chargeRes['ok'] != true) {
      final err = '${chargeRes['error'] ?? 'moyasar_failed'}';
      if (err == 'moyasar_rejected' ||
          err == 'moyasar_auth_error' ||
          err == 'moyasar_account_inactive' ||
          err.startsWith('moyasar_api:')) {
        return {
          'ok': false,
          'error': 'saved_card_charge_failed',
          'detail': chargeRes['moyasar_message'] ?? chargeRes['detail'],
        };
      }
      return {'ok': false, 'error': err};
    }
    final threeDs = '${chargeRes['three_ds_url'] ?? ''}'.trim();
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
    final poll = await _pollBillingWithOverlay(
      billingTransactionId: bid,
      expectedAmountSar: charge,
    );
    if (poll['ok'] == true) {
      return _finalizeSubscriptionAfterMoyasar(
        billingTransactionId: bid,
        titleAr: titleAr,
        titleEn: titleEn,
      );
    }
    return {'ok': false, 'error': poll['error'] ?? 'webhook_timeout'};
  }

  bool get _isOneTimePeriod =>
      widget.period == 'lifetime_one_time' || widget.period == 'one_time';

  /// Apple Pay / مدى عبر محفظة الجوال (Safari iOS أو تطبيق iOS).
  bool _routesToApplePayWallet(String pm) {
    if (!PaymentPlatformDetector.supportsApplePay()) return false;
    return pm == 'apple_pay' || pm == 'mada_pay';
  }

  MoyasarWalletMode? _samsungWalletForGooglePay(String pm) {
    if (pm != 'google_pay') return null;
    if (!PaymentPlatformDetector.isAndroidApp) return null;
    final sid = PaymentService.moyasarSamsungPayServiceId;
    if (sid == null || sid.isEmpty) return null;
    return MoyasarWalletMode.samsungPay;
  }

  Future<Map<String, dynamic>> _payWithMoyasarHostedCheckout({
    required double charge,
    required String titleAr,
    required String titleEn,
    required String pm,
    required MoyasarWalletMode walletMode,
    required bool madaPreferredNetworksOnly,
  }) async {
    if (_shouldUseSavedCardForPayment()) {
      return _payWithSavedCardMoyasar(
        charge: charge,
        titleAr: titleAr,
        titleEn: titleEn,
        pm: pm,
      );
    }

    final paymentMethod = switch (pm) {
      'apple_pay' => 'apple_pay',
      'google_pay' => 'google_pay',
      'mada_pay' => 'mada_pay',
      'stc_pay' => 'stc_pay',
      _ => 'card',
    };

    final pend = await _pay.createPendingBillingTransaction(
      amount: charge,
      subscriptionId: widget.periodSwitchSubscriptionId ??
          widget.renewSubscriptionId ??
          widget.upgradeSubscriptionId,
      titleAr: titleAr,
      titleEn: titleEn,
      paymentMethod: paymentMethod,
    );
    if (pend['ok'] != true) {
      return {'ok': false, 'error': pend['error'] ?? 'pending_tx'};
    }

    final bid = '${pend['transaction_id'] ?? ''}'.trim();
    final meta = _pay.buildMoyasarSubscriptionMetadata(
      billingTransactionId: bid,
      purpose: _moyasarPurpose(),
    );
    final desc = _isAr
        ? 'اشتراك ${AppBranding.shortNameAr} — $titleAr'
        : '${AppBranding.brandNameEn} subscription — $titleEn';

    ApplePayConfig? applePay;
    SamsungPayConfig? samsungPay;
    if (walletMode == MoyasarWalletMode.applePay) {
      final merchantId = PaymentService.moyasarApplePayMerchantId;
      if (merchantId == null || merchantId.isEmpty) {
        return {'ok': false, 'error': 'apple_pay_merchant_missing'};
      }
      applePay = ApplePayConfig(
        merchantId: merchantId,
        label: AppBranding.displayName(isAr: _isAr),
        manual: false,
        saveCard: false,
      );
    } else if (walletMode == MoyasarWalletMode.samsungPay) {
      final serviceId = PaymentService.moyasarSamsungPayServiceId!;
      samsungPay = SamsungPayConfig(
        serviceId: serviceId,
        merchantName: AppBranding.displayName(isAr: _isAr),
        manual: false,
      );
    }

    PaymentConfig? cfg;
    try {
      cfg = _pay.buildMoyasarPaymentConfig(
        amountHalalas: PaymentService.amountToHalalas(charge),
        description: desc.length > 128 ? desc.substring(0, 128) : desc,
        metadata: meta,
        madaPreferredNetworksOnly: madaPreferredNetworksOnly,
        applePay: applePay,
        samsungPay: samsungPay,
      );
    } catch (e, st) {
      debugPrint('[PaymentCheckout] moyasar config: $e\n$st');
      return {'ok': false, 'error': 'moyasar_config_error'};
    }

    if (!mounted) return {'ok': false, 'error': 'unmounted'};

    final planName = AppBranding.planNameFromRow(widget.plan, isAr: _isAr);
    dynamic payResult;
    try {
      _hideProcessingOverlay();
      payResult = await Navigator.of(context).push<dynamic>(
        MaterialPageRoute<dynamic>(
          settings: RouteSettings(
            name: DashboardEmbeddedRoute.shouldUseEmbeddedChrome(context)
                ? '/dashboard/subscriptions/moyasar-pay'
                : '/subscriptions/moyasar-pay',
          ),
          builder: (_) => MoyasarSubscriptionPaymentScreen(
            config: cfg!,
            walletMode: walletMode,
            isAr: _isAr,
            planName: planName,
            amountSar: charge,
            periodLabel: widget.period == 'yearly'
                ? (_isAr ? 'سنوي' : 'Yearly')
                : widget.period == 'lifetime_one_time'
                    ? (_isAr ? 'مرة واحدة' : 'One-time')
                    : (_isAr ? 'شهري' : 'Monthly'),
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('Moyasar checkout error: $e\n$st');
      return {'ok': false, 'error': 'moyasar_widget_error'};
    }

    if (!mounted) return {'ok': false, 'error': 'unmounted'};
    if (payResult is PaymentResponse &&
        PaymentService.moyasarPaymentSucceeded(payResult)) {
      if (walletMode == MoyasarWalletMode.none) {
        unawaited(_pay.persistMoyasarCardFromPaymentResponse(payResult));
      }
      final poll = await _pollBillingWithOverlay(
        billingTransactionId: bid,
        expectedAmountSar: charge,
      );
      if (poll['ok'] == true) {
        return _finalizeSubscriptionAfterMoyasar(
          billingTransactionId: bid,
          titleAr: titleAr,
          titleEn: titleEn,
        );
      }
      return {'ok': false, 'error': poll['error'] ?? 'webhook_timeout'};
    }

    return {
      'ok': false,
      'error': PaymentService.mapMoyasarResultToError(payResult) ??
          'moyasar_cancelled_or_failed',
    };
  }

  Future<void> _payWithWalletMode(String mode) async {
    if (_paying) return;
    setState(() => _mode = mode);
    await _complete();
  }

  Future<Map<String, dynamic>> _pollBillingWithOverlay({
    required String billingTransactionId,
    required double expectedAmountSar,
    bool trackPending = true,
  }) async {
    if (trackPending) {
      await PaymentRecoveryCoordinator.savePending(
        billingTransactionId: billingTransactionId,
        expectedAmountSar: expectedAmountSar,
        planId: '${widget.plan['id']}',
        period: widget.period,
      );
    }
    _showProcessingOverlay();
    try {
      final result = await _pay.pollUntilBillingTransactionPaid(
        billingTransactionId: billingTransactionId,
        expectedAmountSar: expectedAmountSar,
      );
      if (result['ok'] == true) {
        await PaymentRecoveryCoordinator.clearPending();
      }
      return result;
    } finally {
      _hideProcessingOverlay();
    }
  }

  Future<bool> _maybeBiometric() async {
    try {
      final reason =
          AppLocalizations.of(context)!.subscriptionsAuthenticateToPay;
      final can = await _auth.canCheckBiometrics;
      if (!can) return true;
      final ok = await _auth.authenticate(localizedReason: reason);
      return ok;
    } catch (_) {
      return true;
    }
  }

  void _showProcessingOverlay() {
    if (_processingOverlayShown || !mounted) return;
    _processingOverlayShown = true;
    unawaited(
      showDialog<void>(
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
                  _isAr ? 'جاري إكمال الدفع...' : 'Processing payment...',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _isAr
                      ? 'يرجى الانتظار حتى اكتمال العملية'
                      : 'Please wait until the process completes',
                  style: Theme.of(ctx).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideProcessingOverlay() {
    if (!_processingOverlayShown || !mounted) return;
    _processingOverlayShown = false;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  Future<void> _complete() async {
    final t = AppLocalizations.of(context)!;
    if (!_ensureOnlineBeforePay()) return;
    if (Supabase.instance.client.auth.currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'انتهت جلستك — سجّل الدخول ثم أعد المحاولة.'
                : 'Session expired — sign in and try again.',
          ),
        ),
      );
      return;
    }
  final falCtx = widget.billingContext;
    if (falCtx != null && falCtx.ok && falCtx.falBlocksPayment) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            _isAr ? 'رخصة فال مطلوبة' : 'FAL license required',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isAr
                      ? 'رخصة فال منتهية أو موقوفة — يُوقف الدفع حتى التجديد أو التحديث.'
                      : 'FAL license expired or on hold — payment is blocked until renewal or update.',
                ),
                const SizedBox(height: 12),
                FalSupportWhatsappRow(isAr: _isAr, inline: false),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_isAr ? 'حسناً' : 'OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (_mode == 'new' && !PaymentService.useMoyasarLiveFlow) {
      final added = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AddPaymentCardScreen(lang: widget.lang),
        ),
      );
      if (added != true || !mounted) return;
      await _loadCards();
      if (_cards.isEmpty) return;
      setState(() {
        _mode = 'saved';
        _selectedCardId = '${_cards.first['id']}';
      });
    }
    if (!await _maybeBiometric()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.subscriptionsBiometricFailed)),
      );
      return;
    }

    _serverExpectedChargeSar = null;

    // طبقة أمنية: تحقّق سيرفر-سايد قبل أي تحصيل (مبلغ كانوني + حد معدّل +
    // أحقيّة الاشتراك).
    final needsIntentValidation = widget.renewSubscriptionId == null &&
        widget.upgradeSubscriptionId == null &&
        widget.periodSwitchSubscriptionId == null;
    if (needsIntentValidation || _effectiveChargeForPayment() < 1.0) {
      final intent = await _sub.validatePaymentIntent(
        planId: '${widget.plan['id']}',
        period: widget.period,
        amountSar: _chargeAmount > 0 ? _chargeAmount : _total,
        withAutoPay: _autoRenew && !_isExistingSubscriptionPayment,
        upgradeSubscriptionId: widget.upgradeSubscriptionId,
      );
      if (intent['ok'] == true) {
        final exp = intent['expected_amount'] ?? intent['expected'];
        if (exp is num && exp.toDouble() >= 1.0) {
          _serverExpectedChargeSar = exp.toDouble();
          if (kDebugMode) {
            debugPrint(
              '[PaymentCheckout] validatePaymentIntent expected=$exp',
            );
          }
        }
      } else if (needsIntentValidation) {
        if (!mounted) return;
        final err = '${intent['error'] ?? ''}';
        String msg;
        if (err == 'rate_limited') {
          final m = intent['retry_after_minutes'] ?? 10;
          msg = _isAr
              ? 'تم تجاوز عدد محاولات الدفع. حاول مجدّداً بعد $m دقيقة.'
              : 'Too many payment attempts. Try again in $m minutes.';
        } else if (err == 'amount_mismatch') {
          final exp = intent['expected'] ?? '?';
          msg = _isAr
              ? 'تعذّر التحقق من المبلغ. المبلغ الصحيح: ${AppMoney.formatWithCurrencyCode(exp is num ? exp.toDouble() : 0, isAr: true)}. حدّث الصفحة.'
              : 'Amount validation failed. Correct amount: ${AppMoney.formatWithCurrencyCode(exp is num ? exp.toDouble() : 0, isAr: false)}. Refresh.';
        } else if (err == 'team_member_uses_owner_subscription') {
          msg = _isAr
              ? 'كعضو في فريق لا يمكنك الاشتراك بنفسك — يستفيد من اشتراك المالك.'
              : 'As a team member you inherit the owner\'s subscription.';
        } else if (err == 'already_active_subscription') {
          msg = _isAr
              ? 'لديك اشتراك فعّال — استخدم «ترقية الباقة» بدلاً من اشتراك جديد.'
              : 'You have an active subscription — use «Upgrade plan» instead.';
        } else {
          msg = _isAr
              ? 'تعذّر التحقق من نيّة الدفع. حاول لاحقاً.'
              : 'Payment intent validation failed. Try later.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
    }

    final charge = _effectiveChargeForPayment();
    if (charge < 1.0) {
      if (!mounted) return;
      final due = AppMoney.formatWithCurrencyCode(
        charge,
        isAr: _isAr,
        maxFractionDigits: 2,
      );
      final total = AppMoney.formatWithCurrencyCode(
        _total,
        isAr: _isAr,
        maxFractionDigits: 2,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'المبلغ المستحق ($due) أقل من الحد الأدنى للدفع (1 ر.س). إجمالي الباقة: $total'
                : 'Amount due ($due) is below the minimum charge (1 SAR). Plan total: $total',
          ),
        ),
      );
      return;
    }

    setState(() => _paying = true);
    Map<String, dynamic> res = {'ok': false};
    try {
      await SmartPaymentFlow.logMethodChosen(
        sb: Supabase.instance.client,
        mode: _mode,
        amountSar: charge,
      );
      final planLabel = AppBranding.planNameFromRow(widget.plan, isAr: _isAr);
      final titleAr = AppBranding.billingTitleForCheckout(
        planLabel: planLabel,
        period: widget.period,
        isAr: true,
      );
      final titleEn = AppBranding.billingTitleForCheckout(
        planLabel: planLabel,
        period: widget.period,
        isAr: false,
      );
      final pm = _paymentModeKey();
      final useMs = PaymentService.useMoyasarLiveFlow;

      if (useMs && _routesToApplePayWallet(pm)) {
        res = await _payWithMoyasarHostedCheckout(
          charge: charge,
          titleAr: titleAr,
          titleEn: titleEn,
          pm: pm,
          walletMode: MoyasarWalletMode.applePay,
          madaPreferredNetworksOnly: pm == 'mada_pay',
        );
      } else if (useMs && _samsungWalletForGooglePay(pm) != null) {
        res = await _payWithMoyasarHostedCheckout(
          charge: charge,
          titleAr: titleAr,
          titleEn: titleEn,
          pm: pm,
          walletMode: MoyasarWalletMode.samsungPay,
          madaPreferredNetworksOnly: false,
        );
      } else if (useMs && pm == 'google_pay') {
        res = {'ok': false, 'error': 'google_pay_wallet_unavailable'};
      } else if (useMs &&
          (pm == 'card' || pm == 'mada_pay' || pm == 'stc_pay')) {
        res = await _payWithMoyasarHostedCheckout(
          charge: charge,
          titleAr: titleAr,
          titleEn: titleEn,
          pm: pm,
          walletMode: MoyasarWalletMode.none,
          madaPreferredNetworksOnly: pm == 'mada_pay',
        );
      } else if (widget.renewSubscriptionId != null) {
        final pm0 = _paymentModeKey();
        final savedId = _shouldUseSavedCardForPayment()
            ? _resolvedSavedCardId()
            : (_mode == 'saved' ? _selectedCardId : null);
        res = await _sub.renewSubscription(
          subscriptionId: widget.renewSubscriptionId!,
          paymentMode: pm0,
          cardId: savedId,
          autoRenewAfterPayment: _autoRenew,
        );
      } else if (widget.upgradeSubscriptionId != null) {
        final pm0 = _paymentModeKey();
        final savedId = _shouldUseSavedCardForPayment()
            ? _resolvedSavedCardId()
            : (_mode == 'saved' ? _selectedCardId : null);
        res = await _sub.upgradePlan(
          subscriptionId: widget.upgradeSubscriptionId!,
          newPlanId: '${widget.plan['id']}',
          paymentMode: pm0,
          cardId: savedId,
          billedAmountSar: widget.chargeAmountOverride,
        );
      } else {
        final pm0 = _paymentModeKey();
        final savedId = _shouldUseSavedCardForPayment()
            ? _resolvedSavedCardId()
            : (_mode == 'saved' ? _selectedCardId : null);
        String? cardId;
        if (pm0 == 'card' || pm0 == 'mada_pay') {
          cardId = savedId ?? _selectedCardId;
        }
        res = await _sub.subscribeToPlan(
          planId: '${widget.plan['id']}',
          period: widget.period,
          paymentMode: pm0,
          cardId: cardId,
          organizationId: widget.organizationId,
          titleAr: titleAr,
          titleEn: titleEn,
          autoRenew: _autoRenew,
        );
      }
    } finally {
      _hideProcessingOverlay();
      if (mounted) setState(() => _paying = false);
    }
    if (!mounted) return;
    final err = '${res['error'] ?? ''}';
    String msg;
    if (res['ok'] == true) {
      msg = t.subscriptionsPaymentSuccess;
    } else if (err == 'mock_token' || err == 'mock_token_use_new_card') {
      msg = _isAr
          ? 'هذه البطاقة تحتاج إعادة التحقق — اختر «بطاقة جديدة» وأتمم الدفع مرة واحدة.'
          : 'This card needs re-verification — choose “New card” and pay once.';
    } else if (err == 'card_expired') {
      msg = _isAr
          ? 'انتهت صلاحية البطاقة — اختر بطاقة أخرى أو أضف بطاقة جديدة.'
          : 'Card expired — pick another card or add a new one.';
    } else if (err == 'moyasar_config_error') {
      msg = _isAr
          ? 'إعدادات الدفع غير مكتملة (مفتاح ميسّر أو رابط 3DS). راجع supabase_config.json.'
          : 'Payment settings incomplete (Moyasar key or 3DS callback). Check supabase_config.json.';
    } else if (err == 'payment_gateway_not_configured') {
      msg = _isAr
          ? 'بوابة الدفع غير مفعّلة. أضف مفتاح ميسّر (MOYASAR_PUBLISHABLE_KEY) ثم أعد البناء.'
          : 'Payment gateway is not configured. Set MOYASAR_PUBLISHABLE_KEY and rebuild.';
    } else if (err == 'moyasar_widget_error') {
      msg = _isAr
          ? 'تعذّر فتح نموذج الدفع. حدّث الصفحة وحاول مجدداً.'
          : 'Could not open the payment form. Refresh and try again.';
    } else if (err == 'moyasar_account_inactive') {
      msg = _isAr
          ? 'حساب ميسّر غير مفعّل للدفع الحقيقي (خطأ 405). للتجربة: pk_test_ + sk_test_ في Supabase. للإنتاج: فعّل الحساب عند ميسّر.'
          : 'Moyasar live account not activated (HTTP 405). For testing use pk_test_ + sk_test_; for production activate live mode at Moyasar.';
    } else if (err == 'moyasar_auth_error') {
      msg = _isAr
          ? 'مفتاح ميسّر مرفوض (401). تأكد من pk_test_ في supabase_config.json وsk_test_ الكامل في Supabase Secrets.'
          : 'Moyasar key rejected (401). Verify pk_test_ in supabase_config.json and full sk_test_ in Supabase Secrets.';
    } else if (err == 'amount_too_low') {
      final due = AppMoney.formatWithCurrencyCode(
        _effectiveChargeForPayment(),
        isAr: _isAr,
        maxFractionDigits: 2,
      );
      final total = AppMoney.formatWithCurrencyCode(
        _total,
        isAr: _isAr,
        maxFractionDigits: 2,
      );
      msg = _isAr
          ? 'المبلغ المستحق ($due) أقل من الحد الأدنى للدفع (1 ر.س). إجمالي الباقة: $total'
          : 'Amount due ($due) is below the minimum charge (1 SAR). Plan total: $total';
    } else if (err.startsWith('moyasar_validation:') ||
        err.startsWith('moyasar_api:')) {
      final detail = err.contains(':') ? err.split(':').skip(1).join(':').trim() : '';
      msg = _isAr
          ? (detail.isNotEmpty
              ? 'رفض ميسّر: $detail'
              : 'بيانات الدفع مرفوضة من ميسّر.')
          : (detail.isNotEmpty
              ? 'Moyasar rejected: $detail'
              : 'Payment data rejected by Moyasar.');
    } else if (err == 'moyasar_validation_error') {
      msg = _isAr
          ? 'بيانات البطاقة أو المبلغ مرفوضة من ميسّر.'
          : 'Card or amount rejected by Moyasar.';
    } else if (err == 'apple_pay_merchant_missing') {
      msg = _isAr
          ? 'أضف MOYASAR_APPLE_PAY_MERCHANT_ID في إعدادات البيئة لتفعيل Apple Pay.'
          : 'Set MOYASAR_APPLE_PAY_MERCHANT_ID in env to enable Apple Pay.';
    } else if (err == 'google_pay_wallet_unavailable') {
      msg = _isAr
          ? 'Google Pay غير متاح على هذا الجهاز حالياً — استخدم بطاقة محفوظة أو بطاقة جديدة.'
          : 'Google Pay is not available on this device — use a saved or new card.';
    } else if (err == 'webhook_timeout') {
      msg = _isAr
          ? 'تم الدفع لدى ميسّر؛ جارٍ تأكيد السجل. أعد فتح الباقات خلال دقيقة.'
          : 'Paid at Moyasar; confirming ledger. Reopen plans in a minute.';
    } else if (err == 'cors_or_function_unreachable') {
      msg = _isAr
          ? 'تعذّر الاتصال بخادم الدفع (CORS). أعد نشر دالة moyasar-charge-saved-card على Supabase ثم حاول مجدداً.'
          : 'Could not reach the payment server (CORS). Redeploy the moyasar-charge-saved-card Edge Function on Supabase, then retry.';
    } else if (err == 'saved_card_charge_failed') {
      setState(() => _mode = 'new');
      final detail = '${res['detail'] ?? ''}'.trim();
      msg = _isAr
          ? (detail.isNotEmpty
              ? 'تعذّر خصم البطاقة المحفوظة: $detail — جرّب «بطاقة جديدة».'
              : 'تعذّر خصم البطاقة المحفوظة — اختر «بطاقة جديدة» وأتمم الدفع مرة واحدة.')
          : (detail.isNotEmpty
              ? 'Saved card charge failed: $detail — try “New card”.'
              : 'Saved card charge failed — choose “New card” and pay once.');
    } else if (err == 'moyasar_rejected') {
      setState(() => _mode = 'new');
      msg = _isAr
          ? 'رفض البنك/ميسّر العملية — جرّب «بطاقة جديدة».'
          : 'Bank/Moyasar rejected the charge — try “New card”.';
    } else if (err == 'moyasar_cancelled_or_failed') {
      msg = _isAr ? 'أُلغيت العملية أو فشل الدفع.' : 'Payment was cancelled or failed.';
    } else if (err == 'duplicate_active_same_plan' ||
        err == 'active_plan_conflict') {
      msg = _isAr
          ? 'لديك اشتراك فعّال. جدّد عند الانتهاء أو رقِّ الباقة أو حوّل للسنوي من شاشة الباقات.'
          : 'You already have an active subscription. Renew when it ends, upgrade, or switch billing period from the plans screen.';
    } else if (err == 'use_upgrade_flow') {
      msg = _isAr
          ? 'استخدم «ترقية الباقة» من بطاقة الباقة الأعلى.'
          : 'Use «Upgrade plan» from the higher-tier plan card.';
    } else if (err == 'use_period_switch_flow') {
      msg = _isAr
          ? 'لتحويل الفترة إلى سنوي استخدم زر التحويل من نفس الباقة عند اختيار «سنوي».'
          : 'To switch to yearly billing, use the switch action on the same plan when «Yearly» is selected.';
    } else if (err == 'upgrade_only_higher_tier') {
      msg = _isAr
          ? 'الترقية متاحة لباقة أعلى فقط (حسب ترتيب الباقات).'
          : 'Upgrades are only allowed to a higher-tier plan.';
    } else if (err == 'auth') {
      msg = _isAr
          ? 'انتهت جلستك أثناء الدفع — سجّل الدخول ثم راجع الفواتير أو أعد المحاولة.'
          : 'Session expired during payment — sign in, check invoices, or retry.';
    } else if (err == 'team_member_not_allowed_to_subscribe') {
      msg = _isAr
          ? 'كعضو في فريق لا يمكنك الاشتراك بنفسك — تستفيد تلقائياً من اشتراك المالك. يرجى مطالبة المالك بالاشتراك أو ترقية باقته.'
          : 'As a team member you cannot subscribe yourself — you inherit the owner\'s subscription. Ask the owner to subscribe or upgrade.';
    } else if (err == 'topup_requires_main_subscription') {
      msg = _isAr
          ? 'لشراء «طلبات إضافية» يجب أن يكون لديك اشتراك رئيسي فعّال أوّلاً.'
          : 'A main active subscription is required before purchasing add-on listing requests.';
    } else {
      msg = t.subscriptionsPaymentFailed;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    if (res['ok'] == true) {
      SubscriptionService.invalidateSubscriptionCache();
      // اعرض إيصال دفع كامل قبل العودة للصفحة التي أتى منها المستخدم.
      await _showReceiptAndReturn(res);
    }
  }

  /// يعرض شاشة إيصال الدفع ثم يُغلق شاشة الدفع بـ true ليُكمل سير الاستئناف.
  Future<void> _showReceiptAndReturn(Map<String, dynamic> res) async {
    if (!mounted) return;
    final t = AppLocalizations.of(context)!;

    String planName = AppBranding.planNameFromRow(widget.plan, isAr: _isAr);
    if (planName.trim().isEmpty) planName = '—';

    final tx = '${res['billing_transaction_id'] ?? res['transaction_id'] ?? res['payment_id'] ?? ''}'
        .trim();
    final subId = '${res['subscription_id'] ?? res['id'] ?? ''}'.trim();
    final cardLast4 = _selectedCardLast4();
    final pmLabel = _paymentMethodLabel(t);

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaymentReceiptScreen(
          lang: widget.lang,
          planName: planName,
          period: widget.period,
          amountSar: _chargeAmount,
          paymentMethodLabel: pmLabel,
          transactionId: tx.isNotEmpty ? tx : (subId.isNotEmpty ? subId : 'N/A'),
          completedAt: DateTime.now(),
          subscriptionId: subId.isEmpty ? null : subId,
          cardLast4: cardLast4,
          purpose: _moyasarPurpose(),
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String? _selectedCardLast4() {
    final id = _selectedCardId;
    if (id == null) return null;
    for (final c in _cards) {
      if ('${c['id']}' == id) {
        final v = '${c['last4'] ?? c['card_last4'] ?? ''}'.trim();
        return v.isEmpty ? null : v;
      }
    }
    return null;
  }

  String _paymentMethodLabel(AppLocalizations t) {
    switch (_mode) {
      case 'apple_pay':
        return 'Apple Pay';
      case 'google_pay':
        return 'Google Pay';
      case 'mada_pay':
        return _isAr ? 'مدى' : 'mada';
      case 'new':
        return _isAr ? 'بطاقة جديدة' : 'New card';
      case 'saved':
      default:
        return _isAr ? 'بطاقة محفوظة' : 'Saved card';
    }
  }

  Future<Map<String, dynamic>> _finalizeSubscriptionAfterMoyasar({
    required String billingTransactionId,
    required String titleAr,
    required String titleEn,
  }) async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {}
    if (Supabase.instance.client.auth.currentUser == null) {
      return {'ok': false, 'error': 'auth'};
    }
    final pm = _paymentModeKey();
    if (widget.periodSwitchSubscriptionId != null) {
      return _sub.switchSubscriptionToYearlyAfterPayment(
        subscriptionId: widget.periodSwitchSubscriptionId!,
        verifiedBillingTransactionId: billingTransactionId,
        expectedChargeSar: _chargeAmount,
        organizationId: widget.organizationId,
        autoRenew: _autoRenew,
      );
    }
    if (widget.renewSubscriptionId != null) {
      return _sub.renewSubscription(
        subscriptionId: widget.renewSubscriptionId!,
        paymentMode: pm,
        verifiedBillingTransactionId: billingTransactionId,
        autoRenewAfterPayment: _autoRenew,
      );
    }
    if (widget.upgradeSubscriptionId != null) {
      return _sub.upgradePlan(
        subscriptionId: widget.upgradeSubscriptionId!,
        newPlanId: '${widget.plan['id']}',
        paymentMode: pm,
        verifiedBillingTransactionId: billingTransactionId,
        billedAmountSar: _chargeAmount,
      );
    }
    return _sub.subscribeToPlan(
      planId: '${widget.plan['id']}',
      period: widget.period,
      paymentMode: pm,
      organizationId: widget.organizationId,
      titleAr: titleAr,
      titleEn: titleEn,
      verifiedBillingTransactionId: billingTransactionId,
      autoRenew: _autoRenew && widget.period == 'monthly',
      billedAmountSar: _effectiveChargeForPayment(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final name = AppBranding.planNameFromRow(widget.plan, isAr: _isAr);
    final embedded = DashboardEmbeddedRoute.shouldUseEmbeddedChrome(context);
    final paymentMethods = PaymentMethodManager.selectableMethods(
      context: context,
      hasSavedCards: _cards.isNotEmpty,
      savedCardReady: _cards.any(PaymentService.canChargeSavedCard),
    );
    final showAppleWallet = PaymentPlatformDetector.supportsApplePay();
    final showGoogleWallet = _samsungWalletForGooglePay('google_pay') != null;
    final showMadaWallet = PaymentPlatformDetector.supportsMada();
    final mockCheckout = !PaymentService.useMoyasarLiveFlow &&
        PaymentService.allowMockGateway;
    final otherPaymentMethods = paymentMethods.where((m) {
      final mode = PaymentMethodManager.modeKey(m);
      if (mode == 'google_pay' && !showGoogleWallet) return false;
      if (mode == 'apple_pay' && showAppleWallet) return false;
      if (mode == 'google_pay' && showGoogleWallet) return false;
      if (mode == 'mada_pay' && showMadaWallet) return false;
      return true;
    }).toList();

    final body = _loading
        ? const Center(child: AppLogoLoading())
        : AqarPrimaryScrollScope(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (embedded)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        t.subscriptionsCheckoutTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  SubscriptionUiHelpers.section(
                    context: context,
                    title: t.subscriptionsCheckoutTitle,
                    children: [
                      SubscriptionUiHelpers.tableRow(
                        context: context,
                        label: t.subscriptionsPlanLine,
                        value: name,
                      ),
                      SubscriptionUiHelpers.tableRow(
                        context: context,
                        label: t.subscriptionsPeriodLine,
                        value: widget.period == 'lifetime_one_time'
                            ? (_isAr ? 'مرة واحدة' : 'One-time')
                            : widget.period == 'yearly'
                                ? t.subscriptionsYearly
                                : t.subscriptionsMonthly,
                      ),
                      if (widget.period == 'yearly') ...[
                        SubscriptionUiHelpers.priceTableRow(
                          context: context,
                          isAr: _isAr,
                          label: t.subscriptionsOriginalLine,
                          amount: _originalAnnual,
                        ),
                        SubscriptionUiHelpers.priceTableRow(
                          context: context,
                          isAr: _isAr,
                          label: t.subscriptionsDiscountLine,
                          amount: _discount,
                          negative: true,
                        ),
                      ],
                      if (widget.chargeAmountOverride == null &&
                          _autoRenew &&
                          !_isExistingSubscriptionPayment)
                        SubscriptionUiHelpers.priceTableRow(
                          context: context,
                          isAr: _isAr,
                          label: _isAr
                              ? 'خصم الدفع التلقائي (${_autoPayPct.toStringAsFixed(0)}%)'
                              : 'Auto-pay discount (${_autoPayPct.toStringAsFixed(0)}%)',
                          amount: _autoPayDiscount,
                          negative: true,
                        ),
                      SubscriptionUiHelpers.priceTableRow(
                        context: context,
                        isAr: _isAr,
                        label: t.subscriptionsTotalLine,
                        amount: _effectiveChargeForPayment(),
                        emphasize: true,
                      ),
                      const SizedBox(height: 4),
                      SubscriptionUiHelpers.legalNote(
                        context: context,
                        isAr: _isAr,
                      ),
                    ],
                  ),
                  if (SubscriptionUiHelpers.showAutoRenewToggleForPeriod(
                    widget.period,
                  ))
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        _isAr ? 'التجديد التلقائي' : 'Auto-renew',
                        style: SubscriptionUiHelpers.denseLabel(context),
                      ),
                      value: _autoRenew,
                      onChanged: (v) {
                        setState(() => _autoRenew = v);
                        unawaited(_prefetchServerCharge());
                      },
                    ),
                  const SizedBox(height: 12),
                  if (!PaymentService.useMoyasarLiveFlow)
                    Card(
                      color: mockCheckout
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          mockCheckout
                              ? (_isAr
                                  ? 'وضع تجريبي محلي — الدفع للمحاكاة حتى تفعيل بوابة ميسّر المعتمدة في المملكة.'
                                  : 'Local trial mode — simulated checkout until Moyasar is activated for Saudi payments.')
                              : (_isAr
                                  ? 'الدفع غير مفعّل — راجع إعدادات ميسّر أو اضبط ALLOW_PAYMENT_MOCK.'
                                  : 'Payments are not configured — check Moyasar settings or ALLOW_PAYMENT_MOCK.'),
                          style: TextStyle(
                            color: mockCheckout
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  Text(
                    t.subscriptionsPaymentMethod,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  if (showAppleWallet || showGoogleWallet || showMadaWallet)
                    _buildWalletQuickPayRow(
                      showApple: showAppleWallet,
                      showGoogle: showGoogleWallet,
                      showMada: showMadaWallet,
                    ),
                  if (_cards.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(
                          () => _savedCardsExpanded = !_savedCardsExpanded,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.credit_card,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _isAr
                                      ? 'بطاقاتي (${_cards.length})'
                                      : 'My cards (${_cards.length})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Icon(
                                _savedCardsExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_savedCardsExpanded) ...[
                      const SizedBox(height: 8),
                      ..._cards.map(_buildSavedCardVisual),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (_cards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _isAr
                            ? 'بعد أول دفع تُحفظ بطاقتك هنا للخصم المباشر'
                            : 'After your first payment, your card appears here for one-tap checkout',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  for (final method in otherPaymentMethods)
                    _paymentOptionTile(
                      title: PaymentMethodManager.displayName(
                        method,
                        isAr: _isAr,
                      ),
                      value: PaymentMethodManager.modeKey(method),
                      icon: PaymentMethodManager.icon(method),
                    ),
                  const SizedBox(height: 16),
                  if (_mode == 'new' && PaymentService.useMoyasarLiveFlow)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _isAr
                            ? 'اضغط «إتمام الدفع» لإدخال بيانات البطاقة — تُحفظ تلقائياً للخصم المباشر لاحقاً.'
                            : 'Tap «Complete payment» to enter card details — your card saves automatically for one-tap checkout.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    )
                  else if (_mode == 'new')
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute<bool>(
                            settings: RouteSettings(
                              name: DashboardEmbeddedRoute.shouldUseEmbeddedChrome(
                                context,
                              )
                                  ? DashboardEmbeddedRoute.subscriptionsAddCard
                                  : '/subscriptions/add-card',
                            ),
                            builder: (_) =>
                                AddPaymentCardScreen(lang: widget.lang),
                          ),
                        );
                        if (ok == true) await _loadCards();
                      },
                      icon: const Icon(Icons.add_card_outlined),
                      label: Text(t.subscriptionsAddCard),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _paying
                        ? null
                        : () {
                            if (_mode == 'saved' && _selectedCardId != null) {
                              final row = _cardRowById(_selectedCardId);
                              if (row != null &&
                                  PaymentService.isCardExpired(row)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _isAr
                                          ? 'انتهت صلاحية البطاقة المختارة'
                                          : 'Selected card has expired',
                                    ),
                                  ),
                                );
                                return;
                              }
                            }
                            if (!PaymentService.useMoyasarLiveFlow &&
                                _mode == 'saved' &&
                                (_selectedCardId == null ||
                                    _selectedCardId!.isEmpty)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _isAr ? 'اختر بطاقة' : 'Pick a saved card',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (_shouldUseSavedCardForPayment() &&
                                _resolvedSavedCardId() == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _isAr
                                        ? 'اختر بطاقة محفوظة'
                                        : 'Select a saved card',
                                  ),
                                ),
                              );
                              return;
                            }
                            unawaited(_complete());
                          },
                    child: _paying
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(t.subscriptionsPay),
                  ),
                ],
              ),
            ),
          );

    return Scaffold(
      appBar: embedded ? null : AppBar(title: Text(t.subscriptionsCheckoutTitle)),
      body: body,
    );
  }

  IconData _paymentIconFor(SmartPaymentMethod method) =>
      PaymentPlatformDetector.iconFor(method);

  Widget _buildWalletQuickPayRow({
    required bool showApple,
    required bool showGoogle,
    required bool showMada,
  }) {
    final cs = Theme.of(context).colorScheme;
    final buttons = <Widget>[];
    if (showApple) {
      buttons.add(
        Expanded(
          child: FilledButton(
            onPressed: _paying ? null : () => unawaited(_payWithWalletMode('apple_pay')),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.apple, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Apple Pay',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (showGoogle) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 8));
      buttons.add(
        Expanded(
          child: FilledButton(
            onPressed:
                _paying ? null : () => unawaited(_payWithWalletMode('google_pay')),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              'Google Pay',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }
    if (showMada) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 8));
      buttons.add(
        Expanded(
          child: FilledButton.tonal(
            onPressed: _paying ? null : () => unawaited(_payWithWalletMode('mada_pay')),
            child: Text(
              _isAr ? 'مدى Pay' : 'mada Pay',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: buttons),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            _isAr ? 'أو اختر طريقة أخرى' : 'Or choose another method',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildSavedCardVisual(Map<String, dynamic> c) {
    final cs = Theme.of(context).colorScheme;
    final last = '${c['last_four'] ?? ''}';
    final scheme = '${c['card_scheme'] ?? ''}'.toUpperCase();
    final label = c['label']?.toString().trim();
    final expired = PaymentService.isCardExpired(c);
    final selected = _mode == 'saved' && _selectedCardId == '${c['id']}';
    final em = int.tryParse('${c['expiry_month']}') ?? 0;
    final ey = int.tryParse('${c['expiry_year']}') ?? 0;
    final exp = ey >= 2090
        ? ''
        : '${em.toString().padLeft(2, '0')}/${ey.toString().length > 2 ? ey.toString().substring(2) : ey}';
    final gradient = LinearGradient(
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
      colors: [
        cs.primary.withValues(alpha: 0.92),
        cs.primaryContainer.withValues(alpha: 0.95),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        elevation: selected ? 3 : 1,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: expired
              ? null
              : () => unawaited(_selectSavedCardAndMaybePay(c)),
          child: Ink(
            decoration: BoxDecoration(gradient: gradient),
            child: Opacity(
              opacity: expired ? 0.5 : 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.contactless_outlined,
                            color: cs.onPrimary.withValues(alpha: 0.9)),
                        const Spacer(),
                        if (selected)
                          Icon(Icons.check_circle,
                              color: cs.onPrimary.withValues(alpha: 0.95)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      label?.isNotEmpty == true ? label! : scheme,
                      style: TextStyle(
                        color: cs.onPrimary.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '•••• •••• •••• $last',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          expired
                              ? (_isAr ? 'منتهية' : 'Expired')
                              : (exp.isNotEmpty ? exp : '—'),
                          style: TextStyle(
                            color: cs.onPrimary.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          scheme,
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentOptionTile({
    required String title,
    required String value,
    required IconData icon,
  }) {
    final selected = _mode == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(title),
      trailing: Radio<String>(
        value: value,
        groupValue: _mode,
        onChanged: (v) => setState(() => _mode = v ?? value),
      ),
      onTap: () => setState(() => _mode = value),
    );
  }

  Widget _row(String k, String v, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(k)),
          Text(
            v,
            style: strong
                ? const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(
    String k,
    double amount, {
    bool strong = false,
    bool negative = false,
  }) {
    final style = strong
        ? const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(k)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (negative)
                Text('-', style: style ?? Theme.of(context).textTheme.bodyMedium),
              AppMoneyLine(
                amount: amount.abs(),
                currencyCode: 'SAR',
                isAr: _isAr,
                style: style,
                maxFractionDigits: amount == amount.roundToDouble() ? 0 : 2,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
