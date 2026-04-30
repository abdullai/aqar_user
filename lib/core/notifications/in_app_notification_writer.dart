import 'package:supabase_flutter/supabase_flutter.dart';

/// إدراج موحّد لصف في `in_app_notifications` من أي مكان في التطبيق أو لاحقاً من Edge.
///
/// ضع في data مفاتيح مثل: `deep_route`, `request_id`, `title_ar`, `title_en`, `body_ar`, `body_en`
/// (انظر `InAppDeepRoutes` و `WorkflowNotificationKeys` في المشروع).
class InAppNotificationWriter {
  InAppNotificationWriter._();

  static Future<String?> _usernameForUserId(
    SupabaseClient sb,
    String userId,
  ) async {
    try {
      final r = await sb
          .from('users_profiles')
          .select('username')
          .eq('user_id', userId)
          .maybeSingle();
      final u = (r?['username'] ?? '').toString().trim();
      return u.isEmpty ? null : u;
    } catch (_) {
      return null;
    }
  }

  static Future<void> insert(
    SupabaseClient sb, {
    required String userId,
    required String type,
    required Map<String, dynamic> data,
    String? titleFallbackAr,
    String? titleFallbackEn,
    String? bodyFallbackAr,
    String? bodyFallbackEn,
    String? entityType,
    String? entityId,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    // يجب عدم إلغاء الإشعار إن تأخر أو غاب username في الملف — الاعتماد الأساسي user_id.
    var usernameForRow = (await _usernameForUserId(sb, uid)) ?? '';
    if (usernameForRow.isEmpty) {
      usernameForRow = uid;
    }

    final titleAr = (data['title_ar'] ?? titleFallbackAr ?? type).toString();
    final bodyAr =
        (data['body_ar'] ?? bodyFallbackAr ?? data['body'] ?? '').toString();

    final merged = Map<String, dynamic>.from(data);
    if (entityType != null && entityType.trim().isNotEmpty) {
      merged.putIfAbsent('entity_type', () => entityType.trim());
    }
    if (entityId != null && entityId.trim().isNotEmpty) {
      merged.putIfAbsent('entity_id', () => entityId.trim());
    }

    try {
      await sb.from('in_app_notifications').insert({
        'user_id': uid,
        'username': usernameForRow,
        'type': type,
        'title': titleAr,
        'body': bodyAr,
        'data': merged,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_read': false,
      });
    } catch (_) {}
  }
}
