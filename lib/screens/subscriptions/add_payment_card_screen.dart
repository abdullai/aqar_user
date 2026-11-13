import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_credit_card/flutter_credit_card.dart';
import 'package:moyasar/moyasar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/gestures/app_keyboard_inset.dart';
import '../../core/gestures/app_keyboard_popups.dart';
import '../../core/navigation/payment_overlay_route.dart';
import '../../core/navigation/safe_overlay_pop.dart';
import '../../core/payment/card_brand_mark.dart';
import '../../core/payment/payment_input_utils.dart';
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

  Future<void> _showNoChargeCardInfo() async {
    final t = AppLocalizations.of(context)!;
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.credit_card_outlined),
        title: Text(t.subscriptionsAddCardTitle),
        content: Text(
          _isAr
              ? 'لن نخصم رسماً لإضافة البطاقة. تُحفَظ بأمان عند إتمام أول دفعة فعلية عبر ميسر.'
              : 'There is no separate card-saving charge. Your card is securely saved after your first successful Moyasar payment.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_isAr ? 'حسناً' : 'OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyMoyasarTestCard() async {
    if (!PaymentService.isMoyasarTestMode || _saving) return;
    setState(() => _saving = true);
    try {
      final existingCardIds =
          (await _pay.getSavedCards()).map((card) => '${card['id']}').toSet();
      final pending = await _pay.createPendingBillingTransaction(
        amount: 1,
        paymentMethod: 'card',
        purpose: 'save_card_verify',
      );
      if (pending['ok'] != true) {
        throw StateError(
          PaymentService.userFacingError(
            pending['error'] ?? 'pending_tx',
            isAr: _isAr,
          ),
        );
      }
      final billingId = '${pending['transaction_id'] ?? ''}'.trim();
      final rawAmount = pending['amount'] ?? pending['expected_amount'];
      final amount = rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse('$rawAmount') ?? 1;
      if (billingId.isEmpty || amount <= 0) {
        throw StateError(_isAr
            ? 'تعذّر إنشاء معاملة التحقق.'
            : 'Could not create the verification transaction.');
      }

      final config = _pay.buildMoyasarPaymentConfig(
        amountHalalas: PaymentService.amountToHalalas(amount),
        description: _isAr ? 'التحقق من البطاقة' : 'Card verification',
        metadata: _pay.buildMoyasarSubscriptionMetadata(
          billingTransactionId: billingId,
          purpose: 'save_card_verify',
        ),
        madaPreferredNetworksOnly: false,
      );
      if (!mounted) return;
      final result = await PaymentOverlay.push<dynamic>(
        context,
        name: '/subscriptions/moyasar-test-card-verification',
        page: MoyasarSubscriptionPaymentScreen(
          config: config,
          walletMode: MoyasarWalletMode.none,
          isAr: _isAr,
          planName: _isAr ? 'التحقق من البطاقة' : 'Card verification',
          amountSar: amount,
          periodLabel:
              _isAr ? 'اختبار — بلا خصم حقيقي' : 'Test — no real charge',
        ),
      );
      if (!mounted) return;
      if (result is! PaymentResponse ||
          !PaymentService.moyasarPaymentSucceeded(result)) {
        throw StateError(
          PaymentService.userFacingError(
            PaymentService.mapMoyasarResultToError(result) ??
                'moyasar_cancelled_or_failed',
            isAr: _isAr,
          ),
        );
      }

      final confirmation = await _pay.confirmMoyasarPayment(
        billingTransactionId: billingId,
        paymentId: result.id,
      );
      final verified = confirmation['ok'] == true
          ? await _pay.verifyBillingTransactionPaid(
              billingTransactionId: billingId,
              expectedAmountSar: amount,
            )
          : await _pay.pollUntilBillingTransactionPaid(
              billingTransactionId: billingId,
              expectedAmountSar: amount,
            );
      if (verified['ok'] != true) {
        throw StateError(
          PaymentService.userFacingError(
            verified['error'] ?? 'webhook_timeout',
            isAr: _isAr,
          ),
        );
      }

      var savedRealCard = confirmation['card_saved'] == true;
      for (var attempt = 0; attempt < 6 && mounted; attempt++) {
        if (savedRealCard) break;
        final cards = await _pay.getSavedCards();
        savedRealCard = cards.any((card) =>
            !existingCardIds.contains('${card['id']}') &&
            !PaymentService.isMockCardToken(card['card_token']));
        if (savedRealCard) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!savedRealCard) {
        throw StateError(_isAr
            ? 'تم التحقق من البطاقة لكن لم يكتمل حفظها بعد. أعد فتح بطاقات الدفع بعد لحظات، وإن لم تظهر تواصل مع الدعم.'
            : 'The card was verified but saving has not completed yet. Reopen payment cards in a moment, or contact support.');
      }
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e, st) {
      debugPrint('[AddPaymentCard] Moyasar test verification failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            PaymentService.userFacingError(e, isAr: _isAr),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    if (res['ok'] == true) {
      Navigator.pop(context, true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_errorLabel(res['error'], t))),
    );
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
    if (!PaymentService.useMoyasarLiveFlow &&
        !PaymentService.allowMockGateway &&
        !PaymentService.allowDevelopmentMockCards) {
      return PaymentPopGuard(
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: _closeAppBar(t),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _isAr
                    ? 'لا يمكن إضافة بطاقة حتى تهيئة بوابة الدفع لهذه البيئة.'
                    : 'A card cannot be added until a payment gateway is configured for this environment.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      );
    }
    if (PaymentService.useMoyasarLiveFlow &&
        !PaymentService.allowDevelopmentMockCards) {
      return PaymentPopGuard(
        busy: _saving,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: _closeAppBar(t),
          body: AppKeyboardPad(
            extra: 16,
            child: AqarPrimaryScrollScope(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
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
                    Text(
                      _isAr
                          ? PaymentService.isMoyasarTestMode
                              ? 'ستُدخل بيانات بطاقتك في نافذة دفع آمنة للتحقق منها، ثم تُحفَظ تلقائياً. هذا وضع تجريبي: لن يتم خصم أي مبلغ حقيقي.'
                              : 'لن تُخصم رسوم مستقلة لإضافة البطاقة. ستُحفَظ بأمان بعد أول دفعة ناجحة عبر ميسر.'
                          : PaymentService.isMoyasarTestMode
                              ? 'Enter your card details in a secure payment window to verify it; it is then saved automatically. This is test mode: no real amount is charged.'
                              : 'No separate card-saving fee. The card is securely saved after your first successful Moyasar payment.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : PaymentService.isMoyasarTestMode
                              ? _verifyMoyasarTestCard
                              : _showNoChargeCardInfo,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_outline),
                      label: Text(
                        _isAr
                            ? PaymentService.isMoyasarTestMode
                                ? 'إضافة البطاقة وحفظها'
                                : 'معلومات حفظ البطاقة'
                            : PaymentService.isMoyasarTestMode
                                ? 'Add and save card'
                                : 'Card saving details',
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              padding: AppKeyboardInset.scrollViewPadding(
                context,
                base: const EdgeInsets.all(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (PaymentService.allowDevelopmentMockCards)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _isAr
                            ? 'وضع تطوير: تُحفظ بطاقة وهمية محلياً لاختبار الواجهة فقط. لن تُستخدم للدفع أو تفعيل اشتراك.'
                            : 'Development mode: a fake card is stored locally for UI testing only. It cannot pay or activate a subscription.',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
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
                    inputFormatters: [
                      CardPanFormatter(
                          maxDigits: cardSchemeMaxPanDigits(scheme)),
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
