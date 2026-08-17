import 'package:flutter/foundation.dart';

/// ويب: تحديث [StartRouter] الحالي بعد OTP/ضيف دون `pushNamedAndRemoveUntil('/')`
/// — إعادة بناء المكدس كانت تُجمّد Chrome/Edge رغم أن الإقلاع العادي عند `/` يعمل.
abstract final class StartRouterController {
  static Future<void> Function()? _refresh;

  static void register(Future<void> Function() refresh) {
    if (!kIsWeb) return;
    _refresh = refresh;
  }

  static void unregister(Future<void> Function() refresh) {
    if (_refresh == refresh) _refresh = null;
  }

  /// يُحدّث اللوحة داخل [StartRouter] الموجود. يُرجع false إن لم يُسجَّل (fallback للتنقل).
  static Future<bool> refreshInPlaceIfRegistered() async {
    if (!kIsWeb) return false;
    final fn = _refresh;
    if (fn == null) return false;
    await fn();
    return true;
  }
}
