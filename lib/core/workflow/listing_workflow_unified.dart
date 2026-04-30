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

  static bool _noSelectedOfferYet(Map<String, dynamic> r) {
    final v = r['selected_offer_id'];
    if (v == null) return true;
    return v.toString().trim().isEmpty;
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
    final legacy =
        (r['status'] ?? r['listing_request_status'])?.toString() ?? '';
    final st = legacy.trim().toLowerCase();
    // قبل تعيين [selected_offer_id] يبقى الطلب في «بانتظار المسوقين» حتى مع وصول عروض.
    if (_noSelectedOfferYet(r) && _offerLikePreAcceptStatuses.contains(st)) {
      return ListingWorkflowStage.waitingMarketers;
    }
    final reqStage = (r['workflow_stage'] ?? r['request_workflow_stage'])
        ?.toString();
    final wsTrim = (reqStage ?? '').trim();
    final wsRaw = wsTrim.isEmpty ? null : wsTrim;
    final ignoreWs = _offerLikePreAcceptStatuses.contains(st);
    return ListingWorkflowStage.resolve(
      workflowStage: ignoreWs ? null : wsRaw,
      legacyStatus: legacy,
      publishedAt: null,
    );
  }

  /// صف مسوّق (دعوة/عرض + بيانات الطلب المدمجة).
  /// يطابق منطق [fromMergedOwnerHubRow]: إن وُجدت عروض (`offers_received` …) لا نثق
  /// بـ `workflow_stage` إن كان قديماً على `waiting_marketers`.
  static ListingWorkflowStage fromMarketerMergedRow(Map<String, dynamic> r) {
    // لا نستخدم r['status'] هنا: في صفوف الدعوة/العرض/العقد هو حالة السطر وليس الطلب.
    final legacyForOffers = (r['listing_request_status'] ??
            r['request_status'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    if (_noSelectedOfferYet(r) &&
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
    final publishedAt = _parseDt(r['preview_published_at']) ??
        _parseDt(r['published_at']);
    return ListingWorkflowStage.resolve(
      workflowStage: ignoreWs ? null : wsRaw,
      legacyStatus: legacy,
      publishedAt: publishedAt,
    );
  }
}
