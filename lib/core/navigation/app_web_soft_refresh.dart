/// تحديث «ناعم» للصفحة الحالية على الويب (بدون `location.reload`).
abstract final class AppWebSoftRefresh {
  static Future<void> Function()? _handler;

  static void register(Future<void> Function() handler) {
    _handler = handler;
  }

  static void unregister() {
    _handler = null;
  }

  static Future<void> invoke() async {
    final h = _handler;
    if (h != null) {
      await h();
      return;
    }
  }

  static bool get hasHandler => _handler != null;
}
