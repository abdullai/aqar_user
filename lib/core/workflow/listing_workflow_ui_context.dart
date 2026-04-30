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
    'بانتظار التعاقد',
    'لم يتخذ إجراء 72 ساعة',
    'مفسوخ / ملغى',
    'العقارات المحجوزة',
    'إعلاناتي المنشورة',
    'صفقات مكتملة',
  ];

  static const _ownerTabEn = [
    'Awaiting marketer offers',
    'Awaiting contracting',
    'No action (72h)',
    'Cancelled / terminated',
    'Reserved properties',
    'My published ads',
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

    final tab = ListingStageUiHelper.ownerHubDisplayTabIndex(
      stage,
      legacyListingStatus: st,
    ).clamp(0, 6);

    final showOffers = stage == ListingWorkflowStage.waitingMarketers ||
        stage == ListingWorkflowStage.marketerSelected ||
        st == 'offers_received' ||
        st == 'assigned' ||
        st == 'new' ||
        st == 'invited' ||
        st == 'pending';

    final showRelist = wf == 'inactive_72h' ||
        wf == 'cancelled' ||
        wf == 'contract_cancelled' ||
        wf == 'terminated' ||
        st == 'inactive_72h' ||
        st == 'cancelled' ||
        st == 'contract_cancelled' ||
        st == 'terminated' ||
        st == 'rejected' ||
        st == 'declined';

    final showMarketerOffer = stage == ListingWorkflowStage.waitingMarketers ||
        st == 'new' ||
        st == 'invited' ||
        st == 'pending';

    final published = stage == ListingWorkflowStage.published ||
        stage == ListingWorkflowStage.reserved ||
        const {'published', 'active', 'approved', 'live'}.contains(st);

    final deadline = _parseDt(r['permit_deadline_at']) ??
        _parseDt(r['marketer_response_deadline_at']);

    return ListingWorkflowUiContext(
      isPrePublishRequest: true,
      stage: stage,
      statusLabelAr: ListingStageUiHelper.stageLabelAr(stage),
      statusLabelEn: ListingStageUiHelper.stageLabelEn(stage),
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
