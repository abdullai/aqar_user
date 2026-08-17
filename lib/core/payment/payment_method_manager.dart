import 'package:flutter/material.dart';

import 'payment_checkout_platform.dart';
import 'payment_platform_detector.dart';

/// Alias عام لطرق الدفع — يطابق [SmartPaymentMethod].
typedef PaymentMethod = SmartPaymentMethod;

/// إدارة طرق الدفع المتاحة حسب الجهاز / المتصفح / التطبيق.
abstract final class PaymentMethodManager {
  static List<PaymentMethod> getAvailableMethods({
    required BuildContext context,
    bool hasSavedCards = false,
    bool savedCardReady = false,
  }) {
    return PaymentPlatformDetector.prioritizedMethods(
      context: context,
      hasSavedCard: hasSavedCards,
      savedCardReady: savedCardReady,
    );
  }

  /// طرق تظهر في قائمة الاختيار (باستثناء البطاقة المحفوظة — تُعرض منفصلة).
  static List<PaymentMethod> selectableMethods({
    required BuildContext context,
    bool hasSavedCards = false,
    bool savedCardReady = false,
  }) {
    return getAvailableMethods(
      context: context,
      hasSavedCards: hasSavedCards,
      savedCardReady: savedCardReady,
    ).where((m) {
      final mode = PaymentPlatformDetector.methodToModeKey(m);
      if (mode == 'saved') return false;
      if (mode == 'tabby' || mode == 'tamara') return false;
      return PaymentCheckoutPlatform.normalizeMode(context, mode) == mode;
    }).toList();
  }

  static String displayName(PaymentMethod method, {required bool isAr}) =>
      PaymentPlatformDetector.labelFor(method, isAr: isAr);

  static IconData icon(PaymentMethod method) =>
      PaymentPlatformDetector.iconFor(method);

  static String modeKey(PaymentMethod method) =>
      PaymentPlatformDetector.methodToModeKey(method);
}
