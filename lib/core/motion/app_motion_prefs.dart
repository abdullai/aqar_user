import 'package:shared_preferences/shared_preferences.dart';

/// تفضيل تشغيل/إيقاف الحركات الخفيفة (مثل إيماءات التنقل والاهتزاز).
abstract final class AppMotionPrefs {
  static const enabledKey = 'app_motion_enabled_v1';

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(enabledKey, value);
  }
}
