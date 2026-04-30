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

  /// ويب وسطح المكتب: عدّاد أقصر ثم تسجيل خروج تلقائي (مع طبقة ضبابية).
  static const Duration webDesktopAutoLogoutCountdown = Duration(seconds: 30);

  /// ويب/سطح مكتب: مدة خمول قبل تنبيه القفل (15 دقيقة).
  static const Duration webDesktopIdleBeforeLock = Duration(minutes: 15);
}
