import 'app_accent.dart';

/// Set from [main] after notifiers exist — avoids importing `main.dart` from screens.
Future<void> Function()? reloadAppAppearanceFromStoredPrefs;

/// يزامن لغة/ثيم الـ notifiers مع الجلسة الحالية (شاشة دخول أو حساب).
Future<void> Function()? syncSessionAppearanceNotifiers;

/// بعد الخروج: أعد شاشة الدخول لمظهر الكروم فقط — لا تمسح مفاتيح الحساب
/// (ثيم/لغة/لون تبقى لكل uid على الجهاز).
Future<void> resetStoredAppearanceForNextSignIn() async {
  await loadAppAccentFromPrefs(userId: null);
  await reloadAppAppearanceFromStoredPrefs?.call();
}
