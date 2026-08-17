class ListingStatus {
  // Owner flow
  static const String pending = 'pending';
  static const String newRequest = 'new';
  static const String invited = 'invited';
  static const String offersReceived = 'offers_received';
  static const String assigned = 'assigned';
  static const String contract = 'contract';
  /// بانتظار توقيع المسوق على عقد التسويق (واجهة/إشعارات — ليس enum قاعدة البيانات).
  static const String pendingMarketer = 'pending_marketer';
  static const String pendingOwner = 'pending_owner';
  static const String signed = 'signed';
  static const String awaitingContract = 'awaiting_contract';
  static const String awaitContract = 'await_contract';
  static const String awaitingPermits = 'awaiting_permits';
  static const String pendingPermits = 'pending_permits';
  static const String permitSubmitted = 'permit_submitted';
  static const String permitsSubmitted = 'permits_submitted';
  static const String submitted = 'submitted';
  static const String published = 'published';
  static const String active = 'active';
  static const String approved = 'approved';
  static const String live = 'live';
  static const String declined = 'declined';
  static const String rejected = 'rejected';

  // Buckets for UI mapping
  static const Set<String> ownerPendingLike = {
    pending,
    newRequest,
    invited,
    // مسارات العقار/الطلب قبل العقد (إضافة إعلان عقار)
    'waiting_mediator',
    'awaiting_mediator',
    'draft',
    'waiting_marketers',
    'added_by_owner',
  };

  /// وُجدت عروض أو اختيار مسوّق — تبويب «بانتظار التعاقد» مع مراحل العقد لاحقًا.
  static const Set<String> ownerPreContractOffers = {
    offersReceived,
    assigned,
    'marketer_selected',
  };

  static const Set<String> ownerContractLike = {
    contract,
    pendingOwner,
    signed,
    awaitContract,
    awaitingContract,
    awaitingPermits,
    pendingPermits,
    permitSubmitted,
    permitsSubmitted,
    submitted,
  };

  static const Set<String> publishedLike = {
    published,
    active,
    approved,
    live,
  };
}

class WorkflowNotificationKeys {
  static const String role = 'role';
  static const String targetRole = 'target_role';
  static const String status = 'status';
  static const String requestStatus = 'request_status';
  static const String stage = 'stage';
  static const String mainTab = 'main_tab';
  static const String tab = 'tab';
  static const String section = 'section';
  /// قيم مثل: owner_offers، listing_request_status، marketer_dashboard، in_app_notifications
  static const String deepRoute = 'deep_route';
  static const String requestId = 'request_id';
  static const String previewPropertyId = 'preview_property_id';
  static const String propertyId = 'property_id';
  static const String listingId = 'listing_id';
  static const String entityId = 'entity_id';
  /// فهرس تبويب فرعي داخل «صفحتي» عند فتح إشعار سير العمل.
  /// المالك: 0..8 (تسعة تبويبات بما فيها «التصريح — 72 ساعة»)؛ المسوّق: 0..6.
  static const String myAdsSubTab = 'my_ads_sub_tab';

  /// عند ≥2: قيم [myAdsSubTab] لمالك 8 تبويبات؛ عند ≥3: 9 تبويبات؛ عند ≥4: 7 تبويبات (انظر `hub_tab_schema_v`).
  static const String hubTabSchemaV = 'hub_tab_schema_v';
}

class WorkflowMainSections {
  static const String home = 'home';
  static const String myAds = 'my_ads';
  static const String favorites = 'favorites';
  /// طلباتي (إعلاناتي + طلبات السوق التي قدّمتها).
  static const String mySubmissions = 'my_submissions';
  static const String chat = 'chat';
  static const String cart = 'cart';
  static const String reservations = 'reservations';
}

class ListingWorkflowMapper {
  static String normalize(String? status) {
    return (status ?? '').trim().toLowerCase();
  }

  static bool isPublishedLike(String? status) {
    return ListingStatus.publishedLike.contains(normalize(status));
  }

  static bool isOwnerPendingLike(String? status) {
    return ListingStatus.ownerPendingLike.contains(normalize(status));
  }

  static bool isOwnerContractLike(String? status) {
    return ListingStatus.ownerContractLike.contains(normalize(status));
  }

  /// تبويبات صاحب الإعلان (صفحتي): 7 تبويبات (0..6).
  /// 0 بانتظار المسوقين، 1 العروض المقدمة، 2 التعاقد، 3 توقف 72س، 4 ملغى، 5 محجوز، 6 صفقات مكتملة.
  static int ownerSubTabIndex(String? status) {
    final s = normalize(status);
    if (s == 'sold' || s == 'completed') return 6;
    if (s.contains('inactive') && (s.contains('72') || s.contains('72h'))) {
      return 3;
    }
    if (s.contains('cancel') ||
        s.contains('terminat') ||
        s == 'archived' ||
        s == 'contract_cancelled') {
      return 4;
    }
    if (s == 'reserved' || s.contains('reservation')) {
      return 5;
    }
    if (ListingStatus.publishedLike.contains(s)) return 0;
    if (s == ListingStatus.signed ||
        s == 'contract_signed' ||
        s == ListingStatus.permitSubmitted ||
        s == ListingStatus.submitted ||
        s == ListingStatus.awaitingPermits ||
        s == ListingStatus.pendingPermits ||
        ListingStatus.ownerContractLike.contains(s)) {
      return 2;
    }
    if (ListingStatus.ownerPreContractOffers.contains(s)) return 1;
    return 0;
  }

  static bool isOwnerPreContractOffers(String? status) {
    return ListingStatus.ownerPreContractOffers.contains(normalize(status));
  }

  /// تبويبات المسوّق في «صفحتي» (0..4): 0 السوق، 1 عروضي، 2 تم الموافقة، 3 توقف 72س، 4 ملغى.
  static int marketerSubTabIndex(String? status) {
    final s = normalize(status);
    if (s == 'inactive_72h' ||
        s == 'inactive72h' ||
        (s.contains('inactive') && (s.contains('72') || s.contains('72h')))) {
      return 3;
    }
    if (s == 'cancelled' ||
        s == 'terminated' ||
        s == 'archived' ||
        s == 'contract_cancelled') {
      return 4;
    }
    if (ListingStatus.publishedLike.contains(s)) return 0;
    if (s == ListingStatus.permitSubmitted ||
        s == ListingStatus.submitted ||
        s == ListingStatus.awaitingPermits ||
        s == ListingStatus.pendingPermits ||
        s == ListingStatus.contract ||
        s == ListingStatus.pendingMarketer ||
        s == ListingStatus.pendingOwner ||
        s == ListingStatus.signed ||
        s == ListingStatus.awaitContract ||
        s == ListingStatus.awaitingContract ||
        s == 'contract_signed' ||
        s == 'marketer_selected') {
      return 2;
    }
    if (s == ListingStatus.offersReceived ||
        s == ListingStatus.assigned ||
        s == ListingStatus.rejected ||
        s == ListingStatus.declined) {
      return 1;
    }
    return 0;
  }

  /// Owner card visual journey:
  /// 0 created, 1 offers, 2 contract, 3 permits waiting, 4 permits review, 5 published
  static int ownerStageIndex(String? status, {required bool hasPublishedAt}) {
    final s = normalize(status);

    if (hasPublishedAt || ListingStatus.publishedLike.contains(s)) return 5;

    if (s == ListingStatus.submitted ||
        s == ListingStatus.permitSubmitted ||
        s == ListingStatus.permitsSubmitted ||
        s == 'awaiting_owner_permit_approval' ||
        s == 'pending_owner_permit') {
      return 4;
    }

    if (s == ListingStatus.signed ||
        s == 'contract_signed' ||
        s == ListingStatus.awaitingPermits ||
        s == 'permit_waiting' ||
        s == 'permits_pending' ||
        s == ListingStatus.pendingPermits) {
      return 3;
    }

    if (s == ListingStatus.contract ||
        s == ListingStatus.pendingOwner ||
        s == ListingStatus.awaitContract ||
        s == ListingStatus.awaitingContract) {
      return 2;
    }

    if (s == ListingStatus.offersReceived ||
        s == ListingStatus.invited ||
        s == ListingStatus.assigned) {
      return 1;
    }

    return 0;
  }
}
