import 'package:supabase_flutter/supabase_flutter.dart';

/// ربط تطبيق «أمان الدخول / التحقق» بقاعدة Supabase (ترحيل + RPC + أعمدة).
///
/// **ترحيل (أعمدة + دوال):**
/// `supabase/migrations/20260510140000_users_profiles_login_security_counters.sql`
///
/// **استعلامات تشغيل / لوحة (نفس المشروع الذي طُبّق عليه الترحيل):**
/// `supabase/sql/20260510_profile_login_security_sample_queries.sql`
///
/// **استدعاءات من التطبيق:**
/// - بعد نجاح OTP: [recordVerifiedLoginAfterOtp] ← `lib/screens/verify_screen.dart`
/// - بعد كلمة مرور خاطئة: [recordFailedPasswordLogin] ← `lib/services/auth_service.dart`
///
/// **قراءة «آخر دخول» في الواجهة:** ترتيب المفاتيح في
/// [ProfileGreetingFromRow.lastLoginAt] — `lib/core/utils/profile_greeting_from_row.dart`
///
/// **الأجهزة (تفصيل لكل مستخدم + بصمة):** جدول `public.user_devices` — منطق التسجيل
/// الحالي في `register_device` / تثبيت الجهاز بعد الدخول (لا يُستبدل بهذا الملف).
abstract final class LoginSecurityDb {
  LoginSecurityDb._();

  static const String migrationRelativePath =
      'supabase/migrations/20260510140000_users_profiles_login_security_counters.sql';

  static const String sampleQueriesRelativePath =
      'supabase/sql/20260510_profile_login_security_sample_queries.sql';

  static const String rpcRecordVerifiedLoginAfterOtp =
      'record_verified_login_after_otp';

  static const String rpcRecordFailedPasswordLogin =
      'record_failed_password_login';

  /// جزء `select(...)` لـ PostgREST على `users_profiles` (شاشة التحقق + الترحيب).
  static const String usersProfilesSelectForVerifyGreeting =
      'username,avatar_url,'
      'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
      'first_name_en,second_name_en,third_name_en,fourth_name_en,'
      'full_name_ar,full_name_en,full_name,office_name,'
      'last_verified_login_at,last_login_at';

  /// يحدّث `last_verified_login_at` ويزيد `successful_login_count` (يستدعى بعد التحقق من OTP).
  static Future<void> recordVerifiedLoginAfterOtp(SupabaseClient client) async {
    try {
      await client.rpc(rpcRecordVerifiedLoginAfterOtp);
    } catch (_) {}
  }

  /// يزيد عداد فشل كلمة المرور عند حلّ المستخدم (10 أرقام) — بدون جلسة مصدّقة.
  static Future<void> recordFailedPasswordLogin(
    SupabaseClient client, {
    required String tenDigitUsername,
  }) async {
    try {
      await client.rpc(
        rpcRecordFailedPasswordLogin,
        params: {'p_digits': tenDigitUsername},
      );
    } catch (_) {}
  }
}
