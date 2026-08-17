import 'package:flutter/foundation.dart';

/// Web Payment API — يتحقق من دعم المتصفح (تنفيذ آمن مبسّط).
class WebPaymentService {
  WebPaymentService._();

  static Future<bool> isAvailable() async {
    try {
      // يُفعَّل عند توفر PaymentRequest في المتصفح — يُكمَّل عبر Moyasar widget.
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> requestPayment({
    required double amountSar,
    required String label,
    required String currency,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[WebPaymentService] fallback to Moyasar widget '
        'amount=$amountSar $currency',
      );
    }
    return {'ok': false, 'error': 'use_moyasar_widget'};
  }
}
