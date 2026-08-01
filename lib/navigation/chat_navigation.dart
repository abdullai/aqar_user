import 'package:flutter/material.dart';

import '../screens/chat_page.dart';

/// فتح المحادثة كطبقة منبثقة فوق الشاشة الحالية (لا يستبدل المسار بالكامل).
abstract final class ChatOverlayNavigation {
  static Future<void> openContextualModal(
    BuildContext context, {
    required bool isAr,
    String? conversationId,
    String? propertyId,
    String? reservationId,
    String? counterpartyId,
    String? title,
    ConversationKind? kind,
    String? supportUserId,
    String? marketRequestId,
    String? initialDraftMessage,
  }) {
    final h = MediaQuery.sizeOf(context).height;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return SizedBox(
          height: h * 0.78,
          child: ChatPage(
            isAr: isAr,
            embedInParentDashboardShell: false,
            conversationId: conversationId,
            propertyId: propertyId,
            reservationId: reservationId,
            counterpartyId: counterpartyId,
            title: title,
            kind: kind,
            supportUserId: supportUserId,
            marketRequestId: marketRequestId,
            initialDraftMessage: initialDraftMessage,
          ),
        );
      },
    );
  }
}

/// مدخل واحد لفتح [ChatPage] مع `RouteSettings` موحّدة للتتبّع والدفع العميق.
abstract final class ChatNavigation {
  static const String routeName = '/app_chat';

  static Route<void> materialRoute({
    required bool isAr,
    bool embedInParentDashboardShell = false,
    String? conversationId,
    String? propertyId,
    String? reservationId,
    String? counterpartyId,
    String? title,
    ConversationKind? kind,
    String? supportUserId,
    String? marketRequestId,
    String? initialDraftMessage,
  }) {
    return MaterialPageRoute<void>(
      settings: RouteSettings(
        name: routeName,
        arguments: <String, dynamic>{
          if (conversationId != null && conversationId.isNotEmpty)
            'conversation_id': conversationId,
          if (propertyId != null && propertyId.isNotEmpty) 'property_id': propertyId,
          if (reservationId != null && reservationId.isNotEmpty)
            'reservation_id': reservationId,
          if (counterpartyId != null && counterpartyId.isNotEmpty)
            'counterparty_id': counterpartyId,
          if (kind != null) 'kind': kind.name,
          if (marketRequestId != null && marketRequestId.isNotEmpty)
            'market_request_id': marketRequestId,
        },
      ),
      builder: (_) => ChatPage(
        isAr: isAr,
        embedInParentDashboardShell: embedInParentDashboardShell,
        conversationId: conversationId,
        propertyId: propertyId,
        reservationId: reservationId,
        counterpartyId: counterpartyId,
        title: title,
        kind: kind,
        supportUserId: supportUserId,
        marketRequestId: marketRequestId,
        initialDraftMessage: initialDraftMessage,
      ),
    );
  }

  /// بديل مباشر لـ [Navigator.push] عند الحاجة لنتيجة المسار.
  static Future<void> push(
    BuildContext context, {
    required bool isAr,
    bool embedInParentDashboardShell = false,
    String? conversationId,
    String? propertyId,
    String? reservationId,
    String? counterpartyId,
    String? title,
    ConversationKind? kind,
    String? supportUserId,
    String? marketRequestId,
    String? initialDraftMessage,
  }) {
    return Navigator.of(context).push(
      materialRoute(
        isAr: isAr,
        embedInParentDashboardShell: embedInParentDashboardShell,
        conversationId: conversationId,
        propertyId: propertyId,
        reservationId: reservationId,
        counterpartyId: counterpartyId,
        title: title,
        kind: kind,
        supportUserId: supportUserId,
        marketRequestId: marketRequestId,
        initialDraftMessage: initialDraftMessage,
      ),
    );
  }
}
