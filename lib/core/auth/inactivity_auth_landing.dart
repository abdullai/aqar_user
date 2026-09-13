/// هبوط آمن بعد مهلة الخمول — يمنع إعادة بناء شاشة الدخول وظهورها «من البداية» مراراً.
abstract final class InactivityAuthLanding {
  static String preferredRoute = '/login';
  static bool suppressEnterMotion = false;
  static DateTime? _holdUntil;

  static void begin({required String route}) {
    preferredRoute = route;
    suppressEnterMotion = true;
    _holdUntil = DateTime.now().add(const Duration(seconds: 8));
  }

  static bool get isActive {
    final until = _holdUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      suppressEnterMotion = false;
      return false;
    }
    return true;
  }

  static void release() {
    _holdUntil = null;
    suppressEnterMotion = false;
  }
}
