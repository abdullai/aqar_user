import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:moyasar/moyasar.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/branding/app_branding.dart';
import '../../core/gestures/app_keyboard_popups.dart';
import '../../core/gestures/app_keyboard_inset.dart';
import '../../core/navigation/payment_overlay_route.dart';
import '../../core/navigation/safe_overlay_pop.dart';
import '../../core/payment/checkout_offer.dart';
import '../../core/payment/checkout_journey.dart';
import '../../core/payment/payment_checkout_platform.dart';
import '../../core/payment/payment_recovery_coordinator.dart';
import '../../core/payment/payment_plain_explain.dart';
import '../../core/payment/plan_price_resolver.dart';
import '../../core/payment/platform_fee_catalog.dart';
import '../../core/payment/payment_method_manager.dart';
import '../../core/payment/payment_platform_detector.dart';
import '../../core/payment/smart_payment_flow.dart';
import '../../core/payment/moyasar_web_3ds.dart';
import '../../core/session/app_session.dart';
import '../../core/subscription/app_subscription_gate.dart';
import '../../core/subscription/subscription_billing_context.dart';
import '../../core/payment/invoice_document.dart';
import '../../core/utils/app_money.dart';
import '../../l10n/app_localizations.dart';
import '../../services/billing_transaction_repository.dart';
import '../../services/payment_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/aqar_text_field.dart';
import '../../widgets/app_logo_loading.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import '../../widgets/fal_support_whatsapp_row.dart';
import '../../widgets/subscription/checkout_promo_codes_sheet.dart';
import '../../widgets/subscription/subscription_ui_helpers.dart';
import '../../widgets/app_page_close_button.dart';
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
  bool _autoRenew = false;
  double? _serverExpectedChargeSar;
  CheckoutOffer? _offer;
  late final PlanPriceResolver _prices;
  final _promoCtrl = TextEditingController();
  String? _appliedPromoCode;
  bool _promoBusy = false;
  bool _promoAllowed = false;
  bool _promoIntentOpen = false;
  String _promoSort = 'highest';

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  double get _minPayableSar {
    final v = PlatformFeeCatalog.instance
        ?.amountOf(PlatformFeeCatalog.saveCardVerify);
    return (v != null && v > 0) ? v : 0;
  }

  bool _isBelowMinPayable(double charge) {
    final min = _minPayableSar;
    if (min > 0) return charge < min;
    return charge <= 0;
  }

  String get _minPayablePhrase {
    final p = PlatformFeeCatalog.instance?.saveCardPhrase(isAr: _isAr) ?? '';
    if (p.isNotEmpty) return p;
    return AppMoney.formatWithCurrencyCode(
      _minPayableSar,
      isAr: _isAr,
      maxFractionDigits: 2,
    );
  }

  bool get _isExistingSubscriptionPayment =>
      widget.renewSubscriptionId != null ||
      widget.upgradeSubscriptionId != null ||
      widget.periodSwitchSubscriptionId != null;

  SubscriptionCheckoutKind get _checkoutKind => CheckoutJourney.resolve(
        plan: widget.plan,
        renewSubscriptionId: widget.renewSubscriptionId,
        upgradeSubscriptionId: widget.upgradeSubscriptionId,
        periodSwitchSubscriptionId: widget.periodSwitchSubscriptionId,
      );

  bool get _isAddOnCheckout =>
      _checkoutKind == SubscriptionCheckoutKind.addOn;

  bool get _allowsAutoPay =>
      !_isOneTimePeriod &&
      SubscriptionUiHelpers.showAutoPayUi(
        period: widget.period,
        isAddOn: _isAddOnCheckout,
        isExistingSubscription: _isExistingSubscriptionPayment,
        chargeOverride: widget.chargeAmountOverride,
      );

  double get _planAutoPayPct {
    final v = widget.plan['auto_pay_discount_percent'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  bool get _promoAlreadyApplied =>
      (_appliedPromoCode ?? '').trim().isNotEmpty;

  bool get _hasEligiblePromos =>
      _promoAllowed || (_offer?.hasEligiblePromos ?? false);

  bool get _hasBetterPromoThanAutoPay {
    final offer = _offer;
    if (offer != null) {
      return offer.isBetterThanAutoPay(_planAutoPayPct);
    }
    return _hasEligiblePromos;
  }

  bool get _showBetterPromoHint {
    if (!_allowsAutoPay || !_autoRenew) return false;
    if (_promoAlreadyApplied || _promoIntentOpen) return false;
    return _hasBetterPromoThanAutoPay;
  }

  bool get _showPromoField {
    if (_promoAlreadyApplied) return true;
    if (!_hasEligiblePromos) return false;
    if (_autoRenew && _allowsAutoPay) {
      if (!_hasBetterPromoThanAutoPay) return false;
      return _promoIntentOpen;
    }
    return true;
  }

  bool get _payLockedByPromoIntent =>
      _promoIntentOpen && !_promoAlreadyApplied;

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
    _autoRenew = _allowsAutoPay;
    _prices = PlanPriceResolver(widget.plan);
    _prices.debugLog(widget.period);
    PaymentService.configureMoyasarCallbackUrlFromEnv();
    _loadCards();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prefetchServerCharge());
      unawaited(_loadPromoEligibility());
      if (!mounted) return;
      _session = context.read<AppSession>();
      _session!.addListener(_onConnectivityRestored);
      unawaited(_tryRecoverPendingPayment());
    });
  }

  @override
  void dispose() {
    _session?.removeListener(_onConnectivityRestored);
    _promoCtrl.dispose();
    super.dispose();
  }

  void _onConnectivityRestored() {
    if (_session?.hasInternet == true && !_paying && !_recoveringPending) {
      unawaited(_tryRecoverPendingPayment());
    }
  }

  Future<void> _loadPromoEligibility() async {
    await _prefetchServerCharge();
  }

  /// جلب المبلغ الكانوني من السيرفر عند فتح الشاشة (يُصلح عرض 0.00).
  Future<void> _prefetchServerCharge() async {
    try {
      final raw = await _sub.quoteCheckoutOffer(
        planId: '${widget.plan['id']}',
        period: widget.period,
        withAutoPay: _autoRenew && _allowsAutoPay,
        promoCode: _appliedPromoCode,
        upgradeSubscriptionId: widget.upgradeSubscriptionId,
        purpose: _moyasarPurpose(),
      );
      if (!mounted) return;
      final offer = CheckoutOffer.fromRpc(raw);
      if (offer.ok) {
        setState(() {
          _offer = offer;
          _serverExpectedChargeSar =
              offer.finalAmount > 0 ? offer.finalAmount : null;
          _promoAllowed = offer.hasEligiblePromos || _promoAllowed;
          if (_autoRenew &&
              _allowsAutoPay &&
              offer.promoSkipped == 'auto_pay_better') {
            _appliedPromoCode = null;
            if (_promoCtrl.text.isNotEmpty) _promoCtrl.clear();
          } else if ((offer.promoCode ?? '').trim().isNotEmpty &&
              offer.appliedKind == 'promo') {
            _appliedPromoCode = offer.promoCode;
            if (_promoCtrl.text.trim() != offer.promoCode) {
              _promoCtrl.text = offer.promoCode!;
            }
          }
        });
        if (kDebugMode) {
          debugPrint(
            '[PaymentCheckout] offer final=${offer.finalAmount} '
            'kind=${offer.appliedKind} auto=${offer.autoPaySar}',
          );
        }
        return;
      }
      if (raw['error'] == 'auto_pay_better' ||
          offer.promoSkipped == 'auto_pay_better') {
        // handled via offer.ok path
      }
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[PaymentCheckout] offer error: $raw');
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[PaymentCheckout] prefetch failed: $e\n$st');
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
      case 'wrong_plan':
        return t.promoErrWrongPlan;
      case 'wrong_period':
        return t.promoErrWrongPeriod;
      case 'below_minimum':
        return t.promoErrBelowMin;
      case 'auto_pay_better':
        return t.checkoutAutoPayBetter;
      case 'promo_zeros_invoice':
        return t.checkoutPromoZero;
      default:
        return t.promoErrInvalid;
    }
  }

  String _sanitizeGatewayDetail(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower.contains('authorization credentials') ||
        lower.contains('invalid api') ||
        lower.contains('invalid key') ||
        lower.contains('unauthorized')) {
      return _isAr
          ? 'تعذّر التحقق من بوابة الدفع. أكمل ببطاقة جديدة أو حدّث البطاقة المحفوظة.'
          : 'The payment gateway could not authorize this saved card. Try a new card.';
    }
    if (RegExp(r'^[a-z0-9_\-]+$', caseSensitive: false).hasMatch(s) &&
        s.contains('_')) {
      return _isAr
          ? 'رفض البنك أو بوابة الدفع هذه البطاقة.'
          : 'The bank or payment gateway declined this card.';
    }
    return s;
  }

  Future<void> _applyPromo() async {
    final t = AppLocalizations.of(context)!;
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _promoBusy = true);
    final raw = await _sub.quoteCheckoutOffer(
      planId: '${widget.plan['id']}',
      period: widget.period,
      withAutoPay: _autoRenew && _allowsAutoPay,
      promoCode: code,
      upgradeSubscriptionId: widget.upgradeSubscriptionId,
      purpose: _moyasarPurpose(),
    );
    if (!mounted) return;
    final offer = CheckoutOffer.fromRpc(raw);
    if (!offer.ok) {
      setState(() => _promoBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_promoErrorText(t, offer.error))),
      );
      return;
    }
    if (offer.promoSkipped == 'auto_pay_better') {
      setState(() {
        _promoBusy = false;
        _offer = offer;
        _serverExpectedChargeSar = offer.finalAmount;
        _appliedPromoCode = null;
        _promoCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.checkoutAutoPayBetter)),
      );
      return;
    }
    if (offer.appliedKind != 'promo') {
      setState(() {
        _promoBusy = false;
        _offer = offer;
        _serverExpectedChargeSar = offer.finalAmount;
        _appliedPromoCode = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_promoErrorText(t, 'invalid_code'))),
      );
      return;
    }
    if (offer.finalAmount <= 0) {
      setState(() => _promoBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.checkoutPromoZero)),
      );
      return;
    }
    final applied = (offer.promoCode ?? code).trim();
    setState(() {
      _appliedPromoCode = applied;
      _offer = offer;
      _serverExpectedChargeSar = offer.finalAmount;
      _promoBusy = false;
      if (_promoCtrl.text.trim() != applied) {
        _promoCtrl.text = applied;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.checkoutPromoApplied)),
    );
  }

  void _openPromoIntent() {
    setState(() => _promoIntentOpen = true);
  }

  void _cancelPromoIntent() {
    setState(() {
      _promoIntentOpen = false;
      _appliedPromoCode = null;
      _promoCtrl.clear();
      _serverExpectedChargeSar = null;
      _offer = null;
    });
    unawaited(_prefetchServerCharge());
  }

  void _removePromo() {
    setState(() {
      _appliedPromoCode = null;
      _serverExpectedChargeSar = null;
      _promoCtrl.clear();
      _offer = null;
      if (!(_autoRenew && _allowsAutoPay && _hasBetterPromoThanAutoPay)) {
        _promoIntentOpen = false;
      }
    });
    unawaited(_prefetchServerCharge());
  }

  Widget _promoActionButton({
    required bool filled,
    required VoidCallback? onPressed,
    required String label,
  }) {
    final child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    final style = filled
        ? FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )
        : OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: filled
          ? FilledButton(onPressed: onPressed, style: style, child: child)
          : OutlinedButton(onPressed: onPressed, style: style, child: child),
    );
  }

  List<Widget> _promoField(AppLocalizations t) {
    final applied = _promoAlreadyApplied;
    final hasText = _promoCtrl.text.trim().isNotEmpty;
    final verify = _promoActionButton(
      filled: false,
      onPressed: _promoBusy ? null : () => unawaited(_openEligiblePromos(t)),
      label: t.checkoutPromoBrowse,
    );
    final secondary = _promoActionButton(
      filled: !applied,
      onPressed: _promoBusy
          ? null
          : applied
              ? _removePromo
              : (hasText ? () => unawaited(_applyPromo()) : null),
      label: applied ? t.checkoutPromoEdit : t.checkoutPromoApply,
    );
    return [
      AqarTextField(
        controller: _promoCtrl,
        enabled: !_promoBusy && !applied,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: t.checkoutPromoCode,
        ),
        onSubmitted: (_) {
          if (!applied && hasText) unawaited(_applyPromo());
        },
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, c) {
          final stack = c.maxWidth < 420;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                verify,
                const SizedBox(height: 8),
                secondary,
              ],
            );
          }
          return SizedBox(
            height: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: verify),
                const SizedBox(width: 8),
                Expanded(child: secondary),
              ],
            ),
          );
        },
      ),
      if (_promoIntentOpen) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: _promoBusy ? null : _cancelPromoIntent,
          child: Text(t.checkoutPromoCancelIntent),
        ),
      ],
    ];
  }

  Future<void> _openEligiblePromos(AppLocalizations t) async {
    setState(() => _promoBusy = true);
    final raw = await _sub.listEligiblePromoCodes(
      planId: '${widget.plan['id']}',
      period: widget.period,
      sort: _promoSort,
      upgradeSubscriptionId: widget.upgradeSubscriptionId,
    );
    if (!mounted) return;
    setState(() => _promoBusy = false);
    var codes = CheckoutPromoOption.listFrom(raw['codes']);
    final minPct =
        (_autoRenew && _allowsAutoPay) ? _planAutoPayPct : 0.0;
    if (minPct > 0) {
      codes = codes
          .where((c) => c.percent > minPct + 0.0001)
          .toList();
    }
    if (codes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.checkoutPromoNone)),
      );
      return;
    }
    await CheckoutPromoCodesSheet.show(
      context: context,
      codes: codes,
      isAr: _isAr,
      initialSort: _promoSort,
      minPercentExclusive: minPct,
      onSort: (sort) async {
        _promoSort = sort;
        final next = await _sub.listEligiblePromoCodes(
          planId: '${widget.plan['id']}',
          period: widget.period,
          sort: sort,
          upgradeSubscriptionId: widget.upgradeSubscriptionId,
        );
        var list = CheckoutPromoOption.listFrom(next['codes']);
        if (minPct > 0) {
          list = list
              .where((c) => c.percent > minPct + 0.0001)
              .toList();
        }
        return list;
      },
      onUse: (code) {
        _promoCtrl.text = code;
        setState(() {});
        unawaited(_applyPromo());
      },
    );
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

  double get _total => _prices.priceForPeriod(widget.period);

  double get _chargeAmount => _prices.chargeAmount(
        period: widget.period,
        withAutoPay: _autoRenew && _allowsAutoPay,
        isExistingSubscription: _isExistingSubscriptionPayment,
        override: widget.chargeAmountOverride,
      );

  /// المبلغ النهائي للدفع — القيمة المعتمدة من الخادم فقط.
  double _effectiveChargeForPayment() {
    final offer = _offer;
    if (offer != null && offer.ok && offer.finalAmount > 0) {
      return offer.finalAmount;
    }
    final server = _serverExpectedChargeSar;
    if (server != null && server > 0) return server;
    if (widget.chargeAmountOverride != null &&
        widget.chargeAmountOverride! > 0) {
      return widget.chargeAmountOverride!;
    }
    return _prices.priceForPeriod(widget.period);
  }

  String get _checkoutIdempotencyKey => [
        '${widget.plan['id']}',
        widget.period,
        widget.upgradeSubscriptionId ?? '',
        widget.renewSubscriptionId ?? '',
        widget.periodSwitchSubscriptionId ?? '',
        _moyasarPurpose(),
        (_autoRenew && _allowsAutoPay) ? 'ap1' : 'ap0',
        (_appliedPromoCode ?? '').trim().toUpperCase(),
      ].join('|');

  String _moyasarPurpose() {
    if (widget.periodSwitchSubscriptionId != null) return 'period_switch';
    if (widget.renewSubscriptionId != null) return 'renew';
    if (widget.upgradeSubscriptionId != null) return 'upgrade';
    return 'subscribe_new';
  }

  String _paymentModeKey() {
    if (_mode == 'apple_pay') return 'apple_pay';
    if (_mode == 'samsung_pay') return 'samsung_pay';
    if (_mode == 'mada_pay') return 'mada_pay';
    return 'card';
  }

  /// الدفع من بطاقة محفوظة — مدى/جوجل/بطاقة جديدة تمر عبر نموذج ميسّر مباشرة.
  bool _shouldUseSavedCardForPayment() {
    if (_mode == 'new') return false;
    if (PaymentService.useMoyasarLiveFlow &&
        (_mode == 'mada_pay' ||
            _mode == 'samsung_pay' ||
            _mode == 'apple_pay')) {
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
      purpose: _moyasarPurpose(),
      planId: '${widget.plan['id'] ?? ''}',
      period: widget.period,
      withAutoPay: _autoRenew && _allowsAutoPay,
      upgradeSubscriptionId: widget.upgradeSubscriptionId,
      idempotencyKey: _checkoutIdempotencyKey,
      promoCode: _appliedPromoCode,
    );
    if (pend['ok'] != true) {
      return {'ok': false, 'error': pend['error'] ?? 'pending_tx'};
    }
    final bid = '${pend['transaction_id'] ?? ''}'.trim();
    final billed = _canonicalAmountFromPending(pend, charge);
    _serverExpectedChargeSar = billed;
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
      expectedAmountSar: billed,
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

  MoyasarWalletMode? _samsungWallet(String pm) {
    if (pm != 'samsung_pay') return null;
    if (!PaymentPlatformDetector.supportsSamsungPay()) return null;
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
      'samsung_pay' => 'samsung_pay',
      'mada_pay' => 'mada_pay',
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
      purpose: _moyasarPurpose(),
      planId: '${widget.plan['id'] ?? ''}',
      period: widget.period,
      withAutoPay: _autoRenew && _allowsAutoPay,
      upgradeSubscriptionId: widget.upgradeSubscriptionId,
      idempotencyKey: _checkoutIdempotencyKey,
      promoCode: _appliedPromoCode,
    );
    if (pend['ok'] != true) {
      return {'ok': false, 'error': pend['error'] ?? 'pending_tx'};
    }

    final bid = '${pend['transaction_id'] ?? ''}'.trim();
    final billed = _canonicalAmountFromPending(pend, charge);
    _serverExpectedChargeSar = billed;
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
        saveCard: true,
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
        amountHalalas: PaymentService.amountToHalalas(billed),
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
      payResult = await PaymentOverlay.push<dynamic>(
        context,
        name: '/subscriptions/moyasar-pay',
        page: MoyasarSubscriptionPaymentScreen(
            config: cfg,
            walletMode: walletMode,
            isAr: _isAr,
            planName: planName,
            amountSar: billed,
            periodLabel: widget.period == 'yearly'
                ? (_isAr ? 'سنوي' : 'Yearly')
                : widget.period == 'lifetime_one_time'
                    ? (_isAr ? 'مرة واحدة' : 'One-time')
                    : (_isAr ? 'شهري' : 'Monthly'),
          ),
      );
    } catch (e, st) {
      debugPrint('Moyasar checkout error: $e\n$st');
      return {'ok': false, 'error': 'moyasar_widget_error'};
    }

    if (!mounted) return {'ok': false, 'error': 'unmounted'};
    if (payResult is PaymentResponse &&
        PaymentService.moyasarPaymentSucceeded(payResult)) {
      unawaited(_pay.persistMoyasarCardFromPaymentResponse(payResult));
      final poll = await _pollBillingWithOverlay(
        billingTransactionId: bid,
        expectedAmountSar: billed,
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
    if (_paying || _payLockedByPromoIntent) return;
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
    if (_payLockedByPromoIntent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.checkoutPayLockedUntilPromo)),
      );
      return;
    }
    final billing = widget.billingContext;
    if (billing != null &&
        billing.ok &&
        (billing.isTeamMember || billing.billingMode == 'team_member')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'عضو الفريق لا يدفع اشتراكاً — الباقة حسب صلاحيات المنشأة ومديرها.'
                : 'Team members do not pay for a plan — the org owner manages the subscription.',
          ),
        ),
      );
      return;
    }
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
      await showAppDialog<void>(
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
      final added = await PaymentOverlay.push<bool>(
        context,
        name: '/subscriptions/add-card',
        page: AddPaymentCardScreen(lang: widget.lang),
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

    // مبلغ كانوني + أحقيّة: الاشتراك الجديد يُحظر إن وُجدت باقة رئيسية.
    // الإضافة/الترقية/التحويل لا تُعامل كاشتراك جديد.
    final relatedSubId = widget.upgradeSubscriptionId ??
        widget.periodSwitchSubscriptionId;
    final mustValidateIntent = !_isExistingSubscriptionPayment ||
        _isAddOnCheckout ||
        _isBelowMinPayable(_effectiveChargeForPayment());
    if (mustValidateIntent) {
      final intent = await _sub.validatePaymentIntent(
        planId: '${widget.plan['id']}',
        period: widget.period,
        amountSar: _effectiveChargeForPayment(),
        withAutoPay: _autoRenew && _allowsAutoPay,
        upgradeSubscriptionId: relatedSubId,
        promoCode: _appliedPromoCode,
      );
      if (intent['ok'] == true) {
        final exp = intent['expected_amount'] ?? intent['expected'];
        if (exp is num && exp.toDouble() > 0) {
          _serverExpectedChargeSar = exp.toDouble();
          if (kDebugMode) {
            debugPrint(
              '[PaymentCheckout] validatePaymentIntent expected=$exp',
            );
          }
        }
      } else {
        final err = () {
          var e = '${intent['error'] ?? ''}';
          final detail = intent['detail'];
          if (detail is Map &&
              (e == 'not_allowed' || e.isEmpty)) {
            e = '${detail['reason'] ?? e}';
          }
          return e;
        }();
        final ignoreActive = _isAddOnCheckout ||
            relatedSubId != null ||
            widget.renewSubscriptionId != null;
        final skipActiveMsg =
            ignoreActive && err == 'already_active_subscription';
        if (!skipActiveMsg) {
          if (!mounted) return;
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
          } else if (err == 'topup_requires_main_subscription') {
            msg = _isAr
                ? 'شراء الإضافة يتطلب باقة رئيسية سارية أولاً.'
                : 'Add-ons require an active main plan first.';
          } else if (err == 'already_active_subscription') {
            msg = _isAr
                ? 'لديك باقة رئيسية سارية. للترقية استخدم زر «ترقية الباقة»، ولزيادة الصفقات استخدم «شراء الإضافة».'
                : 'You already have a main plan. Use «Upgrade» for a higher tier or «Buy add-on» for extra deals.';
          } else {
            msg = _isAr
                ? 'تعذّر التحقق من نيّة الدفع. حاول لاحقاً.'
                : 'Payment intent validation failed. Try later.';
          }
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
          return;
        }
      }
    }

    final charge = _effectiveChargeForPayment();
    if (_isBelowMinPayable(charge)) {
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
                ? 'المبلغ المستحق ($due) أقل من الحد الأدنى للدفع ($_minPayablePhrase). إجمالي الباقة: $total'
                : 'Amount due ($due) is below the minimum charge ($_minPayablePhrase). Plan total: $total',
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
      } else if (useMs && _samsungWallet(pm) != null) {
        res = await _payWithMoyasarHostedCheckout(
          charge: charge,
          titleAr: titleAr,
          titleEn: titleEn,
          pm: pm,
          walletMode: MoyasarWalletMode.samsungPay,
          madaPreferredNetworksOnly: false,
        );
      } else if (useMs &&
          (pm == 'card' || pm == 'mada_pay')) {
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
    } else if (err == 'moyasar_config_error' ||
        err == 'payment_gateway_not_configured' ||
        err == 'moyasar_widget_error' ||
        err == 'moyasar_account_inactive' ||
        err == 'moyasar_auth_error' ||
        err == 'apple_pay_merchant_missing' ||
        err == 'google_pay_wallet_unavailable' ||
        err == 'moyasar_cancelled_or_failed' ||
        err == 'moyasar_failed') {
      msg = PaymentService.userFacingError(err, isAr: _isAr);
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
                ? 'المبلغ المستحق ($due) أقل من الحد الأدنى للدفع ($_minPayablePhrase). إجمالي الباقة: $total'
                : 'Amount due ($due) is below the minimum charge ($_minPayablePhrase). Plan total: $total';
    } else if (err.startsWith('moyasar_validation:') ||
        err.startsWith('moyasar_api:') ||
        err == 'moyasar_validation_error' ||
        err == 'webhook_timeout' ||
        err == 'cors_or_function_unreachable' ||
        err == 'moyasar_rejected') {
      if (err == 'moyasar_rejected') setState(() => _mode = 'new');
      msg = PaymentService.userFacingError(err, isAr: _isAr);
    } else if (err == 'saved_card_charge_failed') {
      setState(() => _mode = 'new');
      final detailRaw = '${res['detail'] ?? ''}'.trim();
      final detail = _sanitizeGatewayDetail(detailRaw);
      msg = _isAr
          ? (detail.isNotEmpty
              ? 'تعذّر خصم البطاقة المحفوظة: $detail — جرّب «بطاقة ائتمان / مدى».'
              : 'تعذّر خصم البطاقة المحفوظة — اختر «بطاقة ائتمان / مدى» وأتمم الدفع مرة واحدة.')
          : (detail.isNotEmpty
              ? 'Saved card charge failed: $detail — try “Credit / mada card”.'
              : 'Saved card charge failed — choose “Credit / mada card” and pay once.');
    } else if (err == 'duplicate_active_same_plan' ||
        err == 'active_plan_conflict') {
      msg = _isAr
          ? 'لديك اشتراك فعّال. جدّد عند الانتهاء أو رقِّ الباقة أو حوّل للسنوي من شاشة الباقات.'
          : 'You already have an active subscription. Renew when it ends, upgrade, or switch billing period from the plans screen.';
    } else if (err == 'use_upgrade_flow') {
      msg = _isAr
          ? 'هذه باقة رئيسية أعلى. استخدم زر «ترقية الباقة». لزيادة الصفقات استخدم «شراء الإضافة».'
          : 'This is a higher main plan — use «Upgrade». For extra deals use «Buy add-on».';
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
      msg = PaymentService.userFacingError(err, isAr: _isAr);
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
    final promo = _appliedPromoCode;
    if (promo != null && promo.isNotEmpty && tx.isNotEmpty) {
      await _sub.redeemPromoCode(code: promo, billingTransactionId: tx);
    }
    final subId = '${res['subscription_id'] ?? res['id'] ?? ''}'.trim();
    final cardLast4 = _selectedCardLast4();
    final pmLabel = _paymentMethodLabel(t);
    Map<String, dynamic>? bill;
    if (tx.isNotEmpty) {
      bill = await BillingTransactionRepository(Supabase.instance.client)
          .getOwn(tx);
    }
    final live = InvoiceDocument.fromRow(bill ?? const {}, isAr: _isAr);

    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PaymentReceiptScreen(
          lang: widget.lang,
          planName: planName,
          period: widget.period,
          amountSar: bill != null
              ? live.amount
              : ((_serverExpectedChargeSar != null &&
                      _serverExpectedChargeSar! > 0)
                  ? _serverExpectedChargeSar!
                  : _chargeAmount),
          paymentMethodLabel: pmLabel,
          transactionId: live.invoiceNumber,
          completedAt: live.occurredAt ?? DateTime.now(),
          subscriptionId: subId.isEmpty ? null : subId,
          cardLast4: cardLast4,
          purpose: _moyasarPurpose(),
          billingRow: bill,
          invoiceNumber: live.invoiceNumber,
          paymentReference: live.paymentReference,
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
      case 'samsung_pay':
        return 'Samsung Pay';
      case 'mada_pay':
        return _isAr ? 'مدى (على البطاقة)' : 'mada (on card)';
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
    final billed = _serverExpectedChargeSar ?? _effectiveChargeForPayment();
    final res = await _sub.fulfillPaidBilling(
      billingTransactionId: billingTransactionId,
      expectedAmountSar: billed,
      titleAr: titleAr,
      titleEn: titleEn,
    );
    if (res['ok'] == true && mounted) {
      try {
        await context.read<AppSubscriptionGate>().refresh(force: true);
      } catch (_) {}
    }
    return res;
  }

  double _canonicalAmountFromPending(Map<String, dynamic> pend, double fallback) {
    final a = pend['amount'] ?? pend['expected_amount'];
    if (a is num && a.toDouble() > 0) return a.toDouble();
    final parsed = double.tryParse('$a');
    if (parsed != null && parsed > 0) return parsed;
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final name = AppBranding.planNameFromRow(widget.plan, isAr: _isAr);
    final paymentMethods = PaymentMethodManager.selectableMethods(
      context: context,
      hasSavedCards: _cards.isNotEmpty,
      savedCardReady: _cards.any(PaymentService.canChargeSavedCard),
    );
    final showAppleWallet = PaymentPlatformDetector.supportsApplePay();
    final showSamsungWallet = PaymentPlatformDetector.supportsSamsungPay();
    final otherPaymentMethods = paymentMethods.where((m) {
      final mode = PaymentMethodManager.modeKey(m);
      if (mode == 'apple_pay' && showAppleWallet) return false;
      if (mode == 'samsung_pay' && showSamsungWallet) return false;
      return true;
    }).toList();

    final body = _loading
        ? const Center(child: AppLogoLoading())
        : AppKeyboardPad(
            extra: 16,
            child: AqarPrimaryScrollScope(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: AppKeyboardInset.scrollViewPadding(
                context,
                base: const EdgeInsets.all(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SubscriptionUiHelpers.section(
                    context: context,
                    title: t.subscriptionsCheckoutTitle,
                    children: [
                      SubscriptionUiHelpers.tableRow(
                        context: context,
                        label: _isAr ? 'نوع العملية' : 'Payment kind',
                        value: CheckoutJourney.title(
                          isAr: _isAr,
                          kind: _checkoutKind,
                        ),
                      ),
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
                      if (_offer != null && _offer!.showBeforeDiscount)
                        SubscriptionUiHelpers.priceTableRow(
                          context: context,
                          isAr: _isAr,
                          label: t.invoiceBreakdownSubtotal,
                          amount: _offer!.basePrice,
                        ),
                      if (_offer != null && _offer!.showAutoPayRow)
                        SubscriptionUiHelpers.priceTableRow(
                          context: context,
                          isAr: _isAr,
                          label: t.checkoutAutoRenewDiscountPlain,
                          amount: _offer!.autoPaySar,
                          negative: true,
                        ),
                      if (_offer != null && _offer!.showPromoRow)
                        SubscriptionUiHelpers.priceTableRow(
                          context: context,
                          isAr: _isAr,
                          label: t.checkoutPromoCodeDiscountPlain,
                          amount: _offer!.promoDiscountSar,
                          negative: true,
                        ),
                      SubscriptionUiHelpers.priceTableRow(
                        context: context,
                        isAr: _isAr,
                        label: t.subscriptionsTotalLine,
                        amount: _effectiveChargeForPayment(),
                        emphasize: true,
                      ),
                      if (_allowsAutoPay) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(
                            t.checkoutAutoRenew,
                            style: SubscriptionUiHelpers.denseLabel(context),
                          ),
                          subtitle: _planAutoPayPct > 0
                              ? Text(
                                  t.checkoutAutoRenewHint(
                                    _planAutoPayPct ==
                                            _planAutoPayPct.roundToDouble()
                                        ? _planAutoPayPct.toStringAsFixed(0)
                                        : _planAutoPayPct.toStringAsFixed(1),
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                )
                              : null,
                          value: _autoRenew,
                          onChanged: (v) {
                            setState(() {
                              _autoRenew = v;
                              if (v) {
                                if (!_promoAlreadyApplied) {
                                  _promoIntentOpen = false;
                                  if (!_hasBetterPromoThanAutoPay) {
                                    _promoCtrl.clear();
                                  }
                                }
                              } else {
                                _promoIntentOpen = false;
                              }
                            });
                            unawaited(_prefetchServerCharge());
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_showBetterPromoHint)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                t.checkoutBetterPromoNote,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: _openPromoIntent,
                                child: Text(t.checkoutWantPromoLink),
                              ),
                            ],
                          ),
                        ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _showPromoField
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _promoField(t),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 4),
                      SubscriptionUiHelpers.legalNote(
                        context: context,
                        isAr: _isAr,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.7),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          CheckoutJourney.body(
                            isAr: _isAr,
                            kind: _checkoutKind,
                          ),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                height: 1.4,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.subscriptionsPaymentMethod,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    CheckoutJourney.surfaceHint(isAr: _isAr),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 10),
                  if (showAppleWallet || showSamsungWallet) ...[
                    _buildWalletQuickPayRow(
                      showApple: showAppleWallet,
                      showSamsung: showSamsungWallet,
                      showMada: false,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isAr
                          ? 'أو ادفع ببطاقة ائتمان / مدى'
                          : 'Or pay with a credit / mada card',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
                            ? 'اضغط «إتمام الدفع» لإدخال بطاقة ائتمان / مدى — تُحفظ تلقائياً للخصم المباشر لاحقاً.'
                            : 'Tap «Complete payment» to enter a credit / mada card — it saves automatically for one-tap checkout.',
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
                        final ok = await PaymentOverlay.push<bool>(
                          context,
                          name: '/subscriptions/add-card',
                          page: AddPaymentCardScreen(lang: widget.lang),
                        );
                        if (ok == true) await _loadCards();
                      },
                      icon: const Icon(Icons.add_card_outlined),
                      label: Text(t.subscriptionsAddCard),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    PaymentPlainExplain.checkoutTrust(isAr: _isAr),
                    style: TextStyle(
                      height: 1.45,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_payLockedByPromoIntent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        t.checkoutPayLockedUntilPromo,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.error,
                          height: 1.35,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: (_paying || _payLockedByPromoIntent)
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
          ),
        );

    return PaymentPopGuard(
      busy: _paying,
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: AppPageCloseButton(
          isArabic: _isAr,
          onPressed: () {
            if (_paying) return;
            SafeOverlayPop.pop(context);
          },
        ),
        title: Text(t.subscriptionsCheckoutTitle),
      ),
      body: body,
    ),
    );
  }

  Widget _buildWalletQuickPayRow({
    required bool showApple,
    required bool showSamsung,
    required bool showMada,
  }) {
    final cs = Theme.of(context).colorScheme;
    final buttons = <Widget>[];
    if (showApple) {
      buttons.add(
        Expanded(
          child: FilledButton(
            onPressed: (_paying || _payLockedByPromoIntent)
                ? null
                : () => unawaited(_payWithWalletMode('apple_pay')),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.apple, size: 22),
                SizedBox(width: 8),
                Text(
                  'Apple Pay',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (showSamsung) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 8));
      buttons.add(
        Expanded(
          child: FilledButton(
            onPressed: (_paying || _payLockedByPromoIntent)
                ? null
                : () => unawaited(_payWithWalletMode('samsung_pay')),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1428A0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text(
              'Samsung Pay',
              style: TextStyle(fontWeight: FontWeight.w800),
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
            onPressed: (_paying || _payLockedByPromoIntent)
                ? null
                : () => unawaited(_payWithWalletMode('mada_pay')),
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
}
