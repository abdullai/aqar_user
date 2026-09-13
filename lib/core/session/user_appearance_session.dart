import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// لغة ومظهر محليان على الجهاز — بلا شبكة.
///
/// - **شاشة الدخول** (لا جلسة): مفاتيح `login_chrome_*`.
/// - **حساب مسجّل**: `app_theme_$uid` / `app_lang_$uid` — لا تُمسَح عند الخروج.
/// - تغيير الثيم/اللغة من شاشة الدخول يُعلَّم `dirty` ويُنسَخ إلى الحساب عند الدخول.
abstract final class UserAppearanceSession {
  static const String loginThemeKey = 'login_chrome_theme_v1';
  static const String loginLangKey = 'login_chrome_lang_v1';
  static const String loginChromeDirtyKey = 'login_chrome_dirty_v1';

  static String themeKeyFor(String uid) => 'app_theme_$uid';
  static String langKeyFor(String uid) => 'app_lang_$uid';

  static String? _uidOrNull() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static ThemeMode parseMode(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.system;
    }
  }

  static String persistToken(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// المظهر الظاهر فعلياً: عند [ThemeMode.system] يتبع سطوع/وضع الجهاز فوراً.
  static bool resolvesLight(
    ThemeMode mode, [
    Brightness? platformBrightness,
  ]) {
    final platform = platformBrightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    switch (mode) {
      case ThemeMode.light:
        return true;
      case ThemeMode.dark:
        return false;
      case ThemeMode.system:
        return platform == Brightness.light;
    }
  }

  static ThemeMode _modeOf(String? raw) => parseMode(raw);

  static String _langOf(String? raw) =>
      (raw ?? '').trim() == 'en' ? 'en' : 'ar';

  /// يطبّق القيم المحفوظة: حساب إن وُجدت جلسة، وإلا شاشة الدخول.
  static Future<void> applyNotifiersToMatchStoredSession({
    required ValueNotifier<String> langNotifier,
    required ValueNotifier<ThemeMode> themeModeNotifier,
  }) async {
    final uid = _uidOrNull();
    final p = await SharedPreferences.getInstance();

    if (uid != null && uid.isNotEmpty) {
      final themeStr = p.getString(themeKeyFor(uid)) ??
          p.getString(loginThemeKey) ??
          p.getString(AppConfig.prefThemeKey) ??
          'system';
      final langStr = p.getString(langKeyFor(uid)) ??
          p.getString(loginLangKey) ??
          p.getString(AppConfig.prefLangKey) ??
          'ar';
      themeModeNotifier.value = _modeOf(themeStr);
      langNotifier.value = _langOf(langStr);
      return;
    }

    final themeStr = p.getString(loginThemeKey) ??
        p.getString(AppConfig.prefThemeKey) ??
        'system';
    final langStr = p.getString(loginLangKey) ??
        p.getString(AppConfig.prefLangKey) ??
        'ar';
    themeModeNotifier.value = _modeOf(themeStr);
    langNotifier.value = _langOf(langStr);
  }

  /// حفظ الثيم: للحساب إن وُجدت جلسة، وإلا لشاشة الدخول (+ علامة نسخ عند الدخول).
  static Future<void> persistThemeChoice(String lightOrDarkOrSystem) async {
    final v = persistToken(parseMode(lightOrDarkOrSystem));
    final uid = _uidOrNull();
    final p = await SharedPreferences.getInstance();
    if (uid != null && uid.isNotEmpty) {
      await p.setString(themeKeyFor(uid), v);
      return;
    }
    await p.setString(loginThemeKey, v);
    await p.setString(AppConfig.prefThemeKey, v);
    await p.setBool(loginChromeDirtyKey, true);
  }

  static Future<void> persistLangChoice(String arOrEn) async {
    final v = arOrEn == 'en' ? 'en' : 'ar';
    final uid = _uidOrNull();
    final p = await SharedPreferences.getInstance();
    if (uid != null && uid.isNotEmpty) {
      await p.setString(langKeyFor(uid), v);
      return;
    }
    await p.setString(loginLangKey, v);
    await p.setString(AppConfig.prefLangKey, v);
    await p.setBool(loginChromeDirtyKey, true);
  }

  /// إن غيّر الثيم/اللغة من شاشة الدخول ثم دخل: تُنسَخ إلى حسابه دون مسح لون التمييز.
  static Future<void> absorbLoginChromeIntoUser(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool(loginChromeDirtyKey) != true) return;
    final t = p.getString(loginThemeKey);
    final l = p.getString(loginLangKey);
    if (t == 'dark' || t == 'light' || t == 'system') {
      await p.setString(themeKeyFor(u), t!);
    }
    if (l == 'en' || l == 'ar') {
      await p.setString(langKeyFor(u), l!);
    }
    await p.setBool(loginChromeDirtyKey, false);
  }
}
