import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../../services/session_manager.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_signed_out_navigation_guard.dart';
import '../platform/web_browser_lifecycle.dart';
import '../session/app_session.dart';

/// مغادرة اللوحة/الضيف — توجيه حسب طريقة الدخول دون حلقة signOut على الويب.
abstract final class AppExitNavigation {
  /// ضيف: شاشة اختيار الدخول (مستخدم / ضيف).
  static Future<void> leaveGuestToEntryChoice(BuildContext context) async {
    AuthSignedOutNavigationGuard.enter();
    try {
      await SessionManager.clearLocalAuthSessionForPublicReads(
        Supabase.instance.client,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConfig.prefGuestModeKey);
      await prefs.remove(AppConfig.prefEntryModeKey);
      if (context.mounted) {
        await context.read<AppSession>().reloadFromPrefs();
      }
      if (!context.mounted) return;
      if (kIsWeb) suppressWebBeforeUnloadBriefly();
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        '/entryChoice',
        (route) => false,
      );
    } finally {
      AuthSignedOutNavigationGuard.scheduleLeave();
    }
  }

  /// مستخدم مسجّل: شاشة تسجيل الدخول (الخروج الفعلي عبر [SafeSignOutService]).
  static Future<void> leaveLoggedInToLogin(BuildContext context) async {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }
}
