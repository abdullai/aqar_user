import 'dart:async';

/// يمنع [MyApp] من استدعاء [_safeNavTo] إلى `/` عند `AuthChangeEvent.signedOut`
/// عندما يكون تسجيل الخروج صادراً من الشاشة نفسها وتُنفَّذ [pushNamedAndRemoveUntil] إلى `/login`
/// (تعارض مسارين يسبب تجمّداً أو سلوك كاش غريب على بعض المنصات).
abstract final class AuthSignedOutNavigationGuard {
  static int _depth = 0;
  static Timer? _releaseTimer;

  static void enter() {
    _releaseTimer?.cancel();
    _depth++;
  }

  /// يُستدعى بعد انتهاء مسار الخروج والتنقل؛ يؤخر الإفراج قليلاً حتى تنتهي callbacks المجدولة.
  static void scheduleLeave({Duration delay = const Duration(milliseconds: 320)}) {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(delay, () {
      _releaseTimer = null;
      if (_depth > 0) _depth--;
    });
  }

  static bool get suppressRootRedirectOnSignedOut => _depth > 0;
}
