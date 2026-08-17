import '../../models/property.dart';
import 'listing_stage_ui_helper.dart';
import 'listing_workflow_stage.dart';
import 'listing_workflow_unified.dart';

/// واجهة موحّدة: قراءة مرحلة الطلب قبل النشر أو العقار بعد النشر، دون تكرار الشروط في الـ Widgets.
class ListingWorkflowUiContext {
  final bool isPrePublishRequest;
  final ListingWorkflowStage stage;
  final String statusLabelAr;
  final String statusLabelEn;
  final int suggestedOwnerHubTabIndex;
  final String ownerHubTabNameAr;
  final String ownerHubTabNameEn;
  final bool showOwnerOffersEntry;
  final bool showOwnerRelist;
  final bool showMarketerSubmitOffer;
  final bool isPublishedPublic;
  final DateTime? primaryDeadline;

  const ListingWorkflowUiContext({
    required this.isPrePublishRequest,
    required this.stage,
    required this.statusLabelAr,
    required this.statusLabelEn,
    required this.suggestedOwnerHubTabIndex,
    required this.ownerHubTabNameAr,
    required this.ownerHubTabNameEn,
    required this.showOwnerOffersEntry,
    required this.showOwnerRelist,
    required this.showMarketerSubmitOffer,
    required this.isPublishedPublic,
    required this.primaryDeadline,
  });

  static const _ownerTabAr = [
    'بانتظار عروض المسوقين',
    'العروض المقدمة',
    'بانتظار التصريح',
    'لم يتخذ إجراء 72 ساعة',
    'مفسوخ / ملغى',
    'العقارات المحجوزة',
    'صفقات مكتملة',
  ];

  static const _ownerTabEn = [
    'Awaiting marketer offers',
    'Submitted offers',
    'Awaiting permit',
    'No action (72h)',
    'Cancelled / terminated',
    'Reserved properties',
    'Completed deals',
  ];

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// صف `listing_requests` (أو مدمج من صفحتي يحوي workflow_stage / status).
  factory ListingWorkflowUiContext.fromListingRequest(Map<String, dynamic> r) {
    final stage = ListingWorkflowUnified.fromMergedOwnerHubRow(r);
    final wf = (r['workflow_stage'] ?? '').toString().trim().toLowerCase();
    final st = (r['status'] ?? '').toString().trim().toLowerCase();

    final offersN = (r['_owner_pending_offers_count'] is num)
        ? (r['_owner_pending_offers_count'] as num).toInt()
        : int.tryParse('${r['_owner_pending_offers_count'] ?? ''}') ?? 0;
    final tab = ListingStageUiHelper.ownerHubDisplayTabIndex(
      stage,
      legacyListingStatus: st,
      ownerPendingOffersCount: offersN,
    ).clamp(0, 6);

    // بعد توقيع العقد أو بدء التصريح/النشر: لا يُعرض زر «عروض المسوقين».
    final pastContracting = stage == ListingWorkflowStage.marketerSelected ||
        stage == ListingWorkflowStage.contractSigned ||
        stage == ListingWorkflowStage.permitPending ||
        stage == ListingWorkflowStage.permitIssued ||
        stage == ListingWorkflowStage.published ||
        stage == ListingWorkflowStage.reserved ||
        wf == 'contract_signed' ||
        wf == 'permit_pending' ||
        wf == 'permit_issued' ||
        wf == 'published';
    final showOffers = !pastContracting &&
        (stage == ListingWorkflowStage.waitingMarketers ||
            st == 'offers_received' ||
            st == 'assigned' ||
            st == 'new' ||
            st == 'invited' ||
            st == 'pending');

    final showRelist = wf == 'inactive_72h' ||
        wf == 'inactive72h' ||
        wf == 'owner_action_required' ||
        wf == 'cancelled' ||
        wf == 'contract_cancelled' ||
        wf == 'terminated' ||
        st == 'inactive_72h' ||
        st == 'cancelled' ||
        st == 'contract_cancelled' ||
        st == 'terminated' ||
        st == 'rejected' ||
        st == 'declined' ||
        stage == ListingWorkflowStage.inactive72h;

    final activelyCollecting = wf == 'waiting_marketers' ||
        const {
          'waiting_marketers',
          'offers_received',
          'new',
          'invited',
          'pending',
        }.contains(st);

    final showMarketerOffer = stage != ListingWorkflowStage.inactive72h &&
        (activelyCollecting ||
            stage == ListingWorkflowStage.waitingMarketers ||
            st == 'new' ||
            st == 'invited' ||
            st == 'pending');

    final published = wf != 'waiting_marketers' &&
        st != 'waiting_marketers' &&
        (stage == ListingWorkflowStage.published ||
            stage == ListingWorkflowStage.reserved ||
            const {'published', 'active', 'approved', 'live'}.contains(st));

    final deadline = _parseDt(r['permit_deadline_at']) ??
        _parseDt(r['request_permit_deadline_at']) ??
        _parseDt(r['permits_due_at']) ??
        _parseDt(r['marketer_response_deadline_at']);

    final statusAr = ListingStageUiHelper.stageLabelAr(stage);
    final statusEn = ListingStageUiHelper.stageLabelEn(stage);

    return ListingWorkflowUiContext(
      isPrePublishRequest: true,
      stage: stage,
      statusLabelAr: statusAr,
      statusLabelEn: statusEn,
      suggestedOwnerHubTabIndex: tab,
      ownerHubTabNameAr: _ownerTabAr[tab],
      ownerHubTabNameEn: _ownerTabEn[tab],
      showOwnerOffersEntry: showOffers,
      showOwnerRelist: showRelist,
      showMarketerSubmitOffer: showMarketerOffer,
      isPublishedPublic: published,
      primaryDeadline: deadline,
    );
  }

  /// بعد النشر: عقار + حجز اختياري.
  factory ListingWorkflowUiContext.fromProperty(Property p) {
    var stage = p.effectiveWorkflowStage;
    final rs = (p.reservationStatus ?? '').trim().toLowerCase();
    if (rs == 'active' || rs == 'pending' || rs == 'held') {
      if (stage == ListingWorkflowStage.published) {
        stage = ListingWorkflowStage.reserved;
      }
    }

    final tab = ListingStageUiHelper.ownerHubDisplayTabIndex(
      stage,
      legacyListingStatus: p.status,
    ).clamp(0, 6);

    final published = p.isActive ||
        stage == ListingWorkflowStage.published ||
        stage == ListingWorkflowStage.reserved;

    final deadline = p.reservationExpiresAt ?? p.permitDeadlineAt;

    return ListingWorkflowUiContext(
      isPrePublishRequest: false,
      stage: stage,
      statusLabelAr: ListingStageUiHelper.stageLabelAr(stage),
      statusLabelEn: ListingStageUiHelper.stageLabelEn(stage),
      suggestedOwnerHubTabIndex: tab,
      ownerHubTabNameAr: _ownerTabAr[tab],
      ownerHubTabNameEn: _ownerTabEn[tab],
      showOwnerOffersEntry: false,
      showOwnerRelist: false,
      showMarketerSubmitOffer: false,
      isPublishedPublic: published,
      primaryDeadline: deadline,
    );
  }
}
