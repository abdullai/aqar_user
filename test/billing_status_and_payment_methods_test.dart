import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/payment/payment_platform_detector.dart';
import 'package:aqar_user/services/billing_transaction_repository.dart';

void main() {
  group('BillingTransactionRepository.normalizedStatus', () {
    test('maps paid aliases to success', () {
      expect(
        BillingTransactionRepository.normalizedStatus({'status': 'paid'}),
        'success',
      );
      expect(
        BillingTransactionRepository.normalizedStatus({'status': 'success'}),
        'success',
      );
    });

    test('maps refund variants', () {
      expect(
        BillingTransactionRepository.normalizedStatus({'status': 'refunded'}),
        'refunded',
      );
      expect(
        BillingTransactionRepository.normalizedStatus(
          {'status': 'partially_refunded'},
        ),
        'partially_refunded',
      );
    });

    test('authorized stays pending until webhook', () {
      expect(
        BillingTransactionRepository.normalizedStatus({'status': 'authorized'}),
        'pending',
      );
    });

    test('expired and cancelled are not success', () {
      expect(
        BillingTransactionRepository.normalizedStatus({'status': 'expired'}),
        'failed',
      );
      expect(
        BillingTransactionRepository.normalizedStatus({'status': 'cancelled'}),
        'failed',
      );
    });
  });

  group('PaymentCapabilityDetector / PaymentPlatformDetector', () {
    test('unsupported wallets stay disabled', () {
      expect(PaymentPlatformDetector.supportsGooglePay(), isFalse);
      expect(PaymentPlatformDetector.supportsStcPay(), isFalse);
      expect(PaymentPlatformDetector.supportsTabby(), isFalse);
      expect(PaymentPlatformDetector.supportsTamara(), isFalse);
      expect(PaymentCapabilityDetector.supportsGooglePay(), isFalse);
    });
  });
}
