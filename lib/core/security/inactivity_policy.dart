// lib/core/security/inactivity_policy.dart
//
// مصدر واحد لسياسة الخمول داخل التطبيق (قبل حوار «استمرار / خروج»).

import 'package:flutter/material.dart';

@immutable
abstract final class InactivityPolicy {
  /// مدة بدون تفاعل قبل إظهار التنبيه.
  static const Duration idleBeforePrompt = Duration(minutes: 5);

  /// عدّ تنازلي بالثواني ثم قفل أو تسجيل خروج إن لم يُجب المستخدم.
  static const Duration promptCountdown = Duration(minutes: 1);

  /// ويب وسطح المكتب: عدّاد أوضح قبل الخروج التلقائي.
  static const Duration webDesktopAutoLogoutCountdown = Duration(seconds: 60);

  /// ويب/سطح مكتب: مدة خمول قبل تنبيه القفل (أقصر حتى تظهر النافذة فعلياً).
  static const Duration webDesktopIdleBeforeLock = Duration(minutes: 10);
}
