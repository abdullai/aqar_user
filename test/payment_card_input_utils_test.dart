import 'package:aqar_user/core/payment/payment_input_utils.dart';
import 'package:aqar_user/core/payment/payment_recovery_coordinator.dart';
import 'package:aqar_user/core/subscription/card_scheme.dart';
import 'package:aqar_user/services/payment_gateway_mock.dart';
import 'package:aqar_user/services/payment_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyasar/moyasar.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('Moyasar authorization errors map to a safe actionable code', () {
    final error = ValidationError.messageOnly(
      'type: authentication_error, message: Invalid authorization credentials',
    );

    expect(PaymentService.mapMoyasarResultToError(error), 'moyasar_auth_error');
  });

  test('pending payment recovery is isolated per signed-in user', () async {
    SharedPreferences.setMockInitialValues({});
    await PaymentRecoveryCoordinator.savePending(
      userId: 'user-a',
      billingTransactionId: 'billing-a',
      expectedAmountSar: 99,
      planId: 'plan-a',
      period: 'monthly',
    );
    await PaymentRecoveryCoordinator.savePending(
      userId: 'user-b',
      billingTransactionId: 'billing-b',
      expectedAmountSar: 149,
      planId: 'plan-b',
      period: 'monthly',
    );

    expect(
      (await PaymentRecoveryCoordinator.loadPending(
          userId: 'user-a'))?['billing_transaction_id'],
      'billing-a',
    );
    await PaymentRecoveryCoordinator.clearPending(userId: 'user-b');
    expect(
      (await PaymentRecoveryCoordinator.loadPending(
          userId: 'user-a'))?['billing_transaction_id'],
      'billing-a',
    );
    expect(
      await PaymentRecoveryCoordinator.loadPending(userId: 'user-b'),
      isNull,
    );
  });
}
