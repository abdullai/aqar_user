import 'package:flutter/material.dart';

import '../navigation/chat_navigation.dart';
import '../routes.dart';
import '../core/notifications/in_app_notification_catalog.dart';
import 'in_app_notification_hub.dart';
import '../screens/chat_page.dart' show ConversationKind;
import '../screens/listing_loader_page.dart';
import '../screens/listing_request_status_page.dart';
import '../screens/owner_offers_page.dart';

/// فتح الشاشة المناسبة عند النقر على إشعار FCM (بيانات [data] نصية كما يرسلها الخادم).
class PushNavigationService {
  PushNavigationService._();

  static GlobalKey<NavigatorState>? navigatorKey;

  /// يُضبط من [MaterialApp] (مثلاً `() => langNotifier.value`) لتفادي استيراد [main.dart].
  static String Function()? langResolver;

  static void attach(
    GlobalKey<NavigatorState> key, {
    String Function()? langResolver,
  }) {
    navigatorKey = key;
    if (langResolver != null) {
      PushNavigationService.langResolver = langResolver;
    }
  }

  static String get _lang => langResolver?.call() ?? 'ar';

  static Map<String, String> _stringData(Map<String, dynamic> raw) {
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (v == null) return;
      out[k] = v.toString();
    });
    return out;
  }

  /// يُستدعى من getInitialMessage / onMessageOpenedApp / النقر على إشعار محلي بـ payload.
  static void handleNotificationMap(Map<String, dynamic> data) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;

    final d = _stringData(data);
    final kind = (d['kind'] ?? 'property').trim();
    final lang = _lang;
    final isAr = lang != 'en';

    final propertyId = (d['property_id'] ?? '').trim();
    final reservationId = (d['reservation_id'] ?? '').trim();
    final conversationId = (d['conversation_id'] ?? '').trim();
    final counterpartyId = (d['counterparty_id'] ?? '').trim();

    if (kind == 'direct' &&
        conversationId.isEmpty &&
        counterpartyId.isNotEmpty) {
      nav.push<void>(
        ChatNavigation.materialRoute(
          isAr: isAr,
          kind: ConversationKind.direct,
          counterpartyId: counterpartyId,
        ),
      );
      return;
    }

    // أي حمولة تحمل محادثة (بما فيها قناة الفريق) تفتح نفس شاشة الشات قبل مسارات العقار.
    if (conversationId.isNotEmpty) {
      nav.push<void>(
        ChatNavigation.materialRoute(
          isAr: isAr,
          conversationId: conversationId,
          propertyId: propertyId.isNotEmpty ? propertyId : null,
          reservationId: reservationId.isNotEmpty ? reservationId : null,
        ),
      );
      return;
    }

    if (kind == 'reservation' && propertyId.isNotEmpty) {
      nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ListingLoaderPage(propertyId: propertyId, lang: lang),
          settings: RouteSettings(
            name: '/pushProperty',
            arguments: <String, String>{
              if (reservationId.isNotEmpty) 'reservation_id': reservationId,
            },
          ),
        ),
      );
      return;
    }

    if (kind == 'workflow') {
      final entityType = (d['entity_type'] ?? '').trim().toLowerCase();
      final entityId = (d['entity_id'] ?? '').trim();
      final requestId = (d['request_id'] ?? '').trim();
      final deepRoute = (d['deep_route'] ?? '').trim().toLowerCase();
      if (deepRoute == InAppDeepRoutes.ownerOffers.toLowerCase() &&
          requestId.isNotEmpty) {
        nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => OwnerOffersPage(requestId: requestId, lang: lang),
            settings: const RouteSettings(name: '/pushOwnerOffers'),
          ),
        );
        return;
      }
      if (deepRoute == 'market_request' && requestId.isNotEmpty) {
        InAppDashboardDeepLink.pending.value = {
          'id': d['notification_id'] ?? '',
          'type': d['type'] ?? '',
          'data': d,
        };
        nav.pushNamed<void>(
          '/userDashboard',
          arguments: {
            'lang': lang,
            'notification': {
              'id': d['notification_id'] ?? '',
              'type': d['type'] ?? '',
              'data': d,
            },
          },
        );
        return;
      }
      final contractIdField = (d['contract_id'] ?? '').trim();
      final listingContractId =
          contractIdField.isNotEmpty
              ? contractIdField
              : (entityType == 'listing_contract' ? entityId : '');
      if (listingContractId.isNotEmpty) {
        nav.pushNamed<void>(
          AppRoutes.contractVerify,
          arguments: <String, String>{
            'contractId': listingContractId,
            'lang': lang,
          },
        );
        return;
      }
      final prop =
          propertyId.isNotEmpty
              ? propertyId
              : (entityType == 'property' ? entityId : '');
      if (prop.isNotEmpty) {
        nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                ListingLoaderPage(propertyId: prop, lang: lang),
            settings: const RouteSettings(name: '/pushWorkflowProperty'),
          ),
        );
        return;
      }
      final req =
          requestId.isNotEmpty
              ? requestId
              : (entityType == 'listing_request' ? entityId : '');
      if (req.isNotEmpty) {
        nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ListingRequestStatusPage(
              requestId: req,
              lang: lang,
            ),
            settings: const RouteSettings(name: '/pushWorkflowRequest'),
          ),
        );
        return;
      }
    }

    if (propertyId.isNotEmpty) {
      nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ListingLoaderPage(propertyId: propertyId, lang: lang),
          settings: const RouteSettings(name: '/pushProperty'),
        ),
      );
    }
  }

  static void handleLocalNotificationPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return;
    final parts = payload.split('&');
    final map = <String, dynamic>{};
    for (final p in parts) {
      final i = p.indexOf('=');
      if (i <= 0) continue;
      map[p.substring(0, i)] = p.substring(i + 1);
    }
    if (map.isNotEmpty) handleNotificationMap(map);
  }
}
