import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_credit_card/flutter_credit_card.dart';
import 'package:moyasar/moyasar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/branding/app_branding.dart';
import '../../core/gestures/app_keyboard_inset.dart';
import '../../core/gestures/app_keyboard_popups.dart';
import '../../core/navigation/payment_overlay_route.dart';
import '../../core/navigation/safe_overlay_pop.dart';
import '../../core/payment/card_brand_mark.dart';
import '../../core/payment/payment_input_utils.dart';
import '../../core/payment/platform_fee_catalog.dart';
import '../../core/subscription/card_scheme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/payment_service.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import '../../widgets/app_page_close_button.dart';
import 'moyasar_subscription_payment_screen.dart';

class AddPaymentCardScreen extends StatefulWidget {
  const AddPaymentCardScreen({super.key, required this.lang});

  final String lang;

  @override
  State<AddPaymentCardScreen> createState() => _AddPaymentCardScreenState();
}

class _AddPaymentCardScreenState extends State<AddPaymentCardScreen> {
  final _num = TextEditingController();
  final _holder = TextEditingController();
  final _exp = TextEditingController();
  final _cvv = TextEditingController();
  final _label = TextEditingController();
  final _pay = PaymentService(Supabase.instance.client);
  bool _default = false;
  bool _saving = false;
  bool _cvvBack = false;
  bool _capsLockOn = false;
  Timer? _latinNameDialogDebounce;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    PaymentService.configureMoyasarCallbackUrlFromEnv();
    _capsLockOn = HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.capsLock);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    final caps = HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.capsLock);
    if (caps != _capsLockOn) setState(() => _capsLockOn = caps);
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _latinNameDialogDebounce?.cancel();
    _num.dispose();
    _holder.dispose();
    _exp.dispose();
    _cvv.dispose();
    _label.dispose();
    super.dispose();
  }

  (int mm, int yy)? _parseExpiry() {
    final m = RegExp(r'(\d{1,2})\D+(\d{2,4})').firstMatch(_exp.text.trim());
    if (m == null) return null;
    var mm = int.tryParse(m.group(1) ?? '') ?? 0;
    var yy = int.tryParse(m.group(2) ?? '') ?? 0;
    if (yy < 100) yy += 2000;
    if (mm < 1 || mm > 12) return null;
    return (mm, yy);
  }

  String _errorLabel(dynamic code, AppLocalizations t) {
    return PaymentService.userFacingError(code, isAr: _isAr);
  }

  void _onHolderTextChanged(String value) {
    if (!containsArabicOrPersianScript(value)) {
      setState(() {});
      return;
    }
    final cleaned = stripArabicOrPersianScript(value);
    if (_holder.text != cleaned) {
      _holder.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    _latinNameDialogDebounce?.cancel();
    _latinNameDialogDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final loc = AppLocalizations.of(context)!;
      showAppDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.subscriptionsCardHolderLatinTitle),
          content: Text(loc.subscriptionsCardHolderLatinBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.subscriptionsCardHolderLatinOk),
            ),
          ],
        ),
      );
    });
    setState(() {});
  }

  Future<void> _saveViaMoyasar() async {
    final t = AppLocalizations.of(context)!;
    if (!(await _pay.canAddMoreCards())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'الحد الأقصى ${PaymentService.maxSavedCards} بطاقات — احذف بطاقة لإضافة أخرى.'
                : 'Maximum ${PaymentService.maxSavedCards} cards — delete one to add another.',
          ),
        ),
      );
      return;
    }
    final charge =
        PlatformFeeCatalog.of(context).amountOf(PlatformFeeCatalog.saveCardVerify) ??
            0;
    if (charge <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'تعذّر قراءة مبلغ التحقق من الكتالوج.'
                : 'Could not read the verification amount from the catalog.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    Map<String, dynamic> res = {'ok': false};
    try {
      final pend = await _pay.createPendingBillingTransaction(
        amount: charge,
        titleAr: 'حفظ بطاقة — تحقق',
        titleEn: 'Save card — verification',
        paymentMethod: 'card',
        purpose: 'save_card_only',
        gatewayPendingMeta: const {'purpose': 'save_card_only'},
      );
      if (pend['ok'] != true) {
        res = {'ok': false, 'error': pend['error'] ?? 'pending_tx'};
      } else {
        final bid = '${pend['transaction_id'] ?? ''}'.trim();
        var billed = charge;
        final rawAmt = pend['amount'];
        if (rawAmt is num && rawAmt.toDouble() > 0) {
          billed = rawAmt.toDouble();
        }
        final meta = _pay.buildMoyasarSubscriptionMetadata(
          billingTransactionId: bid,
          purpose: 'save_card_only',
        );
        final desc = _isAr
            ? 'حفظ بطاقة — ${AppBranding.shortNameAr}'
            : 'Save card — ${AppBranding.shortNameEn}';
        final cfg = _pay.buildMoyasarPaymentConfig(
          amountHalalas: PaymentService.amountToHalalas(billed),
          description: desc,
          metadata: meta,
          madaPreferredNetworksOnly: false,
          applePay: null,
        );
        if (!mounted) {
          res = {'ok': false, 'error': 'unmounted'};
        } else {
          dynamic payResult;
          try {
            payResult = await PaymentOverlay.push<dynamic>(
              context,
              name: '/subscriptions/moyasar-save-card',
              page: MoyasarSubscriptionPaymentScreen(
                config: cfg,
                walletMode: MoyasarWalletMode.none,
                isAr: _isAr,
                planName: _isAr ? 'حفظ بطاقة' : 'Save card',
                amountSar: billed,
                periodLabel: _isAr ? 'تحقق' : 'Verification',
              ),
            );
          } catch (e, st) {
            debugPrint('Moyasar save-card error: $e\n$st');
            payResult = null;
            res = {'ok': false, 'error': 'moyasar_widget_error'};
          }
          if (res['error'] == 'moyasar_widget_error') {
            // already set
          } else if (!mounted) {
            res = {'ok': false, 'error': 'unmounted'};
          } else if (payResult is PaymentResponse &&
              PaymentService.moyasarPaymentSucceeded(payResult)) {
            final saved = await _pay.persistMoyasarCardFromPaymentResponse(
              payResult,
              setDefault: _default,
            );
            if (saved['ok'] == true) {
              final cardId = '${saved['card_id'] ?? saved['row']?['id'] ?? ''}'
                  .trim();
              final label = _label.text.trim();
              if (cardId.isNotEmpty && label.isNotEmpty) {
                await _pay.updateCardLabel(cardId: cardId, label: label);
              }
            }
            res = saved;
          } else {
            res = {
              'ok': false,
              'error': PaymentService.mapMoyasarResultToError(payResult) ??
                  'moyasar_cancelled_or_failed',
            };
          }
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true
              ? t.subscriptionsCardSaved
              : _errorLabel(res['error'], t),
        ),
      ),
    );
    if (res['ok'] == true) Navigator.pop(context, true);
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context)!;
    final digits =
        normalizeWesternDigits(_num.text).replaceAll(RegExp(r'\D'), '');
    final exp = _parseExpiry();
    if (exp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.subscriptionsFieldRequired)),
      );
      return;
    }
    if (_holder.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.subscriptionsFieldRequired)),
      );
      return;
    }
    setState(() => _saving = true);
    final res = await _pay.addCard(
      cardNumberDigits: digits,
      holderName: _holder.text.trim(),
      expiryMonth: exp.$1,
      expiryYear: exp.$2,
      cvv: _cvv.text.trim(),
      label: _label.text.trim(),
      setDefault: _default,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true
              ? t.subscriptionsCardSaved
              : _errorLabel(res['error'], t),
        ),
      ),
    );
    if (res['ok'] == true) Navigator.pop(context, true);
  }

  AppBar _closeAppBar(AppLocalizations t) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: AppPageCloseButton(
        isArabic: _isAr,
        onPressed: () => SafeOverlayPop.pop(context),
      ),
      title: Text(t.subscriptionsAddCardTitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (PaymentService.useMoyasarLiveFlow) {
      final verifyAmount = PlatformFeeCatalog.of(context, listen: true)
          .saveCardPhrase(isAr: _isAr);
      return PaymentPopGuard(
        busy: _saving,
        child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: _closeAppBar(t),
        body: AppKeyboardPad(
          extra: 16,
          child: AqarPrimaryScrollScope(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: AppKeyboardInset.scrollViewPadding(
                context,
                base: const EdgeInsets.all(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.credit_card,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.subscriptionsAddCardTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (verifyAmount.isNotEmpty)
                    Text(
                      _isAr
                          ? 'يُخصم $verifyAmount للتحقق من البطاقة وحفظها للخصم المباشر لاحقاً.'
                          : 'A $verifyAmount verification charge saves your card for one-tap payments.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 20),
                  CheckboxListTile(
                    value: _default,
                    onChanged: (v) => setState(() => _default = v ?? false),
                    title: Text(t.subscriptionsDefaultCard),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        _saving ? null : () => unawaited(_saveViaMoyasar()),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline),
                    label: Text(
                      _isAr ? 'إدخال البطاقة والتحقق' : 'Enter card & verify',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      );
    }
    final scheme = detectCardSchemeFromPan(_num.text);
    final brand = cardSchemeDisplayLabel(scheme, isAr: _isAr);
    return PaymentPopGuard(
      busy: _saving,
      child: Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: _closeAppBar(t),
      body: AppKeyboardPad(
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
                CreditCardWidget(
                  cardNumber:
                      _num.text.isEmpty ? '0000 0000 0000 0000' : _num.text,
                  expiryDate: _exp.text.isEmpty ? '00/00' : _exp.text,
                  cardHolderName: _holder.text.isEmpty
                      ? 'NAME'
                      : _holder.text.toUpperCase(),
                  cvvCode: _cvv.text,
                  showBackView: _cvvBack,
                  isHolderNameVisible: true,
                  obscureCardCvv: true,
                  onCreditCardWidgetChange: (_) {},
                ),
                if (brand.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    brand,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
                const SizedBox(height: 20),
                if (kIsWeb && _capsLockOn)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.keyboard_capslock,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                t.subscriptionsCapsLockOn,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                AqarTextField(
                  controller: _num,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  textDirection: TextDirection.ltr,
                  inputFormatters: const [
                    CardPanFormatter(maxDigits: 19),
                  ],
                  decoration: InputDecoration(
                    labelText: t.subscriptionsCardNumber,
                    prefixIcon: const Icon(Icons.credit_card),
                    suffixIcon: scheme == 'unknown'
                        ? null
                        : Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: CardBrandMark(scheme: scheme),
                          ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 28,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                AqarTextField(
                  controller: _holder,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: t.subscriptionsCardHolder,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  inputFormatters: const [
                    CardHolderLatinUppercaseFormatter(),
                  ],
                  onChanged: _onHolderTextChanged,
                ),
                const SizedBox(height: 12),
                AqarTextField(
                  controller: _exp,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [
                    const WesternDigitNormalizer(),
                    const CardExpirySlashFormatter(),
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: InputDecoration(
                    labelText: t.subscriptionsExpiry,
                    hintText: '12/28',
                    prefixIcon: const Icon(Icons.date_range_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Focus(
                  onFocusChange: (f) => setState(() => _cvvBack = f),
                  child: AqarTextField(
                    controller: _cvv,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    textDirection: TextDirection.ltr,
                    obscureText: true,
                    inputFormatters: const [
                      WesternDigitNormalizer(),
                      DigitsOnlyFormatter(4),
                    ],
                    decoration: InputDecoration(
                      labelText: t.subscriptionsCvv,
                      prefixIcon: const Icon(Icons.lock_outline),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                AqarTextField(
                  controller: _label,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: t.subscriptionsCardLabel,
                    prefixIcon: const Icon(Icons.label_outline),
                  ),
                ),
                CheckboxListTile(
                  value: _default,
                  onChanged: (v) => setState(() => _default = v ?? false),
                  title: Text(t.subscriptionsDefaultCard),
                ),
                FilledButton(
                  onPressed: _saving ? null : () => unawaited(_save()),
                  child: Text(t.subscriptionsSaveCard),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
