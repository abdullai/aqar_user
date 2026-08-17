import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_motion_prefs.dart';

/// سياسة حركة خفيفة مركزية — بدون Wave/Flip أو مراقب FPS.
///
/// الاستخدام: [AppMotionPolicy.enabled] + [duration] / [curve].
/// تُحمَّل من prefs عند الإقلاع عبر [bootstrap].
abstract final class AppMotionPolicy {
  static bool _userEnabled = true;

  /// تفضيل المستخدم (إعدادات). يُحترم مع [MediaQuery.disableAnimations].
  static bool get userEnabled => _userEnabled;

  static set userEnabled(bool v) => _userEnabled = v;

  static Future<void> bootstrap() async {
    _userEnabled = await AppMotionPrefs.isEnabled();
  }

  static Future<void> setEnabled(bool value) async {
    _userEnabled = value;
    await AppMotionPrefs.setEnabled(value);
  }

  /// هل تُشغَّل الحركات في هذا السياق؟
  static bool enabledOf(BuildContext context) {
    if (!_userEnabled) return false;
    final mq = MediaQuery.maybeOf(context);
    if (mq != null && mq.disableAnimations) return false;
    return true;
  }

  static Duration get barSlide =>
      _userEnabled ? const Duration(milliseconds: 45) : Duration.zero;

  static Duration get tabSwitch =>
      _userEnabled ? const Duration(milliseconds: 40) : Duration.zero;

  /// تنقّل التبويبات: شبه فوري حتى مع الحركات مفعّلة.
  static Duration durationOf(BuildContext context) {
    if (!enabledOf(context)) return Duration.zero;
    if (kIsWeb) return const Duration(milliseconds: 40);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return const Duration(milliseconds: 55);
      default:
        return const Duration(milliseconds: 45);
    }
  }

  static Curve get curve => Curves.easeOutCubic;

  static Curve get springy => Curves.easeOutBack;
}
