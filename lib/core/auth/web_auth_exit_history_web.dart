// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// بعد تسجيل الخروج: استبدال عنوان المتصفح حتى لا يعيد زر الرجوع لوحة التحكم.
abstract final class WebAuthExitHistory {
  static void replaceLoginUrl() {
    try {
      final loc = html.window.location;
      final next = '${loc.pathname}${loc.search}#/login';
      html.window.history.replaceState(null, '', next);
    } catch (_) {}
  }
}
