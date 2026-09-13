import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:moyasar/moyasar.dart';
import 'package:moyasar/src/utils/card_utils.dart';
import 'package:moyasar/src/widgets/three_d_s_webview.dart';

import '../../core/input/locale_text_input_guard.dart';
import '../../core/subscription/card_scheme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/payment_service.dart';
import 'card_brand_mark.dart';
import 'moyasar_web_3ds.dart';
import 'payment_input_utils.dart';

/// نموذج بطاقة موحّد (ويب + تطبيق): شعار الشبكة، اسم لاتيني كبير، تاريخ MM/YY.
class AqarMoyasarCreditCard extends StatefulWidget {
  const AqarMoyasarCreditCard({
    super.key,
    required this.config,
    required this.onPaymentResult,
    this.locale = const Localization.en(),
  });

  final PaymentConfig config;
  final void Function(dynamic result) onPaymentResult;
  final Localization locale;

  @override
  State<AqarMoyasarCreditCard> createState() => _AqarMoyasarCreditCardState();
}

class _AqarMoyasarCreditCardState extends State<AqarMoyasarCreditCard> {
  final _cardData = CardFormModel();
  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvcCtrl = TextEditingController();
  bool _submitting = false;
  String? _nameError;
  String? _cardNumberError;
  String? _expiryError;
  String? _cvcError;

  bool get _isAr => widget.locale.languageCode == 'ar';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _expiryCtrl.dispose();
    _cvcCtrl.dispose();
    super.dispose();
  }

  bool get _isValid {
    return _nameError == null &&
        _cardNumberError == null &&
        _expiryError == null &&
        _cvcError == null &&
        _cardData.name.trim().isNotEmpty &&
        _cardData.number.trim().isNotEmpty &&
        _cardData.month.trim().isNotEmpty &&
        _cardData.year.trim().isNotEmpty &&
        _cardData.cvc.trim().isNotEmpty;
  }

  void _validateAll(Localization loc) {
    _nameError = CardUtils.validateName(_cardData.name, loc);
    _cardNumberError = CardUtils.validateCardNum(_cardData.number, loc);
    final expiryShown = '${_cardData.month}/${_cardData.year}'
        .replaceAll('\u200E', '');
    _expiryError = CardUtils.validateDate(expiryShown, loc);
    if (_expiryError == null &&
        isCardExpiryInPast(_cardData.month, _cardData.year)) {
      _expiryError = loc.languageCode == 'ar'
          ? 'تاريخ الانتهاء منتهٍ'
          : 'Card has expired';
    }
    _cvcError = CardUtils.validateCVC(_cardData.cvc, loc);
  }

  void _syncCardDataFromControllers() {
    _cardData.name = _nameCtrl.text.trim();
    _cardData.number =
        CardUtils.getCleanedNumber(normalizeWesternDigits(_numberCtrl.text));
    final expiry = _expiryCtrl.text.replaceAll('\u200E', '');
    final parts = CardUtils.getExpiryDate(expiry);
    _cardData.month =
        parts.isNotEmpty ? parts.first.replaceAll('\u200E', '') : '';
    _cardData.year =
        parts.length > 1 ? parts[1].replaceAll('\u200E', '') : '';
    _cardData.cvc = _cvcCtrl.text;
  }

  Future<void> _pay() async {
    if (_submitting) return;
    final loc = widget.locale;
    _syncCardDataFromControllers();
    _validateAll(loc);
    if (!_isValid) {
      setState(() {});
      return;
    }

    setState(() => _submitting = true);

    try {
      PaymentService.configureMoyasarCallbackUrlFromEnv();
      final source = CardPaymentRequestSource(
        creditCardData: _cardData,
        tokenizeCard: widget.config.creditCard?.saveCard ?? true,
        manualPayment: widget.config.creditCard?.manual ?? false,
      );
      final paymentRequest = PaymentRequest(widget.config, source);
      final result = await Moyasar.pay(
        apiKey: widget.config.publishableApiKey,
        paymentRequest: paymentRequest,
      );

      if (result is! PaymentResponse ||
          result.status != PaymentStatus.initiated) {
        widget.onPaymentResult(result);
        return;
      }

      final transactionUrl =
          (result.source as CardPaymentResponseSource).transactionUrl ?? '';
      if (transactionUrl.trim().isEmpty) {
        widget.onPaymentResult(result);
        return;
      }

      if (kIsWeb) {
        final threeDs = await runMoyasarWeb3ds(transactionUrl);
        _applyThreeDsStatus(result, threeDs.status, threeDs.message);
        widget.onPaymentResult(result);
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => ThreeDSWebView(
            transactionUrl: transactionUrl,
            on3dsDone: (String status, String message) {
              _applyThreeDsStatus(result, status, message);
              Navigator.of(ctx).pop();
              widget.onPaymentResult(result);
            },
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AqarMoyasarCreditCard] pay error: $e');
      widget.onPaymentResult(ValidationError.messageOnly(e.toString()));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _applyThreeDsStatus(
    PaymentResponse result,
    String status,
    String message,
  ) {
    final st = status.toLowerCase();
    if (st == 'paid' || st == PaymentStatus.paid.name) {
      result.status = PaymentStatus.paid;
    } else if (st == 'authorized' || st == PaymentStatus.authorized.name) {
      result.status = PaymentStatus.authorized;
    } else if (st == 'captured' || st == PaymentStatus.captured.name) {
      result.status = PaymentStatus.captured;
    } else {
      result.status = PaymentStatus.failed;
      (result.source as CardPaymentResponseSource).message =
          message.isNotEmpty ? message : st;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locale;
    final l10n = AppLocalizations.of(context);
    final dir = _isAr ? TextDirection.rtl : TextDirection.ltr;
    final scheme = detectCardSchemeFromPan(_numberCtrl.text);

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n?.subscriptionsCreditMadaTitle ?? loc.cardInformation,
            textAlign:
                dir == TextDirection.rtl ? TextAlign.right : TextAlign.left,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          AqarTextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: loc.nameOnCard,
              border: const OutlineInputBorder(),
              errorText: _nameError,
            ),
            textInputAction: TextInputAction.next,
            textDirection: TextDirection.ltr,
            textCapitalization: TextCapitalization.characters,
            autofocus: true,
            localeScript: AqarLocaleScript.english,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: const [AutofillHints.creditCardName],
            onChanged: (v) {
              _cardData.name = v.trim();
              _nameError = CardUtils.validateName(_cardData.name, loc);
              setState(() {});
            },
            inputFormatters: const [
              CardHolderLatinUppercaseFormatter(),
            ],
          ),
          const SizedBox(height: 12),
          AqarTextField(
            controller: _numberCtrl,
            decoration: InputDecoration(
              labelText: loc.cardNumber,
              border: const OutlineInputBorder(),
              errorText: _cardNumberError,
              suffixIcon: scheme == 'unknown'
                  ? null
                  : Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: CardBrandMark(scheme: scheme),
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 28,
              ),
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            textDirection: TextDirection.ltr,
            autofillHints: const [AutofillHints.creditCardNumber],
            onChanged: (v) {
              _cardData.number = CardUtils.getCleanedNumber(
                normalizeWesternDigits(v),
              );
              _cardNumberError = CardUtils.validateCardNum(
                _cardData.number,
                loc,
              );
              setState(() {});
            },
            inputFormatters: const [
              CardPanFormatter(maxDigits: 19),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AqarTextField(
                  controller: _expiryCtrl,
                  decoration: InputDecoration(
                    labelText: loc.expiry,
                    hintText: 'MM/YY',
                    border: const OutlineInputBorder(),
                    errorText: _expiryError,
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [
                    AutofillHints.creditCardExpirationDate,
                  ],
                  onChanged: (v) {
                    final parts = CardUtils.getExpiryDate(
                      normalizeWesternDigits(v).replaceAll('\u200E', ''),
                    );
                    _cardData.month = parts.isNotEmpty
                        ? parts.first.replaceAll('\u200E', '')
                        : '';
                    _cardData.year = parts.length > 1
                        ? parts[1].replaceAll('\u200E', '')
                        : '';
                    _expiryError = CardUtils.validateDate(
                      v.replaceAll('\u200E', ''),
                      loc,
                    );
                    if (_expiryError == null &&
                        isCardExpiryInPast(
                          _cardData.month,
                          _cardData.year,
                        )) {
                      _expiryError = _isAr
                          ? 'تاريخ الانتهاء منتهٍ'
                          : 'Card has expired';
                    }
                    setState(() {});
                  },
                  inputFormatters: const [
                    WesternDigitNormalizer(),
                    CardExpirySlashFormatter(),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AqarTextField(
                  controller: _cvcCtrl,
                  decoration: InputDecoration(
                    labelText: loc.cvc,
                    border: const OutlineInputBorder(),
                    errorText: _cvcError,
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  textDirection: TextDirection.ltr,
                  obscureText: true,
                  autofillHints: const [AutofillHints.creditCardSecurityCode],
                  onChanged: (v) {
                    _cardData.cvc = normalizeWesternDigits(v);
                    _cvcError = CardUtils.validateCVC(_cardData.cvc, loc);
                    setState(() {});
                  },
                  onSubmitted: (_) => _pay(),
                  inputFormatters: const [
                    WesternDigitNormalizer(),
                    DigitsOnlyFormatter(4),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting || !_isValid ? null : _pay,
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(loc.pay),
          ),
          const SizedBox(height: 8),
          Text(
            loc.saveCardNotice,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
