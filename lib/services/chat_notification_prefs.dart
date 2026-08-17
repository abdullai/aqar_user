import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات **إشعار الدفع/الدرج** للدردشة (FCM / إشعار محلي في الخلفية على الجوال).
/// على **الويب** التنبيهات أثناء الجلسة تمر غالباً عبر الواجهة الداخلية وليس درج الجوال.
/// منفصلة عن [ChatMessageSoundPrefs] (تغذية داخل شاشة المحادثة) وعن [AppSoundCoordinator] (أصول WAV على المتصفح فقط).
abstract final class ChatNotificationPrefs {
  static const String _key = 'chat_notifications_enabled';

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }
}
