import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/payment_service.dart';
import 'payment_platform_detector.dart';

/// تحقق نهائي قبل عرض خيار الدفع في واجهة الدفع.
class PaymentCheckoutPlatform {
  PaymentCheckoutPlatform._();

  /// مدى — كل المنصات.
  static bool showMadaPay(BuildContext context) =>
      PaymentPlatformDetector.supportsMada();

  static bool showApplePay(BuildContext context) =>
      PaymentPlatformDetector.supportsApplePay();

  static bool showGooglePay(BuildContext context) =>
      PaymentPlatformDetector.supportsGooglePay();

  static bool showStcPay(BuildContext context) =>
      PaymentPlatformDetector.supportsStcPay();

  static bool showCardPayment(BuildContext context) =>
      PaymentService.useMoyasarLiveFlow || PaymentService.allowMockGateway;

  static String normalizeMode(BuildContext context, String mode) {
    switch (mode) {
      case 'saved':
        return showCardPayment(context) ? mode : 'new';
      case 'new':
        return showCardPayment(context) ? mode : mode;
      case 'mada_pay':
        return showMadaPay(context) ? mode : 'new';
      case 'apple_pay':
        return showApplePay(context) ? mode : 'new';
      case 'google_pay':
        return showGooglePay(context) ? mode : 'new';
      case 'stc_pay':
        return showStcPay(context) ? mode : 'new';
      case 'web_pay':
        return 'new';
      default:
        return mode;
    }
  }
}
