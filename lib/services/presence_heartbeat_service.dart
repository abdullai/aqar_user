import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_install_session_service.dart';

/// Periodic ping so [get_app_audience_stats] reflects open clients (guest or signed-in).
///
/// النبضة تحدّث أيضاً [users_profiles.chat_last_seen_at] للمستخدم المسجّل
/// عبر RPC [ping_app_presence] على جانب الخادم — وبهذا تنعكس حالة «متصل الآن»
/// لحظياً على بطاقات الإعلان والطلبات (التي تشترك Realtime على نفس الجدول).
abstract final class PresenceHeartbeatService {
  static const int _maxKeyLen = 480;

  static Future<String> clientKey(SupabaseClient sb) async {
    final install = await UserInstallSessionService.installDeviceKey();
    final uid = sb.auth.currentUser?.id ?? '';
    final raw = uid.isNotEmpty ? '$uid|$install' : 'g|$install';
    return raw.length <= _maxKeyLen ? raw : raw.substring(0, _maxKeyLen);
  }

  static Future<void> ping(SupabaseClient sb) async {
    try {
      final key = await clientKey(sb);
      await sb
          .rpc<void>(
            'ping_app_presence',
            params: {'p_client_key': key},
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// نبضة وداع — تستدعى عند إغلاق التبويب/تسجيل الخروج/إخفاء التطبيق
  /// لتسجيل آخر ظهور حقيقي على الخادم فوراً (بدلاً من بقاء «متصل الآن»
  /// حتى تنتهي مهلة 90 ثانية تلقائياً).
  static Future<void> markOffline(SupabaseClient sb) async {
    try {
      if (sb.auth.currentSession == null) return;
      await sb.rpc<void>('ping_app_offline').timeout(
            const Duration(seconds: 4),
          );
    } catch (_) {}
  }
}
