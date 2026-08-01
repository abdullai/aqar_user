/// Web Payment API غير متاح على هذا المنصّ.
class WebPaymentService {
  WebPaymentService._();

  static Future<bool> isAvailable() async => false;

  static Future<Map<String, dynamic>> requestPayment({
    required double amountSar,
    required String label,
    required String currency,
  }) async {
    return {'ok': false, 'error': 'web_payment_unavailable'};
  }
}
