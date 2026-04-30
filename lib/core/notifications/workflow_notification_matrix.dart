// مصفوفة مرجعية: أحداث مسار التسويق (listing_requests / offers / contracts / permits / publish)
// ↔ المستلم ↔ نوع الإشعار ↔ وجهة التطبيق (deep_route).
//
// التنفيذ الفعلي: دوال SQL `workflow_create_notification` داخل الـ RPCs، و/أو
// `InAppNotificationWriter.insert` من Dart. عند إضافة حدث جديد، حدّث هذا الملف
// والتوجيه في `InAppNotificationCatalog.enrichedRowForNavigation` و`InAppNotificationRouter.open`.
//
// FCM: بعد إدراج `in_app_notifications` يمكن إرسال دفع عبر Edge Function `send_push`
// (Webhook على INSERT لهذا الجدول). راجع `docs/WORKFLOW_FCM_AND_REGA.md`.

import 'in_app_notification_catalog.dart';
import '../workflow/listing_workflow.dart';

/// حدث منطقي في سير الإعلان (قبل وبعد النشر).
enum WorkflowListingNotifEvent {
  offerSubmitted,
  offerAccepted,
  offerDeclined,
  listingRequestReceived,
  previewPropertyCreated,
  contractPendingSignature,
  contractMessage,
  permitPackageSubmitted,
  permitSubmitted,
  listingPublished,
  reservationEvent,
}

/// صف توثيقي (لا يُشغّل تلقائياً — للقراءة والاختبار اليدوي).
class WorkflowNotifMatrixRow {
  final WorkflowListingNotifEvent event;
  final String recipientRole; // owner | marketer | buyer | both
  final String typeColumn; // قيمة عمود in_app_notifications.type
  final String deepRoute; // InAppDeepRoutes.*
  final String notes;

  const WorkflowNotifMatrixRow({
    required this.event,
    required this.recipientRole,
    required this.typeColumn,
    required this.deepRoute,
    required this.notes,
  });
}

/// مرجع ثابت — اطّلع عليه عند إضافة triggers أو إشعارات جديدة.
abstract final class WorkflowListingNotificationMatrix {
  static const List<WorkflowNotifMatrixRow> rows = [
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.offerSubmitted,
      recipientRole: 'owner',
      typeColumn: 'offer_received',
      deepRoute: InAppDeepRoutes.ownerOffers,
      notes: 'RPC submit_listing_offer + اختياري InAppNotificationWriter (offer_submitted)',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.offerAccepted,
      recipientRole: 'marketer',
      typeColumn: 'offer_accepted',
      deepRoute: InAppDeepRoutes.listingRequestStatus,
      notes: 'RPC accept_listing_offer — إشعار واحد من الخادم فقط (لا تكرار من Dart)',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.offerDeclined,
      recipientRole: 'marketer',
      typeColumn: 'offer_declined',
      deepRoute: InAppDeepRoutes.listingRequestStatus,
      notes: 'RPC owner_decline_listing_offer',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.offerDeclined,
      recipientRole: 'owner',
      typeColumn: 'listing_offer_decline_limit',
      deepRoute: InAppDeepRoutes.listingRequestStatus,
      notes: 'RPC owner_decline_listing_offer عند بلوغ 3 مسوّقين مرفوضين',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.listingRequestReceived,
      recipientRole: 'owner',
      typeColumn: InAppNotifTypes.listingRequestSubmitted,
      deepRoute: InAppDeepRoutes.listingRequestStatus,
      notes: 'MarketingFlowService.notifyOwnerListingRequestSubmitted',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.previewPropertyCreated,
      recipientRole: 'owner',
      typeColumn: InAppNotifTypes.propertyCreated,
      deepRoute: InAppDeepRoutes.userDashboard,
      notes: 'MarketingFlowService.notifyOwnerPropertyListed',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.contractPendingSignature,
      recipientRole: 'marketer | owner',
      typeColumn: InAppNotifTypes.contractPendingSignature,
      deepRoute: InAppDeepRoutes.listingRequestStatus,
      notes: 'MarketingFlowService.notifyMarketerContractPendingSignature / أقران',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.contractMessage,
      recipientRole: 'marketer | owner',
      typeColumn: InAppNotifTypes.chatMessage,
      deepRoute: InAppDeepRoutes.listingRequestStatus,
      notes: 'MarketingFlowService عند رسائل عقد التسويق',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.permitPackageSubmitted,
      recipientRole: 'owner',
      typeColumn: InAppNotifTypes.permitPackageSubmitted,
      deepRoute: InAppDeepRoutes.listingRequestStatus,
      notes: 'MarketingFlowService.notifyOwnerPermitPackageSubmitted',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.permitSubmitted,
      recipientRole: 'owner',
      typeColumn: InAppNotifTypes.permitSubmitted,
      deepRoute: InAppDeepRoutes.listingRequestStatus,
      notes: 'سير عمل SQL / Edge حسب النشر',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.listingPublished,
      recipientRole: 'owner | marketer',
      typeColumn: InAppNotifTypes.listingPublished,
      deepRoute: InAppDeepRoutes.userDashboard,
      notes: 'MarketingFlowService._notifyListingPublishedParties',
    ),
    WorkflowNotifMatrixRow(
      event: WorkflowListingNotifEvent.reservationEvent,
      recipientRole: 'owner | buyer',
      typeColumn: InAppNotifTypes.reservation,
      deepRoute: InAppDeepRoutes.userDashboard,
      notes: 'حجز / إشعارات السلة — SQL أو خدمات الحجز',
    ),
  ];

  /// يملأ حقول التوجيه الموصى بها داخل `data` عند الإدراج من Dart.
  static Map<String, dynamic> dataHintsForEvent(
    WorkflowListingNotifEvent event, {
    required String requestId,
    String? propertyId,
  }) {
    final rid = requestId.trim();
    final base = <String, dynamic>{
      WorkflowNotificationKeys.requestId: rid,
      WorkflowNotificationKeys.mainTab: WorkflowMainSections.myAds,
    };
    switch (event) {
      case WorkflowListingNotifEvent.offerSubmitted:
        return {
          ...base,
          WorkflowNotificationKeys.deepRoute: InAppDeepRoutes.ownerOffers,
        };
      case WorkflowListingNotifEvent.offerAccepted:
      case WorkflowListingNotifEvent.offerDeclined:
      case WorkflowListingNotifEvent.permitPackageSubmitted:
      case WorkflowListingNotifEvent.permitSubmitted:
      case WorkflowListingNotifEvent.contractPendingSignature:
      case WorkflowListingNotifEvent.contractMessage:
        return {
          ...base,
          WorkflowNotificationKeys.deepRoute:
              InAppDeepRoutes.listingRequestStatus,
        };
      case WorkflowListingNotifEvent.listingRequestReceived:
        return {
          ...base,
          WorkflowNotificationKeys.deepRoute:
              InAppDeepRoutes.listingRequestStatus,
        };
      case WorkflowListingNotifEvent.previewPropertyCreated:
      case WorkflowListingNotifEvent.listingPublished:
      case WorkflowListingNotifEvent.reservationEvent:
        final pid = (propertyId ?? '').trim();
        return {
          ...base,
          WorkflowNotificationKeys.deepRoute: InAppDeepRoutes.userDashboard,
          if (pid.isNotEmpty) WorkflowNotificationKeys.propertyId: pid,
          if (pid.isNotEmpty) WorkflowNotificationKeys.previewPropertyId: pid,
        };
    }
  }
}
