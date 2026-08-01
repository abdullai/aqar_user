import 'dart:async';

import 'app_sound_coordinator.dart';
import 'in_app_notification_sound.dart';

/// أصوات موحّدة لتبويبات «صفحتي / إدارتي» وسير العقود (أصول WAV الحالية).
enum HubWorkflowSoundKind {
  /// عرض جديد أو رسالة عرض واردة.
  newOffer,

  /// قبول عرض، إنشاء عقد، توقيع ناجح.
  contractSuccess,

  /// تصريح، مهلة 72 ساعة، إلغاء، تحذير.
  permitWarning,
}

void playHubWorkflowSound(HubWorkflowSoundKind kind) {
  if (!InAppNotificationSoundPrefs.isEnabled) return;
  switch (kind) {
    case HubWorkflowSoundKind.newOffer:
      unawaited(
        AppSoundCoordinator.playUiEffect(
          assetPath: 'sounds/chat_incoming.wav',
          volume: 0.58,
        ),
      );
      break;
    case HubWorkflowSoundKind.contractSuccess:
      unawaited(
        AppSoundCoordinator.playUiEffect(
          assetPath: 'sounds/in_app_chime.wav',
          volume: 0.68,
        ),
      );
      break;
    case HubWorkflowSoundKind.permitWarning:
      unawaited(
        AppSoundCoordinator.playUiEffect(
          assetPath: 'sounds/otp_chime.wav',
          volume: 0.52,
        ),
      );
      break;
  }
}
