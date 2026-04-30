import 'dart:async';

import 'in_app_notification_sound.dart';
import 'app_sound_coordinator.dart';

/// نغمات موحّدة لإشعارات سير العمل (نفس أصول المشروع الحالية — بدون ملفات جديدة).
void playWorkflowToastSound(String notificationType) {
  if (!InAppNotificationSoundPrefs.isEnabled) return;
  final t = notificationType.toLowerCase();

  if (t.contains('apology')) {
    unawaited(
      AppSoundCoordinator.playUiEffect(
        assetPath: 'sounds/otp_chime.wav',
        volume: 0.42,
      ),
    );
    return;
  }

  if (t.contains('permit_deadline') ||
      t.contains('deadline') ||
      t.contains('expir') ||
      t.contains('void') ||
      t.contains('cancel')) {
    unawaited(
      AppSoundCoordinator.playUiEffect(
        assetPath: 'sounds/otp_chime.wav',
        volume: 0.48,
      ),
    );
    return;
  }

  if (t.contains('offer') ||
      t.contains('received') ||
      t.contains('submitted')) {
    unawaited(
      AppSoundCoordinator.playUiEffect(
        assetPath: 'sounds/chat_incoming.wav',
        volume: 0.58,
      ),
    );
    return;
  }

  if (t.contains('signed') ||
      t.contains('publish') ||
      t.contains('success') ||
      t.contains('accepted')) {
    unawaited(
      AppSoundCoordinator.playUiEffect(
        assetPath: 'sounds/in_app_chime.wav',
        volume: 0.68,
      ),
    );
    return;
  }

  playInAppNotificationChime();
}
