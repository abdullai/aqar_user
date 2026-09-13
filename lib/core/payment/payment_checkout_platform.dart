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

  static bool showGooglePay(BuildContext context) => false;

  static bool showSamsungPay(BuildContext context) =>
      PaymentPlatformDetector.supportsSamsungPay();

  static bool showStcPay(BuildContext context) => false;

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
        return 'new';
      case 'samsung_pay':
        return showSamsungPay(context) ? mode : 'new';
      case 'stc_pay':
        return 'new';
      case 'web_pay':
        return 'new';
      default:
        return mode;
    }
  }
}
