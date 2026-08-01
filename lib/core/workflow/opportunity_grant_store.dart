import 'package:shared_preferences/shared_preferences.dart';

/// عدّاد «إتاحة فرصة» لكل مستخدم+طلب في تبويب بدون إجراء 72 ساعة.
/// الحد الأقصى 4 مرات؛ بعدها يختفي الصف من التبويب لذلك المستخدم.
class OpportunityGrantStore {
  OpportunityGrantStore._();

  static const int maxGrants = 4;
  static const String _prefix = 'opp_grant_v1_';

  static String _key(String userId, String requestId) =>
      '$_prefix${userId.trim()}_${requestId.trim()}';

  static Future<int> countFor({
    required String userId,
    required String requestId,
  }) async {
    if (userId.trim().isEmpty || requestId.trim().isEmpty) return 0;
    final p = await SharedPreferences.getInstance();
    return p.getInt(_key(userId, requestId)) ?? 0;
  }

  static Future<bool> canGrant({
    required String userId,
    required String requestId,
  }) async {
    final n = await countFor(userId: userId, requestId: requestId);
    return n < maxGrants;
  }

  /// يزيد العداد ويرجع الرقم الجديد (1..4) أو null إن استُنفد.
  static Future<int?> increment({
    required String userId,
    required String requestId,
  }) async {
    if (userId.trim().isEmpty || requestId.trim().isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final k = _key(userId, requestId);
    final next = (p.getInt(k) ?? 0) + 1;
    if (next > maxGrants) return null;
    await p.setInt(k, next);
    return next;
  }

  static Future<bool> isExhausted({
    required String userId,
    required String requestId,
  }) async {
    final n = await countFor(userId: userId, requestId: requestId);
    return n >= maxGrants;
  }

  static String ordinalLabel(int n, {required bool isAr}) {
    switch (n) {
      case 1:
        return isAr ? 'الأولى' : '1st';
      case 2:
        return isAr ? 'الثانية' : '2nd';
      case 3:
        return isAr ? 'الثالثة' : '3rd';
      case 4:
        return isAr ? 'الرابعة (أخيرة)' : '4th (final)';
      default:
        return isAr ? 'رقم $n' : '#$n';
    }
  }
}
