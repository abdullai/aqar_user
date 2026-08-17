import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// وهمي للتجربة — استبدل ببوابة معتمدة (HyperPay / Tap / PayTabs) بعد التصاريح.
class PaymentGatewayMock {
  PaymentGatewayMock._();
  static final _rng = Random.secure();
  static const _uuid = Uuid();

  /// نجاح تقريبي 90٪ (قابل للضبط للاختبارات).
  static double successProbability = 0.9;

  static String issueCardToken({
    required String cardBin,
    required String lastFour,
    required int expiryMonth,
    required int expiryYear,
  }) {
    final raw =
        '$cardBin|$lastFour|$expiryMonth|$expiryYear|${_uuid.v4()}|mock_gateway_v1';
    final digest = sha256.convert(raw.codeUnits);
    return 'mock_${digest.toString().substring(0, 32)}';
  }

  /// يعيد null إذا صالحة، أو رسالة خطأ مختصرة.
  static String? mockValidateCard({
    required String cardNumberDigits,
    required int expiryMonth,
    required int expiryYear,
    required String cvv,
    required String holderName,
    DateTime? now,
  }) {
    final n = cardNumberDigits.replaceAll(RegExp(r'\D'), '');
    if (n.length < 12 || n.length > 19) {
      return 'invalid_length';
    }
    if (!_passesLuhn(n)) {
      return 'luhn';
    }
    final cn = holderName.trim();
    if (cn.length < 2) {
      return 'holder';
    }
    if (!RegExp(r'^\d{3,4}$').hasMatch(cvv.trim())) {
      return 'cvv';
    }
    final clock = now ?? DateTime.now();
    if (expiryYear < clock.year ||
        (expiryYear == clock.year && expiryMonth < clock.month)) {
      return 'expired';
    }
    if (expiryMonth < 1 || expiryMonth > 12) {
      return 'expiry_month';
    }
    return null;
  }

  static bool mockProcessPayment({
    required String cardToken,
    required String amountKey,
  }) {
    // تثبيت خفيف: نفس المبلغ + نفس التوكن يعطي نفس النتيجة (مفيد للاختبار).
    final det = (cardToken.hashCode ^ amountKey.hashCode).abs() % 100;
    if (det < (successProbability * 100).round()) {
      return true;
    }
    return _rng.nextDouble() < successProbability;
  }

  static bool mockWalletPay({required String walletKind}) {
    return _rng.nextDouble() < successProbability;
  }

  static String mockGatewayTransactionId() =>
      'TXN-${DateTime.now().toUtc().millisecondsSinceEpoch}-${_rng.nextInt(9999)}';

  static bool passesLuhnPublic(String input) =>
      _passesLuhn(input.replaceAll(RegExp(r'\D'), ''));

  static bool _passesLuhn(String input) {
    var sum = 0;
    var alternate = false;
    for (var i = input.length - 1; i >= 0; i--) {
      var n = int.parse(input[i], radix: 10);
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }
}
