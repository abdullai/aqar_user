// lib/core/security/inactivity_policy.dart
//
// مصدر واحد لسياسة الخمول داخل التطبيق (قبل حوار «استمرار / خروج»).

import 'package:flutter/material.dart';

@immutable
abstract final class InactivityPolicy {
  /// مدة بدون تفاعل قبل إظهار التنبيه.
  static const Duration idleBeforePrompt = Duration(minutes: 3);

  /// عدّ تنازلي بالثواني ثم قفل أو تسجيل خروج إن لم يُجب المستخدم.
  static const Duration promptCountdown = Duration(minutes: 1);

  /// ويب وسطح المكتب: نفس مهلة الخمول ثم نافذة العدّ.
  static const Duration webDesktopAutoLogoutCountdown = Duration(seconds: 60);

  /// ويب/سطح مكتب: ثلاث دقائق بدون تفاعل ثم تظهر نافذة العدّاد.
  static const Duration webDesktopIdleBeforeLock = Duration(minutes: 3);
}
