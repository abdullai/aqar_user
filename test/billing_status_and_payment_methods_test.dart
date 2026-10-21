import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:aqar_user/core/payment/payment_platform_detector.dart';
import 'package:aqar_user/services/billing_transaction_repository.dart';
import 'package:aqar_user/services/payment_service.dart';
import 'package:aqar_user/services/subscription_service.dart';

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: ''));

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
      expect(
        PaymentPlatformDetector.supportsStcPay(),
        PaymentService.useMoyasarLiveFlow,
      );
      expect(PaymentPlatformDetector.supportsTabby(), isFalse);
      expect(PaymentPlatformDetector.supportsTamara(), isFalse);
      expect(PaymentCapabilityDetector.supportsGooglePay(), isFalse);
    });

    test('STC Pay is wired only when Moyasar is configured', () {
      expect(
        PaymentPlatformDetector.methodToModeKey(SmartPaymentMethod.stcPay),
        'stc_pay',
      );
      expect(PaymentPlatformDetector.supportsStcPay(), isFalse);

      dotenv.testLoad(fileInput: 'MOYASAR_PUBLISHABLE_KEY=pk_test_example');
      expect(PaymentPlatformDetector.supportsStcPay(), isTrue);

      dotenv.testLoad(fileInput: '');
      expect(PaymentPlatformDetector.supportsStcPay(), isFalse);
    });
  });

  group('Lifetime subscription access', () {
    test('active lifetime plan remains paid with no end date', () {
      final row = {
        'status': 'active',
        'is_lifetime': true,
        'ends_at': null,
      };

      expect(SubscriptionService.subscriptionRowInPaidAccess(row), isTrue);
      expect(
        SubscriptionService.pickPreferredSubscriptionRow([row])?['is_lifetime'],
        isTrue,
      );
    });

    test('one-time operation credits are not selected as the main plan', () {
      final main = {
        'id': 'main-subscription',
        'status': 'active',
        'ends_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 10))
            .toIso8601String(),
        'is_topup': false,
      };
      final credit = {
        'id': 'deal-credit',
        'status': 'active',
        'is_lifetime': true,
        'is_topup': true,
        'ends_at': null,
      };

      expect(
        SubscriptionService.pickPreferredSubscriptionRow([main, credit])?['id'],
        'main-subscription',
      );
      expect(
        SubscriptionService.pickPreferredSubscriptionRow([credit]),
        isNull,
      );
    });
  });
}
