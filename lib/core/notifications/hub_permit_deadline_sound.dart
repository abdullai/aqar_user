import 'hub_workflow_sound.dart';

/// تنبيه صوتي مرة واحدة لكل سياق عند دخول نافذة «6 ساعات أو أقل» قبل انتهاء مهلة التصريح.
abstract final class HubPermitDeadlineSoundCoordinator {
  static final Set<String> _sixHourWarned = <String>{};

  static void resetForTests() {
    _sixHourWarned.clear();
  }

  /// [contextId] يُفضَّل `request_id` أو `contract_id` ثابت.
  static void maybePlaySixHourWarning({
    required String contextId,
    required DateTime? deadline,
  }) {
    final id = contextId.trim();
    if (id.isEmpty || deadline == null) return;
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) return;
    if (left.inHours > 6) return;
    if (_sixHourWarned.contains(id)) return;
    if (_sixHourWarned.length > 400) {
      _sixHourWarned.clear();
    }
    _sixHourWarned.add(id);
    playHubWorkflowSound(HubWorkflowSoundKind.permitWarning);
  }
}
