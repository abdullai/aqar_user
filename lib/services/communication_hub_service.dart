import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_inbox_service.dart';
import 'marketing_flow_service.dart';
import 'notification_service.dart';

/// عمليات موحّدة لمركز الإشعارات والمحادثات.
abstract final class CommunicationHubService {
  /// قراءة الكل: إشعارات + دردشات + شارة النظام — فوري.
  static Future<void> markEverythingRead(SupabaseClient sb) async {
    final inbox = ChatInboxService(sb);
    final flow = MarketingFlowService(sb);
    await Future.wait([
      flow.markAllInAppNotificationsRead(),
      inbox.markAllConversationsRead(),
    ]);
    try {
      await NotificationService.clearOsApplicationIconBadge();
    } catch (_) {}
  }

  /// حذف جماعي للإشعارات مع تنظيف فوري للواجهة.
  static Future<void> deleteNotificationsBulk(
    SupabaseClient sb,
    Iterable<String> ids,
  ) async {
    final flow = MarketingFlowService(sb);
    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      try {
        await flow.deleteInAppNotification(id);
      } catch (_) {}
    }
  }

  /// أرشفة جماعية للإشعارات.
  static Future<void> archiveNotificationsBulk(
    SupabaseClient sb,
    Iterable<String> ids,
  ) async {
    final flow = MarketingFlowService(sb);
    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      try {
        await flow.archiveInAppNotification(id);
      } catch (_) {}
    }
  }
}
