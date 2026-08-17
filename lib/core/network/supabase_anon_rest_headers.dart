import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/core/supabase_config.dart';
import '../auth/auth_local_sign_out.dart';
import '../config/app_config.dart';

/// رؤوس REST الآمنة للقراءة العامة (ضيف / بدون جلسة).
abstract final class SupabaseAnonRestHeaders {
  static bool get usesPublishableKey =>
      SupabaseConfig.supabaseAnonKey.startsWith('sb_publishable_');

  /// قبل طلب عام: أزل JWT منتهٍ فقط في وضع الضيف.
  /// أثناء تسجيل الدخول/التحقق (`entry_mode=user`) لا نمسح الجلسة —
  /// كان ذلك يطلق `signedOut` ويعيد المستخدم لشاشة الدخول مع 401.
  static Future<void> dropStaleUserSessionIfNeeded(SupabaseClient client) async {
    final session = client.auth.currentSession;
    if (session == null || !session.isExpired) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final guest = prefs.getBool(AppConfig.prefGuestModeKey) ?? false;
      final entry =
          (prefs.getString(AppConfig.prefEntryModeKey) ?? '').trim().toLowerCase();
      if (!guest && entry == 'user') return;
      await AuthLocalSignOut.signOutLocal(client);
    } catch (_) {}
  }
}
