import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/fast_login_service.dart';
import '../../services/session_tracking_service.dart';

/// بعد فتح الجلسة: ثقة الجهاز + تتبع الدخول. لا يعيق الانتقال للوحة.
abstract final class PostLoginSecurityGuard {
  static Future<void> run({
    required String uid,
    required String usernameNationalId,
    String? displayName,
    required String loginMethod,
    required bool isAr,
    String? authEntryRoute,
  }) async {
    try {
      await FastLoginService.rememberSuccessfulAuth(
        loginMethod: loginMethod,
        entryRoute: authEntryRoute,
      );
    } catch (_) {}
    try {
      await FastLoginService.saveUserContext(
        uid: uid,
        usernameNationalId: usernameNationalId,
        displayName: displayName,
      );
    } catch (_) {}
    try {
      await FastLoginService.markTrustedInstall(uid: uid);
    } catch (_) {}
    try {
      await SessionTrackingService.recordLoginStart(
        Supabase.instance.client,
        loginMethod: loginMethod,
      );
    } catch (_) {}
  }
}
