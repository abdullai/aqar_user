import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// يحفظ معاملة دفع معلّقة لاستئناف التحقق عند عودة الإنترنت — دون إنهاء اشتراك قبل تأكيد الخادم.
class PaymentRecoveryCoordinator {
  PaymentRecoveryCoordinator._();

  static const _prefKey = 'aqar_pending_payment_recovery_v1';

  static Future<void> savePending({
    required String billingTransactionId,
    required double expectedAmountSar,
    required String planId,
    required String period,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _prefKey,
      jsonEncode({
        'billing_transaction_id': billingTransactionId,
        'expected_amount_sar': expectedAmountSar,
        'plan_id': planId,
        'period': period,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<Map<String, dynamic>?> loadPending() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      return Map<String, dynamic>.from(m);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPending() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefKey);
  }
}
