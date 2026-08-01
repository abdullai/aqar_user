import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'app_accent.dart';

/// Set from [main] after notifiers exist — avoids importing `main.dart` from screens.
Future<void> Function()? reloadAppAppearanceFromStoredPrefs;

/// يزامن لغة/ثيم الـ notifiers مع الجلسة الحالية (ضيف بدون uid أو مسجّل + مزامنة لغة).
/// أخف من [reloadAppAppearanceFromStoredPrefs] (لا يعيد مقياس النص ولا لون التمييز).
Future<void> Function()? syncSessionAppearanceNotifiers;

/// After logout on a shared device, reset theme / text scale / accent so the next
/// account does not inherit the previous user’s display preferences.
Future<void> resetStoredAppearanceForNextSignIn() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(AppConfig.prefThemeKey, 'light');
  await prefs.setDouble(AppConfig.prefTextScaleKey, 1.0);
  await prefs.setInt(kPrefAccentId, 0);
  // لا تمسح مفاتيح accent لكل مستخدم — تبقى محفوظة لكل حساب.
  accentSeedNotifier.value = AppAccent.seeds[0];
  await reloadAppAppearanceFromStoredPrefs?.call();
}
