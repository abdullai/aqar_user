import 'package:aqar_user/core/payment/payment_input_utils.dart';
import 'package:aqar_user/core/subscription/card_scheme.dart';
import 'package:aqar_user/services/payment_gateway_mock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CardHolderLatinUppercaseFormatter uppercases latin and strips Arabic',
      () {
    const f = CardHolderLatinUppercaseFormatter();
    final next = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: 'ahmad علي nasser',
        selection: TextSelection.collapsed(offset: 16),
      ),
    );
    expect(next.text, 'AHMAD NASSER');
    expect(containsArabicOrPersianScript(next.text), isFalse);
  });

  test('CardExpirySlashFormatter inserts slash and rejects month 13', () {
    const f = CardExpirySlashFormatter();
    final first = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '9',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    expect(first.text, '09/');

    final full = f.formatEditUpdate(
      first,
      const TextEditingValue(
        text: '1329',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    expect(full.text, '12/29');
  });

  test('isCardExpiryInPast detects expired month', () {
    expect(isCardExpiryInPast('01', '20'), isTrue);
    expect(isCardExpiryInPast('12', '99'), isFalse);
    expect(isCardExpiryInPast('', '26'), isFalse);
  });

  test('card networks are detected from early prefixes', () {
    expect(detectCardSchemeFromPan('4'), 'visa');
    expect(detectCardSchemeFromPan('51'), 'mastercard');
    expect(detectCardSchemeFromPan('2221'), 'mastercard');
    expect(detectCardSchemeFromPan('34'), 'amex');
    expect(detectCardSchemeFromPan('9682011234567890'), 'mada');
    expect(cardSchemeMaxPanDigits('amex'), 15);
    expect(cardSchemeMaxPanDigits('unknown'), 19);
  });

  test('mock-only invalid PAN mode is opt-in and keeps other fields checked',
      () {
    final nextYear = DateTime.now().year + 1;
    final strictResult = PaymentGatewayMock.mockValidateCard(
      cardNumberDigits: '1234567890123',
      expiryMonth: 12,
      expiryYear: nextYear,
      cvv: '123',
      holderName: 'DEV TESTER',
    );
    expect(strictResult, 'luhn');

    final mockResult = PaymentGatewayMock.mockValidateCard(
      cardNumberDigits: '1234567890123',
      expiryMonth: 12,
      expiryYear: nextYear,
      cvv: '123',
      holderName: 'DEV TESTER',
      allowInvalidCardNumber: true,
    );
    expect(mockResult, isNull);
  });
}
