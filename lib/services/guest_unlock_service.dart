import 'package:shared_preferences/shared_preferences.dart';

import 'payment_service.dart';

/// Local one-time unlock after successful mock checkout (until full billing is wired).
abstract final class GuestUnlockService {
  static const _kind = 'guest_ot_unlock_kind_v1';
  static const _paidMs = 'guest_ot_unlock_paid_ms_v1';
  static const _consumed = 'guest_ot_unlock_consumed_v1';

  /// `offer` | `listing` | `request`
  static Future<String?> activeKind() async {
    // لا تُفعَّل أقفال وهمية في إصدارات الإنتاج بدون بوابة مسموحة.
    if (!PaymentService.allowMockGateway) return null;
    final p = await SharedPreferences.getInstance();
    final k = (p.getString(_kind) ?? '').trim();
    if (k.isEmpty) return null;
    if (p.getBool(_consumed) ?? false) return null;
    return k;
  }

  static Future<bool> hasUnusedKind(String kind) async {
    final k = await activeKind();
    return k == kind;
  }

  static Future<void> markPaid({required String kind}) async {
    if (!PaymentService.allowMockGateway) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kind, kind);
    await p.setInt(_paidMs, DateTime.now().toUtc().millisecondsSinceEpoch);
    await p.setBool(_consumed, false);
  }

  static Future<void> consume() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_consumed, true);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kind);
    await p.remove(_paidMs);
    await p.remove(_consumed);
  }
}
