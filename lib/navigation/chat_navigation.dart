import 'package:flutter/material.dart';

import '../screens/chat_page.dart';

/// فتح أي محادثة كطبقة ملء الشاشة فوق كل الواجهة (مثل واتساب) مع زر إغلاق.
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
    return ChatNavigation.push(
      context,
      isAr: isAr,
      conversationId: conversationId,
      propertyId: propertyId,
      reservationId: reservationId,
      counterpartyId: counterpartyId,
      title: title,
      kind: kind,
      supportUserId: supportUserId,
      marketRequestId: marketRequestId,
      initialDraftMessage: initialDraftMessage,
    );
  }
}

/// مدخل واحد لفتح [ChatPage] فوق الجذر — ملء الشاشة دائماً.
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
      fullscreenDialog: true,
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
        // الطبقة الجذرية لا تُضمَّن داخل هيكل اللوحة — شريط دردشة كامل + X.
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
  }

  /// يفتح فوق [rootNavigator] ليغطي الشريط السفلي والتبويبات والهب بالكامل.
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
    return Navigator.of(context, rootNavigator: true).push<void>(
      materialRoute(
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
  }
}
