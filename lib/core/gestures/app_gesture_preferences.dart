import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppGesturePreferences {
  AppGesturePreferences._();

  static const swipeBackEnabledKey = 'gesture_swipe_back_enabled_v1';
  static const edgeOnlySwipeBackKey = 'gesture_edge_only_swipe_back_v1';
  static const keyboardBackEnabledKey = 'gesture_keyboard_back_enabled_v1';

  static bool get supportsTouchBack =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get supportsKeyboardBack =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  static bool get shouldShowSettings =>
      supportsTouchBack || supportsKeyboardBack;

  static Future<bool> swipeBackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(swipeBackEnabledKey) ?? true;
  }

  static Future<void> setSwipeBackEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(swipeBackEnabledKey, value);
  }

  static Future<bool> edgeOnlySwipeBack() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(edgeOnlySwipeBackKey) ?? false;
  }

  static Future<void> setEdgeOnlySwipeBack(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(edgeOnlySwipeBackKey, value);
  }

  static Future<bool> keyboardBackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyboardBackEnabledKey) ?? true;
  }

  static Future<void> setKeyboardBackEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyboardBackEnabledKey, value);
  }
}
