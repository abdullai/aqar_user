import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/payment_service.dart';
import 'payment_platform_detector.dart';
import 'payment_security.dart';
import 'web_payment_service.dart';

/// نظام الدفع الذكي — يختار أفضل طريقة دفع حسب المنصة والسياق.
/// Smart payment flow — picks the best method per platform/context.
class SmartPaymentFlow {
  SmartPaymentFlow({
    required this.context,
    required this.isAr,
    required this.hasSavedCards,
    required this.savedCardReady,
    this.preferredMode,
  });

  final BuildContext context;
  final bool isAr;
  final bool hasSavedCards;
  final bool savedCardReady;
  final String? preferredMode;

  List<SmartPaymentMethod> get availableMethods =>
      PaymentPlatformDetector.prioritizedMethods(
        context: context,
        hasSavedCard: hasSavedCards,
        savedCardReady: savedCardReady,
      );

  /// الوضع الافتراضي الأفضل عند فتح شاشة الدفع.
  String resolveDefaultMode() {
    if (preferredMode != null && preferredMode!.trim().isNotEmpty) {
      return PaymentPlatformDetector.methodToModeKey(
        _methodFromMode(preferredMode!) ?? availableMethods.first,
      );
    }
    for (final m in availableMethods) {
      return PaymentPlatformDetector.methodToModeKey(m);
    }
    return 'new';
  }

  SmartPaymentMethod? _methodFromMode(String mode) {
    for (final m in SmartPaymentMethod.values) {
      if (PaymentPlatformDetector.methodToModeKey(m) == mode) return m;
    }
    return null;
  }

  /// هل الطريقة المختارة مدعومة فعلياً؟
  bool isModeSupported(String mode) {
    final m = _methodFromMode(mode);
    if (m == null) return mode == 'saved' || mode == 'new';
    return availableMethods.contains(m) ||
        m == SmartPaymentMethod.newCardMoyasar ||
        m == SmartPaymentMethod.savedCard;
  }

  /// Fallback: إن فشلت الطريقة الحالية، جرّب التالية.
  String? nextFallbackMode(String currentMode) {
    final methods = availableMethods;
    final keys = methods
        .map((m) => PaymentPlatformDetector.methodToModeKey(m))
        .toList();
    final idx = keys.indexOf(currentMode);
    if (idx < 0 || idx >= keys.length - 1) {
      if (!keys.contains('new')) return 'new';
      return null;
    }
    return keys[idx + 1];
  }

  /// محاولة Web Payment API على Safari/Chrome قبل نموذج ميسّر (ويب فقط).
  Future<Map<String, dynamic>?> tryWebPaymentFirst({
    required double amountSar,
    required String description,
  }) async {
    if (!kIsWeb) return null;
    if (!PaymentPlatformDetector.supportsGooglePay() &&
        !PaymentPlatformDetector.supportsApplePay()) {
      return null;
    }
    final ok = await WebPaymentService.isAvailable();
    if (!ok) return null;
    if (kDebugMode) {
      debugPrint('[SmartPaymentFlow] trying Web Payment API amount=$amountSar');
    }
    final res = await WebPaymentService.requestPayment(
      amountSar: amountSar,
      label: description,
      currency: 'SAR',
    );
    if (res['ok'] == true) return res;
    return null;
  }

  /// تسجيل اختيار الطريقة للتدقيق.
  static Future<void> logMethodChosen({
    required SupabaseClient sb,
    required String mode,
    required double amountSar,
  }) async {
    await PaymentSecurity.recordOutcome(
      sb: sb,
      event: 'payment_method_chosen',
      amountSar: amountSar,
      payload: {'mode': mode},
    );
  }

  /// هل نستخدم بطاقة محفوظة لهذا الوضع؟
  bool shouldUseSavedCard(String mode, List<Map<String, dynamic>> cards) {
    if (mode != 'saved' && mode != 'mada_pay') return false;
    if (cards.isEmpty) return false;
    if (!PaymentService.useMoyasarLiveFlow) {
      return mode == 'saved' || mode == 'mada_pay';
    }
    if (mode == 'saved') {
      return cards.any(PaymentService.canChargeSavedCard);
    }
    if (mode == 'mada_pay') {
      return cards.any(
        (c) =>
            '${c['card_scheme']}'.toLowerCase() == 'mada' &&
            PaymentService.canChargeSavedCard(c),
      );
    }
    return false;
  }
}
