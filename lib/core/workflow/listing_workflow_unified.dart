import 'listing_workflow_stage.dart';

DateTime? _parseDt(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// مركز واحد: قبل النشر من `listing_requests`، بعد النشر من `Property` / صف `properties`.
class ListingWorkflowUnified {
  ListingWorkflowUnified._();

  /// حالات الطلب التي تعني «وصلت عروض» لكن لا تُنقل لتبويب التعاقد قبل قبول المالك.
  static const _offerLikePreAcceptStatuses = {
    'offers_received',
    'assigned',
    'marketer_selected',
  };

  /// يُضبط من [user_dashboard.marketing_loaders] بعد جلب `listing_offers.expires_at`.
  static bool offersDeadlineFullyPast(Map<String, dynamic> r) {
    final v = r['_owner_offers_all_expired_by_deadline'];
    if (v == true) return true;
    if (v == 1 || v == '1' || '$v'.toLowerCase() == 'true') return true;
    return false;
  }

  static bool _pendingOfferStatus(String st) =>
      const {
        'submitted',
        'pending',
        '',
        'active',
        'expired',
        'offer_expired',
        'deadline_passed',
        'timed_out',
        'no_action',
      }.contains(st);

  static bool _offerStatusPastOwnerDeadline(String st) =>
      const {
        'expired',
        'offer_expired',
        'deadline_passed',
        'timed_out',
        'no_action',
        'inactive_72h',
      }.contains(st);

  static const Duration _ownerDecisionWindow = Duration(hours: 72);

  /// انتهت مهلة انتظار قرار المالك — `expires_at` أو 72 ساعة من `created_at`.
  static bool offerAwaitingOwnerPastDeadline(Map<String, dynamic> r) {
    final st = (r['status'] ?? '').toString().toLowerCase().trim();
    if (_offerStatusPastOwnerDeadline(st)) return true;
    if (!_pendingOfferStatus(st)) return false;
    final now = DateTime.now().toUtc();
    final exp = _parseDt(r['expires_at']);
    if (exp != null) {
      return !exp.toUtc().isAfter(now);
    }
    final created = _parseDt(r['created_at']);
    if (created == null) return false;
    return now.isAfter(created.toUtc().add(_ownerDecisionWindow));
  }

  /// عرض المسوّق الحالي انتهت مهلة انتظار قرار المالك (`expires_at`).
  static bool marketerOwnOfferPastDeadline(Map<String, dynamic> r) {
    if (!_marketerRowIsListingOffer(r)) return false;
    return offerAwaitingOwnerPastDeadline(r);
  }

  /// الطلب أو عرض المسوّق تجاوز مهلة 72 ساعة دون قبول المالك.
  static bool marketerOfferAwaitingOwnerPastDeadline(Map<String, dynamic> r) {
    if (r['_hub_inactive_72h'] == true) return true;
    if (offersDeadlineFullyPast(r)) return true;
    return marketerOwnOfferPastDeadline(r);
  }

  /// بطاقة «صفحتي» للمسوّق — تبويب بدون إجراء 72 ساعة.
  static bool marketerHubRowInactive72h(Map<String, dynamic> r) {
    if (marketerOfferAwaitingOwnerPastDeadline(r)) return true;
    return fromMarketerMergedRow(r) == ListingWorkflowStage.inactive72h;
  }

  static bool _marketerRowIsListingOffer(Map<String, dynamic> r) {
    final hk = (r['_hubKind'] ?? r['_ui_type'] ?? '').toString().trim();
    if (hk == 'offer') return true;
    return r.containsKey('offer_amount');
  }

  static bool _noSelectedOfferYet(Map<String, dynamic> r) {
    final v = r['selected_offer_id'];
    if (v == null) return true;
    return v.toString().trim().isEmpty;
  }

  /// قبول المالك قد يُحدَّث فيه [selected_marketer_id] / [contract_id] قبل اكتمال
  /// تعبئة [selected_offer_id] في بعض نسخ الـ RPC — لا نُبقِ الطلب في «بانتظار المسوقين» حينها.
  static bool _ownerCommittedToMarketerYet(Map<String, dynamic> r) {
    final sm = (r['selected_marketer_id'] ?? '').toString().trim();
    if (sm.isNotEmpty) return true;
    final cid = (r['contract_id'] ?? '').toString().trim();
    return cid.isNotEmpty;
  }

  /// `workflow_stage` من الطلب يدل أن المالك تجاوز استقبال العروض حتى لو بقي [status] قديماً.
  static bool _permitDeadlineExpired(Map<String, dynamic> r) {
    for (final k in const [
      'permit_deadline_at',
      'request_permit_deadline_at',
      'permits_due_at',
    ]) {
      final d = _parseDt(r[k]);
      if (d != null && d.isBefore(DateTime.now())) return true;
    }
    return false;
  }

  static bool _stageIsPrePublishPostApproval(ListingWorkflowStage stage) {
    return const {
      ListingWorkflowStage.marketerSelected,
      ListingWorkflowStage.contractPending,
      ListingWorkflowStage.contractSent,
      ListingWorkflowStage.contractReturned,
      ListingWorkflowStage.contractSigned,
      ListingWorkflowStage.permitPending,
      ListingWorkflowStage.permitIssued,
    }.contains(stage);
  }

  static ListingWorkflowStage _applyPublishDeadlineExpiry(
    ListingWorkflowStage stage,
    Map<String, dynamic> r,
  ) {
    if (!_stageIsPrePublishPostApproval(stage)) return stage;
    if (!_permitDeadlineExpired(r)) return stage;
    return ListingWorkflowStage.inactive72h;
  }

  static bool _workflowStagePastOfferCollection(Map<String, dynamic> r) {
    final raw = (r['workflow_stage'] ?? r['request_workflow_stage'] ?? '')
        .toString()
        .trim();
    final ws = ListingWorkflowStage.tryParse(raw);
    if (ws == null) return false;
    return ws != ListingWorkflowStage.waitingMarketers &&
        ws != ListingWorkflowStage.addedByOwner;
  }

  /// بعد إعادة الطلب للسوق: لا نعتمد `published_at` من معاينة العقار.
  static bool requestActivelyCollectingOffers(Map<String, dynamic> r) {
    final ws = (r['workflow_stage'] ?? r['request_workflow_stage'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (ws == 'waiting_marketers' || ws == 'added_by_owner') return true;
    final st = (r['status'] ?? r['listing_request_status'] ?? r['request_status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return const {
      'waiting_marketers',
      'new',
      'invited',
      'pending',
      'offers_received',
    }.contains(st);
  }

  static bool _requestActivelyCollectingOffers(Map<String, dynamic> r) =>
      requestActivelyCollectingOffers(r);

  static DateTime? _publishedAtForResolve(Map<String, dynamic> r) {
    if (_requestActivelyCollectingOffers(r)) return null;
    return _parseDt(r['preview_published_at']) ?? _parseDt(r['published_at']);
  }

  static ListingWorkflowStage fromListingRequestRow(Map<String, dynamic> r) {
    return ListingWorkflowStage.resolve(
      workflowStage: r['workflow_stage']?.toString(),
      legacyStatus: (r['status'] ?? r['listing_request_status'])?.toString(),
      publishedAt: null,
    );
  }

  /// صف مدمج (طلب + معاينة عقار): يدمج `status` مع `workflow_stage`.
  /// إن بقي `workflow_stage` على `waiting_marketers` بينما `status` يدل على وصول عروض،
  /// نعتمد الحالة الوراثية حتى يتطابق التبويب مع الواقع.
  static ListingWorkflowStage fromMergedOwnerHubRow(Map<String, dynamic> r) {
    if (_workflowStagePastOfferCollection(r)) {
      final legacy =
          (r['status'] ?? r['listing_request_status'])?.toString() ?? '';
      final reqStage = (r['workflow_stage'] ?? r['request_workflow_stage'])
          ?.toString();
      final wsTrim = (reqStage ?? '').trim();
      final wsRaw = wsTrim.isEmpty ? null : wsTrim;
      return _applyPublishDeadlineExpiry(
        ListingWorkflowStage.resolve(
          workflowStage: wsRaw,
          legacyStatus: legacy,
          publishedAt: null,
        ),
        r,
      );
    }

    final legacy =
        (r['status'] ?? r['listing_request_status'])?.toString() ?? '';
    final st = legacy.trim().toLowerCase();
    // قبل تعيين [selected_offer_id] يبقى الطلب في «بانتظار المسوقين» حتى مع وصول عروض،
    // ما لم يُثبت اختيار مسوّق (مثل تعبئة [selected_marketer_id] من قبول العرض).
    if (_noSelectedOfferYet(r) && !_ownerCommittedToMarketerYet(r)) {
      if (offersDeadlineFullyPast(r)) {
        return ListingWorkflowStage.inactive72h;
      }
      if (_offerLikePreAcceptStatuses.contains(st)) {
        return ListingWorkflowStage.waitingMarketers;
      }
    }
    final reqStage = (r['workflow_stage'] ?? r['request_workflow_stage'])
        ?.toString();
    final wsTrim = (reqStage ?? '').trim();
    final wsRaw = wsTrim.isEmpty ? null : wsTrim;
    final ignoreWs = _offerLikePreAcceptStatuses.contains(st);
    final resolved = ListingWorkflowStage.resolve(
      workflowStage: ignoreWs ? null : wsRaw,
      legacyStatus: legacy,
      publishedAt: null,
    );
    return _applyPublishDeadlineExpiry(resolved, r);
  }

  /// صف مسوّق (دعوة/عرض + بيانات الطلب المدمجة).
  /// يطابق منطق [fromMergedOwnerHubRow]: إن وُجدت عروض (`offers_received` …) لا نثق
  /// بـ `workflow_stage` إن كان قديماً على `waiting_marketers`.
  static ListingWorkflowStage fromMarketerMergedRow(Map<String, dynamic> r) {
    if (_workflowStagePastOfferCollection(r)) {
      final legacy = (r['listing_request_status'] ?? r['request_status'] ?? '')
          .toString();
      final reqStage =
          (r['request_workflow_stage'] ?? r['workflow_stage'])?.toString();
      final wsTrim = (reqStage ?? '').trim();
      final wsRaw = wsTrim.isEmpty ? null : wsTrim;
      final resolved = ListingWorkflowStage.resolve(
        workflowStage: wsRaw,
        legacyStatus: legacy,
        publishedAt: _publishedAtForResolve(r),
      );
      return _applyPublishDeadlineExpiry(resolved, r);
    }

    // لا نستخدم r['status'] هنا: في صفوف الدعوة/العرض/العقد هو حالة السطر وليس الطلب.
    if (_marketerRowIsListingOffer(r) &&
        _noSelectedOfferYet(r) &&
        !_ownerCommittedToMarketerYet(r) &&
        marketerOfferAwaitingOwnerPastDeadline(r)) {
      return ListingWorkflowStage.inactive72h;
    }
    final legacyForOffers = (r['listing_request_status'] ??
            r['request_status'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    if (_noSelectedOfferYet(r) &&
        !_ownerCommittedToMarketerYet(r) &&
        _offerLikePreAcceptStatuses.contains(legacyForOffers)) {
      return ListingWorkflowStage.waitingMarketers;
    }
    final reqStage =
        (r['request_workflow_stage'] ?? r['workflow_stage'])?.toString();
    final wsTrim = (reqStage ?? '').trim();
    final wsRaw = wsTrim.isEmpty ? null : wsTrim;
    final ignoreWs = _offerLikePreAcceptStatuses.contains(legacyForOffers);
    final legacy = (r['listing_request_status'] ?? r['request_status'] ?? '')
        .toString();
    final resolved = ListingWorkflowStage.resolve(
      workflowStage: ignoreWs ? null : wsRaw,
      legacyStatus: legacy,
      publishedAt: _publishedAtForResolve(r),
    );
    return _applyPublishDeadlineExpiry(resolved, r);
  }
}
