import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_sound_coordinator.dart';

/// تفضيل صوت التنبيه عند وصول إشعار داخل الجلسة (Realtime → شريط علوي).
abstract final class InAppNotificationSoundPrefs {
  static const String _key = 'in_app_notification_sound_enabled';

  static bool _loaded = false;
  static bool _enabled = true;

  static bool get isEnabled => _loaded ? _enabled : true;

  static Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool(_key) ?? true;
    _loaded = true;
  }

  static Future<void> setEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    _enabled = value;
    await p.setBool(_key, value);
  }
}

/// **الويب:** نغمة من أصول التطبيق عبر [AppSoundCoordinator] (لا يوجد درج إشعارات كالجوال).
/// **غير الويب (جوال/سطح مكتب):** اهتزاز خفيف + صوت نظام قصير — بدون ملفات WAV
/// حتى لا تتعارض مع نغمات قنوات الإشعارات التي يضبطها المستخدم على الجهاز.
void playInAppNotificationChime() {
  if (!InAppNotificationSoundPrefs.isEnabled) return;
  if (kIsWeb) {
    unawaited(
      AppSoundCoordinator.playUiEffect(
        assetPath: 'sounds/in_app_chime.wav',
        volume: 0.74,
      ),
    );
    return;
  }
  unawaited(_nativeInAppBannerFeedback());
}

Future<void> _nativeInAppBannerFeedback() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await HapticFeedback.mediumImpact();
    }
  } catch (_) {}
  try {
    SystemSound.play(SystemSoundType.alert);
  } catch (_) {}
}
