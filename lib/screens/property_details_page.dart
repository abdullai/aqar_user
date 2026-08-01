import 'dart:async' show Timer, unawaited;
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/aqar_brand_colors.dart';
import '../l10n/app_localizations.dart';
import '../core/branding/branding_logo_image.dart';
import '../core/listing/listing_media_urls.dart';
import '../core/listing/property_listing_display.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/session/app_session.dart';
import '../core/utils/app_money.dart';
import '../core/utils/display_ids.dart';
import '../core/share/app_listing_links.dart';
import '../core/share/listing_share_helper.dart';
import '../core/subscription/app_subscription_gate.dart';
import '../core/subscription/marketing_subscription_access.dart';
import '../core/subscription/subscription_gate_helper.dart';
import '../models/property.dart';
import '../services/marketing_flow_service.dart';
import '../services/marketing_workflow_hub.dart';
import '../services/subscription_service.dart';
import '../services/property_view_service.dart';
import '../services/property_auction_service.dart';
import '../services/listing_payment_service.dart';
import '../services/reservations_service.dart';
import '../core/workflow/listing_edit_permissions.dart';
import '../core/workflow/listing_permissions_helper.dart';
import '../core/workflow/listing_workflow_stage.dart';
import '../services/user_listing_preferences_service.dart';
import '../widgets/listing_pricing_breakdown.dart';
import '../widgets/listing_public_actions_menu.dart';
import '../widgets/listing_report_sheet.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/marketing_offer_submit_sheet.dart';
import '../widgets/marketer_policy_notice_card.dart';
import '../widgets/inline_property_video.dart';
import '../widgets/listing_watermark_overlay.dart';
import '../widgets/listing_media_gallery.dart';
import '../widgets/property_video_sheet.dart';
import '../widgets/listing_formatted_spec_panel.dart';
import '../widgets/listing_marketing_tracking_sheet.dart';
import '../widgets/guest_participation_gate.dart';
import '../services/guest_session_bridge.dart';
import '../services/guest_unlock_service.dart';
import '../widgets/government_in_app_web_page.dart';
import '../navigation/chat_navigation.dart';
import 'listing_request_status_page.dart';
import 'listing_contract_chat_page.dart';
import 'subscriptions/subscriptions_root_screen.dart';
import 'owner_offers_page.dart';
import 'property_map_discovery_page.dart';

class PropertyDetailsPage extends StatefulWidget {
  final Property property;
  final bool isAr;
  final String currentUserId;
  final String? ownerUsername;
  final bool isFavorite;
  final Future<void> Function() onToggleFavorite;
  final bool canManageProperty;
  final String? marketingRequestId;
  final String? marketingInviteId;
  final bool allowMarketingOffer;

  /// من لوحة المسوق: `invite` | `offer` | `contract` لإظهار اختصارات الطلب.
  final String? marketerHubPhase;

  /// قبل النشر: للمسوّق فقط — إظهار الاسم الرباعي للمعلن تحت «هذا الإعلان بواسطة».
  /// بعد النشر يُخفى تلقائياً من الرابط العام؛ يُفضّل تمرير false عندما تكون `published`.
  final bool showOwnerLegalNameToViewer;
  final Future<Property?> Function(Property property)? onEditProperty;

  /// تعديل المسوّق لمطابقة بيانات الهيئة بعد إصدار التصريح وقبل النشر.
  final Future<Property?> Function(Property property)? onMarketerRegaAlignEdit;
  final Future<bool> Function(Property property)? onRequestDelete;

  /// من الرئيسية عند تفعيل عرض «المخفية» فقط — قائمة ⋮ تعرض إظهارًا وسحب بلاغ معلّق.
  final bool homeFeedShowsHiddenOnly;

  /// بعد إخفاء/إظهار/بلاغ/سحب بلاغ من جهة الزائر — لتحديث شريط المخفية في الرئيسية.
  final VoidCallback? onVisitorListingPreferenceChanged;

  /// عند `true`: لا يُعرض سهم الرجوع الداخلي — الشريط العلوي للوحة الداشبورد
  /// يعرض سهم الرجوع الموحَّد. يُمرَّر `true` من `_pushBody` في الداشبورد.
  final bool embedAppBar;

  /// إتمام صفقة على إعلان منشور (إضافة للسلة) — يُمرَّر من الداشبورد.
  final Future<void> Function(Property property)? onCompleteDeal;

  const PropertyDetailsPage({
    super.key,
    required this.property,
    required this.isAr,
    required this.currentUserId,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.ownerUsername,
    this.canManageProperty = false,
    this.marketingRequestId,
    this.marketingInviteId,
    this.allowMarketingOffer = false,
    this.marketerHubPhase,
    this.showOwnerLegalNameToViewer = false,
    this.onEditProperty,
    this.onMarketerRegaAlignEdit,
    this.onRequestDelete,
    this.homeFeedShowsHiddenOnly = false,
    this.onVisitorListingPreferenceChanged,
    this.embedAppBar = false,
    this.onCompleteDeal,
  });

  @override
  State<PropertyDetailsPage> createState() => _PropertyDetailsPageState();
}

class _PropertyDetailsPageState extends State<PropertyDetailsPage> {
  final _sb = Supabase.instance.client;
  final _page = PageController();

  static const String _imagesBucket = 'property-images';
  static const String _videosBucket = 'property-videos';

  late Property _property;

  int _imgIndex = 0;
  double? lat;
  double? lng;
  bool _loadingCoords = false;
  bool _checkingMarketingOffer = false;
  bool _offerSentThisRound = false;
  bool _openingChat = false;
  bool _openingVideo = false;
  bool _runningOwnerAction = false;
  bool _loadingWorkflowSidecars = false;
  String? _resolvedListingRequestId;
  String? _resolvedListingRequestWorkflow;
  String? _resolvedListingContractId;
  DateTime? _resolvedContractStartedAt;
  int _ownerOffersCount = 0;
  bool _loadingDeleteMeta = false;
  bool _sharing = false;

  final _bidAmountController = TextEditingController();
  bool _loadingAuctionBids = false;
  bool _placingBid = false;
  List<Map<String, dynamic>> _auctionBids = const [];

  RealtimeChannel? _auctionRtChannel;

  Map<String, dynamic>? _openAuctionSession;
  bool _loadingAuctionSession = false;
  bool _openingAuctionSession = false;
  bool _closingAuctionSession = false;
  Timer? _auctionSessionTick;

  bool _platformStaff = false;
  List<Map<String, dynamic>> _paymentEvents = const [];
  bool _loadingPaymentEvents = false;
  bool _recordingPaymentEvent = false;

  bool _deleteRequested = false;
  bool _deleteApproved = false;
  DateTime? _deleteRequestedAt;
  String? _deleteRequestReason;

  bool _viewerInCartForListing = false;
  bool _buyerDealSubscriptionOk = false;
  bool _loadingBuyerDealAccess = false;

  bool get _isGuest => widget.currentUserId == 'guest';
  bool get _isOwnerManager => widget.canManageProperty;
  String get _effectiveMarketingRequestId {
    final w = (widget.marketingRequestId ?? '').trim();
    if (w.isNotEmpty) return w;
    return (_resolvedListingRequestId ?? '').trim();
  }

  String get _effectiveOwnerListingRequestId {
    final w = (widget.marketingRequestId ?? '').trim();
    if (w.isNotEmpty) return w;
    return (_resolvedListingRequestId ?? '').trim();
  }

  bool get _resolvedMarketerSidecar =>
      !_isGuest &&
      !_isListingOwner &&
      widget.currentUserId.trim().isNotEmpty &&
      widget.currentUserId != _property.ownerId;

  bool get _allowMarketingOfferEffective =>
      widget.allowMarketingOffer ||
      (_resolvedMarketerSidecar &&
          (_resolvedListingRequestId ?? '').trim().isNotEmpty &&
          !_isPublishedLikeListing);

  bool get _canUseMarketingOfferAction =>
      _allowMarketingOfferEffective &&
      !_isGuest &&
      _effectiveMarketingRequestId.isNotEmpty;

  bool get _marketerWorkflowBlocksNewOffer {
    final s = _property.effectiveWorkflowStage;
    switch (s) {
      case ListingWorkflowStage.marketerSelected:
      case ListingWorkflowStage.contractPending:
      case ListingWorkflowStage.contractSent:
      case ListingWorkflowStage.contractReturned:
      case ListingWorkflowStage.contractSigned:
      case ListingWorkflowStage.contractCancelled:
      case ListingWorkflowStage.permitPending:
      case ListingWorkflowStage.permitIssued:
      case ListingWorkflowStage.published:
      case ListingWorkflowStage.reserved:
      case ListingWorkflowStage.cancelled:
      case ListingWorkflowStage.terminated:
      case ListingWorkflowStage.archived:
        return true;
      default:
        return false;
    }
  }

  bool get _showMarketerSubmitOfferButton =>
      _canUseMarketingOfferAction &&
      !_isPublishedLikeListing &&
      !_marketerWorkflowBlocksNewOffer &&
      !_offerSentThisRound &&
      !_checkingMarketingOffer;

  String get _effectiveMarketerHubPhase {
    final raw = (widget.marketerHubPhase ?? '').trim();
    if (raw.isNotEmpty) return raw.toLowerCase();
    if (!_canUseMarketingOfferAction && !_isPartyMarketerOnListing) {
      return '';
    }
    if (_offerSentThisRound) return 'offer_pending';
    final s = _property.effectiveWorkflowStage;
    if (s == ListingWorkflowStage.marketerSelected) return 'accepted';
    if (s == ListingWorkflowStage.contractPending ||
        s == ListingWorkflowStage.contractSent ||
        s == ListingWorkflowStage.contractReturned) {
      return 'contract';
    }
    if (s == ListingWorkflowStage.contractSigned) return 'signed';
    // مرحلة «التصاريح 72 ساعة»: العقد موقَّع والمسوّق ينتظر/يُدخل تصريح REGA.
    if (s == ListingWorkflowStage.permitPending ||
        s == ListingWorkflowStage.permitIssued) {
      return 'permit';
    }
    return '';
  }

  /// `true` إذا كان المسوّق وصل إلى مرحلة «تصاريح 72 ساعة» أو ما بعدها — يحلّ
  /// لنا قرار كشف رقم جوّال المالك للمسوّق فقط في هذه المرحلة وما تلاها.
  bool get _marketerCanSeeOwnerContact {
    if (_isListingOwner) return true; // المالك يرى بياناته دائماً
    if (!_isPartyMarketerOnListing && !widget.allowMarketingOffer) {
      return false; // مستخدم عادي/ضيف لا يرى رقم المالك (يبقى التواصل عبر المسوّق)
    }
    final phase = _effectiveMarketerHubPhase;
    return phase == 'signed' || phase == 'permit';
  }

  bool get _showMarketerHubShortcuts =>
      !_isGuest &&
      _effectiveMarketingRequestId.isNotEmpty &&
      (_effectiveMarketerHubPhase.isNotEmpty || _isPartyMarketerOnListing);

  /// إخفاء بطاقة «التسويق والتعاقد» عندما يكون عرض المسوّق قيد المراجعة فقط — يكفي «مسار التسويق» أعلاه والفوترة.
  bool get _showMarketerMarketingHubCard {
    if (_isPublishedLikeListing) return false;
    if (!_canUseMarketingOfferAction && !_showMarketerHubShortcuts) {
      return false;
    }
    if (!_isListingOwner &&
        _offerSentThisRound &&
        _effectiveMarketerHubPhase == 'offer_pending') {
      return false;
    }
    return true;
  }

  bool get _ownerMarketingDeskEligible =>
      _isListingOwner &&
      !_isGuest &&
      !_isPublishedLikeListing &&
      _effectiveOwnerListingRequestId.isNotEmpty;

  /// زر/بطاقة «تتبع التسويق» — للمالك أو المسوّق المرتبط بالإعلان عند وجود طلب.
  bool get _showMarketingTrackingEntry =>
      !_isGuest &&
      widget.currentUserId.trim().isNotEmpty &&
      _effectiveMarketingRequestId.isNotEmpty &&
      (_isListingOwner ||
          _isPublishingMarketer ||
          _isSelectedMarketerForListing ||
          _showMarketerHubShortcuts);

  bool get _ownerShowsOffersEntry =>
      _ownerMarketingDeskEligible &&
      (_ownerOffersCount > 0 ||
          _property.effectiveWorkflowStage ==
              ListingWorkflowStage.waitingMarketers);

  bool get _ownerShowsContractDeskEntry =>
      _ownerMarketingDeskEligible &&
      (_resolvedListingContractId ?? '').trim().isNotEmpty &&
      <ListingWorkflowStage>{
        ListingWorkflowStage.contractSent,
        ListingWorkflowStage.contractPending,
        ListingWorkflowStage.marketerSelected,
        ListingWorkflowStage.contractReturned,
      }.contains(_property.effectiveWorkflowStage);

  String get _marketingLang => widget.isAr ? 'ar' : 'en';

  /// رقم الجوال لا يُعرض للعامة — التواصل عبر الدردشة داخل التطبيق.
  bool get _isListingOwner =>
      !_isGuest &&
      widget.currentUserId.trim().isNotEmpty &&
      widget.currentUserId == _property.ownerId;

  bool get _isPublishingMarketer =>
      !_isGuest &&
      widget.currentUserId.trim().isNotEmpty &&
      widget.currentUserId == (_property.publishedByMarketerId ?? '').trim();

  bool get _canManageAuctionSession =>
      !_isGuest &&
      (_isListingOwner || _isPublishingMarketer || _platformStaff) &&
      _isPublishedLikeListing;

  bool get _canRecordPaymentAsPrivileged =>
      !_isGuest &&
      _isPublishedLikeListing &&
      (_isListingOwner || _isPublishingMarketer || _platformStaff);

  bool get _isSelectedMarketerForListing =>
      !_isGuest &&
      widget.currentUserId == (_property.selectedMarketerId ?? '').trim();

  /// عدّاد ٧٢ ساعة لإنشاء العقد بعد قبول المالك لعرضك.
  bool get _showMarketerContract72Countdown =>
      !_isGuest &&
      !_isListingOwner &&
      _isSelectedMarketerForListing &&
      (_resolvedListingContractId ?? '').trim().isEmpty &&
      _resolvedContractStartedAt != null &&
      _property.effectiveWorkflowStage ==
          ListingWorkflowStage.marketerSelected;

  /// مشتري محتمل فقط — ليس مالكاً ولا مسوّقاً مرتبطاً بالإعلان (منشّر/مختار).
  bool get _canRecordBuyerGoodFaith =>
      !_isGuest &&
      _property.isAuction &&
      _isPublishedLikeListing &&
      !_isListingOwner &&
      !_isPublishingMarketer &&
      !_isSelectedMarketerForListing &&
      !_platformStaff;

  bool get _auctionSessionTimeEnded {
    final s = _openAuctionSession;
    if (s == null) return false;
    final e = s['ends_at'];
    if (e == null) return false;
    final dt = DateTime.tryParse(e.toString());
    if (dt == null) return false;
    return !dt.toUtc().isAfter(DateTime.now().toUtc());
  }

  /// محادثة العقار مع المسوّق المنشّر/المختار فقط (لا المالك).
  String? get _chatMarketerId {
    final p = (_property.publishedByMarketerId ?? '').trim();
    if (p.isNotEmpty) return p;
    final s = (_property.selectedMarketerId ?? '').trim();
    return s.isNotEmpty ? s : null;
  }

  bool get _canOpenMarketerChat =>
      !_isGuest &&
      (_chatMarketerId ?? '').isNotEmpty &&
      _chatMarketerId != widget.currentUserId;

  bool get _isPartyMarketerOnListing =>
      !_isGuest &&
      widget.currentUserId.trim().isNotEmpty &&
      widget.currentUserId != _property.ownerId &&
      (widget.currentUserId == (_property.selectedMarketerId ?? '').trim() ||
          widget.currentUserId ==
              (_property.publishedByMarketerId ?? '').trim());

  /// قبل النشر: مسوّق مرتبط أو لديه عرض/دعوة يفتح محادثة مع المالك.
  bool get _canOpenListingOwnerChat =>
      !_isGuest &&
      !_isPublishedLikeListing &&
      widget.currentUserId.trim() != _property.ownerId &&
      (_isPartyMarketerOnListing || widget.allowMarketingOffer);

  /// ⋮ للزائر: ليس مالكاً ولا مسوّقاً مرتبطاً بالإعلان ولا موظف منصّة.
  bool get _showVisitorListingPublicMenu {
    if (_isGuest) return false;
    if (widget.canManageProperty) return false;
    if (_isListingOwner) return false;
    if (_isPublishingMarketer) return false;
    if (_isSelectedMarketerForListing) return false;
    if (_platformStaff) return false;
    return true;
  }

  bool get _isPublicBuyerOnPublishedListing =>
      _isPublishedLikeListing &&
      !_isGuest &&
      !_isListingOwner &&
      !_isPublishingMarketer &&
      !_isSelectedMarketerForListing &&
      !_platformStaff &&
      !_isPartyMarketerOnListing &&
      !_allowMarketingOfferEffective;

  bool get _publicBuyerMayChatMarketer =>
      _viewerInCartForListing && _buyerDealSubscriptionOk;

  bool get _showMarketerChatButton {
    if (!_canOpenMarketerChat) return false;
    if (_isPublicBuyerOnPublishedListing) {
      return _publicBuyerMayChatMarketer;
    }
    return _isPublishedLikeListing ||
        _isListingOwner ||
        !_isPartyMarketerOnListing;
  }

  bool get _showGuestCompleteDealBar =>
      _isGuest &&
      _isPublishedLikeListing &&
      !_allowMarketingOfferEffective &&
      widget.onCompleteDeal != null;

  bool get _showBuyerCompleteDealBar =>
      !_isGuest &&
      _isPublishedLikeListing &&
      !_isListingOwner &&
      !_isPublishingMarketer &&
      !_isSelectedMarketerForListing &&
      !_allowMarketingOfferEffective &&
      !_platformStaff &&
      widget.onCompleteDeal != null &&
      !_viewerInCartForListing;

  Future<void> _loadBuyerDealAccess() async {
    if (_isGuest) return;
    final uid = widget.currentUserId.trim();
    if (uid.isEmpty || uid == 'guest') return;
    setState(() => _loadingBuyerDealAccess = true);
    try {
      final inCart =
          await ReservationsService.userHasActiveReservationForProperty(
        userId: uid,
        propertyId: _property.id,
      );
      final gate = context.read<AppSubscriptionGate>();
      await gate.refresh(force: false);
      if (!mounted) return;
      setState(() {
        _viewerInCartForListing = inCart;
        _buyerDealSubscriptionOk = gate.canCompleteMarketDeal;
        _loadingBuyerDealAccess = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBuyerDealAccess = false);
    }
  }

  bool get _showMarketerRegaEdit =>
      widget.onMarketerRegaAlignEdit != null &&
      ListingEditPermissions.marketerMayAlignWithRega(
        _property,
        widget.currentUserId,
      );

  bool get _hasDeedInfo {
    if ((_property.deedNumber ?? '').trim().isNotEmpty) return true;
    if (_property.deedDate != null) return true;
    if ((_property.deedIssuer ?? '').trim().isNotEmpty) return true;
    // احتياطي من لقطة الترخيص إن لم تُملأ أعمدة الصك على الصف.
    final snapDeed = _licenseField('deed_or_benefit_doc_number');
    if (snapDeed.isNotEmpty) return true;
    final snapDate = _licenseField('deed_date');
    if (snapDate.isNotEmpty) return true;
    return false;
  }

  String get _deedNumberDisplay {
    final n = (_property.deedNumber ?? '').trim();
    if (n.isNotEmpty) return n;
    return _licenseField('deed_or_benefit_doc_number');
  }

  String get _deedDateDisplay {
    if (_property.deedDate != null) {
      final d = _property.deedDate!;
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return _licenseField('deed_date');
  }

  String get _deedIssuerDisplay {
    final i = (_property.deedIssuer ?? '').trim();
    if (i.isNotEmpty) return i;
    return _licenseField('deed_issuer');
  }

  String _maskDeedNumber(String raw) {
    final s = raw.trim();
    if (s.length <= 4) return s;
    final tail = s.substring(s.length - 4);
    return '${'*' * (s.length - 4)}$tail';
  }

  Map<String, dynamic>? get _licenseSnap => _property.marketingLicenseSnapshot;

  String? get _marketerPublicLine =>
      _property.marketerEntityPublicLine(widget.isAr);

  String _licenseField(String k) => (_licenseSnap?[k] ?? '').toString().trim();

  String _licenseQrImageSrc() {
    final p = _licenseField('ad_qr_storage_path');
    if (p.isNotEmpty) return p;
    return _licenseField('ad_qr_image_url');
  }

  bool get _hasMarketingLicenseInfo {
    final m = _licenseSnap;
    if (m == null || m.isEmpty) return false;
    const keys = <String>[
      'rega_ad_license_number',
      'rega_issue_date',
      'rega_expiry_date',
      'fal_broker_license_number',
      'deed_or_benefit_doc_number',
      'notes',
      'ad_qr_storage_path',
      'ad_qr_image_url',
      'rega_source_url',
      'marketer_entity_display_name',
      'rega_advertiser_unified_number',
      'rega_ad_responsible_name',
      'rega_ad_responsible_mobile',
      'rega_ad_purpose',
      'rega_deed_doc_type',
      'rega_unit_price',
    ];
    return keys.any((k) => _licenseField(k).isNotEmpty);
  }

  @override
  void initState() {
    super.initState();
    _property = widget.property;
    _loadCoordinates();
    _loadDeleteMeta();
    _loadMarketingOfferAvailability();
    unawaited(_loadWorkflowSidecars());
    _loadAuctionBidsIfNeeded();
    _ensureAuctionRealtimeChannel();
    unawaited(_loadAuctionSession());
    if (!_isGuest) {
      unawaited(_loadPlatformStaff());
    }
    unawaited(_loadPaymentEvents());
    if (!_isGuest) {
      unawaited(_loadBuyerDealAccess());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isGuest) {
        PropertyViewService.recordView(_sb, _property.id);
      }
    });
  }

  bool get _isPublishedLikeListing {
    final reqWf = (_resolvedListingRequestWorkflow ?? '').trim().toLowerCase();
    if (reqWf == 'waiting_marketers') return false;
    final st = (_property.status ?? '').trim().toLowerCase();
    final wf = (_property.workflowStage ?? '').trim().toLowerCase();
    if (wf == 'waiting_marketers') return false;
    return st == 'published' ||
        st == 'live' ||
        st == 'active' ||
        wf == 'published';
  }

  Future<void> _loadWorkflowSidecars() async {
    if (_isGuest || _isPublishedLikeListing) return;
    final pid = _property.id.trim();
    if (pid.isEmpty) return;
    setState(() => _loadingWorkflowSidecars = true);
    try {
      Map<String, dynamic>? row = await MarketingFlowService(_sb)
          .listingRequestSummaryForPreviewProperty(pid);
      final midPass = (widget.marketingRequestId ?? '').trim();
      if (row == null && midPass.isNotEmpty) {
        row = await MarketingFlowService(_sb).ownerListingRequestSnapshot(midPass);
      }
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _resolvedListingRequestId = null;
          _resolvedListingContractId = null;
          _resolvedContractStartedAt = null;
          _ownerOffersCount = 0;
          _loadingWorkflowSidecars = false;
        });
        await _loadMarketingOfferAvailability();
        return;
      }
      final rid = (row['id'] ?? '').toString().trim();
      final reqWf = (row['workflow_stage'] ?? '').toString().trim();
      final cid = (row['contract_id'] ?? '').toString().trim();
      final cStart = DateTime.tryParse(
        (row['contract_started_at'] ?? '').toString(),
      );
      var count = 0;
      if (_isListingOwner && rid.isNotEmpty) {
        count = await MarketingFlowService(_sb).ownerOffersCountForRequest(rid);
      }
      if (!mounted) return;
      setState(() {
        _resolvedListingRequestId = rid.isNotEmpty ? rid : null;
        _resolvedListingRequestWorkflow = reqWf.isNotEmpty ? reqWf : null;
        _resolvedListingContractId = cid.isNotEmpty ? cid : null;
        _resolvedContractStartedAt = cStart;
        _ownerOffersCount = count;
        _loadingWorkflowSidecars = false;
      });
      await _loadMarketingOfferAvailability();
    } catch (_) {
      if (mounted) {
        setState(() => _loadingWorkflowSidecars = false);
      }
    }
  }

  Future<void> _loadMarketingOfferAvailability() async {
    if (_isGuest || _isListingOwner) return;
    final reqId = _effectiveMarketingRequestId.trim();
    if (reqId.isEmpty) return;
    setState(() => _checkingMarketingOffer = true);
    try {
      final has = await MarketingFlowService(_sb)
          .marketerHasLiveOfferForRequestRound(reqId);
      if (!mounted) return;
      setState(() => _offerSentThisRound = has);
    } catch (_) {
      if (!mounted) return;
      setState(() => _offerSentThisRound = false);
    } finally {
      if (mounted) setState(() => _checkingMarketingOffer = false);
    }
  }

  Future<bool> _ensureMarketingSubscriptionForPropertyDetails() async {
    if (!_showMarketerHubShortcuts &&
        !_isPartyMarketerOnListing &&
        !widget.allowMarketingOffer) {
      return true;
    }
    return SubscriptionGateHelper.ensure(
      context,
      isAr: widget.isAr,
      action: SubscriptionGateAction.marketingPaidWorkflow,
      onGoSubscribe: () {
        if (!mounted) return;
        final lang = widget.isAr ? 'ar' : 'en';
        unawaited(
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              settings:
                  const RouteSettings(name: '/propertyDetails/subscriptions'),
              builder: (_) => SubscriptionsRootScreen(
                lang: lang,
                accountType: '',
                embedAppBar: true,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitMarketingOfferFromDetails() async {
    if (!await _ensureMarketingSubscriptionForPropertyDetails()) return;
    if (!mounted) return;
    final reqId = _effectiveMarketingRequestId.trim();
    if (reqId.isEmpty) return;
    final inv = (widget.marketingInviteId ?? '').trim();
    final hint = _property.price > 0 ? _property.price : null;
    await showMarketingOfferSubmitSheet(
      context,
      requestId: reqId,
      inviteId: inv.isEmpty ? null : inv,
      isAr: widget.isAr,
      propertyBaseSarHint: hint,
      onAfterSubmit: () async {
        MarketingWorkflowHub.notifyBucketsChanged();
        if (!mounted) return;
        await _loadMarketingOfferAvailability();
      },
    );
  }

  Future<void> _openMarketingListingStatusPage() async {
    if (!await _ensureMarketingSubscriptionForPropertyDetails()) return;
    if (!mounted) return;
    final rid = _effectiveMarketingRequestId.trim();
    if (rid.isEmpty) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingRequestStatusPage(
          requestId: rid,
          lang: _marketingLang,
        ),
      ),
    );
  }

  Future<void> _openMarketingTrackingSheet() async {
    final rid = _effectiveMarketingRequestId.trim();
    final uid = widget.currentUserId.trim();
    if (rid.isEmpty || uid.isEmpty) return;
    await showListingMarketingTrackingSheet(
      context: context,
      sb: _sb,
      requestId: rid,
      isAr: widget.isAr,
      viewerUserId: uid,
    );
  }

  void _openOwnerOffersFromDetails() {
    final rid = _effectiveOwnerListingRequestId.trim();
    if (rid.isEmpty) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OwnerOffersPage(
          requestId: rid,
          lang: _marketingLang,
        ),
      ),
    );
  }

  Future<void> _openMarketerListingContractDetails() async {
    if (!await _ensureMarketingSubscriptionForPropertyDetails()) return;
    if (!mounted) return;
    final cid = (_resolvedListingContractId ?? '').trim();
    if (cid.isEmpty) {
      await _openMarketingListingStatusPage();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ListingContractChatPage(
          contractId: cid,
          lang: _marketingLang,
          strictReadOnly: true,
          lockAfterOwnerSigns: true,
        ),
      ),
    );
  }

  @override
  void dispose() {
    try {
      _auctionRtChannel?.unsubscribe();
    } catch (_) {}
    _auctionRtChannel = null;
    _auctionSessionTick?.cancel();
    _auctionSessionTick = null;
    _bidAmountController.dispose();
    _page.dispose();
    super.dispose();
  }

  void _ensureAuctionRealtimeChannel() {
    if (!_property.isAuction || !_isPublishedLikeListing) return;
    try {
      _auctionRtChannel?.unsubscribe();
      _auctionRtChannel = null;
      final pid = _property.id.trim();
      if (pid.isEmpty) return;
      final ch = _sb.channel('property_auction_rt_$pid');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'property_auction_bids',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'property_id',
          value: pid,
        ),
        callback: (_) {
          if (!mounted) return;
          unawaited(() async {
            await _loadAuctionBidsIfNeeded();
            final nb =
                await PropertyAuctionService.refreshCurrentBid(_property.id);
            if (mounted && nb != null) {
              setState(() => _property = _property.copyWith(currentBid: nb));
            }
          }());
        },
      );
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'property_auction_sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'property_id',
          value: pid,
        ),
        callback: (_) {
          if (!mounted) return;
          unawaited(_loadAuctionSession());
        },
      );
      ch.subscribe();
      _auctionRtChannel = ch;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('auction realtime bind failed: $e');
      }
    }
  }

  Future<void> _loadAuctionBidsIfNeeded() async {
    if (!_property.isAuction || !_isPublishedLikeListing) return;
    setState(() => _loadingAuctionBids = true);
    try {
      final rows =
          await PropertyAuctionService.fetchRecentBids(_property.id, limit: 50);
      if (!mounted) return;
      setState(() => _auctionBids = rows);
    } finally {
      if (mounted) setState(() => _loadingAuctionBids = false);
    }
  }

  Future<void> _submitPropertyBid() async {
    if (!_property.isAuction || !_isPublishedLikeListing) return;
    if (_isGuest) {
      _snackLoginRequired();
      return;
    }
    if (_isListingOwner || _isPublishingMarketer) {
      _snack(
        widget.isAr
            ? 'لا يمكن للمالك أو المسوّق المنشّر المزايدة على هذا الإعلان'
            : 'Owner or publishing marketer cannot bid here',
        isError: true,
      );
      return;
    }
    if (_openAuctionSession != null && _auctionSessionTimeEnded) {
      _snack(
        widget.isAr
            ? 'انتهت جلسة المزاد — لا يمكن المزايدة.'
            : 'The auction session has ended — bidding is closed.',
        isError: true,
      );
      return;
    }
    final raw = _bidAmountController.text.trim().replaceAll(',', '');
    final amt = double.tryParse(raw);
    if (amt == null || amt <= 0) {
      _snack(
        widget.isAr ? 'أدخل مبلغاً صحيحاً' : 'Enter a valid amount',
        isError: true,
      );
      return;
    }
    setState(() => _placingBid = true);
    try {
      try {
        final ok = await PropertyAuctionService.placeBid(
          propertyId: _property.id,
          amount: amt,
        );
        if (!ok) {
          if (!mounted) return;
          _snack(
            widget.isAr
                ? 'تعذّر تسجيل المزايدة. تحقق من أن المبلغ يزيد عن الحد الأدنى وأن الإعلان مفتوحاً.'
                : 'Could not place bid. Check minimum amount and listing status.',
            isError: true,
          );
          return;
        }
      } on PostgrestException catch (e) {
        if (!mounted) return;
        final msg = PropertyAuctionService.userFacingErrorMessage(
          e,
          isAr: widget.isAr,
        );
        _snack(msg ?? e.message, isError: true);
        return;
      }
      final newBid =
          await PropertyAuctionService.refreshCurrentBid(_property.id);
      if (!mounted) return;
      if (newBid != null) {
        setState(() => _property = _property.copyWith(currentBid: newBid));
      }
      _bidAmountController.clear();
      await _loadAuctionBidsIfNeeded();
      _snack(widget.isAr ? 'تم تسجيل مزايدتك' : 'Your bid was recorded');
    } finally {
      if (mounted) setState(() => _placingBid = false);
    }
  }

  bool _isUrl(String s) => s.startsWith('http://') || s.startsWith('https://');

  String _normalizeImageUrl(String value) {
    final v = value.trim();
    if (v.isEmpty) return v;
    if (_isUrl(v)) return v;
    return _sb.storage.from(_imagesBucket).getPublicUrl(v);
  }

  String _resolveVideoPlayableUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return v;
    if (_isUrl(v)) return v;
    return _sb.storage.from(_videosBucket).getPublicUrl(v);
  }

  List<String> get _galleryUrls {
    if (_property.defaultCoverUsed) return const [];
    final out = <String>[];

    for (final raw in _property.images) {
      final normalized = _normalizeImageUrl(raw);
      if (normalized.isNotEmpty) {
        out.add(normalized);
      }
    }

    return out;
  }

  bool get _coverPrimaryPrefersVideo {
    final g = _property.listingGuidance;
    final v = (g?['cover_primary'] ?? 'image').toString().trim().toLowerCase();
    return v == 'video';
  }

  /// فيديو يظهر كشريحة أولى في المعرض (لا صور، أو الإعداد يفضّل فيديو الغلاف).
  bool get _videoAsGalleryLead =>
      _hasVideo && (_galleryUrls.isEmpty || _coverPrimaryPrefersVideo);

  Uri get _listingShareUri => AppListingLinks.listingWebUri(
        _property.id,
        lang: widget.isAr ? 'ar' : 'en',
      );

  String get _shareImageUrlForRichShare =>
      _galleryUrls.isNotEmpty
          ? _galleryUrls.first
          : PropertyListingDisplay.propertySharePreviewUrl(_property, _sb);

  String get _shareBodyWithLinkAndBrand {
    final brand = AppBranding.shareBrandLine(isAr: widget.isAr);
    final more = widget.isAr
        ? 'لمزيد من معلومات العقار والصور، قم بزيارة  الرابط:'
        : 'More photos and full details at:';
    return '${_shareText.trimRight()}\n$more\n${_listingShareUri.toString()}\n\n— $brand';
  }

  Future<void> _loadDeleteMeta() async {
    if (!_isOwnerManager) return;

    setState(() => _loadingDeleteMeta = true);

    try {
      final row = await _sb
          .from('properties')
          .select(
            'delete_requested, delete_approved, delete_requested_at, delete_request_reason',
          )
          .eq('id', _property.id)
          .maybeSingle();

      if (row == null || !mounted) return;

      setState(() {
        _deleteRequested = row['delete_requested'] == true;
        _deleteApproved = row['delete_approved'] == true;
        _deleteRequestedAt = DateTime.tryParse(
          (row['delete_requested_at'] ?? '').toString(),
        );
        final reason = (row['delete_request_reason'] ?? '').toString().trim();
        _deleteRequestReason = reason.isEmpty ? null : reason;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingDeleteMeta = false);
    }
  }

  Future<void> _loadCoordinates() async {
    setState(() => _loadingCoords = true);

    if (_property.latitude != null && _property.longitude != null) {
      setState(() {
        lat = _property.latitude;
        lng = _property.longitude;
        _loadingCoords = false;
      });
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'coords_${_property.id}';
      final raw = prefs.getString(key);

      if (raw != null) {
        final data = json.decode(raw) as Map<String, dynamic>;
        lat = (data['lat'] as num?)?.toDouble();
        lng = (data['lng'] as num?)?.toDouble();
      }

      if (lat == null || lng == null) {
        final temp = prefs.getString('coords_temp_${widget.currentUserId}');
        if (temp != null) {
          final data = json.decode(temp) as Map<String, dynamic>;
          lat = (data['lat'] as num?)?.toDouble();
          lng = (data['lng'] as num?)?.toDouble();
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _loadingCoords = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? cs.error : null,
        content: Text(
          msg,
          style: TextStyle(color: isError ? cs.onError : null),
        ),
      ),
    );
  }

  void _snackLoginRequired() {
    _snack(
      widget.isAr ? 'يجب تسجيل الدخول أولاً' : 'You must log in first',
      isError: true,
    );
  }

  Future<void> _onGuestSubmitOfferTap() async {
    final choice = await showGuestHomeOfferGateSheet(
      context: context,
      isAr: widget.isAr,
    );
    if (!mounted) return;
    if (choice == GuestHomeOfferGateResult.login) {
      await Navigator.of(context).pushNamed('/login');
      return;
    }
    if (choice == GuestHomeOfferGateResult.register) {
      await Navigator.of(context, rootNavigator: true).pushNamed('/register');
      return;
    }
    if (choice == GuestHomeOfferGateResult.payOnce) {
      final paid = await runGuestOneTimePaymentFlow(
        context: context,
        isAr: widget.isAr,
        unlockKind: 'offer',
      );
      if (!paid || !mounted) return;
      final up = await GuestSessionBridge.tryEstablishBrowsingUser(
        sb: Supabase.instance.client,
        appSession: context.read<AppSession>(),
      );
      if (!mounted) return;
      if (up) {
        await GuestUnlockService.clear();
        if (mounted) Navigator.of(context).pop();
      } else {
        await GuestUnlockService.clear();
        _snack(
          widget.isAr
              ? 'فعّل تسجيل الدخول المجهول في Supabase أو أنشئ حساباً.'
              : 'Enable anonymous sign-in in Supabase or create an account.',
          isError: true,
        );
      }
    }
  }

  Widget _guestParticipationBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 10,
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SafeArea(
          top: false,
          child: FilledButton.icon(
            onPressed: () => unawaited(_onGuestSubmitOfferTap()),
            icon: const Icon(Icons.local_offer_outlined),
            label: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
          ),
        ),
      ),
    );
  }

  Widget _buyerCompleteDealBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 10,
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SafeArea(
          top: false,
          child: FilledButton.icon(
            onPressed: _loadingBuyerDealAccess
                ? null
                : () async {
                    final fn = widget.onCompleteDeal;
                    if (fn == null) return;
                    await fn(_property);
                    if (!mounted) return;
                    await _loadBuyerDealAccess();
                  },
            icon: _loadingBuyerDealAccess
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: AppLogoLoading(compact: true, size: 20),
                  )
                : const Icon(Icons.handshake_outlined),
            label: Text(widget.isAr ? 'إتمام الصفقة' : 'Complete deal'),
          ),
        ),
      ),
    );
  }

  Future<void> _openChatWithMarketer() async {
    if (_isGuest) {
      _snackLoginRequired();
      return;
    }
    if (!_canOpenMarketerChat) {
      _snack(
        widget.isAr
            ? 'لا يوجد مسوّق مسؤول عن هذا الإعلان للمراسلة بعد.'
            : 'No marketer is assigned for this listing yet.',
        isError: true,
      );
      return;
    }
    if (_isPublicBuyerOnPublishedListing) {
      if (!_viewerInCartForListing) {
        _snack(
          widget.isAr
              ? 'أكمل الصفقة أولاً (أضف الإعلان إلى صفقاتك) ثم يمكنك مراسلة المسوّق.'
              : 'Complete the deal first (add to My deals), then you can message the marketer.',
          isError: true,
        );
        return;
      }
      if (!await SubscriptionGateHelper.ensure(
        context,
        isAr: widget.isAr,
        action: SubscriptionGateAction.completeMarketDeal,
        onGoSubscribe: () {
          if (!mounted) return;
          final lang = widget.isAr ? 'ar' : 'en';
          unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                settings: const RouteSettings(
                  name: '/propertyDetails/subscriptions',
                ),
                builder: (_) => SubscriptionsRootScreen(
                  lang: lang,
                  accountType: '',
                  embedAppBar: true,
                  marketOfferPlansOnly: true,
                ),
              ),
            ),
          );
        },
      )) {
        return;
      }
      if (!mounted) return;
      await _loadBuyerDealAccess();
      if (!mounted || !_publicBuyerMayChatMarketer) return;
    }
    if (_openingChat) return;

    setState(() => _openingChat = true);

    try {
      final conversationId =
          await ReservationsService.getOrCreatePropertyConversation(
        propertyId: _property.id,
        title: _property.title,
      );

      if (!mounted) return;

      await Navigator.push<void>(
        context,
        ChatNavigation.materialRoute(
          isAr: widget.isAr,
          conversationId: conversationId,
          propertyId: _property.id,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      _snack(
        widget.isAr
            ? 'تعذر فتح الدردشة مع المسوّق'
            : 'Failed to open chat with the marketer',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _openingChat = false);
      }
    }
  }

  Future<void> _openChatWithListingOwner() async {
    if (_isGuest) {
      _snackLoginRequired();
      return;
    }
    if (!_canOpenListingOwnerChat) {
      _snack(
        widget.isAr
            ? 'لا يمكن فتح محادثة المالك في هذه المرحلة.'
            : 'Owner chat is not available at this stage.',
        isError: true,
      );
      return;
    }
    if (_openingChat) return;

    setState(() => _openingChat = true);

    try {
      final conversationId =
          await ReservationsService.getOrCreatePropertyOwnerConversation(
        propertyId: _property.id,
        title: _property.title,
      );

      if (!mounted) return;

      await Navigator.push<void>(
        context,
        ChatNavigation.materialRoute(
          isAr: widget.isAr,
          conversationId: conversationId,
          propertyId: _property.id,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      _snack(
        widget.isAr
            ? 'تعذر فتح الدردشة مع المالك'
            : 'Failed to open chat with the owner',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _openingChat = false);
      }
    }
  }

  Future<void> _handleEditProperty() async {
    if (!_isOwnerManager || widget.onEditProperty == null) return;
    if (_runningOwnerAction) return;
    if (!ListingEditPermissions.ownerMayEditListingBody(_property)) {
      _snack(
        widget.isAr
            ? 'لا يمكن تعديل الإعلان بعد انتقاله إلى مرحلة التصاريح أو بعد نشره.'
            : 'This listing can no longer be edited after permits or once published.',
        isError: true,
      );
      return;
    }

    setState(() => _runningOwnerAction = true);

    try {
      final updated = await widget.onEditProperty!(_property);
      if (updated != null && mounted) {
        setState(() {
          _property = updated;
          lat = updated.latitude ?? lat;
          lng = updated.longitude ?? lng;
          _imgIndex = 0;
        });
        await _loadDeleteMeta();
        await _loadAuctionBidsIfNeeded();
      }
    } finally {
      if (mounted) {
        setState(() => _runningOwnerAction = false);
      }
    }
  }

  Future<void> _handleMarketerRegaAlignEdit() async {
    if (widget.onMarketerRegaAlignEdit == null) return;
    if (_runningOwnerAction) return;
    if (!ListingEditPermissions.marketerMayAlignWithRega(
      _property,
      widget.currentUserId,
    )) {
      _snack(
        widget.isAr
            ? 'التعديل متاح فقط بعد إصدار التصريح وقبل النشر، وللمسوّق المرتبط بالإعلان.'
            : 'Editing is only available after the permit is issued, before publish, for the assigned marketer.',
        isError: true,
      );
      return;
    }

    setState(() => _runningOwnerAction = true);

    try {
      final updated = await widget.onMarketerRegaAlignEdit!(_property);
      if (updated != null && mounted) {
        setState(() {
          _property = updated;
          lat = updated.latitude ?? lat;
          lng = updated.longitude ?? lng;
          _imgIndex = 0;
        });
        await _loadDeleteMeta();
        await _loadAuctionBidsIfNeeded();
      }
    } finally {
      if (mounted) {
        setState(() => _runningOwnerAction = false);
      }
    }
  }

  Future<void> _handleDeleteRequest() async {
    if (!_isOwnerManager || widget.onRequestDelete == null) return;
    if (_runningOwnerAction) return;

    setState(() => _runningOwnerAction = true);

    try {
      final ok = await widget.onRequestDelete!(_property);
      if (ok && mounted) {
        await _loadDeleteMeta();
      }
    } finally {
      if (mounted) {
        setState(() => _runningOwnerAction = false);
      }
    }
  }

  String _formatNumber(num value) {
    final s = value.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  String get _currencyCode =>
      _property.currency.trim().isEmpty ? 'SAR' : _property.currency.trim();

  /// للنصوص المشتركة (مثل المشاركة) — رمز يونيكود للعربية عند SAR.
  String get _currencySymbol {
    final c = _currencyCode;
    if (!widget.isAr) return c;
    if (c.toUpperCase() == 'SAR') return AppMoney.saudiRiyalSignUnicode;
    return c;
  }

  /// السعر المُدخل من المعلن (أو المزايدة الحالية في المزاد) قبل أي حساب.
  double get _enteredPrice {
    final p = _property.price.toDouble();
    final bid = (_property.currentBid ?? p).toDouble();
    return _property.isAuction ? bid : p;
  }

  /// تفاصيل الفاتورة المطابقة لـ ZATCA / REGA — مشتقة من بيانات العقار المخزّنة.
  ListingInvoiceModel get _invoice => ListingInvoiceModel(
        enteredPrice: _enteredPrice,
        priceIncludesVat: _property.priceIncludesVat,
        vatRate: _property.vatRate,
        commissionKind: _property.marketingCommissionKind,
        commissionRate: _property.marketingCommissionRate,
        commissionAmount: _property.marketingCommissionAmount,
        currencyCode: _currencyCode,
      );

  /// السعر الأساسي قبل الضريبة (يستحقّه البائع).
  double get _basePrice => _invoice.basePrice;
  double get _vatAmount => _invoice.vatAmount;
  double get _platformFee => _invoice.commissionTotal;
  double get _totalAfterVat => _invoice.totalWithVat;
  double get _finalTotal => _invoice.finalTotal;

  String get _licensedMarketerPhone =>
      _licenseField('rega_ad_responsible_mobile');

  String get _shareText {
    final coordsText = (lat != null && lng != null)
        ? '\n📍 ${widget.isAr ? 'الإحداثيات:' : 'Coordinates:'} ${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
        : '';
    final licPh = _licensedMarketerPhone;
    final licLine = licPh.isNotEmpty
        ? '\n📞 ${widget.isAr ? 'تواصل المسوّق (بيانات ترخيص الهيئة):' : 'Marketer (REGA license):'} $licPh'
        : '';

    final vatNote = _property.priceIncludesVat
        ? (widget.isAr ? 'محتسبة ضمن المبلغ' : 'included in total')
        : (widget.isAr ? 'مضافة على المبلغ' : 'added on top');
    final commissionLine = _platformFee > 0
        ? '\n🌐 ${widget.isAr ? 'عمولة التسويق:' : 'Marketing commission:'} ${_formatNumber(_platformFee)} $_currencySymbol'
        : '';
    return '''
🏡 ${_property.title}
📍 ${widget.isAr ? 'الموقع:' : 'Location:'} ${_property.locationText}
$licLine
💰 ${widget.isAr ? 'السعر الأساسي:' : 'Base price:'} ${_formatNumber(_basePrice)} $_currencySymbol
🧾 ${widget.isAr ? 'الضريبة (5%) — $vatNote:' : 'VAT (5%) — $vatNote:'} ${_formatNumber(_vatAmount)} $_currencySymbol
✅ ${widget.isAr ? 'الإجمالي مع الضريبة:' : 'Total with VAT:'} ${_formatNumber(_totalAfterVat)} $_currencySymbol$commissionLine
🏁 ${widget.isAr ? 'المجموع النهائي:' : 'Final total:'} ${_formatNumber(_finalTotal)} $_currencySymbol$coordsText

#Aqar #${widget.isAr ? 'عقار' : 'RealEstate'}
''';
  }

  Future<void> _loadAuctionSession() async {
    if (!_property.isAuction || !_isPublishedLikeListing) return;
    if (mounted) setState(() => _loadingAuctionSession = true);
    try {
      final row = await PropertyAuctionService.fetchOpenSession(_property.id);
      if (!mounted) return;
      setState(() {
        _loadingAuctionSession = false;
        _openAuctionSession = row;
      });
      _armAuctionSessionTicker();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAuctionSession = false;
        _openAuctionSession = null;
      });
    }
  }

  Future<void> _loadPlatformStaff() async {
    if (_isGuest || widget.currentUserId.trim().isEmpty) {
      if (mounted) setState(() => _platformStaff = false);
      return;
    }
    try {
      final row = await _sb
          .from('users_profiles')
          .select('platform_staff')
          .eq('user_id', widget.currentUserId.trim())
          .maybeSingle();
      final v = row?['platform_staff'];
      final ok = v == true || '${v ?? ''}'.toLowerCase() == 'true';
      if (mounted) setState(() => _platformStaff = ok);
    } catch (_) {
      if (mounted) setState(() => _platformStaff = false);
    }
  }

  Future<void> _loadPaymentEvents() async {
    if (!_property.isAuction || !_isPublishedLikeListing) return;
    if (mounted) setState(() => _loadingPaymentEvents = true);
    try {
      final rows = await ListingPaymentService.fetchEventsForProperty(
          _property.id,
          limit: 12);
      if (!mounted) return;
      setState(() {
        _paymentEvents = rows;
        _loadingPaymentEvents = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPaymentEvents = false);
    }
  }

  void _armAuctionSessionTicker() {
    _auctionSessionTick?.cancel();
    _auctionSessionTick = null;
    if (!_property.isAuction || !_isPublishedLikeListing) return;
    final s = _openAuctionSession;
    if (s == null) return;
    final e = s['ends_at'];
    if (e == null) return;
    final dt = DateTime.tryParse(e.toString());
    if (dt == null) return;
    if (!dt.toUtc().isAfter(DateTime.now().toUtc())) return;
    _auctionSessionTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final endRaw = _openAuctionSession?['ends_at']?.toString();
      final end = endRaw != null ? DateTime.tryParse(endRaw) : null;
      if (end == null) {
        _auctionSessionTick?.cancel();
        _auctionSessionTick = null;
        return;
      }
      if (!end.toUtc().isAfter(DateTime.now().toUtc())) {
        _auctionSessionTick?.cancel();
        _auctionSessionTick = null;
      }
      setState(() {});
    });
  }

  String _formatAuctionCountdown(Duration d) {
    if (d.isNegative) {
      return widget.isAr ? 'انتهى الوقت' : 'Time ended';
    }
    final days = d.inDays;
    final h = d.inHours.remainder(24);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (widget.isAr) {
      final parts = <String>[];
      if (days > 0) parts.add('$days يوم');
      if (days > 0 || h > 0) parts.add('$h ساعة');
      parts.add('$m د $s ث');
      return parts.join(' ');
    }
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (days > 0 || h > 0) parts.add('${h}h');
    parts.add('${m}m ${s}s');
    return parts.join(' ');
  }

  Duration? _remainingUntilSessionEnd() {
    final raw = _openAuctionSession?['ends_at']?.toString();
    if (raw == null) return null;
    final end = DateTime.tryParse(raw);
    if (end == null) return null;
    return end.toUtc().difference(DateTime.now().toUtc());
  }

  Future<void> _openAuctionSessionDialog() async {
    if (!_canManageAuctionSession) return;
    var useDeadline = true;
    var endAt = DateTime.now().add(const Duration(days: 1));
    final minCtrl = TextEditingController(text: '100');
    var capturedMinText = '100';

    bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                title: Text(
                  widget.isAr ? 'بدء جلسة مزاد' : 'Start auction session',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          widget.isAr ? 'تحديد وقت انتهاء' : 'Set end time',
                        ),
                        value: useDeadline,
                        onChanged: (v) => setLocal(() => useDeadline = v),
                      ),
                      if (useDeadline) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            widget.isAr ? 'ينتهي في' : 'Ends at',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            _fmtDateTime(endAt.toLocal()),
                            style: TextStyle(
                                color: Theme.of(ctx).colorScheme.primary),
                          ),
                          trailing: const Icon(Icons.event_outlined),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: endAt,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365 * 2)),
                            );
                            if (d == null || !ctx.mounted) return;
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(endAt),
                            );
                            if (t == null || !ctx.mounted) return;
                            setLocal(() {
                              endAt = DateTime(
                                  d.year, d.month, d.day, t.hour, t.minute);
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      AqarTextField(
                        controller: minCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: widget.isAr
                              ? 'الحد الأدنى للزيادة (${AppMoney.saudiRiyalSignUnicode}) — اختياري'
                              : 'Min increment (SAR) — optional',
                          border: const OutlineInputBorder(),
                          helperText: widget.isAr
                              ? 'اتركه 100 للافتراضي من الخادم'
                              : 'Leave as 100 for server default',
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(widget.isAr ? 'بدء' : 'Start'),
                  ),
                ],
              );
            },
          );
        },
      );
      capturedMinText = minCtrl.text;
    } finally {
      minCtrl.dispose();
    }

    if (ok != true || !mounted) return;

    double? minInc;
    final minParsed = double.tryParse(
      capturedMinText.trim().replaceAll(',', ''),
    );
    if (minParsed != null && minParsed >= 1) {
      minInc = minParsed;
    }

    setState(() => _openingAuctionSession = true);
    try {
      await PropertyAuctionService.openAuctionSession(
        propertyId: _property.id,
        endsAt: useDeadline ? endAt : null,
        minIncrementSar: minInc,
      );
      if (!mounted) return;
      await _loadAuctionSession();
      _snack(
        widget.isAr ? 'تم فتح جلسة المزاد' : 'Auction session started',
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = PropertyAuctionService.userFacingErrorMessage(
        e,
        isAr: widget.isAr,
      );
      _snack(
        msg ?? e.message,
        isError: true,
      );
    } catch (e) {
      if (mounted) {
        _snack(e.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _openingAuctionSession = false);
    }
  }

  Future<void> _closeAuctionSessionConfirmed() async {
    if (!_canManageAuctionSession) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.isAr ? 'إغلاق جلسة المزاد؟' : 'Close auction session?',
        ),
        content: Text(
          widget.isAr
              ? 'لن يُقبل مزايدات جديدة وفق وقت/حالة الجلسة في الخادم.'
              : 'New bids follow server rules for session state.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(widget.isAr ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _closingAuctionSession = true);
    try {
      await PropertyAuctionService.closeAuctionSession(_property.id);
      if (!mounted) return;
      await _loadAuctionSession();
      _snack(
        widget.isAr ? 'تم إغلاق الجلسة' : 'Session closed',
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = PropertyAuctionService.userFacingErrorMessage(
        e,
        isAr: widget.isAr,
      );
      _snack(msg ?? e.message, isError: true);
    } catch (e) {
      if (mounted) _snack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _closingAuctionSession = false);
    }
  }

  Widget _buildAuctionSessionPanel(ColorScheme cs) {
    if (_loadingAuctionSession) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const AppLogoLoading(compact: true, size: 22),
            const SizedBox(width: 10),
            Text(
              widget.isAr
                  ? 'جاري تحميل جلسة المزاد…'
                  : 'Loading auction session…',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final session = _openAuctionSession;
    if (session == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.isAr
                ? 'لا توجد جلسة مزاد «مفتوحة» مسجّلة. يمكن للمالك أو المسوّق المنشّر أو مشرف المنصة بدء جلسة؛ وإلا تبقى المزايدة وفق سياسة الخادم الحالية.'
                : 'No open session. Owner, publishing marketer, or platform staff can start one; otherwise server rules apply.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
          ),
          if (_canManageAuctionSession) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _openingAuctionSession
                  ? null
                  : () => unawaited(_openAuctionSessionDialog()),
              icon: _openingAuctionSession
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: AppLogoLoading(compact: true, size: 18),
                    )
                  : const Icon(Icons.play_circle_outline),
              label: Text(
                widget.isAr ? 'بدء جلسة مزاد' : 'Start auction session',
              ),
            ),
          ],
        ],
      );
    }

    final rem = _remainingUntilSessionEnd();
    final endedByTime = _auctionSessionTimeEnded;
    final minIncRaw = session['min_increment_sar'];
    final minInc = minIncRaw is num
        ? minIncRaw.toDouble()
        : double.tryParse('${minIncRaw ?? ''}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, color: cs.primary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.isAr ? 'جلسة المزاد' : 'Auction session',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Text(
                widget.isAr ? 'نشطة' : 'Open',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Colors.green.shade900,
                ),
              ),
            ),
          ],
        ),
        if (rem != null) ...[
          const SizedBox(height: 8),
          Text(
            endedByTime
                ? (widget.isAr
                    ? 'انتهى وقت الجلسة المحدد — لا يُقبل مزايدات جديدة.'
                    : 'The scheduled session time has ended — no new bids.')
                : (widget.isAr
                    ? 'الوقت المتبقي: ${_formatAuctionCountdown(rem)}'
                    : 'Time left: ${_formatAuctionCountdown(rem)}'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: endedByTime ? cs.error : cs.primary,
              height: 1.3,
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            widget.isAr
                ? 'جلسة مفتوحة بدون وقت انتهاء محدد في السجل.'
                : 'Open session with no fixed end time in the record.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
          ),
        ],
        if (minInc != null && minInc > 0) ...[
          const SizedBox(height: 6),
          Text(
            widget.isAr
                ? 'الحد الأدنى للزيادة المسجّل للجلسة: ${_formatNumber(minInc)} $_currencySymbol (الخادم يحدّد خطوة المزايدة الفعلية حسب السياسة الحالية).'
                : 'Session min. increment on file: ${_formatNumber(minInc)} $_currencySymbol (server applies its bid-step rules).',
            style: TextStyle(
                fontSize: 12, color: cs.onSurfaceVariant, height: 1.35),
          ),
        ],
        if (_canManageAuctionSession) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _closingAuctionSession
                ? null
                : () => unawaited(_closeAuctionSessionConfirmed()),
            icon: _closingAuctionSession
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: AppLogoLoading(compact: true, size: 16),
                  )
                : const Icon(Icons.stop_circle_outlined),
            label: Text(
              widget.isAr ? 'إغلاق الجلسة' : 'Close session',
            ),
          ),
        ],
      ],
    );
  }

  String _paymentKindLabelUi(String raw) {
    if (!widget.isAr) return raw;
    return switch (raw) {
      'auction_escrow_hold' => 'عربون/ضمان مزاد',
      'bidder_good_faith' => 'نية عربون (مشتري)',
      'marketer_service_fee' => 'رسوم خدمة تسويق',
      'platform_fee' => 'رسوم منصة',
      'manual_ledger' => 'تسجيل يدوي',
      'other' => 'أخرى',
      _ => raw,
    };
  }

  Future<void> _showRegisterPaymentDialog({required bool buyerOnly}) async {
    if (buyerOnly && !_canRecordBuyerGoodFaith) return;
    if (!buyerOnly && !_canRecordPaymentAsPrivileged) return;

    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var kind = buyerOnly ? 'bidder_good_faith' : 'auction_escrow_hold';
    var provider = 'manual';

    final kindsPrivileged = <String>[
      'auction_escrow_hold',
      'marketer_service_fee',
      if (_platformStaff) 'platform_fee',
      'manual_ledger',
      'other',
    ];

    bool? ok;
    var capturedAmount = '';
    var capturedNotes = '';
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                title: Text(
                  buyerOnly
                      ? (widget.isAr
                          ? 'تسجيل نية عربون'
                          : 'Record good-faith deposit')
                      : (widget.isAr
                          ? 'تسجيل حدث دفع/ضمان'
                          : 'Record payment / escrow'),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!buyerOnly)
                        DropdownButtonFormField<String>(
                          value: kind,
                          decoration: InputDecoration(
                            labelText: widget.isAr ? 'نوع الحدث' : 'Event kind',
                          ),
                          items: kindsPrivileged
                              .map(
                                (k) => DropdownMenuItem(
                                  value: k,
                                  child: Text(_paymentKindLabelUi(k)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setLocal(() => kind = v);
                          },
                        ),
                      if (!buyerOnly) const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: provider,
                        decoration: InputDecoration(
                          labelText: widget.isAr ? 'البوابة' : 'Provider',
                          helperText: widget.isAr
                              ? 'Stripe: يفتح صفحة دفع بعد التسجيل. Moyasar: يُكمَل من الخادم.'
                              : 'Stripe opens checkout after save. Moyasar: complete server-side.',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'manual',
                            child: Text(widget.isAr
                                ? 'يدوي / تحويل'
                                : 'Manual / transfer'),
                          ),
                          DropdownMenuItem(
                            value: 'stripe',
                            child: Text('Stripe'),
                          ),
                          DropdownMenuItem(
                            value: 'moyasar',
                            child: Text('Moyasar'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => provider = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      AqarTextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: widget.isAr
                              ? 'المبلغ (${AppMoney.saudiRiyalSignUnicode})'
                              : 'Amount (SAR)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      AqarTextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: widget.isAr
                              ? 'ملاحظات (اختياري)'
                              : 'Notes (optional)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(widget.isAr ? 'حفظ' : 'Save'),
                  ),
                ],
              );
            },
          );
        },
      );
      capturedAmount = amountCtrl.text;
      capturedNotes = notesCtrl.text;
    } finally {
      amountCtrl.dispose();
      notesCtrl.dispose();
    }

    if (ok != true || !mounted) return;

    final amt = double.tryParse(capturedAmount.trim().replaceAll(',', ''));
    if (amt == null || amt <= 0) {
      _snack(
        widget.isAr ? 'أدخل مبلغاً صحيحاً' : 'Enter a valid amount',
        isError: true,
      );
      return;
    }

    final sessId = (_openAuctionSession?['id'] ?? '').toString().trim();
    setState(() => _recordingPaymentEvent = true);
    try {
      final id = await ListingPaymentService.registerEvent(
        propertyId: _property.id,
        kind: kind,
        provider: provider,
        amountSar: amt,
        auctionSessionId: sessId.isEmpty ? null : sessId,
        escrowNotes: capturedNotes.trim().isEmpty ? null : capturedNotes.trim(),
      );
      if (!mounted) return;
      if (id == null) {
        _snack(
          widget.isAr ? 'تعذّر التسجيل' : 'Could not save',
          isError: true,
        );
        return;
      }
      await _loadPaymentEvents();
      _snack(widget.isAr ? 'تم تسجيل الحدث' : 'Event recorded');
      if (provider == 'stripe' && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(widget.isAr ? 'متابعة الدفع؟' : 'Open checkout?'),
            content: Text(
              widget.isAr
                  ? 'سيتم فتح صفحة Stripe في المتصفح (عند تفعيل المفتاح في الخادم).'
                  : 'Opens Stripe Checkout in the browser when the server secret is set.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(widget.isAr ? 'لاحقاً' : 'Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(widget.isAr ? 'متابعة' : 'Continue'),
              ),
            ],
          ),
        );
        if (go == true && mounted) {
          final r = await ListingPaymentService.openStripeCheckoutIfAvailable(
            paymentEventId: id,
          );
          _snack(
            widget.isAr ? r.messageAr : r.messageEn,
            isError: !r.ok,
          );
          if (mounted) await _loadPaymentEvents();
        }
      } else if (provider == 'moyasar' && mounted) {
        _snack(
          widget.isAr
              ? 'سجّلنا الحدث بحالة «في انتظار البوابة». أكمل دمج Moyasar في Edge Function.'
              : 'Recorded as pending gateway. Complete Moyasar in the Edge Function.',
        );
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = ListingPaymentService.userFacingRegisterError(
        e,
        isAr: widget.isAr,
      );
      _snack(msg ?? e.message, isError: true);
    } catch (e) {
      if (mounted) _snack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _recordingPaymentEvent = false);
    }
  }

  Widget _buildListingPaymentsSection(ColorScheme cs) {
    if (!_property.isAuction || !_isPublishedLikeListing) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.isAr
                    ? 'المدفوعات والعربون (السجل)'
                    : 'Payments & escrow (ledger)',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.isAr
              ? 'سجل تدقيق للعربون والضمان والرسوم. التحصيل الفعلي عبر بوابة معتمدة (Stripe دولياً، Moyasar/مدى محلياً) بعد ضبط الأسرار في Supabase. المسوّق غير المنشّر لا يُسجّل هنا لهذا الإعلان.'
              : 'Audit trail for deposits and fees. Actual collection uses a licensed gateway (Stripe international; Moyasar/Mada locally) once secrets are set. Non-publishing marketers cannot record here.',
          style: TextStyle(
              fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.35),
        ),
        if (_canRecordPaymentAsPrivileged || _canRecordBuyerGoodFaith) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_canRecordPaymentAsPrivileged)
                FilledButton.icon(
                  onPressed: _recordingPaymentEvent
                      ? null
                      : () => unawaited(
                          _showRegisterPaymentDialog(buyerOnly: false)),
                  icon: _recordingPaymentEvent
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: AppLogoLoading(compact: true, size: 16),
                        )
                      : const Icon(Icons.add_chart_outlined),
                  label: Text(
                    widget.isAr
                        ? 'تسجيل حدث (مالك/منشّر/مشرف)'
                        : 'Record (owner/publisher/staff)',
                  ),
                ),
              if (_canRecordBuyerGoodFaith)
                OutlinedButton.icon(
                  onPressed: _recordingPaymentEvent
                      ? null
                      : () => unawaited(
                          _showRegisterPaymentDialog(buyerOnly: true)),
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(
                    widget.isAr ? 'نية عربون مشتري' : 'Buyer deposit intent',
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (_loadingPaymentEvents)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: AppLogoLoading(compact: true, size: 24),
            ),
          )
        else if (_paymentEvents.isEmpty)
          Text(
            widget.isAr
                ? 'لا توجد أحداث مسجّلة بعد.'
                : 'No recorded events yet.',
            style: TextStyle(color: cs.onSurfaceVariant),
          )
        else
          ..._paymentEvents.map((row) {
            final id = (row['id'] ?? '').toString();
            final kind = (row['kind'] ?? '').toString();
            final st = (row['status'] ?? '').toString();
            final prov = (row['provider'] ?? '').toString();
            final role = (row['recorded_as_role'] ?? '').toString();
            final amtRaw = row['amount_sar'];
            final amt = amtRaw is num
                ? amtRaw.toDouble()
                : double.tryParse('${amtRaw ?? ''}') ?? 0;
            final created = row['created_at']?.toString() ?? '';
            final dt = DateTime.tryParse(created);
            final timeStr = dt != null ? _fmtDateTime(dt.toLocal()) : created;
            final mine = (row['initiator_id'] ?? '').toString() ==
                widget.currentUserId.trim();
            final pendingStripe =
                mine && prov == 'stripe' && st == 'pending_gateway';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _paymentKindLabelUi(kind),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '${_formatNumber(amt)} $_currencySymbol',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.isAr ? 'الحالة:' : 'Status:'} $st · ${widget.isAr ? 'الدور:' : 'Role:'} $role · $prov',
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      Text(
                        timeStr,
                        style:
                            TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      if (pendingStripe)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () async {
                              final r = await ListingPaymentService
                                  .openStripeCheckoutIfAvailable(
                                paymentEventId: id,
                              );
                              if (!mounted) return;
                              _snack(
                                widget.isAr ? r.messageAr : r.messageEn,
                                isError: !r.ok,
                              );
                              await _loadPaymentEvents();
                            },
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Text(
                              widget.isAr
                                  ? 'دفع عبر Stripe'
                                  : 'Pay with Stripe',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAuctionBidsCard(ColorScheme cs) {
    final opening = _property.currentBid ?? _property.price;
    final openNum = opening.toDouble();
    final nextMin = PropertyAuctionService.minimumNextBid(openNum);
    final inc = PropertyAuctionService.suggestedMinimumIncrement(openNum);
    final sessionBlocksBid =
        _openAuctionSession != null && _auctionSessionTimeEnded;
    final canBid = !_isGuest &&
        !_isListingOwner &&
        !_isPublishingMarketer &&
        !sessionBlocksBid;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_outlined, color: Colors.orange.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.isAr ? 'المزايدة' : 'Bidding',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildAuctionSessionPanel(cs),
          _buildListingPaymentsSection(cs),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isAr ? 'أعلى مزايدة حالية' : 'Current high bid',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              AppMoneyLine(
                amount: openNum,
                currencyCode: 'SAR',
                isAr: widget.isAr,
                maxFractionDigits: 0,
                symbolColor: Colors.orange.shade800,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.orange.shade900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isAr
                    ? 'الحد الأدنى للمزايدة التالية (زيادة ≥ ${_formatNumber(inc)}):'
                    : 'Minimum next bid (increment ≥ ${_formatNumber(inc)}):',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 4),
              AppMoneyLine(
                amount: nextMin,
                currencyCode: 'SAR',
                isAr: widget.isAr,
                maxFractionDigits: 0,
                symbolColor: Colors.orange.shade800,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          if (canBid) ...[
            const SizedBox(height: 12),
            AqarTextField(
              controller: _bidAmountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: widget.isAr ? 'مبلغ المزايدة' : 'Your bid amount',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _placingBid ? null : _submitPropertyBid,
              icon: _placingBid
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: AppLogoLoading(
                        compact: true,
                        size: 18,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
              label: Text(widget.isAr ? 'إرسال المزايدة' : 'Submit bid'),
            ),
          ] else if (_isGuest) ...[
            const SizedBox(height: 8),
            Text(
              widget.isAr ? 'سجّل الدخول للمزايدة' : 'Sign in to bid',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              widget.isAr
                  ? 'عرض السجل فقط (المالك/المسوّق المنشّر لا يمزايدان)'
                  : 'View only (owner / publishing marketer cannot bid)',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            widget.isAr ? 'آخر المزايدات' : 'Recent bids',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (_loadingAuctionBids)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: AppLogoLoading(compact: true, size: 28),
              ),
            )
          else if (_auctionBids.isEmpty)
            Text(
              widget.isAr ? 'لا توجد مزايدات مسجّلة بعد' : 'No bids yet',
              style: TextStyle(color: cs.onSurfaceVariant),
            )
          else
            ..._auctionBids.asMap().entries.map((e) {
              final idx = e.key;
              final row = e.value;
              final rank = idx + 1;
              final rawAmt = row['amount'];
              final amt = rawAmt is num
                  ? rawAmt.toDouble()
                  : double.tryParse('${rawAmt ?? ''}') ?? 0;
              final created = row['created_at']?.toString() ?? '';
              final dt = DateTime.tryParse(created);
              final timeStr = dt != null ? _fmtDateTime(dt.toLocal()) : created;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Color.alphaBlend(
                    Colors.orange.withValues(alpha: 0.08),
                    cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Colors.orange.shade800.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              Colors.orange.shade100.withValues(alpha: 0.9),
                          child: Text(
                            '$rank',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isAr ? 'مزايد $rank' : 'Bidder $rank',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              AppMoneyLine(
                                amount: amt,
                                currencyCode: 'SAR',
                                isAr: widget.isAr,
                                maxFractionDigits: 0,
                                symbolColor: Colors.orange.shade800,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(
    String text, {
    String? successMessage,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    _snack(successMessage ?? (widget.isAr ? 'تم النسخ' : 'Copied'));
  }

  Future<void> _hideListingFromHomeFeed() async {
    await UserListingPreferencesService.addHiddenProperty(_property.id);
    if (!mounted) return;
    widget.onVisitorListingPreferenceChanged?.call();
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _snack(l10n.propertyDetailsHiddenFromYourHomeSnack);
    }
  }

  Future<void> _restoreListingToHomeFeed() async {
    await UserListingPreferencesService.removeHiddenProperty(_property.id);
    if (!mounted) return;
    widget.onVisitorListingPreferenceChanged?.call();
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _snack(l10n.propertyDetailsShownOnHomeAgainSnack);
    }
  }

  Future<void> _withdrawMyPendingReport() async {
    await UserListingPreferencesService.withdrawPendingPropertyReport(
      _sb,
      _property.id,
    );
    if (!mounted) return;
    widget.onVisitorListingPreferenceChanged?.call();
    final l10n = AppLocalizations.of(context);
    if (l10n != null) {
      _snack(l10n.propertyDetailsReportWithdrawnSnack);
    }
  }

  Future<void> _openListingReportSheet() async {
    await showPropertyListingReportSheet(
      context,
      sb: _sb,
      property: _property,
      onDone: widget.onVisitorListingPreferenceChanged,
    );
    if (mounted) widget.onVisitorListingPreferenceChanged?.call();
  }

  Future<void> _openSystemShare() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final subject = widget.isAr
          ? 'إعلان عقار — ${_property.title}'
          : 'Property listing — ${_property.title}';
      await shareListingRich(
        text: _shareBodyWithLinkAndBrand,
        imageHttpUrl: _shareImageUrlForRichShare,
        subject: subject,
      );
    } catch (e) {
      if (mounted) {
        _snack(e.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  bool get _hasVideo => (_property.videoUrl ?? '').trim().isNotEmpty;

  Future<void> _openVideoSheet() async {
    if (!_hasVideo || _openingVideo) return;

    setState(() => _openingVideo = true);
    try {
      final raw = _property.videoUrl!.trim();
      final url = _resolveVideoPlayableUrl(raw);
      if (url.isEmpty) return;

      await PropertyVideoSheet.open(
        context,
        isAr: widget.isAr,
        title: _property.title,
        videoUrl: url,
      );
    } finally {
      if (mounted) {
        setState(() => _openingVideo = false);
      }
    }
  }

  Widget _buildOwnerManageCard() {
    final cs = Theme.of(context).colorScheme;
    final busy = _runningOwnerAction || _loadingDeleteMeta;
    final canOwnerEditBody =
        ListingEditPermissions.ownerMayEditListingBody(_property);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.manage_accounts_outlined,
                color: const Color(0xFF0F766E),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.isAr ? 'إدارة الإعلان' : 'Manage listing',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_deleteRequested) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withOpacity(0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _deleteApproved
                        ? (widget.isAr
                            ? 'تمت الموافقة على طلب الحذف'
                            : 'Deletion request approved')
                        : (widget.isAr
                            ? 'طلب الحذف قيد مراجعة الإدارة'
                            : 'Deletion request is under admin review'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_deleteRequestedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.isAr
                          ? 'تاريخ الطلب: ${_fmtDateTime(_deleteRequestedAt!)}'
                          : 'Requested at: ${_fmtDateTime(_deleteRequestedAt!)}',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if ((_deleteRequestReason ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.isAr
                          ? 'سبب الحذف: $_deleteRequestReason'
                          : 'Deletion reason: $_deleteRequestReason',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (!_deleteApproved) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.isAr
                          ? 'لن يتم حذف الإعلان إلا بعد موافقة الإدارة.'
                          : 'The listing will not be deleted until admin approval.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (!canOwnerEditBody) ...[
            Text(
              widget.isAr
                  ? 'التعديل متاح حتى قبل مرحلة إصدار التصاريح، وبحد أقصى 3 تعديلات حسب النظام.'
                  : 'Editing is allowed until the permit stage, with up to 3 edits per policy.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      busy || !canOwnerEditBody ? null : _handleEditProperty,
                  icon: busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: AppLogoLoading(compact: true, size: 20),
                        )
                      : const Icon(Icons.edit_outlined),
                  label: Text(widget.isAr ? 'تعديل' : 'Edit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      busy || _deleteRequested ? null : _handleDeleteRequest,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    _deleteRequested
                        ? (widget.isAr ? 'تم إرسال الطلب' : 'Request sent')
                        : (widget.isAr ? 'طلب حذف' : 'Request delete'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error.withOpacity(0.45)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMarketerRegaAlignCard() {
    final cs = Theme.of(context).colorScheme;
    final busy = _runningOwnerAction;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.isAr ? 'مطابقة بيانات الهيئة' : 'Align with REGA data',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.isAr
                ? 'بعد إصدار التصريح وقبل النشر يمكنك تعديل الحقول لتتوافق مع بيانات الهيئة العامة للعقار.'
                : 'After the permit is issued and before publish, you may adjust fields to match REGA.',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : _handleMarketerRegaAlignEdit,
            icon: busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: AppLogoLoading(compact: true, size: 20),
                  )
                : const Icon(Icons.edit_note_outlined),
            label: Text(widget.isAr ? 'تعديل للمطابقة' : 'Edit to align'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// قسم الدلائلية من `listing_guidance` (عناصر label/value بالعربية أو الإنجليزية).
  List<Widget> _buildListingGuidanceSection(ColorScheme cs) {
    final g = _property.listingGuidance;
    if (g == null || g.isEmpty) return const [];
    final raw = g['items'];
    if (raw is! List || raw.isEmpty) return const [];

    final children = <Widget>[
      const SizedBox(height: 8),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.explore_outlined, size: 22, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  widget.isAr ? 'دلائلية العقار' : 'Property guidance',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...raw.map<Widget>((e) {
              if (e is! Map) return const SizedBox.shrink();
              final m = Map<String, dynamic>.from(e);
              final label = widget.isAr
                  ? (m['label_ar'] ?? m['label'] ?? '').toString().trim()
                  : (m['label_en'] ?? m['label'] ?? '').toString().trim();
              final value = widget.isAr
                  ? (m['value_ar'] ?? m['value'] ?? '').toString().trim()
                  : (m['value_en'] ?? m['value'] ?? '').toString().trim();
              if (label.isEmpty && value.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label.isNotEmpty)
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                          fontSize: 13,
                        ),
                      ),
                    if (value.isNotEmpty) ...[
                      if (label.isNotEmpty) const SizedBox(height: 4),
                      Text(
                        value,
                        style: TextStyle(
                          height: 1.35,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ];
    return children;
  }

  Widget _buildGallery() {
    final cs = Theme.of(context).colorScheme;
    final imgs = _galleryUrls;
    final videoLead = _videoAsGalleryLead;
    final total = (videoLead ? 1 : 0) + imgs.length;

    if (total == 0) {
      return ColoredBox(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: const BrandingLogoImage(
            fillFrame: true,
            errorIcon: Icons.image_not_supported_outlined,
          ),
        ),
      );
    }

    // صور فقط (بدون فيديو كغلاف): المعرض الموحّد مع أسهم وتكبير.
    if (!videoLead) {
      final idShort = _property.id.trim();
      final wmTrace = idShort.length <= 8
          ? idShort
          : idShort.substring(idShort.length - 8);
      return ListingMediaGallery(
        imageUrls: imgs,
        isAr: widget.isAr,
        aspectRatio: 16 / 9,
        maxHeight: 480,
        borderRadius: 0,
        initialIndex: 0,
        watermark: ListingWatermarkOverlay(
          traceId: wmTrace,
          isAr: widget.isAr,
        ),
      );
    }

    final safeIndex = _imgIndex >= total ? 0 : _imgIndex;
    if (safeIndex != _imgIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _imgIndex = safeIndex);
      });
    }

    final idShort = _property.id.trim();
    final wmTrace =
        idShort.length <= 8 ? idShort : idShort.substring(idShort.length - 8);

    void go(int delta) {
      if (total <= 1) return;
      final next = (_imgIndex + delta).clamp(0, total - 1);
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }

    final frame = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 480),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _page,
              itemCount: total,
              onPageChanged: (i) => setState(() => _imgIndex = i),
              itemBuilder: (_, i) {
                if (videoLead && i == 0) {
                  final raw = _property.videoUrl!.trim();
                  final url = _resolveVideoPlayableUrl(raw);
                  return ClipRect(
                    child: InlinePropertyVideoPlayer(
                      videoUrl: url,
                      isAr: widget.isAr,
                    ),
                  );
                }
                final imgIndex = videoLead ? i - 1 : i;
                final imageUrl = imgs[imgIndex];
                return GestureDetector(
                  onTap: () {
                    // فتح معرض الصور فقط (تخطي شريحة الفيديو).
                    showDialog<void>(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.92),
                      builder: (_) => ListingImageLightbox(
                        urls: imgs,
                        initialIndex: imgIndex.clamp(0, imgs.length - 1),
                        isAr: widget.isAr,
                      ),
                    );
                  },
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: kIsWeb ? 900 : 1400,
                    memCacheHeight: kIsWeb ? 650 : 1000,
                    placeholder: (_, __) => const Center(
                      child: AppLogoLoading(compact: true, size: 40),
                    ),
                    errorWidget: (_, __, error) {
                      debugPrint(
                        'PropertyDetails image load error: $error | url=$imageUrl',
                      );
                      return ColoredBox(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                        child: const Center(
                          child: BrandingLogoImage(
                            fit: BoxFit.contain,
                            errorIcon: Icons.broken_image_outlined,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            ListingWatermarkOverlay(traceId: wmTrace, isAr: widget.isAr),
            PositionedDirectional(
              top: 10,
              start: 10,
              child: _Pill(
                text: '${safeIndex + 1} / $total',
                icon: safeIndex == 0
                    ? Icons.videocam_outlined
                    : Icons.photo_library_outlined,
              ),
            ),
            if (total > 1) ...[
              Positioned(
                left: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => go(-1),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.chevron_left_rounded,
                            color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => go(1),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.chevron_right_rounded,
                            color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: frame,
          ),
          if (total > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  GestureDetector(
                    onTap: () => _page.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: Container(
                      width: 72,
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          width: _imgIndex == 0 ? 2.2 : 1,
                          color: _imgIndex == 0
                              ? const Color(0xFF0F766E)
                              : cs.outlineVariant.withValues(alpha: 0.75),
                        ),
                        color: Colors.black87,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                  ...List.generate(imgs.length, (i) {
                    final pageIndex = i + 1;
                    final selected = pageIndex == _imgIndex;
                    return GestureDetector(
                      onTap: () => _page.animateToPage(
                        pageIndex,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      child: Container(
                        width: 72,
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            width: selected ? 2.2 : 1,
                            color: selected
                                ? const Color(0xFF0F766E)
                                : cs.outlineVariant.withValues(alpha: 0.75),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CachedNetworkImage(
                          imageUrl: imgs[i],
                          fit: BoxFit.cover,
                          memCacheWidth: 220,
                          memCacheHeight: 160,
                          errorWidget: (_, __, ___) => ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openFocusedPropertyMap() async {
    final la = lat ?? _property.latitude;
    final lo = lng ?? _property.longitude;
    if (la == null || lo == null) return;
    final focused = _property.copyWith(latitude: la, longitude: lo);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PropertyMapDiscoveryPage(
          isAr: widget.isAr,
          properties: <Property>[focused],
          focusProperty: focused,
        ),
      ),
    );
  }

  Future<void> _openExternalPropertyMap() async {
    final la = lat ?? _property.latitude;
    final lo = lng ?? _property.longitude;
    if (la == null || lo == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$la,$lo',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildCoordsCard() {
    final cs = Theme.of(context).colorScheme;

    if (_loadingCoords) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: AppLogoLoading(compact: true, size: 40),
        ),
      );
    }

    if (lat == null || lng == null) {
      return Text(
        widget.isAr ? 'لا توجد إحداثيات' : 'No coordinates',
        style: TextStyle(color: cs.onSurfaceVariant),
      );
    }

    final lat0 = lat!;
    final lng0 = lng!;
    final staticUrl = staticMapUrlForPosition(lat: lat0, lng: lng0);
    final priceLabel = '${_formatNumber(_property.price)} $_currencySymbol';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _openFocusedPropertyMap,
          borderRadius: BorderRadius.circular(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CachedNetworkImage(
                  imageUrl: staticUrl,
                  height: 210,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  memCacheWidth: kIsWeb ? 900 : 1200,
                  memCacheHeight: kIsWeb ? 420 : 560,
                  errorWidget: (_, __, ___) => Container(
                    height: 210,
                    color: cs.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, color: cs.primary, size: 34),
                        const SizedBox(height: 8),
                        Text(
                          widget.isAr
                              ? 'تعذر تحميل صورة الخريطة'
                              : 'Could not load map preview',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.10),
                          Colors.black.withValues(alpha: 0.36),
                        ],
                      ),
                    ),
                  ),
                ),
                Icon(
                  Icons.location_pin,
                  size: 48,
                  color: AqarBrandColors.primary,
                ),
                PositionedDirectional(
                  start: 12,
                  top: 12,
                  end: 88,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AqarBrandColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AqarBrandColors.gold.withValues(alpha: 0.7),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            priceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            PropertyListingDisplay.displayListingTitle(
                              _property,
                              widget.isAr,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                          if ([
                            if ((_property.location ?? '').trim().isNotEmpty)
                              _property.location!.trim(),
                            if (_property.city.trim().isNotEmpty &&
                                !PropertyListingDisplay.displayListingTitle(
                                      _property,
                                      widget.isAr,
                                    )
                                    .contains(_property.city.trim()))
                              _property.city.trim(),
                          ].isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              [
                                if ((_property.location ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  _property.location!.trim(),
                                if (_property.city.trim().isNotEmpty)
                                  _property.city.trim(),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w600,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 12,
                  bottom: 12,
                  child: FilledButton.tonalIcon(
                    onPressed: _openFocusedPropertyMap,
                    icon: const Icon(Icons.zoom_out_map_outlined, size: 18),
                    label: Text(widget.isAr ? 'تكبير الموقع' : 'Zoom'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            widget.isAr
                ? 'اضغط الخريطة لفتح الموقع مع وصف الدبوس على الخريطة'
                : 'Tap the map to open the location with a rich pin description',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MonoBox(
                label: 'Lat',
                value: lat!.toStringAsFixed(6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MonoBox(
                label: 'Lng',
                value: lng!.toStringAsFixed(6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openExternalPropertyMap,
          icon: const Icon(Icons.near_me_outlined),
          label: Text(
            widget.isAr ? 'فتح في خرائط Google' : 'Open in Google Maps',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _copyToClipboard(
            '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}',
            successMessage:
                widget.isAr ? 'تم نسخ الإحداثيات' : 'Coordinates copied',
          ),
          icon: const Icon(Icons.copy_outlined),
          label: Text(
            widget.isAr ? 'نسخ الإحداثيات' : 'Copy coordinates',
          ),
        ),
      ],
    );
  }

  Widget _buildAmenities() {
    final cs = Theme.of(context).colorScheme;
    final a = _property.amenities ?? const <String, bool>{};

    final keys = a.keys.where((k) => a[k] == true).toList();
    if (keys.isEmpty) {
      return Text(
        widget.isAr ? 'لا توجد مرافق محددة' : 'No amenities selected',
        style: TextStyle(color: cs.onSurfaceVariant),
      );
    }

    String label(String k) {
      switch (k) {
        case 'pool':
          return widget.isAr ? 'مسبح' : 'Pool';
        case 'gym':
          return widget.isAr ? 'نادي' : 'Gym';
        case 'elevator':
          return widget.isAr ? 'مصعد' : 'Elevator';
        case 'security':
          return widget.isAr ? 'أمن' : 'Security';
        case 'garden':
          return widget.isAr ? 'حديقة' : 'Garden';
        case 'balcony':
          return widget.isAr ? 'شرفة' : 'Balcony';
        case 'ac':
          return widget.isAr ? 'مكيف' : 'AC';
        case 'parking':
          return widget.isAr ? 'مواقف' : 'Parking';
        case 'wifi':
          return widget.isAr ? 'واي فاي' : 'Wi-Fi';
        default:
          return k;
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keys
          .map(
            (k) => _Tag(
              text: label(k),
              color: const Color(0xFF0F766E),
            ),
          )
          .toList(),
    );
  }

  String _typeLabel() {
    final k = _property.listingTypeKey.trim().isNotEmpty
        ? _property.listingTypeKey
        : _property.type.name;
    return PropertyTypeCatalog.label(k, widget.isAr);
  }

  String _fmtDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  bool get _hasEffectiveMapPin {
    final la = lat ?? _property.latitude;
    final lo = lng ?? _property.longitude;
    return la != null && lo != null;
  }

  bool get _shouldShowDeedMapTrustBanner {
    if (!_hasEffectiveMapPin) return false;
    if (_hasDeedInfo) return true;
    return _licenseField('deed_or_benefit_doc_number').isNotEmpty;
  }

  Widget _buildDeedMapTrustBanner(BuildContext context) {
    if (!_shouldShowDeedMapTrustBanner) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.secondaryContainer.withOpacity(0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.map_outlined, color: cs.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.isAr
                      ? 'تأكد من مطابقة موقع الخريطة لوصف الموقع في الصك أو ترخيص الإعلان قبل المعاينة أو التعاقد.'
                      : 'Verify the map pin matches the location description on the deed or ad license before a visit or contract.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.35,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ownerNameRaw = (((widget.ownerUsername?.trim().isNotEmpty ?? false)
                ? widget.ownerUsername
                : _property.ownerDisplayName)
            ?.trim() ??
        '');
    final ownerName = ownerNameRaw.isNotEmpty
        ? ownerNameRaw
        : (widget.isAr ? 'معلن' : 'Owner');
    final marketerLine = (_marketerPublicLine ?? '').trim();
    final showOwnerIdentity = widget.canManageProperty;
    final publishedLike = _isPublishedLikeListing;
    final showQuadToMarketerPrePublish =
        widget.showOwnerLegalNameToViewer && !publishedLike;
    final showAdvertiserByLine = !showOwnerIdentity && ownerNameRaw.isNotEmpty;
    final marketerBrandUrl =
        (_property.marketerBrandImagePublicUrl ?? '').trim();

    return Directionality(
      textDirection: widget.isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          // عند الفتح داخل لوحة الداشبورد: الشريط العلوي يعرض سهم الرجوع
          // الموحَّد، فنخفي السهم الداخلي. عند الفتح من رابط مباشر فإن
          // [canPop] أصلاً false فلا فرق.
          automaticallyImplyLeading: !widget.embedAppBar,
          title: Text(
            widget.isAr ? 'تفاصيل العقار' : 'Property details',
          ),
          actions: [
            Opacity(
              opacity: _isGuest ? 0.5 : 1,
              child: IconButton(
                tooltip: widget.isAr ? 'مفضلة' : 'Favorite',
                icon: Icon(
                  widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: widget.isFavorite ? cs.primary : cs.onSurface,
                ),
                onPressed: _isGuest
                    ? _snackLoginRequired
                    : () async => widget.onToggleFavorite(),
              ),
            ),
            if (_showVisitorListingPublicMenu)
              ListingPublicActionsMenuButton(
                property: _property,
                colorScheme: cs,
                useAppBarStyle: true,
                homeFeedShowsHiddenOnly: widget.homeFeedShowsHiddenOnly,
                onShare: _openSystemShare,
                onHideFromHome: !widget.homeFeedShowsHiddenOnly
                    ? _hideListingFromHomeFeed
                    : null,
                onReport: !widget.homeFeedShowsHiddenOnly &&
                        ListingPermissionsHelper.shouldOfferPublicListingReport(
                          _property,
                        )
                    ? _openListingReportSheet
                    : null,
                onRestoreToHome: widget.homeFeedShowsHiddenOnly
                    ? _restoreListingToHomeFeed
                    : null,
                onWithdrawReport: widget.homeFeedShowsHiddenOnly
                    ? _withdrawMyPendingReport
                    : null,
              ),
          ],
        ),
        body: ListView(
          children: [
            _buildGallery(),
            _buildDeedMapTrustBanner(context),
            LayoutBuilder(
              builder: (context, _) {
                final sw = MediaQuery.sizeOf(context).width;
                final mosaic = kIsWeb && sw >= 1040;
                final tileW = ((sw - 32 - 16) / 2).clamp(300.0, 620.0);
                return Padding(
                  padding: EdgeInsets.all(mosaic ? 24 : 16),
                  child: _DetailsFlow(
                    mosaic: mosaic,
                    tileWidth: tileW,
                    children: [
                      if (_isOwnerManager) ...[
                        _buildOwnerManageCard(),
                        const SizedBox(height: 12),
                      ],
                      if (_showMarketerRegaEdit) ...[
                        _buildMarketerRegaAlignCard(),
                        const SizedBox(height: 12),
                      ],
                      _Card(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                PropertyListingDisplay.displayListingTitle(
                                  _property,
                                  widget.isAr,
                                ),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (_property.isAuction)
                              _Tag(
                                text: widget.isAr ? 'مزاد' : 'Auction',
                                color: Colors.orange,
                              ),
                          ],
                        ),
                      ),
                      if (_hasDeedInfo) ...[
                        const SizedBox(height: 12),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.isAr
                                    ? 'بيانات الصك'
                                    : 'Deed information',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_deedNumberDisplay.isNotEmpty)
                                _InfoRow(
                                  icon: Icons.numbers_outlined,
                                  title:
                                      widget.isAr ? 'رقم الصك' : 'Deed number',
                                  value: _maskDeedNumber(_deedNumberDisplay),
                                  copyValue:
                                      _maskDeedNumber(_deedNumberDisplay),
                                  copiedMessage: widget.isAr
                                      ? 'تم نسخ رقم الصك (كما يظهر)'
                                      : 'Deed number copied (as shown)',
                                ),
                              if (_deedDateDisplay.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.calendar_today_outlined,
                                  title:
                                      widget.isAr ? 'تاريخ الصك' : 'Deed date',
                                  value: _deedDateDisplay,
                                  copyValue: _deedDateDisplay,
                                  copiedMessage: widget.isAr
                                      ? 'تم نسخ تاريخ الصك'
                                      : 'Deed date copied',
                                ),
                              ],
                              if (_deedIssuerDisplay.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.account_balance_outlined,
                                  title: widget.isAr
                                      ? 'الجهة المصدرة'
                                      : 'Issuing authority',
                                  value: _deedIssuerDisplay,
                                  copyValue: _deedIssuerDisplay,
                                  copiedMessage: widget.isAr
                                      ? 'تم نسخ اسم الجهة'
                                      : 'Issuer copied',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      ..._buildListingGuidanceSection(cs),
                      const SizedBox(height: 12),
                      _Card(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (publishedLike) ...[
                                    Text(
                                      widget.isAr
                                          ? 'نشر بواسطة'
                                          : 'Published by',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor:
                                              const Color(0xFF0F766E)
                                                  .withValues(alpha: 0.12),
                                          backgroundImage: marketerBrandUrl
                                                  .isNotEmpty
                                              ? NetworkImage(marketerBrandUrl)
                                              : null,
                                          child: marketerBrandUrl.isEmpty
                                              ? const Icon(
                                                  Icons.apartment_outlined,
                                                  color: Color(0xFF0F766E),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            marketerLine.isNotEmpty
                                                ? marketerLine
                                                : (widget.isAr
                                                    ? 'مسوّق معتمد'
                                                    : 'Licensed marketer'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Theme(
                                      data: Theme.of(context).copyWith(
                                        dividerColor: Colors.transparent,
                                      ),
                                      child: ExpansionTile(
                                        initiallyExpanded: true,
                                        maintainState: true,
                                        tilePadding: EdgeInsets.zero,
                                        expandedAlignment: widget.isAr
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        childrenPadding: const EdgeInsets.only(
                                          top: 6,
                                          bottom: 2,
                                        ),
                                        leading: Icon(
                                          Icons.article_outlined,
                                          size: 22,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                        title: Text(
                                          widget.isAr
                                              ? 'البيانات التنظيمية للإعلان'
                                              : 'Structured listing data',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            fontFamily: 'Cairo',
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                        ),
                                        children: [
                                          ListingFormattedSpecPanel(
                                            property: _property,
                                            isAr: widget.isAr,
                                            omitDeedSection: _hasDeedInfo,
                                          ),
                                          const SizedBox(height: 10),
                                          LayoutBuilder(
                                            builder: (context, c) {
                                              final narrow = c.maxWidth < 420;
                                              final verifyBtn = FilledButton.tonalIcon(
                                                onPressed: () async {
                                                  final src =
                                                      _licenseField('rega_source_url')
                                                          .trim();
                                                  final license =
                                                      _licenseField(
                                                              'rega_ad_license_number')
                                                          .trim();
                                                  Uri? u;
                                                  if (src.isNotEmpty) {
                                                    u = Uri.tryParse(src);
                                                  }
                                                  u ??= Uri.tryParse(
                                                    license.isNotEmpty
                                                        ? 'https://eservicesredp.rega.gov.sa/public/OfficesBroker/ElanDetails/$license'
                                                        : 'https://rega.gov.sa',
                                                  );
                                                  if (u == null) return;
                                                  if (!context.mounted) return;
                                                  await Navigator.of(context)
                                                      .push<void>(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          GovernmentInAppWebViewPage(
                                                        uri: u!,
                                                        title: widget.isAr
                                                            ? 'الهيئة العامة للعقار'
                                                            : 'REGA',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.verified_outlined,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  widget.isAr
                                                      ? 'التحقق من الإعلان في الهيئة'
                                                      : 'Verify listing on REGA',
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              );
                                              final mapBtn = OutlinedButton.icon(
                                                onPressed: (lat != null ||
                                                        _property.latitude !=
                                                            null)
                                                    ? () => unawaited(
                                                          _openExternalPropertyMap(),
                                                        )
                                                    : null,
                                                icon: const Icon(
                                                  Icons.map_outlined,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  widget.isAr
                                                      ? 'الموقع على الخريطة'
                                                      : 'Open on map',
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              );
                                              if (narrow) {
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.stretch,
                                                  children: [
                                                    verifyBtn,
                                                    const SizedBox(height: 8),
                                                    mapBtn,
                                                  ],
                                                );
                                              }
                                              return Row(
                                                children: [
                                                  Expanded(child: verifyBtn),
                                                  const SizedBox(width: 8),
                                                  Expanded(child: mapBtn),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!showOwnerIdentity) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        widget.isAr
                                            ? 'التواصل والدردشة مع المسوّق المعتمد'
                                            : 'Contact and chat are with the licensed marketer',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ] else
                                      const SizedBox(height: 12),
                                  ],
                                  if (showQuadToMarketerPrePublish ||
                                      showAdvertiserByLine) ...[
                                    Text(
                                      widget.isAr
                                          ? 'هذا الإعلان بواسطة'
                                          : 'This listing is by',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      ownerName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (showOwnerIdentity) ...[
                                    if (publishedLike) ...[
                                      Text(
                                        widget.isAr
                                            ? 'المعلن (أنت)'
                                            : 'Advertiser (you)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    Text(
                                      ownerName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.isAr ? 'المالك' : 'Owner',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ] else if (!publishedLike &&
                                      !showQuadToMarketerPrePublish) ...[
                                    Text(
                                      widget.isAr
                                          ? 'بعد اعتماد المسوّق يظهر ناشر الإعلان هنا.'
                                          : 'The publishing marketer will appear here once assigned.',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if ((_showMarketerChatButton &&
                                    (!_isListingOwner ||
                                        _ownerOffersCount > 0)) ||
                                _canOpenListingOwnerChat) ...[
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_showMarketerChatButton &&
                                      (!_isListingOwner ||
                                          _ownerOffersCount > 0))
                                    SizedBox(
                                      height: 42,
                                      child: ElevatedButton.icon(
                                        onPressed: _openingChat
                                            ? null
                                            : () async {
                                                if (!_canOpenMarketerChat) {
                                                  _snack(
                                                    widget.isAr
                                                        ? 'لا يوجد مسوّق مسؤول عن هذا الإعلان للمراسلة بعد.'
                                                        : 'No marketer is assigned for chat yet.',
                                                    isError: true,
                                                  );
                                                  return;
                                                }
                                                await _openChatWithMarketer();
                                              },
                                        icon: _openingChat
                                            ? SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: AppLogoLoading(
                                                  compact: true,
                                                  size: 20,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.chat_bubble_outline),
                                        label: Text(widget.isAr
                                            ? 'مراسلة المسوّق'
                                            : 'Message marketer'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF0F766E),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_showMarketerChatButton &&
                                      (!_isListingOwner ||
                                          _ownerOffersCount > 0) &&
                                      _canOpenListingOwnerChat)
                                    const SizedBox(height: 8),
                                  if (_canOpenListingOwnerChat)
                                    SizedBox(
                                      height: 42,
                                      child: OutlinedButton.icon(
                                        onPressed: _openingChat
                                            ? null
                                            : _openChatWithListingOwner,
                                        icon: _openingChat
                                            ? SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: AppLogoLoading(
                                                  compact: true,
                                                  size: 20,
                                                ),
                                              )
                                            : const Icon(Icons.person_outline),
                                        label: Text(widget.isAr
                                            ? 'مراسلة المالك'
                                            : 'Message owner'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              const Color(0xFF0F766E),
                                          side: const BorderSide(
                                            color: Color(0xFF0F766E),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_hasVideo ||
                          (_property.virtualTourUrl ?? '')
                              .trim()
                              .isNotEmpty) ...[
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.isAr ? 'الوسائط' : 'Media',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_hasVideo)
                                FilledButton.icon(
                                  onPressed:
                                      _openingVideo ? null : _openVideoSheet,
                                  icon: _openingVideo
                                      ? SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: AppLogoLoading(
                                            compact: true,
                                            size: 20,
                                          ),
                                        )
                                      : const Icon(Icons.play_circle_outline),
                                  label: Text(
                                    widget.isAr
                                        ? 'عرض فيديو العقار'
                                        : 'Play property video',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F766E),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              if ((_property.virtualTourUrl ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: () => _copyToClipboard(
                                    _property.virtualTourUrl!.trim(),
                                    successMessage: widget.isAr
                                        ? 'تم نسخ رابط الجولة'
                                        : 'Virtual tour link copied',
                                  ),
                                  icon: const Icon(Icons.public_outlined),
                                  label: Text(
                                    widget.isAr
                                        ? 'نسخ رابط الجولة الافتراضية'
                                        : 'Copy virtual tour link',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.isAr ? 'الموقع' : 'Location',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _InfoRow(
                              icon: Icons.location_on_outlined,
                              title: widget.isAr ? 'العنوان' : 'Address',
                              value: _property.locationText,
                              copyValue: _property.locationText.trim().isEmpty
                                  ? null
                                  : _property.locationText.trim(),
                              copiedMessage: widget.isAr
                                  ? 'تم نسخ العنوان'
                                  : 'Address copied',
                            ),
                            if ((_property.buildingNumber ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _InfoRow(
                                icon: Icons.home_work_outlined,
                                title:
                                    widget.isAr ? 'رقم المبنى' : 'Building no.',
                                value: _property.buildingNumber!.trim(),
                                copyValue: _property.buildingNumber!.trim(),
                                copiedMessage: widget.isAr
                                    ? 'تم نسخ رقم المبنى'
                                    : 'Building number copied',
                              ),
                            ],
                            if ((_property.addressLine ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _InfoRow(
                                icon: Icons.map_outlined,
                                title: widget.isAr
                                    ? 'العنوان الوطني'
                                    : 'National address',
                                value: _property.addressLine!.trim(),
                                copyValue: _property.addressLine!.trim(),
                                copiedMessage: widget.isAr
                                    ? 'تم نسخ العنوان الوطني'
                                    : 'National address copied',
                              ),
                            ],
                            const SizedBox(height: 10),
                            _buildCoordsCard(),
                          ],
                        ),
                      ),
                      if ((_property.listingPublicCode ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _Card(
                          child: Row(
                            children: [
                              Icon(
                                Icons.tag_outlined,
                                size: 20,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SelectableText(
                                  widget.isAr
                                      ? 'رقم الإعلان: ${DisplayIds.tenDigit(_property.listingPublicCode)}'
                                      : 'Listing no.: ${DisplayIds.tenDigit(_property.listingPublicCode)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: widget.isAr
                                    ? 'نسخ رقم الإعلان'
                                    : 'Copy listing ID',
                                onPressed: () async {
                                  final code = DisplayIds.tenDigit(
                                    _property.listingPublicCode,
                                  );
                                  await Clipboard.setData(
                                      ClipboardData(text: code));
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        widget.isAr
                                            ? 'تم نسخ رقم الإعلان'
                                            : 'Listing ID copied',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_hasMarketingLicenseInfo) ...[
                        const SizedBox(height: 12),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.isAr
                                    ? 'بيانات ترخيص الهيئة العامة للعقار (REGA)'
                                    : 'REGA ad-license data',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.isAr
                                    ? 'تُعرض البيانات التي أدخلها المسوق/المكتب عند تقديم التصاريح، ويمكن تحديثها لاحقًا عند التكامل مع الهيئة.'
                                    : 'Shown from marketer-submitted permit data; may be updated when authority integration is live.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_licenseField('rega_ad_license_number')
                                  .isNotEmpty)
                                _InfoRow(
                                  icon: Icons.badge_outlined,
                                  title: widget.isAr
                                      ? 'رقم ترخيص الإعلان'
                                      : 'Ad license no.',
                                  value:
                                      _licenseField('rega_ad_license_number'),
                                  copyValue:
                                      _licenseField('rega_ad_license_number'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              if (_licenseField('rega_issue_date')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.event_available_outlined,
                                  title: widget.isAr
                                      ? 'تاريخ الإصدار'
                                      : 'Issue date',
                                  value: _licenseField('rega_issue_date'),
                                  copyValue:
                                      _licenseField('rega_issue_date'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField('rega_expiry_date')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.event_busy_outlined,
                                  title: widget.isAr
                                      ? 'تاريخ الانتهاء'
                                      : 'Expiry date',
                                  value: _licenseField('rega_expiry_date'),
                                  copyValue:
                                      _licenseField('rega_expiry_date'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField('fal_broker_license_number')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.verified_user_outlined,
                                  title: widget.isAr
                                      ? 'رقم ترخيص الوساطة (فال)'
                                      : 'FAL broker license',
                                  value: _licenseField(
                                      'fal_broker_license_number'),
                                  copyValue: _licenseField(
                                      'fal_broker_license_number'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField('deed_or_benefit_doc_number')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.description_outlined,
                                  title: widget.isAr
                                      ? 'رقم الصك / مستند المنفعة'
                                      : 'Deed / benefit doc no.',
                                  value: _licenseField(
                                      'deed_or_benefit_doc_number'),
                                  copyValue: _licenseField(
                                      'deed_or_benefit_doc_number'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField(
                                      'rega_advertiser_unified_number')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.numbers_outlined,
                                  title: widget.isAr
                                      ? 'الرقم الموحّد للمعلن'
                                      : 'Advertiser unified number',
                                  value: _licenseField(
                                      'rega_advertiser_unified_number'),
                                  copyValue: _licenseField(
                                      'rega_advertiser_unified_number'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField('rega_ad_responsible_name')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.person_outline,
                                  title: widget.isAr
                                      ? 'اسم المسؤول الإعلاني'
                                      : 'Ad responsible name',
                                  value:
                                      _licenseField('rega_ad_responsible_name'),
                                  copyValue: _licenseField(
                                      'rega_ad_responsible_name'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField('rega_ad_responsible_mobile')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.phone_android_outlined,
                                  title: widget.isAr
                                      ? 'جوال المسؤول الإعلاني'
                                      : 'Ad responsible mobile',
                                  value: _licenseField(
                                      'rega_ad_responsible_mobile'),
                                  copyValue: _licenseField(
                                      'rega_ad_responsible_mobile'),
                                  copiedMessage: widget.isAr
                                      ? 'تم نسخ رقم الجوال'
                                      : 'Phone copied',
                                ),
                              ],
                              if (_licenseField('rega_ad_purpose')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.flag_outlined,
                                  title: widget.isAr
                                      ? 'غرض الإعلان (الهيئة)'
                                      : 'REGA ad purpose',
                                  value: _licenseField('rega_ad_purpose'),
                                  copyValue:
                                      _licenseField('rega_ad_purpose'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField('rega_unit_price')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.attach_money_outlined,
                                  title: widget.isAr
                                      ? 'سعر الوحدة (الهيئة)'
                                      : 'REGA unit price',
                                  value: _licenseField('rega_unit_price'),
                                  copyValue:
                                      _licenseField('rega_unit_price'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField('notes').isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.notes_outlined,
                                  title: widget.isAr ? 'ملاحظات' : 'Notes',
                                  value: _licenseField('notes'),
                                  copyValue: _licenseField('notes'),
                                  copiedMessage: widget.isAr
                                      ? 'تم النسخ'
                                      : 'Copied',
                                ),
                              ],
                              if (_licenseField('rega_source_url')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: widget.isAr
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () async {
                                      final u = Uri.tryParse(
                                        _licenseField('rega_source_url'),
                                      );
                                      if (u == null) return;
                                      if (!context.mounted) return;
                                      await Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              GovernmentInAppWebViewPage(
                                            uri: u,
                                            title: widget.isAr
                                                ? 'الهيئة العامة للعقار'
                                                : 'REGA',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.verified_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'عرض صفحة الترخيص (داخل التطبيق)'
                                          : 'View license page (in-app)',
                                    ),
                                  ),
                                ),
                              ],
                              if (_licenseQrImageSrc().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  widget.isAr
                                      ? 'رمز الاستجابة السريعة للهيئة (QR)'
                                      : 'REGA QR code',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (_licenseField('rega_source_url')
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.isAr
                                        ? 'اضغط على الرمز لعرض الصفحة الرسمية داخل التطبيق دون الخروج.'
                                        : 'Tap the QR to view the official page inside the app.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _licenseField('rega_source_url')
                                            .isNotEmpty
                                        ? () async {
                                            final u = Uri.tryParse(
                                              _licenseField('rega_source_url'),
                                            );
                                            if (u == null) return;
                                            if (!context.mounted) return;
                                            await Navigator.of(context)
                                                .push<void>(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    GovernmentInAppWebViewPage(
                                                  uri: u,
                                                  title: widget.isAr
                                                      ? 'الهيئة العامة للعقار'
                                                      : 'REGA',
                                                ),
                                              ),
                                            );
                                          }
                                        : null,
                                    borderRadius: BorderRadius.circular(10),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: CachedNetworkImage(
                                        imageUrl: _normalizeImageUrl(
                                            _licenseQrImageSrc()),
                                        height: 180,
                                        fit: BoxFit.contain,
                                        memCacheWidth: 360,
                                        memCacheHeight: 360,
                                        errorWidget: (_, __, ___) => Text(
                                          widget.isAr
                                              ? 'تعذر تحميل الصورة'
                                              : 'Could not load image',
                                          style: TextStyle(color: cs.error),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.isAr ? 'الوصف' : 'Description',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _property.description.trim().isEmpty
                                  ? (widget.isAr
                                      ? 'لا يوجد وصف'
                                      : 'No description')
                                  : _property.description,
                              style: TextStyle(
                                fontSize: 15,
                                color: cs.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_showMarketingTrackingEntry) ...[
                        const SizedBox(height: 12),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.isAr
                                    ? 'تتبّع مسار التسويق'
                                    : 'Marketing journey',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.isAr
                                    ? 'عرض دعوات وعروض وعقود والمراحل دون الخروج من صفحة العقار.'
                                    : 'Invites, offers, contracts, and stages in one place.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    unawaited(_openMarketingTrackingSheet()),
                                icon: const Icon(Icons.route_outlined),
                                label: Text(
                                  _isListingOwner
                                      ? (widget.isAr
                                          ? 'تتبّع طلب التسويق'
                                          : 'Track marketing request')
                                      : (widget.isAr
                                          ? 'تتبّع عرضي التسويقي'
                                          : 'Track my marketing offer'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_ownerMarketingDeskEligible) ...[
                        const SizedBox(height: 12),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.isAr
                                    ? 'إدارة طلب التسويق'
                                    : 'Manage marketing request',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_loadingWorkflowSidecars)
                                const AppLogoLoading(compact: true, size: 24)
                              else ...[
                                if (_ownerShowsOffersEntry)
                                  FilledButton.icon(
                                    onPressed: _openOwnerOffersFromDetails,
                                    icon: const Icon(Icons.local_offer_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'العروض المقدّمة'
                                          : 'Submitted offers',
                                    ),
                                  ),
                                if (_ownerShowsOffersEntry &&
                                    _showMarketerChatButton)
                                  const SizedBox(height: 8),
                                if (_showMarketerChatButton &&
                                    _isListingOwner &&
                                    (_chatMarketerId ?? '').isNotEmpty &&
                                    _ownerOffersCount > 0)
                                  OutlinedButton.icon(
                                    onPressed: _openingChat
                                        ? null
                                        : () {
                                            unawaited(_openChatWithMarketer());
                                          },
                                    icon: const Icon(Icons.chat_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'المراسلة مع المسوّق'
                                          : 'Message marketer',
                                    ),
                                  ),
                                if (_ownerShowsContractDeskEntry) ...[
                                  if (_ownerShowsOffersEntry ||
                                      (_showMarketerChatButton &&
                                          _isListingOwner))
                                    const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: () => unawaited(_openMarketingListingStatusPage()),
                                    icon: const Icon(Icons.draw_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'توقيع العقد أو إلغاؤه'
                                          : 'Sign or cancel contract',
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (_showMarketerMarketingHubCard) ...[
                        const SizedBox(height: 12),
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.isAr
                                    ? 'التسويق والتعاقد'
                                    : 'Marketing & contracting',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_loadingWorkflowSidecars)
                                const AppLogoLoading(compact: true, size: 24)
                              else ...[
                                if (_showMarketerSubmitOfferButton)
                                  FilledButton.icon(
                                    onPressed: _submitMarketingOfferFromDetails,
                                    icon: const Icon(Icons.edit_note_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'إتمام الصفقة'
                                          : 'Complete deal',
                                    ),
                                  ),
                                if (_offerSentThisRound &&
                                    !_marketerWorkflowBlocksNewOffer) ...[
                                  if (_showMarketerSubmitOfferButton)
                                    const SizedBox(height: 8),
                                  // بدل النص القصير القديم — بطاقة سياسة كاملة
                                  // تشرح للمسوّق المسار من العرض إلى النشر
                                  // ومنع التواصل المباشر مع المالك قبل التعاقد.
                                  MarketerPolicyNoticeCard(
                                    isAr: widget.isAr,
                                    stageHint: MarketerPolicyStage.afterOffer,
                                  ),
                                ],
                                if (_effectiveMarketerHubPhase == 'accepted' ||
                                    _effectiveMarketerHubPhase == 'contract')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: MarketerPolicyNoticeCard(
                                      isAr: widget.isAr,
                                      stageHint:
                                          MarketerPolicyStage.contractPending,
                                    ),
                                  ),
                                if (_effectiveMarketerHubPhase == 'signed')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: MarketerPolicyNoticeCard(
                                      isAr: widget.isAr,
                                      stageHint:
                                          MarketerPolicyStage.permitWindow,
                                    ),
                                  ),
                                if (_effectiveMarketerHubPhase == 'accepted') ...[
                                  if (_showMarketerSubmitOfferButton ||
                                      (_offerSentThisRound &&
                                          !_marketerWorkflowBlocksNewOffer))
                                    const SizedBox(height: 8),
                                  if (_showMarketerContract72Countdown) ...[
                                    _MarketerContract72Countdown(
                                      startAt: _resolvedContractStartedAt!,
                                      isAr: widget.isAr,
                                      supabase: _sb,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  FilledButton.icon(
                                    onPressed: () => unawaited(_openMarketingListingStatusPage()),
                                    icon: const Icon(Icons.description_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'إنشاء العقد'
                                          : 'Create contract',
                                    ),
                                  ),
                                ],
                                if (_effectiveMarketerHubPhase == 'contract') ...[
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => unawaited(_openMarketerListingContractDetails()),
                                    icon: const Icon(Icons.article_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'تفاصيل العقد (قراءة)'
                                          : 'Contract details (read-only)',
                                    ),
                                  ),
                                ],
                                if (_effectiveMarketerHubPhase == 'signed') ...[
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: () => unawaited(_openMarketingListingStatusPage()),
                                    icon: const Icon(Icons.verified_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'إصدار التصاريح'
                                          : 'Issue permits',
                                    ),
                                  ),
                                ],
                                if (_effectiveMarketingRequestId
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => unawaited(_openMarketingListingStatusPage()),
                                    icon: const Icon(Icons.dashboard_customize_outlined),
                                    label: Text(
                                      widget.isAr
                                          ? 'لوحة الطلب والتعاقد'
                                          : 'Request & contract hub',
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.isAr ? 'تفاصيل العقار' : 'Details',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Chip(
                                  icon: Icons.home_outlined,
                                  label: _typeLabel(),
                                ),
                                if (_property.usageSuitableResidential)
                                  _Chip(
                                    icon: Icons.home_work_outlined,
                                    label: widget.isAr
                                        ? 'سكني ✓'
                                        : 'Residential ✓',
                                  ),
                                if (_property.usageSuitableCommercial)
                                  _Chip(
                                    icon: Icons.storefront_outlined,
                                    label: widget.isAr
                                        ? 'تجاري ✓'
                                        : 'Commercial ✓',
                                  ),
                                _Chip(
                                  icon: Icons.square_foot_outlined,
                                  label: widget.isAr
                                      ? '${_property.area.toStringAsFixed(0)} م²'
                                      : '${_property.area.toStringAsFixed(0)} m²',
                                ),
                                _Chip(
                                  icon: Icons.remove_red_eye_outlined,
                                  label: '${_property.views}',
                                  onTap: () => PropertyViewService.showSheet(
                                    context: context,
                                    sb: _sb,
                                    propertyId: _property.id,
                                    viewsCount: _property.views,
                                    isOwner: _isListingOwner,
                                    isPublishingMarketer: _isPublishingMarketer,
                                    isAr: widget.isAr,
                                    listingRequestId:
                                        _effectiveMarketingRequestId.trim(),
                                    currentUserId: _isGuest
                                        ? null
                                        : widget.currentUserId.trim(),
                                  ),
                                ),
                                if (_property.bedrooms != null)
                                  _Chip(
                                    icon: Icons.bed_outlined,
                                    label: '${_property.bedrooms}',
                                  ),
                                if (_property.bathrooms != null)
                                  _Chip(
                                    icon: Icons.bathtub_outlined,
                                    label: '${_property.bathrooms}',
                                  ),
                                if (_property.parkingSpots != null)
                                  _Chip(
                                    icon: Icons.local_parking_outlined,
                                    label: '${_property.parkingSpots}',
                                  ),
                                if (_property.furnished == true)
                                  _Chip(
                                    icon: Icons.weekend_outlined,
                                    label: widget.isAr ? 'مفروش' : 'Furnished',
                                  ),
                                if (_property.yearBuilt != null)
                                  _Chip(
                                    icon: Icons.event_outlined,
                                    label: '${_property.yearBuilt}',
                                  ),
                                if (_property.floor != null)
                                  _Chip(
                                    icon: Icons.layers_outlined,
                                    label:
                                        '${widget.isAr ? 'الدور' : 'Floor'}: ${_property.floor}',
                                  ),
                                if (_property.totalFloors != null)
                                  _Chip(
                                    icon: Icons.domain_outlined,
                                    label:
                                        '${widget.isAr ? 'الأدوار' : 'Floors'}: ${_property.totalFloors}',
                                  ),
                                if (_property.negotiable)
                                  _Chip(
                                    icon: Icons.handshake_outlined,
                                    label: widget.isAr
                                        ? 'قابل للتفاوض'
                                        : 'Negotiable',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildAmenities(),
                            const SizedBox(height: 12),
                            if ((_property.listingPublicCode ?? '')
                                .trim()
                                .isNotEmpty)
                              _InfoRow(
                                icon: Icons.tag_outlined,
                                title: widget.isAr
                                    ? 'رقم الإعلان'
                                    : 'Listing code',
                                value: DisplayIds.tenDigit(
                                  _property.listingPublicCode,
                                ),
                                copyValue: DisplayIds.tenDigit(
                                  _property.listingPublicCode,
                                ),
                                copiedMessage: widget.isAr
                                    ? 'تم نسخ رقم الإعلان'
                                    : 'Listing code copied',
                              ),
                            if (_property.city.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _InfoRow(
                                icon: Icons.location_city_outlined,
                                title: widget.isAr ? 'المدينة' : 'City',
                                value: _property.city.trim(),
                                copyValue: _property.city.trim(),
                                copiedMessage: widget.isAr
                                    ? 'تم نسخ المدينة'
                                    : 'City copied',
                              ),
                            ],
                            if ((_property.province ?? '').trim().isNotEmpty ||
                                (_property.region ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _InfoRow(
                                icon: Icons.map_outlined,
                                title: widget.isAr ? 'النطاق الجغرافي' : 'Area',
                                value: [
                                  (_property.province ?? '').trim(),
                                  (_property.region ?? '').trim(),
                                ].where((e) => e.isNotEmpty).join(' - '),
                                copyValue: [
                                  (_property.province ?? '').trim(),
                                  (_property.region ?? '').trim(),
                                ].where((e) => e.isNotEmpty).join(' - '),
                                copiedMessage: widget.isAr
                                    ? 'تم النسخ'
                                    : 'Copied',
                              ),
                            ],
                            if ((_property.location ?? '').trim().isNotEmpty ||
                                (_property.addressLine ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _InfoRow(
                                icon: Icons.place_outlined,
                                title: widget.isAr ? 'الموقع' : 'Location',
                                value: [
                                  (_property.location ?? '').trim(),
                                  (_property.addressLine ?? '').trim(),
                                ].where((e) => e.isNotEmpty).join(' - '),
                                copyValue: [
                                  (_property.location ?? '').trim(),
                                  (_property.addressLine ?? '').trim(),
                                ].where((e) => e.isNotEmpty).join(' - '),
                                copiedMessage: widget.isAr
                                    ? 'تم نسخ الموقع'
                                    : 'Location copied',
                              ),
                            ],
                            if ((_property.status ?? '').trim().isNotEmpty ||
                                (_property.workflowStage ?? '')
                                    .trim()
                                    .isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _InfoRow(
                                icon: Icons.verified_outlined,
                                title: widget.isAr
                                    ? 'حالة الإعلان'
                                    : 'Listing status',
                                value: [
                                  (_property.status ?? '').trim(),
                                  (_property.workflowStage ?? '').trim(),
                                ].where((e) => e.isNotEmpty).join(' / '),
                                copyValue: [
                                  (_property.status ?? '').trim(),
                                  (_property.workflowStage ?? '').trim(),
                                ].where((e) => e.isNotEmpty).join(' / '),
                                copiedMessage: widget.isAr
                                    ? 'تم النسخ'
                                    : 'Copied',
                              ),
                            ],
                            if (_property.availabilityDate != null) ...[
                              const SizedBox(height: 10),
                              _InfoRow(
                                icon: Icons.event_available_outlined,
                                title: widget.isAr
                                    ? 'تاريخ الإتاحة'
                                    : 'Available from',
                                value: _fmtDateTime(
                                  _property.availabilityDate!.toLocal(),
                                ),
                                copyValue: _fmtDateTime(
                                  _property.availabilityDate!.toLocal(),
                                ),
                                copiedMessage: widget.isAr
                                    ? 'تم النسخ'
                                    : 'Copied',
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.isAr
                                  ? 'الأسعار والرسوم (الفاتورة)'
                                  : 'Pricing & invoice',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            // — تفصيل الفاتورة الموحّد (مشترك مع شاشة الإضافة
                            //   والتعديل والمعاينة الحيّة).
                            ListingPricingBreakdown(
                              invoice: _invoice,
                              isAr: widget.isAr,
                              showTitle: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_property.isAuction && _isPublishedLikeListing) ...[
                        _buildAuctionBidsCard(cs),
                        const SizedBox(height: 12),
                      ],
                      if (_licensedMarketerPhone.isNotEmpty) ...[
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.verified_outlined,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      widget.isAr
                                          ? 'تواصل المسوّق (من بيانات ترخيص الهيئة)'
                                          : 'Marketer contact (from REGA license)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.isAr
                                    ? 'لا يُعرض رقم المالك على الإعلان. الرقم أدناه مرتبط بالمسوّق المرخّص حسب التصريح.'
                                    : 'The owner\'s private number is not shown. The number below is the licensed marketer from the permit record.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _InfoRow(
                                icon: Icons.phone_android_outlined,
                                title: widget.isAr
                                    ? 'جوال المسوّق'
                                    : 'Marketer mobile',
                                value: _licensedMarketerPhone,
                                copyValue: _licensedMarketerPhone,
                                copiedMessage: widget.isAr
                                    ? 'تم نسخ رقم الجوال'
                                    : 'Phone copied',
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final raw = _licensedMarketerPhone
                                          .replaceAll(RegExp(r'[\s\-]'), '');
                                      final u = Uri.parse('tel:$raw');
                                      try {
                                        await launchUrl(u);
                                      } catch (_) {}
                                    },
                                    icon: const Icon(Icons.call_outlined),
                                    label: Text(widget.isAr ? 'اتصال' : 'Call'),
                                  ),
                                  if (_showMarketerChatButton)
                                    FilledButton.icon(
                                      onPressed: _openingChat
                                          ? null
                                          : () async {
                                              await _openChatWithMarketer();
                                            },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF25D366),
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: _openingChat
                                        ? SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: AppLogoLoading(
                                              compact: true,
                                              size: 20,
                                            ),
                                          )
                                        : const Icon(Icons.chat_rounded),
                                    label: Text(
                                      widget.isAr
                                          ? 'دردشة (مثل واتساب داخل التطبيق)'
                                          : 'Chat (in-app, WhatsApp-style)',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _copyToClipboard(
                                      _licensedMarketerPhone,
                                      successMessage: widget.isAr
                                          ? 'تم نسخ الرقم'
                                          : 'Number copied',
                                    ),
                                    icon: const Icon(Icons.copy_outlined),
                                    label: Text(widget.isAr ? 'نسخ' : 'Copy'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _Card(
                        child: Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _isPublishedLikeListing
                                    ? (widget.isAr
                                        ? 'الدردشة داخل التطبيق تكون مع المسوّق المعتمد فقط؛ لا يُعرض رقم المالك على الإعلان العلني.'
                                        : 'In-app chat is with the licensed marketer only; the owner\'s phone is not shown on the public listing.')
                                    : (widget.isAr
                                        ? 'قبل النشر: يمكن للمسوّقين المعنيين مراسلة المالك من هذه الصفحة. بعد النشر يقتصر التواصل الظاهر للجميع على المسوّق المرخّص.'
                                        : 'Before publishing, involved marketers can message the owner from this page. After publishing, public-facing contact is through the licensed marketer.'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              onPressed: _sharing ? null : _openSystemShare,
                              icon: _sharing
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: AppLogoLoading(
                                        compact: true,
                                        size: 20,
                                      ),
                                    )
                                  : const Icon(Icons.share_rounded),
                              label: Text(
                                widget.isAr
                                    ? 'مشاركة الإعلان'
                                    : 'Share listing',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => _copyToClipboard(
                                _shareBodyWithLinkAndBrand,
                                successMessage: widget.isAr
                                    ? 'تم نسخ النص والرابط'
                                    : 'Text and link copied',
                              ),
                              icon: const Icon(Icons.copy_outlined),
                              label: Text(
                                widget.isAr
                                    ? 'نسخ النص والرابط'
                                    : 'Copy text & link',
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => _copyToClipboard(
                                _property.description,
                                successMessage: widget.isAr
                                    ? 'تم نسخ الوصف'
                                    : 'Description copied',
                              ),
                              icon: const Icon(Icons.description_outlined),
                              label: Text(
                                widget.isAr ? 'نسخ الوصف' : 'Copy description',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: _showGuestCompleteDealBar
            ? _guestParticipationBottomBar(context)
            : _showBuyerCompleteDealBar
                ? _buyerCompleteDealBottomBar(context)
                : null,
      ),
    );
  }
}

/// على الويب العريض: بطاقات بشكل شبكي (Wrap) مع حواف مميّزة لموثوق لاين العقارية.
class _DetailsFlow extends StatelessWidget {
  final bool mosaic;
  final double tileWidth;
  final List<Widget> children;

  const _DetailsFlow({
    required this.mosaic,
    required this.tileWidth,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (!mosaic) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    final out = <Widget>[];
    for (final w in children) {
      if (w is SizedBox &&
          w.child == null &&
          w.height != null &&
          w.height! >= 8 &&
          w.height! <= 16) {
        continue;
      }
      out.add(
        SizedBox(
          width: tileWidth,
          child: w,
        ),
      );
    }
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.start,
      children: out,
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wideWeb = kIsWeb && MediaQuery.sizeOf(context).width >= 1040;
    final accent = const Color(0xFF0F766E);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(wideWeb ? 20 : 18),
        border: Border.all(
          color: wideWeb
              ? accent.withOpacity(0.28)
              : cs.outlineVariant.withOpacity(0.35),
          width: wideWeb ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: wideWeb
                ? accent.withOpacity(0.07)
                : cs.shadow.withOpacity(0.06),
            blurRadius: wideWeb ? 14 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? copyValue;
  final String? copiedMessage;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.copyValue,
    this.copiedMessage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final showCopy = (copyValue ?? '').trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: const Color(0xFF0F766E)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: Text(
                  value,
                  textAlign: rtl ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showCopy) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: rtl ? 'نسخ' : 'Copy',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            iconSize: 16,
            icon: Icon(Icons.copy_rounded, color: cs.primary),
            onPressed: () async {
              final v = copyValue!.trim();
              await Clipboard.setData(ClipboardData(text: v));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(copiedMessage ?? (rtl ? 'تم النسخ' : 'Copied')),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _Chip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final child = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0F766E)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;

  const _Tag({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Pill({
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketerContract72Countdown extends StatefulWidget {
  const _MarketerContract72Countdown({
    required this.startAt,
    required this.isAr,
    required this.supabase,
  });

  final DateTime startAt;
  final bool isAr;
  final SupabaseClient supabase;

  @override
  State<_MarketerContract72Countdown> createState() =>
      _MarketerContract72CountdownState();
}

class _MarketerContract72CountdownState extends State<_MarketerContract72Countdown> {
  late DateTime _deadline;
  Timer? _t;
  bool _syncedAfterExpiry = false;

  @override
  void initState() {
    super.initState();
    _deadline = widget.startAt.toLocal().add(const Duration(hours: 72));
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
      if (!_syncedAfterExpiry && DateTime.now().isAfter(_deadline)) {
        _syncedAfterExpiry = true;
        unawaited(
          MarketingFlowService(widget.supabase).syncExpiredContractCreationWindows(),
        );
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _fmtRemaining(Duration d) {
    if (d.isNegative) return widget.isAr ? '٠' : '0';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (widget.isAr) {
      return '$hس $mد';
    }
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final left = _deadline.difference(now);
    final expired = left.isNegative;

    return Material(
      color: expired
          ? cs.errorContainer.withValues(alpha: 0.45)
          : cs.primaryContainer.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              expired ? Icons.timer_off_outlined : Icons.timer_outlined,
              color: expired ? cs.error : cs.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                expired
                    ? (widget.isAr
                        ? 'انتهت مهلة ٧٢ ساعة لإنشاء العقد. حدّث الصفحة أو ارجع إلى «إدارتي» — قد يُعاد طرح الطلب تلقائياً.'
                        : 'The 72-hour window to create the contract has ended. Refresh or check «My hub» — the request may reopen for offers.')
                    : (widget.isAr
                        ? 'المتبقي لإنشاء العقد: ${_fmtRemaining(left)} (مهلة ٧٢ ساعة من قبول المالك).'
                        : 'Time left to create the contract: ${_fmtRemaining(left)} (72h from owner acceptance).'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  height: 1.35,
                  color: expired ? cs.onErrorContainer : cs.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonoBox extends StatelessWidget {
  final String label;
  final String value;

  const _MonoBox({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Monospace',
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String title;
  final double value;
  final String currencyCode;
  final bool isAr;
  final bool bold;
  final bool big;
  final bool highlight;

  const _PriceRow({
    required this.title,
    required this.value,
    required this.currencyCode,
    required this.isAr,
    this.bold = false,
    this.big = false,
    this.highlight = false,
  });

  String _fmt(num v) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();

    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }

    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final valueStyle = TextStyle(
      color: const Color(0xFF0F766E),
      fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
      fontSize: big ? 18 : 14,
    );

    final trailing = currencyCode.trim().toUpperCase() == 'SAR'
        ? AppMoneyLine(
            amount: value,
            currencyCode: 'SAR',
            isAr: isAr,
            maxFractionDigits: 0,
            style: valueStyle,
          )
        : Text(
            '${_fmt(value)} $currencyCode',
            style: valueStyle,
          );

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 5,
          child: Text(
            title,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: big ? 16 : 14,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(flex: 6, child: trailing),
      ],
    );

    if (!highlight) return row;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF0F766E).withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: row,
      ),
    );
  }
}
