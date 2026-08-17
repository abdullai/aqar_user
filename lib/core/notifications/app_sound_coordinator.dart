import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// منسّق أصول WAV داخل التطبيق (مشغّل واحد + تسلسل) عبر `audioplayers` — ويب وجوال وسطح مكتب
/// حيث يدعم المشغّل التشغيل المباشر من `AssetSource`.
///
/// **منفصل عن:** FCM في الخلفية، و`flutter_local_notifications` بصوت القناة على الجوال.
class AppSoundCoordinator {
  AppSoundCoordinator._();

  static AudioPlayer? _player;
  static Future<void> _chain = Future<void>.value();

  /// تشغيل ملف من `assets/` (المسار كما في [AssetSource]، مثل `sounds/x.wav`).
  static Future<void> playUiEffect({
    required String assetPath,
    double volume = 0.62,
  }) {
    final next = _chain.then((_) => _playNow(assetPath: assetPath, volume: volume));
    _chain = next.catchError((_, __) {});
    return next;
  }

  static Future<void> _playNow({
    required String assetPath,
    required double volume,
  }) async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.setVolume(volume.clamp(0.0, 1.0));
      await _player!.play(AssetSource(assetPath));
    } catch (_) {
      try {
        SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }
}
