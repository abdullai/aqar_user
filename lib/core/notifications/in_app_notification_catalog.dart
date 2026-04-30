import 'dart:convert';

import 'package:flutter/material.dart';

import '../workflow/listing_workflow.dart';

// =============================================================================
// عقد موحّد لإشعارات التطبيق — للاستخدام من Dart ومن SQL (data JSON)
// =============================================================================

/// قيم موصى بها لحقل [WorkflowNotificationKeys.deepRoute] داخل عمود data.
abstract final class InAppDeepRoutes {
  static const String listingRequestStatus = 'listing_request_status';
  static const String ownerOffers = 'owner_offers';
  static const String submitPermits = 'submit_permits';
  static const String submitOffer = 'submit_offer';
  static const String marketerDashboard = 'marketer_dashboard';
  static const String ownerRequests = 'owner_requests';
  static const String inAppNotifications = 'in_app_notifications';
  static const String userDashboard = 'user_dashboard';
  static const String settings = 'settings';
  static const String orgTeamManagement = 'org_team_management';
  static const String orgMonitoring = 'org_monitoring';
  static const String propertyDetails = 'property_details';
  static const String chat = 'chat';
}

/// أنواع شائعة لعمود type (يمكنك إضافة أي نص؛ الافتراضي يُعرض كإشعار عام).
abstract final class InAppNotifTypes {
  static const String workflow = 'workflow';
  static const String offerSubmitted = 'offer_submitted';
  /// نفس الدلالة عند الإدراج من SQL (`submit_listing_offer`).
  static const String offerReceived = 'offer_received';
  static const String contractCreated = 'contract_created';
  static const String contractPendingSignature = 'contract_pending_signature';
  static const String permitSubmitted = 'permit_submitted';
  static const String reservation = 'reservation';
  static const String chatMessage = 'chat_message';
  static const String system = 'system';
  static const String listingRequestSubmitted = 'listing_request_submitted';
  static const String propertyCreated = 'property_created';
  static const String offerAccepted = 'offer_accepted';
  static const String offerDeclined = 'offer_declined';
  /// اعتذار المالك عن عرض (يُدرَج من SQL `owner_decline_listing_offer` عند p_decline_kind = apology).
  static const String offerApologyFromOwner = 'offer_apology_from_owner';
  static const String permitPackageSubmitted = 'permit_package_submitted';
  static const String listingPublished = 'listing_published';
  /// بلاغ مستخدم على إعلان منشور (تنبيه للمسوّق/المعلن المسؤول).
  static const String listingReported = 'listing_reported';

  /// تجاوز عتبة بلاغات من مستخدمين مختلفين — إخفاء مؤقت من الرئيسية + مراجعة عاجلة.
  static const String listingReportEscalated = 'listing_report_escalated';
}

/// كيانات شائعة لعمود entity_type.
abstract final class InAppEntityTypes {
  static const String listingRequest = 'listing_request';
  static const String listingOffer = 'listing_offer';
  static const String listingContract = 'listing_contract';
  static const String listingPermit = 'listing_permit';
  static const String property = 'property';
}

/// مفاتيح إضافية داخل JSON data (إلى جانب WorkflowNotificationKeys).
abstract final class InAppDataKeys {
  /// home | my_ads | favorites | cart | chat | reservations
  static const String dashboardTab = 'dashboard_tab';

  /// محادثة عامة (جدول messages)
  static const String conversationId = 'conversation_id';
}

/// عرض موحّد (أيقونة + لون) لأي إشعار في التطبيق.
abstract final class InAppNotificationCatalog {
  static Map<String, dynamic> parseDataColumn(Map<String, dynamic> row) {
    final raw = row['data'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return {};
  }

  /// يدمج entity_type / entity_id ويستنتج deep_route عند غيابه — للتوجيه الموحّد.
  static Map<String, dynamic> enrichedRowForNavigation(
    Map<String, dynamic> row,
  ) {
    final out = Map<String, dynamic>.from(row);
    final data = Map<String, dynamic>.from(parseDataColumn(row));

    final type = (row['type'] ?? '').toString();
    final entityType = (row['entity_type'] ??
            data['entity_type'] ??
            '')
        .toString()
        .trim();
    final entityId =
        (row['entity_id'] ?? data['entity_id'] ?? '').toString().trim();

    final hasDeep = (data[WorkflowNotificationKeys.deepRoute] ?? '')
        .toString()
        .trim()
        .isNotEmpty;

    void setDeep(String v) {
      if (!hasDeep) data[WorkflowNotificationKeys.deepRoute] = v;
    }

    if (entityType == InAppEntityTypes.listingRequest && entityId.isNotEmpty) {
      setDeep(InAppDeepRoutes.listingRequestStatus);
      const rk = WorkflowNotificationKeys.requestId;
      if ((data[rk] ?? '').toString().trim().isEmpty) {
        data[rk] = entityId;
      }
    } else if (entityType == InAppEntityTypes.property && entityId.isNotEmpty) {
      const pk = WorkflowNotificationKeys.previewPropertyId;
      const pid = WorkflowNotificationKeys.propertyId;
      if ((data[pk] ?? '').toString().trim().isEmpty) data[pk] = entityId;
      if ((data[pid] ?? '').toString().trim().isEmpty) data[pid] = entityId;
    } else if (entityType == InAppEntityTypes.listingOffer) {
      setDeep(InAppDeepRoutes.ownerOffers);
    } else if (entityType == InAppEntityTypes.listingContract) {
      setDeep(InAppDeepRoutes.listingRequestStatus);
    } else if (entityType == InAppEntityTypes.listingPermit) {
      setDeep(InAppDeepRoutes.listingRequestStatus);
    }

    final tl = type.toLowerCase();
    if (tl == InAppNotifTypes.chatMessage ||
        tl == 'chat_message' ||
        tl == 'message') {
      setDeep(InAppDeepRoutes.chat);
      if ((data[WorkflowNotificationKeys.mainTab] ?? '').toString().trim().isEmpty) {
        data[WorkflowNotificationKeys.mainTab] = WorkflowMainSections.chat;
      }
    }

    if (tl == InAppNotifTypes.listingRequestSubmitted ||
        tl == InAppNotifTypes.propertyCreated) {
      setDeep(InAppDeepRoutes.listingRequestStatus);
      const rk = WorkflowNotificationKeys.requestId;
      if (entityId.isNotEmpty && (data[rk] ?? '').toString().trim().isEmpty) {
        data[rk] = entityId;
      }
    }
    if (tl == InAppNotifTypes.offerApologyFromOwner) {
      setDeep(InAppDeepRoutes.listingRequestStatus);
      const rk = WorkflowNotificationKeys.requestId;
      if (entityId.isNotEmpty && (data[rk] ?? '').toString().trim().isEmpty) {
        data[rk] = entityId;
      }
    }
    if (tl == InAppNotifTypes.permitPackageSubmitted) {
      setDeep(InAppDeepRoutes.listingRequestStatus);
    }
    if (tl == InAppNotifTypes.listingPublished) {
      setDeep(InAppDeepRoutes.propertyDetails);
      if (entityType == InAppEntityTypes.property && entityId.isNotEmpty) {
        const pk = WorkflowNotificationKeys.previewPropertyId;
        const pid = WorkflowNotificationKeys.propertyId;
        if ((data[pk] ?? '').toString().trim().isEmpty) data[pk] = entityId;
        if ((data[pid] ?? '').toString().trim().isEmpty) data[pid] = entityId;
      }
    }
    if (tl == InAppNotifTypes.listingReported ||
        tl == InAppNotifTypes.listingReportEscalated) {
      setDeep(InAppDeepRoutes.propertyDetails);
      if (entityType == InAppEntityTypes.property && entityId.isNotEmpty) {
        const pk = WorkflowNotificationKeys.previewPropertyId;
        const pid = WorkflowNotificationKeys.propertyId;
        if ((data[pk] ?? '').toString().trim().isEmpty) data[pk] = entityId;
        if ((data[pid] ?? '').toString().trim().isEmpty) data[pid] = entityId;
      }
    }
    if (tl == InAppNotifTypes.reservation || tl == 'booking') {
      setDeep(InAppDeepRoutes.userDashboard);
      if ((data[WorkflowNotificationKeys.mainTab] ?? '').toString().trim().isEmpty) {
        data[WorkflowNotificationKeys.mainTab] = WorkflowMainSections.reservations;
      }
    }

    // ربط request_id من الكيان عند غيابه (صفوف قديمة أو إدراج من SQL بدون JSON كامل).
    if (entityType == InAppEntityTypes.listingRequest && entityId.isNotEmpty) {
      const rk = WorkflowNotificationKeys.requestId;
      if ((data[rk] ?? '').toString().trim().isEmpty) {
        data[rk] = entityId;
      }
      if (tl == InAppNotifTypes.offerAccepted ||
          tl == InAppNotifTypes.offerDeclined ||
          tl == InAppNotifTypes.offerApologyFromOwner ||
          tl == InAppNotifTypes.permitSubmitted ||
          tl == InAppNotifTypes.permitPackageSubmitted) {
        setDeep(InAppDeepRoutes.listingRequestStatus);
      }
    }

    if (!hasDeep &&
        (data[WorkflowNotificationKeys.deepRoute] ?? '').toString().trim().isEmpty) {
      if (tl == InAppNotifTypes.offerSubmitted ||
          tl == InAppNotifTypes.offerReceived) {
        data[WorkflowNotificationKeys.deepRoute] = InAppDeepRoutes.ownerOffers;
      } else if (tl == 'market_request_offer' ||
          tl == 'market_request_offer_updated' ||
          tl == 'market_request_offer_accepted' ||
          tl == 'market_request_offer_rejected' ||
          tl == 'market_request_deal_completed') {
        data[WorkflowNotificationKeys.deepRoute] = 'market_request';
      } else if (tl == InAppNotifTypes.offerAccepted) {
        data[WorkflowNotificationKeys.deepRoute] =
            InAppDeepRoutes.listingRequestStatus;
      } else if (tl == InAppNotifTypes.offerDeclined ||
          tl == InAppNotifTypes.offerApologyFromOwner) {
        data[WorkflowNotificationKeys.deepRoute] =
            InAppDeepRoutes.listingRequestStatus;
      } else if (tl == InAppNotifTypes.contractPendingSignature ||
          tl == InAppNotifTypes.contractCreated) {
        if ((data[WorkflowNotificationKeys.requestId] ?? '')
            .toString()
            .trim()
            .isNotEmpty) {
          data[WorkflowNotificationKeys.deepRoute] =
              InAppDeepRoutes.listingRequestStatus;
        } else {
          data[WorkflowNotificationKeys.deepRoute] = InAppDeepRoutes.ownerOffers;
        }
      } else if (tl == InAppNotifTypes.permitSubmitted) {
        data[WorkflowNotificationKeys.deepRoute] =
            InAppDeepRoutes.listingRequestStatus;
      }
    }

    final dt = (data[InAppDataKeys.dashboardTab] ?? '').toString().trim();
    if (dt.isNotEmpty &&
        (data[WorkflowNotificationKeys.mainTab] ?? '')
            .toString()
            .trim()
            .isEmpty) {
      data[WorkflowNotificationKeys.mainTab] = dt;
    }

    out['data'] = data;
    if (entityType.isNotEmpty) {
      out['entity_type'] = entityType;
    }
    if (entityId.isNotEmpty) {
      out['entity_id'] = entityId;
    }
    return out;
  }

  static IconData iconFor({
    required String type,
    String entityType = '',
  }) {
    final t = type.toLowerCase().trim();
    final et = entityType.toLowerCase().trim();

    switch (et) {
      case InAppEntityTypes.listingRequest:
        return Icons.assignment_rounded;
      case InAppEntityTypes.listingOffer:
        return Icons.local_offer_rounded;
      case InAppEntityTypes.listingContract:
        return Icons.description_rounded;
      case InAppEntityTypes.listingPermit:
        return Icons.verified_rounded;
      case InAppEntityTypes.property:
        return Icons.home_work_rounded;
    }

    switch (t) {
      case InAppNotifTypes.offerSubmitted:
      case InAppNotifTypes.offerReceived:
      case 'market_request_offer':
      case 'market_request_offer_updated':
      case 'marketing_offer':
        return Icons.local_offer_rounded;
      case 'market_request_offer_accepted':
      case 'market_request_deal_completed':
        return Icons.check_circle_rounded;
      case 'market_request_offer_rejected':
        return Icons.cancel_rounded;
      case InAppNotifTypes.offerAccepted:
        return Icons.check_circle_rounded;
      case InAppNotifTypes.offerDeclined:
        return Icons.cancel_rounded;
      case InAppNotifTypes.listingRequestSubmitted:
      case InAppNotifTypes.propertyCreated:
        return Icons.post_add_rounded;
      case InAppNotifTypes.permitPackageSubmitted:
        return Icons.fact_check_rounded;
      case InAppNotifTypes.listingPublished:
        return Icons.public_rounded;
      case InAppNotifTypes.listingReported:
        return Icons.flag_outlined;
      case InAppNotifTypes.listingReportEscalated:
        return Icons.priority_high_rounded;
      case InAppNotifTypes.contractCreated:
      case 'contract_signed':
      case InAppNotifTypes.contractPendingSignature:
        return Icons.description_rounded;
      case InAppNotifTypes.permitSubmitted:
      case 'permit_issued':
        return Icons.verified_rounded;
      case InAppNotifTypes.reservation:
      case 'booking':
        return Icons.event_available_rounded;
      case InAppNotifTypes.chatMessage:
      case 'chat':
      case 'message':
        return Icons.chat_bubble_rounded;
      case 'otp':
      case 'verification':
        return Icons.sms_rounded;
      case 'payment':
        return Icons.payments_rounded;
      case InAppNotifTypes.system:
        return Icons.info_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  static Color accentFor({
    required String type,
    String entityType = '',
  }) {
    final t = type.toLowerCase().trim();
    final et = entityType.toLowerCase().trim();

    switch (et) {
      case InAppEntityTypes.listingOffer:
        return const Color(0xFFEA580C);
      case InAppEntityTypes.listingContract:
        return const Color(0xFF2563EB);
      case InAppEntityTypes.listingPermit:
        return const Color(0xFF16A34A);
      case InAppEntityTypes.property:
        return const Color(0xFF0F766E);
    }

    switch (t) {
      case InAppNotifTypes.offerSubmitted:
      case InAppNotifTypes.offerReceived:
      case 'market_request_offer':
      case 'market_request_offer_updated':
      case 'marketing_offer':
        return const Color(0xFFEA580C);
      case 'market_request_offer_accepted':
      case 'market_request_deal_completed':
        return const Color(0xFF16A34A);
      case 'market_request_offer_rejected':
        return const Color(0xFFDC2626);
      case InAppNotifTypes.offerAccepted:
        return const Color(0xFF16A34A);
      case InAppNotifTypes.offerDeclined:
        return const Color(0xFFDC2626);
      case InAppNotifTypes.listingRequestSubmitted:
      case InAppNotifTypes.propertyCreated:
        return const Color(0xFF0F766E);
      case InAppNotifTypes.permitPackageSubmitted:
        return const Color(0xFFCA8A04);
      case InAppNotifTypes.listingPublished:
        return const Color(0xFF2563EB);
      case InAppNotifTypes.listingReported:
        return const Color(0xFFEA580C);
      case InAppNotifTypes.listingReportEscalated:
        return const Color(0xFFB91C1C);
      case InAppNotifTypes.contractCreated:
      case 'contract_signed':
      case InAppNotifTypes.contractPendingSignature:
        return const Color(0xFF2563EB);
      case InAppNotifTypes.permitSubmitted:
      case 'permit_issued':
        return const Color(0xFF16A34A);
      case 'otp':
      case 'verification':
        return const Color(0xFF7C3AED);
      case InAppNotifTypes.reservation:
        return const Color(0xFFDB2777);
      default:
        return const Color(0xFF0F766E);
    }
  }
}
