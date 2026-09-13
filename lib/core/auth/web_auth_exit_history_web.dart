// ignore_for_file: avoid_web_libraries_in_flutter

import '../navigation/web_in_app_history.dart';

/// بعد تسجيل الخروج: استبدال عنوان المتصفح حتى لا يعيد زر الرجوع/التقدّم لوحة التحكم.
abstract final class WebAuthExitHistory {
  static void replaceLoginUrl() {
    webInAppHistorySealAuth();
  }
}
