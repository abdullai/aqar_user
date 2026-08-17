import 'hub_workflow_sound.dart';
import 'in_app_notification_sound.dart';
import 'in_app_notification_catalog.dart';

/// نغمات موحّدة لإشعارات سير العمل — تُوجَّه إلى [playHubWorkflowSound] حيث ينطبق.
void playWorkflowToastSound(String notificationType) {
  if (!InAppNotificationSoundPrefs.isEnabled) return;
  final t = notificationType.toLowerCase().trim();
  bool eq(String constant) => t == constant.toLowerCase();

  if (t.contains('apology') || eq(InAppNotifTypes.offerApologyFromOwner)) {
    playHubWorkflowSound(HubWorkflowSoundKind.permitWarning);
    return;
  }

  if (eq(InAppNotifTypes.permitSubmitted) ||
      eq(InAppNotifTypes.permitPackageSubmitted) ||
      t.contains('permit_deadline') ||
      t.contains('deadline') ||
      t.contains('expir') ||
      t.contains('void') ||
      t.contains('cancel') ||
      t.contains('permit_auto_terminated')) {
    playHubWorkflowSound(HubWorkflowSoundKind.permitWarning);
    return;
  }

  if (eq(InAppNotifTypes.contractCreated) || t.contains('contract_created')) {
    playHubWorkflowSound(HubWorkflowSoundKind.newOffer);
    return;
  }

  if (eq(InAppNotifTypes.contractPendingSignature) ||
      t.contains('contract_pending')) {
    playHubWorkflowSound(HubWorkflowSoundKind.newOffer);
    return;
  }

  if (t.contains('offer') ||
      t.contains('received') ||
      (t.contains('submitted') && !t.contains('permit'))) {
    playHubWorkflowSound(HubWorkflowSoundKind.newOffer);
    return;
  }

  if (t.contains('signed') ||
      t.contains('publish') ||
      t.contains('success') ||
      t.contains('accepted') ||
      t.contains('contract_signed')) {
    playHubWorkflowSound(HubWorkflowSoundKind.contractSuccess);
    return;
  }

  playInAppNotificationChime();
}
