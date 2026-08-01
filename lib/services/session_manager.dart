import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth/auth_local_sign_out.dart';
import '../core/config/app_config.dart';
import '../core/session/account_role_cache.dart';
import '../core/session/web_auth_tab_guard.dart';
import 'fast_login_service.dart';
import 'org_permission_manager.dart';
import 'session_tracking_service.dart';

/// جلسة Supabase + تفضيلات الجهاز: إقلاع الويب، التحقق، ومسح آمن عند الخروج.
abstract final class SessionManager {
  /// أثناء `signOut(local)` المتعمّد للقراءة العامة — تجاهل مستمعي `signedOut` (كانوا يعلّقون الويب).
  static int _publicSessionResetDepth = 0;

  static bool get duringPublicSessionReset => _publicSessionResetDepth > 0;
  /// بعد [Supabase.initialize] على الويب: لا نُلغي الجلسة على كل تحديث للصفحة.
  /// نحاول [refreshSession] قصيراً؛ عند الفشل نُسقط الجلسة المحلية فقط.
  static Future<void> bootstrapWebAfterSupabaseInit(SupabaseClient client) async {
    if (!kIsWeb) return;

    // ضيف الويب: أي JWT قديم في localStorage يسبب 401 على properties للزائر.
    try {
      final prefs = await SharedPreferences.getInstance();
      final guestMode = prefs.getBool(AppConfig.prefGuestModeKey) ?? false;
      final entry =
          (prefs.getString(AppConfig.prefEntryModeKey) ?? '').trim().toLowerCase();
      if (guestMode || entry == 'guest') {
        await clearLocalAuthSessionForPublicReads(client);
        return;
      }
    } catch (_) {}

    final s = client.auth.currentSession;
    if (s == null) {
      // قد يبقى refresh_token تالفاً في التخزين بلا session ظاهرة — امسحه.
      try {
        await AuthLocalSignOut.signOutLocal(client);
      } catch (_) {}
      return;
    }
    try {
      await client.auth
          .refreshSession()
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // 400 refresh_token شائع بعد جلسات قديمة — امسح فوراً ولا تُعد المحاولة.
      await clearLocalAuthSessionForPublicReads(client);
    }
  }

  /// قبل جلب الرئيسية كضيف أو بعد 401 — لا تُرسل جلسة مستخدم منتهية مع طلبات عامة.
  static Future<void> clearLocalAuthSessionForPublicReads(
    SupabaseClient client,
  ) async {
    if (client.auth.currentSession == null) return;
    _publicSessionResetDepth++;
    try {
      await AuthLocalSignOut.signOutLocal(client);
    } catch (_) {
      // تجاهل 401 عند logout بجلسة منتهية — الهدف مسح التخزين المحلي فقط.
    } finally {
      if (_publicSessionResetDepth > 0) {
        _publicSessionResetDepth--;
      }
    }
  }

  /// قبل طلبات REST الحساسة: يعيد التحديث عند اقتراب الانتهاء (اختياري خفيف).
  static Future<void> touchSessionIfNeeded(SupabaseClient client) async {
    final s = client.auth.currentSession;
    if (s == null) return;
    final exp = s.expiresAt;
    if (exp == null) return;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp - nowSec > 120) return;
    try {
      await client.auth
          .refreshSession()
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// مسح مفاتيح الجلسة/الصلاحيات/التتبع (بدون مسح اللغة/الثيم/حجم النص).
  static Future<void> clearPreferencesAfterLogout(String? supabaseUserId) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      await prefs.remove(AppConfig.prefGuestModeKey);
      await prefs.remove(AppConfig.prefEntryModeKey);
      await prefs.remove(AppConfig.prefGuestLegacyIsGuestKey);
      await prefs.remove(AppConfig.prefGuestLegacyGuestKey);
      await prefs.remove(AppConfig.prefDashboardAdvancedSearchDraftKey);
      await prefs.remove(AppConfig.prefWebGuestLastActivityMs);
      final keys = prefs.getKeys().toList();
      for (final k in keys) {
        if (k.startsWith('otp_verified_')) {
          await prefs.remove(k);
        }
      }
      await prefs.remove(AppConfig.prefRegulatoryCookieAckKey);
    } catch (_) {}

    try {
      await FastLoginService.clearSecretsKeepResume();
    } catch (_) {}

    try {
      await AccountRoleCache.clear();
    } catch (_) {}

    try {
      if (supabaseUserId != null && supabaseUserId.isNotEmpty) {
        await OrgPermissionManager.clearUser(supabaseUserId);
      } else {
        await OrgPermissionManager.clearAllCachedUsers();
      }
    } catch (_) {}

    try {
      await SessionTrackingService.clearLocalTrackingState();
    } catch (_) {}

    try {
      await WebAuthTabGuard.clearBinding();
    } catch (_) {}
  }

  /// على شاشة الدخول: إزالة أعلام OTP عندما لا توجد جلسة (كاش قديم بعد F5).
  static Future<void> scrubStaleOtpFlagsWithoutSession() async {
    try {
      if (Supabase.instance.client.auth.currentSession != null) return;
    } catch (_) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('otp_verified_'));
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
