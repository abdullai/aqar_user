import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/services.dart';
import 'package:moyasar/moyasar.dart';
import 'package:moyasar/src/utils/card_utils.dart';
import 'package:moyasar/src/utils/input_formatters.dart';

import '../../services/payment_service.dart';
import 'moyasar_web_3ds.dart';

/// نموذج بطاقة ميسّر مع معالجة 3DS آمنة على الويب (بدون WebView المعطّل).
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
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return CreditCard(
        config: widget.config,
        locale: widget.locale,
        onPaymentResult: widget.onPaymentResult,
      );
    }

    return _WebCreditCardBridge(
      config: widget.config,
      locale: widget.locale,
      onPaymentResult: widget.onPaymentResult,
    );
  }
}

/// على الويب: نموذج بطاقة مع 3DS عبر نافذة منبثقة + postMessage.
class _WebCreditCardBridge extends StatefulWidget {
  const _WebCreditCardBridge({
    required this.config,
    required this.locale,
    required this.onPaymentResult,
  });

  final PaymentConfig config;
  final Localization locale;
  final void Function(dynamic result) onPaymentResult;

  @override
  State<_WebCreditCardBridge> createState() => _WebCreditCardBridgeState();
}

class _WebCreditCardBridgeState extends State<_WebCreditCardBridge> {
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
    _expiryError = CardUtils.validateDate(
      '${_cardData.month}/${_cardData.year}'.replaceAll('\u200E', ''),
      loc,
    );
    _cvcError = CardUtils.validateCVC(_cardData.cvc, loc);
  }

  void _syncCardDataFromControllers() {
    _cardData.name = _nameCtrl.text;
    _cardData.number = CardUtils.getCleanedNumber(_numberCtrl.text);
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

      final threeDs = await runMoyasarWeb3ds(transactionUrl);
      final st = threeDs.status.toLowerCase();
      if (st == 'paid' || st == 'authorized' || st == 'captured') {
        result.status = PaymentStatus.paid;
      } else if (st == 'failed' ||
          st == 'cancelled' ||
          st == 'error' ||
          st == 'closed' ||
          st == 'timeout') {
        result.status = PaymentStatus.failed;
        (result.source as CardPaymentResponseSource).message =
            threeDs.message.isNotEmpty ? threeDs.message : st;
      }
      widget.onPaymentResult(result);
    } catch (e) {
      if (kDebugMode) debugPrint('[AqarMoyasarCreditCard] pay error: $e');
      widget.onPaymentResult(ValidationError.messageOnly(e.toString()));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.locale;
    final dir =
        loc.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          loc.cardInformation,
          textAlign:
              dir == TextDirection.rtl ? TextAlign.right : TextAlign.left,
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
          textDirection: dir,
          autofocus: true,
          autofillHints: const [AutofillHints.creditCardName],
          onChanged: (v) {
            _cardData.name = v;
            _nameError = CardUtils.validateName(v, loc);
            setState(() {});
          },
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z. ]')),
          ],
        ),
        const SizedBox(height: 12),
        AqarTextField(
          controller: _numberCtrl,
          decoration: InputDecoration(
            labelText: loc.cardNumber,
            border: const OutlineInputBorder(),
            errorText: _cardNumberError,
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.creditCardNumber],
          onChanged: (v) {
            _cardData.number = CardUtils.getCleanedNumber(v);
            _cardNumberError = CardUtils.validateCardNum(v, loc);
            setState(() {});
          },
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(16),
            CardNumberInputFormatter(),
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
                  border: const OutlineInputBorder(),
                  errorText: _expiryError,
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.creditCardExpirationDate],
                onChanged: (v) {
                  final parts = CardUtils.getExpiryDate(
                    v.replaceAll('\u200E', ''),
                  );
                  _cardData.month = parts.first.replaceAll('\u200E', '');
                  _cardData.year = parts.length > 1
                      ? parts[1].replaceAll('\u200E', '')
                      : '';
                  _expiryError = CardUtils.validateDate(
                    v.replaceAll('\u200E', ''),
                    loc,
                  );
                  setState(() {});
                },
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                  CardMonthInputFormatter(),
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
                obscureText: true,
                autofillHints: const [AutofillHints.creditCardSecurityCode],
                onChanged: (v) {
                  _cardData.cvc = v;
                  _cvcError = CardUtils.validateCVC(v, loc);
                  setState(() {});
                },
                onSubmitted: (_) => _pay(),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
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
    );
  }
}
