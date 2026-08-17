import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_sound_coordinator.dart';

/// صوت تنبيه عند وصول رسالة من الطرف الآخر أثناء فتح شاشة المحادثة.
///
/// يُشغَّل أصل `assets/sounds/chat_incoming.wav` عبر [AppSoundCoordinator] على كل المنصات
/// التي يدعمها `audioplayers`، مع اهتزاز خفيف على الجوال عند التفعيل.
abstract final class ChatMessageSoundPrefs {
  static const String _key = 'chat_message_sound_enabled';

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

void playChatIncomingMessageSound() {
  if (!ChatMessageSoundPrefs.isEnabled) return;
  unawaited(
    AppSoundCoordinator.playUiEffect(
      assetPath: 'sounds/chat_incoming.wav',
      volume: kIsWeb ? 0.60 : 0.52,
    ),
  );
  unawaited(_companionHapticsFallback());
}

/// اهتزاز خفيف على الجوال؛ لا يستبدل الصوت بل يكمّله.
Future<void> _companionHapticsFallback() async {
  try {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await HapticFeedback.lightImpact();
    }
  } catch (_) {}
}
