// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/notifications/in_app_notification_catalog.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../core/workflow/listing_workflow.dart';
import '../navigation/chat_navigation.dart';
import '../routes.dart';
import '../screens/subscriptions/subscriptions_root_screen.dart';
import 'in_app_notification_hub.dart';
import 'marketing_flow_service.dart';

/// توجيه موحّد عالمي من صف `in_app_notifications` — أي شاشة في التطبيق تستخدم [open] فقط.
class InAppNotificationRouter {
  InAppNotificationRouter._();

  /// مسارات الجذر (مع [AppOrphanRouteChrome] في [main.dart]) — لا تُفتح داخل [Navigator] الداخلي للوحة.
  static Future<T?> _pushRootNamed<T extends Object?>(
    BuildContext context,
    String name, {
    Object? arguments,
  }) {
    if (!context.mounted) return Future<T?>.value(null);
    return Navigator.of(context, rootNavigator: true).pushNamed<T>(
      name,
      arguments: arguments,
    );
  }

  static Map<String, dynamic> _dataMap(Map<String, dynamic> row) {
    return InAppNotificationCatalog.parseDataColumn(row);
  }

  static Future<void> markRead(Map<String, dynamic> row) async {
    final id = (row['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    try {
      await MarketingFlowService(Supabase.instance.client).markNotificationRead(id);
      InAppNotificationHub.onInboxInvalidate?.call();
    } catch (_) {}
  }

  static bool _onUserDashboardRoute(BuildContext context) {
    final name =
        (ModalRoute.of(context)?.settings.name ?? '').trim().toLowerCase();
    return name == '/userdashboard' || name == '/';
  }

  static Future<void> _goDashboard(
    BuildContext context,
    Map<String, dynamic> row,
    String lang,
  ) async {
    final copy = Map<String, dynamic>.from(row);
    if (_onUserDashboardRoute(context)) {
      InAppDashboardDeepLink.pending.value = copy;
      return;
    }
    await Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      PostAuthNavigation.resolveDashboardRoute('/userDashboard'),
      (r) => false,
      arguments: <String, dynamic>{'lang': lang},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      InAppDashboardDeepLink.pending.value = copy;
    });
  }

  /// يفتح الشاشة المناسبة ويضع علامة مقروء عند الحاجة.
  static Future<void> open(
    BuildContext context,
    Map<String, dynamic> row, {
    required String lang,
    bool markAsRead = true,
  }) async {
    if (!context.mounted) return;
    if (markAsRead) {
      await markRead(row);
    }

    final enriched = InAppNotificationCatalog.enrichedRowForNavigation(
      Map<String, dynamic>.from(row),
    );

    final data = _dataMap(enriched);
    final type = (enriched['type'] ?? '').toString();
    final entityType = (enriched['entity_type'] ??
            data['entity_type'] ??
            '')
        .toString();
    final entityId =
        (enriched['entity_id'] ?? data['entity_id'] ?? '').toString().trim();
    final deepRoute =
        (data[WorkflowNotificationKeys.deepRoute] ?? '').toString().trim().toLowerCase();

    final typeLower = type.trim().toLowerCase();
    final isAr = lang.toLowerCase() != 'en';

    final convId =
        (data[InAppDataKeys.conversationId] ?? '').toString().trim();
    final mainTabChat =
        (data['main_tab'] ?? '').toString().trim().toLowerCase() == 'chat';
    final opensChatDeepLink = deepRoute == 'chat' || mainTabChat;

    // محادثات: يمرّر معرفات من data عند توفرها (محادثة مباشرة / عقار / طلب سوق / قناة فريق).
    if (typeLower == InAppNotifTypes.chatMessage ||
        typeLower == 'message' ||
        typeLower == 'chat' ||
        (opensChatDeepLink && convId.isNotEmpty)) {
      if (context.mounted) {
        final cp = (data['counterparty_id'] ??
                data['sender_id'] ??
                data['from_user_id'] ??
                '')
            .toString()
            .trim();
        final propChat = (data[WorkflowNotificationKeys.propertyId] ?? '')
            .toString()
            .trim();
        final mkt =
            (data['market_request_id'] ?? '').toString().trim();
        await ChatNavigation.push(
          context,
          isAr: isAr,
          conversationId: convId.isEmpty ? null : convId,
          counterpartyId: cp.isEmpty ? null : cp,
          propertyId: propChat.isEmpty ? null : propChat,
          marketRequestId: mkt.isEmpty ? null : mkt,
        );
      }
      return;
    }

    // تحقق من رقم الهاتف / OTP — الإعدادات مكان المنطقي لإكمال الخطوة.
    if (typeLower == 'otp' ||
        typeLower == 'verification' ||
        typeLower == 'phone_verification') {
      if (context.mounted) {
        await _pushRootNamed<void>(context, '/settings');
      }
      return;
    }

    // دفع / حجز: لوحة المستخدم (تبويب السلة أو الحجوزات حسب data بعد الإثراء).
    if (typeLower == InAppNotifTypes.reservation ||
        typeLower == 'booking' ||
        typeLower == 'payment') {
      await _goDashboard(context, enriched, lang);
      return;
    }

    if (deepRoute == 'market_request' ||
        typeLower == 'market_request_offer' ||
        typeLower == 'market_request_offer_updated' ||
        typeLower == 'market_request_offer_accepted' ||
        typeLower == 'market_request_offer_rejected' ||
        typeLower == 'market_request_deal_completed') {
      final rid = (data[WorkflowNotificationKeys.requestId] ??
              data['market_request_id'] ??
              entityId)
          .toString()
          .trim();
      if (rid.isNotEmpty) {
        await _goDashboard(context, enriched, lang);
        return;
      }
    }

    // بلاغات إعلان: تفاصيل العقار عبر اللوحة عند توفر المعرف.
    if (typeLower == InAppNotifTypes.listingReported ||
        typeLower == InAppNotifTypes.listingReportEscalated) {
      final propId = (data[WorkflowNotificationKeys.previewPropertyId] ??
              data[WorkflowNotificationKeys.propertyId] ??
              (entityType == InAppEntityTypes.property ? entityId : ''))
          .toString()
          .trim();
      if (propId.isNotEmpty) {
        await _goDashboard(context, enriched, lang);
        return;
      }
    }

    if (deepRoute == InAppDeepRoutes.listingRequestStatus) {
      final rid = (data[WorkflowNotificationKeys.requestId] ?? '').toString().trim();
      if (rid.isNotEmpty) {
        await _pushRootNamed<void>(
          context,
          AppRoutes.listingRequestStatus,
          arguments: <String, dynamic>{'requestId': rid, 'lang': lang},
        );
        return;
      }
    }

    // اعتذار المالك (نوع من SQL) — يضمن فتح الطلب حتى مع اختلاف entity_type القديم.
    if (typeLower == InAppNotifTypes.offerApologyFromOwner) {
      final rid = (data[WorkflowNotificationKeys.requestId] ?? entityId)
          .toString()
          .trim();
      if (rid.isNotEmpty && context.mounted) {
        await _pushRootNamed<void>(
          context,
          AppRoutes.listingRequestStatus,
          arguments: <String, dynamic>{'requestId': rid, 'lang': lang},
        );
        return;
      }
    }

    // قبل التوجيه العام لـ listing_request: عروض المالك تفتح صفحة العروض صراحةً.
    if (deepRoute == InAppDeepRoutes.ownerOffers ||
        type == InAppNotifTypes.offerSubmitted ||
        type == InAppNotifTypes.offerReceived ||
        type == InAppNotifTypes.contractCreated) {
      final rid =
          (data[WorkflowNotificationKeys.requestId] ?? entityId).toString().trim();
      if (rid.isNotEmpty) {
        await _pushRootNamed<void>(
          context,
          AppRoutes.ownerOffers,
          arguments: <String, dynamic>{'requestId': rid, 'lang': lang},
        );
        return;
      }
    }

    if (entityType == InAppEntityTypes.listingRequest && entityId.isNotEmpty) {
      await _pushRootNamed<void>(
        context,
        AppRoutes.listingRequestStatus,
        arguments: <String, dynamic>{'requestId': entityId, 'lang': lang},
      );
      return;
    }

    if (deepRoute == InAppDeepRoutes.submitPermits &&
        (data[WorkflowNotificationKeys.requestId] ?? entityId).toString().trim().isNotEmpty) {
      final rid =
          (data[WorkflowNotificationKeys.requestId] ?? entityId).toString().trim();
      await _pushRootNamed<void>(
        context,
        AppRoutes.submitPermits,
        arguments: <String, dynamic>{'requestId': rid, 'lang': lang},
      );
      return;
    }

    if (deepRoute == InAppDeepRoutes.submitOffer &&
        (data[WorkflowNotificationKeys.requestId] ?? entityId).toString().trim().isNotEmpty) {
      final rid =
          (data[WorkflowNotificationKeys.requestId] ?? entityId).toString().trim();
      await _pushRootNamed<void>(
        context,
        AppRoutes.submitOffer,
        arguments: <String, dynamic>{'requestId': rid, 'lang': lang},
      );
      return;
    }

    if (deepRoute == InAppDeepRoutes.marketerDashboard ||
        (data[WorkflowNotificationKeys.role] ?? '').toString() == 'marketer') {
      await _pushRootNamed<void>(context, AppRoutes.marketerDashboard);
      return;
    }

    if (deepRoute == InAppDeepRoutes.ownerRequests) {
      await _pushRootNamed<void>(context, AppRoutes.ownerRequests);
      return;
    }

    if (deepRoute == InAppDeepRoutes.settings) {
      await _pushRootNamed<void>(context, '/settings');
      return;
    }

    if (deepRoute == InAppDeepRoutes.subscriptionsHub ||
        deepRoute == 'subscriptions_hub' ||
        typeLower == InAppNotifTypes.billingPaymentSuccess) {
      final at = (data['account_type'] ?? 'user').toString().trim();
      if (context.mounted) {
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SubscriptionsRootScreen(
              lang: lang,
              accountType: at.isEmpty ? 'user' : at,
              organizationId: null,
              initialIndex: 2,
            ),
          ),
        );
      }
      return;
    }

    if (deepRoute == InAppDeepRoutes.orgTeamManagement) {
      await _pushRootNamed<void>(context, AppRoutes.orgTeamManagement);
      return;
    }

    if (deepRoute == InAppDeepRoutes.orgMonitoring) {
      await _pushRootNamed<void>(context, AppRoutes.orgMonitoring);
      return;
    }

    if (deepRoute == InAppDeepRoutes.inAppNotifications ||
        deepRoute == 'notifications') {
      await _pushRootNamed<void>(
        context,
        AppRoutes.inAppNotifications,
        arguments: <String, dynamic>{'lang': lang},
      );
      return;
    }

    if (deepRoute == InAppDeepRoutes.chat) {
      await _goDashboard(context, enriched, lang);
      return;
    }

    final propId = (data[WorkflowNotificationKeys.previewPropertyId] ??
            data[WorkflowNotificationKeys.propertyId] ??
            '')
        .toString()
        .trim();
    if (propId.isNotEmpty &&
        (deepRoute == InAppDeepRoutes.propertyDetails ||
            entityType == InAppEntityTypes.property)) {
      await _goDashboard(context, enriched, lang);
      return;
    }

    if (deepRoute == InAppDeepRoutes.userDashboard ||
        deepRoute == 'dashboard') {
      await _goDashboard(context, enriched, lang);
      return;
    }

    await _goDashboard(context, enriched, lang);
  }
}
