import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart';

import '../platform/web_pointer_unblock.dart';
import 'web_bootstrap_diag.dart';

/// على الويب: فك حظر اللمس من طبقات semantics العالقة فقط.
///
/// **لا** تُغلق حوارات [showDialog] هنا — كان الاسترداد الدوري يستدعي
/// [RootOverlayGuard] فيُغلق حوار OTP/كلمة المرور كل ثانيتين (يظهر ويختفي).
abstract final class WebInteractionRecovery {
  static Timer? _recoveryTimer;
  static Timer? _keepaliveTimer;
  static DateTime? _lastDomUnblockAt;

  /// فك حظر DOM فقط — آمن أثناء حوارات الأجهزة/OTP.
  static void unblockPointersOnly() {
    if (!kIsWeb) return;
    final now = DateTime.now();
    if (_lastDomUnblockAt != null &&
        now.difference(_lastDomUnblockAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastDomUnblockAt = now;
    webUnblockPointerDom();
  }

  /// توافق مع الاستدعاءات القديمة — **بدون** إغلاق حوارات.
  static void dismissStuckOverlaysOnce() => unblockPointersOnly();

  /// مايو: لا جدولة استرداد عند الدخول (كانت تُبطئ/تُجمّد أول إطارات اللوحة).
  static void scheduleDashboardRecovery({
    Duration forDuration = const Duration(seconds: 12),
  }) {
    if (!kIsWeb) return;
    // no-op — فك الحظر يدوياً عبر [unblockPointersOnly] عند الحاجة فقط.
  }

  static void cancelScheduledRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }
}
