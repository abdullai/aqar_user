import 'package:flutter/services.dart';

/// اهتزازات مركزية؛ عطّل من الإعدادات لاحقاً عبر [enabled].
class AppHaptics {
  AppHaptics._();

  static bool enabled = true;

  static void selection() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  static void light() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  static void medium() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }

  static void vibrate() {
    if (!enabled) return;
    HapticFeedback.vibrate();
  }
}
