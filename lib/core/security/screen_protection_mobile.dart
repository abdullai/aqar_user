import 'package:flutter/foundation.dart';
import 'package:no_screenshot/no_screenshot.dart';

class ScreenProtection {
  static final NoScreenshot _ns = NoScreenshot.instance;

  static Future<void> enable() async {
    if (kIsWeb) return;

    try {
      await _ns.screenshotOff();
    } catch (_) {}
  }

  static Future<void> disable() async {
    if (kIsWeb) return;

    try {
      await _ns.screenshotOn();
    } catch (_) {}
  }
}