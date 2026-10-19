import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// يحفظ معاملة دفع معلّقة لاستئناف التحقق عند عودة الإنترنت — دون إنهاء اشتراك قبل تأكيد الخادم.
class PaymentRecoveryCoordinator {
  PaymentRecoveryCoordinator._();

  static const _prefKeyPrefix = 'aqar_pending_payment_recovery_v1';

  static String _prefKey(String userId) =>
      '${_prefKeyPrefix}_${userId.trim()}';

  static Future<void> savePending({
    required String userId,
    required String billingTransactionId,
    required double expectedAmountSar,
    required String planId,
    required String period,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _prefKey(uid),
      jsonEncode({
        'user_id': uid,
        'billing_transaction_id': billingTransactionId,
        'expected_amount_sar': expectedAmountSar,
        'plan_id': planId,
        'period': period,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<Map<String, dynamic>?> loadPending({
    required String userId,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey(uid));
      if (raw == null || raw.trim().isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final row = Map<String, dynamic>.from(m);
      if ('${row['user_id'] ?? ''}' != uid) return null;
      return row;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPending({required String userId}) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefKey(uid));
  }
}
