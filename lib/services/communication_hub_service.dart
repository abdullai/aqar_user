import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_inbox_service.dart';
import 'marketing_flow_service.dart';
import 'notification_service.dart';

/// عمليات موحّدة لمركز الإشعارات والمحادثات.
abstract final class CommunicationHubService {
  static Future<void> _clearOsBadge() async {
    try {
      await NotificationService.clearOsApplicationIconBadge();
    } catch (_) {}
  }

  /// قراءة كل إشعارات الصندوق (بدون محادثات).
  static Future<void> markAllNotificationsRead(SupabaseClient sb) async {
    await MarketingFlowService(sb).markAllInAppNotificationsRead();
    await _clearOsBadge();
  }

  /// قراءة الإشعارات المحدّدة فوراً.
  static Future<void> markNotificationsReadBulk(
    SupabaseClient sb,
    Iterable<String> ids,
  ) async {
    final flow = MarketingFlowService(sb);
    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      try {
        await flow.markNotificationRead(id);
      } catch (_) {}
    }
    await _clearOsBadge();
  }

  /// قراءة كل المحادثات (بدون إشعارات العمليات).
  static Future<void> markAllChatsRead(SupabaseClient sb) async {
    await ChatInboxService(sb).markAllConversationsRead();
    await _clearOsBadge();
  }

  /// قراءة الكل: إشعارات + دردشات + شارة النظام — فوري.
  static Future<void> markEverythingRead(SupabaseClient sb) async {
    await Future.wait([
      MarketingFlowService(sb).markAllInAppNotificationsRead(),
      ChatInboxService(sb).markAllConversationsRead(),
    ]);
    await _clearOsBadge();
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
