// lib/services/auth_service.dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:aqar_user/models.dart';
import 'package:aqar_user/core/input/input_normalizers.dart';

class LoginResult {
  final bool ok;
  final String message;
  final bool locked;
  final AppUser? user;

  const LoginResult({
    required this.ok,
    required this.message,
    required this.locked,
    this.user,
  });
}

class AuthService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /* ============================================================
   * Helpers
   * ============================================================ */

  /// تحويل الأرقام العربية/الفارسية إلى 0-9
  static String normalizeNumbers(String input) => normalizeAsciiDigits(input);

  static bool _isValidLoginKey(String v) {
    final s = digitsOnly(normalizeAsciiDigits(v.trim()));
    return isTenDigitLoginKey(s);
  }

  /// مفتاح موحّد لاستدعاءات الأمان/OTP (يطابق users_profiles.username عند الحاجة).
  static Future<String> securityUsernameForDeviceFlow(String rawInput) async {
    final u = digitsOnly(normalizeAsciiDigits(rawInput.trim()));
    if (!isTenDigitLoginKey(u)) return u;
    try {
      final res = await _sb.rpc(
        'get_security_username_for_login',
        params: {'p_digits': u},
      );
      final s = res?.toString().trim() ?? '';
      if (isTenDigitLoginKey(s)) return s;
    } catch (_) {}
    return u;
  }

  /// ✅ يعمل على Web بدون dart:io
  /// بصمة الجهاز لاستدعاءات الأمان / تسجيل الجهاز (نفس المنطق الداخلي).
  static Future<String> deviceFingerprint() async {
    return _deviceFingerprint();
  }

  static Future<String> _deviceFingerprint() async {
    final info = DeviceInfoPlugin();

    try {
      if (kIsWeb) {
        final w = await info.webBrowserInfo;
        final vendor = (w.vendor ?? 'unknown').toString();
        final userAgent = (w.userAgent ?? 'unknown').toString();
        return 'web:$vendor:$userAgent';
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final a = await info.androidInfo;
          return 'android:${a.id}:${a.model}:${a.brand}';
        case TargetPlatform.iOS:
          final i = await info.iosInfo;
          return 'ios:${i.identifierForVendor}:${i.model}';
        case TargetPlatform.windows:
          final w = await info.windowsInfo;
          return 'win:${w.deviceId}:${w.computerName}';
        default:
          break;
      }
    } catch (_) {}

    return 'unknown-device';
  }

  /// تسمية منصة/طراز للعرض وتخزينها مع الجهاز الموثوق.
  static Future<String> devicePlatformModelLabel() async {
    final info = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        final w = await info.webBrowserInfo;
        return 'web:${w.browserName.name}';
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final a = await info.androidInfo;
          return 'android:${a.brand} ${a.model}';
        case TargetPlatform.iOS:
          final i = await info.iosInfo;
          return 'ios:${i.model}';
        case TargetPlatform.windows:
          final w = await info.windowsInfo;
          return 'windows:${w.computerName}';
        case TargetPlatform.macOS:
          final m = await info.macOsInfo;
          return 'macos:${m.model}';
        case TargetPlatform.linux:
          final l = await info.linuxInfo;
          return 'linux:${l.name}';
        default:
          break;
      }
    } catch (_) {}
    return defaultTargetPlatform.name;
  }

  static Future<void> _logSecurity({
    required String username,
    required String action,
    required bool success,
    String? details,
  }) async {
    // ✅ لا ترسل null لأي باراميتر
    final u = username.trim().isEmpty ? 'guest' : username.trim();
    final d = (details ?? '').toString();

    try {
      await _sb.rpc(
        'log_security_event',
        params: {
          'p_username': u,
          'p_action': action,
          'p_success': success,
          'p_details': d,
        },
      );
    } catch (_) {
      // تجاهل الأخطاء حتى لا تعلق الواجهات
    }
  }

  /* ============================================================
   * Account status
   * ============================================================ */

  /// RPC: get_status_by_username
  static Future<String?> getAccountStatus(String username) async {
    final u = digitsOnly(normalizeAsciiDigits(username.trim()));
    if (!_isValidLoginKey(u)) return null;

    try {
      final res = await _sb.rpc(
        'get_login_account_status',
        params: {'p_digits': u},
      );
      final s = res?.toString().trim();
      if (s != null && s.isNotEmpty && s != 'null') return s;
    } catch (_) {}

    try {
      final res = await _sb.rpc(
        'get_status_by_username',
        params: {'p_username': u},
      );
      return res?.toString();
    } catch (_) {
      return null;
    }
  }

  static bool _isLockedStatus(String? status) {
    return status == 'locked' ||
        status == 'disabled' ||
        status == 'suspended' ||
        status == 'banned';
  }

  /* ============================================================
   * Email by username
   * ============================================================ */

  static Future<String?> getEmailByUsername(String username) async {
    final u = digitsOnly(normalizeAsciiDigits(username.trim()));
    if (!_isValidLoginKey(u)) return null;

    try {
      final res = await _sb.rpc(
        'get_login_email',
        params: {'p_digits': u},
      );
      final email = res?.toString().trim();
      if (email != null && email.isNotEmpty && email != 'null') return email;
    } catch (_) {}

    try {
      final res = await _sb.rpc(
        'get_email_by_national_id',
        params: {'p_national_id': u},
      );
      final email = res?.toString().trim();
      if (email == null || email.isEmpty || email == 'null') return null;
      return email;
    } catch (_) {
      return null;
    }
  }

  /* ============================================================
   * OTP  (✅ UNIFIED: in-app)
   * ============================================================ */

  /// ✅ RPC: request_inapp_otp(p_username)
  /// تحقق من رمز OTP داخل التطبيق (نفس منطق [VerifyScreen]).
  static Future<bool> verifyInAppOtp({
    required String usernameDigits,
    required String code,
  }) async {
    final u = digitsOnly(normalizeAsciiDigits(usernameDigits.trim()));
    if (!_isValidLoginKey(u)) return false;
    final canonical = await securityUsernameForDeviceFlow(u);
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return false;
    try {
      final v = await _sb.rpc(
        'verify_inapp_otp',
        params: {'p_username': canonical, 'p_code': digits},
      );
      return (v is bool) ? v : (v?.toString() == 'true');
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestOtp(String username) async {
    final u = digitsOnly(normalizeAsciiDigits(username.trim()));
    if (!_isValidLoginKey(u)) return false;

    final canonical = await securityUsernameForDeviceFlow(u);

    try {
      await _sb.rpc(
        'request_inapp_otp',
        params: {'p_username': canonical},
      );
      await _logSecurity(
        username: canonical,
        action: 'otp_requested',
        success: true,
        details: '',
      );
      return true;
    } catch (e) {
      await _logSecurity(
        username: canonical,
        action: 'otp_requested',
        success: false,
        details: e.toString(),
      );
      return false;
    }
  }

  /* ============================================================
   * Device trust
   * ============================================================ */

  static Future<bool> isDeviceKnown(String username) async {
    final u = digitsOnly(normalizeAsciiDigits(username.trim()));
    if (!_isValidLoginKey(u)) return false;

    final canonical = await securityUsernameForDeviceFlow(u);
    final deviceId = await _deviceFingerprint();

    try {
      final res = await _sb.rpc(
        'is_device_known',
        params: {
          'p_username': canonical,
          'p_device_id': deviceId,
        },
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> registerDevice(String username) async {
    final u = digitsOnly(normalizeAsciiDigits(username.trim()));
    if (!_isValidLoginKey(u)) return;

    final canonical = await securityUsernameForDeviceFlow(u);
    final deviceId = await _deviceFingerprint();

    try {
      await _sb.rpc(
        'register_device',
        params: {
          'p_username': canonical,
          'p_device_id': deviceId,
        },
      );
      await _logSecurity(
        username: canonical,
        action: 'device_registered',
        success: true,
        details: '',
      );
    } catch (e) {
      await _logSecurity(
        username: canonical,
        action: 'device_registered',
        success: false,
        details: e.toString(),
      );
    }
  }

  /* ============================================================
   * Login (step 1 – before OTP)
   * ============================================================ */

  static Future<LoginResult> login({
    required String username,
    required String password,
    String lang = 'ar',
  }) async {
    final isAr = lang != 'en';
    final u = digitsOnly(normalizeAsciiDigits(username.trim()));

    if (!_isValidLoginKey(u)) {
      return LoginResult(
        ok: false,
        locked: false,
        message: isAr
            ? 'أدخل 10 أرقام: هوية/إقامة، رخصة فال، أو الرقم الوطني الموحّد (700…)'
            : 'Enter 10 digits: ID/Iqama, FAL license, or unified national no. (700…)',
      );
    }

    final status = await getAccountStatus(u);
    if (_isLockedStatus(status)) {
      await _logSecurity(
        username: u,
        action: 'login_blocked',
        success: false,
        details: 'status=$status',
      );
      return LoginResult(
        ok: false,
        locked: true,
        message: isAr
            ? 'الحساب مقفل، استخدم استعادة كلمة المرور'
            : 'Account is locked. Use password recovery.',
      );
    }

    final email = await getEmailByUsername(u);
    if (email == null) {
      return LoginResult(
        ok: false,
        locked: false,
        message: isAr ? 'لا يوجد حساب مرتبط' : 'No account found',
      );
    }

    try {
      await _sb.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      await _logSecurity(
        username: u,
        action: 'login_password_failed',
        success: false,
        details: e.message,
      );
      return LoginResult(
        ok: false,
        locked: false,
        message: isAr ? 'كلمة المرور غير صحيحة' : 'Wrong password',
      );
    }

    await _logSecurity(
      username: u,
      action: 'login_password_ok',
      success: true,
      details: '',
    );

    return const LoginResult(ok: true, locked: false, message: '');
  }

  /* ============================================================
   * Password recovery
   * ============================================================ */

  static Future<LoginResult> sendResetPasswordEmail({
    required String username,
    String lang = 'ar',
    String? redirectTo,
  }) async {
    final isAr = lang != 'en';
    final u = digitsOnly(normalizeAsciiDigits(username.trim()));

    if (!_isValidLoginKey(u)) {
      return LoginResult(
        ok: false,
        locked: false,
        message: isAr
            ? 'المعرّف غير صالح (10 أرقام)'
            : 'Invalid identifier (10 digits)',
      );
    }

    final email = await getEmailByUsername(u);
    if (email == null) {
      return LoginResult(
        ok: false,
        locked: false,
        message: isAr ? 'لا يوجد حساب' : 'No account found',
      );
    }

    try {
      await _sb.auth.resetPasswordForEmail(email, redirectTo: redirectTo);

      await _logSecurity(
        username: u,
        action: 'password_recovery_sent',
        success: true,
        details: '',
      );

      return LoginResult(
        ok: true,
        locked: false,
        message: isAr
            ? 'تم إرسال رابط استعادة كلمة المرور'
            : 'Recovery email sent',
      );
    } catch (e) {
      await _logSecurity(
        username: u,
        action: 'password_recovery_failed',
        success: false,
        details: e.toString(),
      );
      return LoginResult(
        ok: false,
        locked: false,
        message: isAr ? 'فشل الإرسال' : 'Failed to send email',
      );
    }
  }
}
