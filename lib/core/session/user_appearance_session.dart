import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// ثيم ولغة الواجهة: **جهاز** (ضيف / بدون جلسة) + **حساب** (مسجّل) مع خيار مزامنة اللغة والثيم.
///
/// التطبيق الموحّد: تغيير اللغة/الثيم عبر `setAppLang` و `setAppTheme` في `main.dart`؛
/// لون التمييز عبر `loadAppAccentFromPrefs` و `setAppAccentIndex`؛ بعد تبديل جلسة أو ضيف
/// استدعِ `applyNotifiersToMatchStoredSession` أو `syncSessionAppearanceNotifiers` من الجسر.
abstract final class UserAppearanceSession {
  static const String _kSyncLangWithAccount = 'sync_lang_with_account_v1';
  static const String _kSyncThemeWithAccount = 'sync_theme_with_account_v1';

  static String _themeKeyFor(String? uid) =>
      (uid != null && uid.isNotEmpty) ? 'app_theme_$uid' : AppConfig.prefThemeKey;

  static String _langKeyFor(String? uid) =>
      (uid != null && uid.isNotEmpty) ? 'app_lang_$uid' : AppConfig.prefLangKey;

  static Future<bool> readSyncLangWithAccount() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSyncLangWithAccount) ?? true;
  }

  static Future<void> writeSyncLangWithAccount(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSyncLangWithAccount, value);
  }

  static Future<bool> readSyncThemeWithAccount() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kSyncThemeWithAccount) ?? true;
  }

  static Future<void> writeSyncThemeWithAccount(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSyncThemeWithAccount, value);
  }

  /// يطبّق القيم المحفوظة على المنوّعات حسب وجود جلسة وخيار المزامنة.
  static Future<void> applyNotifiersToMatchStoredSession({
    required ValueNotifier<String> langNotifier,
    required ValueNotifier<ThemeMode> themeModeNotifier,
  }) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final p = await SharedPreferences.getInstance();

    final syncTheme = await readSyncThemeWithAccount();
    final themeStr = () {
      if (uid != null && uid.isNotEmpty && syncTheme) {
        return p.getString(_themeKeyFor(uid)) ??
            p.getString(AppConfig.prefThemeKey) ??
            'light';
      }
      return p.getString(AppConfig.prefThemeKey) ?? 'light';
    }();

    final syncLang = await readSyncLangWithAccount();
    final langStr = (uid != null && uid.isNotEmpty && syncLang)
        ? (p.getString(_langKeyFor(uid)) ??
            p.getString(AppConfig.prefLangKey) ??
            'ar')
        : (p.getString(AppConfig.prefLangKey) ?? 'ar');

    themeModeNotifier.value =
        themeStr == 'dark' ? ThemeMode.dark : ThemeMode.light;
    langNotifier.value = langStr == 'en' ? 'en' : 'ar';
  }

  /// حفظ الثيم: الجهاز دائماً؛ وللمسجّل مفتاح الحساب إن كانت مزامنة الثيم مفعّلة.
  static Future<void> persistThemeChoice(String lightOrDark) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final p = await SharedPreferences.getInstance();
    await p.setString(AppConfig.prefThemeKey, lightOrDark);
    if (uid != null &&
        uid.isNotEmpty &&
        await readSyncThemeWithAccount()) {
      await p.setString(_themeKeyFor(uid), lightOrDark);
    }
  }

  /// حفظ اللغة: الجهاز دائماً؛ وللمسجّل مفتاح الحساب إن كانت المزامنة مفعّلة.
  static Future<void> persistLangChoice(String arOrEn) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final p = await SharedPreferences.getInstance();
    await p.setString(AppConfig.prefLangKey, arOrEn);
    if (uid != null &&
        uid.isNotEmpty &&
        await readSyncLangWithAccount()) {
      await p.setString(_langKeyFor(uid), arOrEn);
    }
  }
}
