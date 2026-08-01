/// مراحل موحّدة. قبل النشر: يُفضَّل `listing_requests.workflow_stage` (+ `status` احتياطي).
/// بعد النشر: مرآة على `properties.workflow_stage` (+ `status` + `published_at`).
enum ListingWorkflowStage {
  addedByOwner,
  waitingMarketers,
  marketerSelected,
  contractPending,
  contractSent,
  contractReturned,
  contractSigned,
  contractCancelled,
  permitPending,
  permitIssued,
  published,
  reserved,
  inactive72h,
  cancelled,
  terminated,
  archived;

  String get wireValue {
    switch (this) {
      case ListingWorkflowStage.addedByOwner:
        return 'added_by_owner';
      case ListingWorkflowStage.waitingMarketers:
        return 'waiting_marketers';
      case ListingWorkflowStage.marketerSelected:
        return 'marketer_selected';
      case ListingWorkflowStage.contractPending:
        return 'contract_pending';
      case ListingWorkflowStage.contractSent:
        return 'contract_sent';
      case ListingWorkflowStage.contractReturned:
        return 'contract_returned';
      case ListingWorkflowStage.contractSigned:
        return 'contract_signed';
      case ListingWorkflowStage.contractCancelled:
        return 'contract_cancelled';
      case ListingWorkflowStage.permitPending:
        return 'permit_pending';
      case ListingWorkflowStage.permitIssued:
        return 'permit_issued';
      case ListingWorkflowStage.published:
        return 'published';
      case ListingWorkflowStage.reserved:
        return 'reserved';
      case ListingWorkflowStage.inactive72h:
        return 'inactive_72h';
      case ListingWorkflowStage.cancelled:
        return 'cancelled';
      case ListingWorkflowStage.terminated:
        return 'terminated';
      case ListingWorkflowStage.archived:
        return 'archived';
    }
  }

  static ListingWorkflowStage? tryParse(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty) return null;
    for (final v in ListingWorkflowStage.values) {
      if (v.wireValue == s) return v;
    }
    return null;
  }

  /// يحلّ المرحلة من [workflowStage] و/أو [legacyStatus] و [publishedAt].
  ///
  /// بعد النشر: إن وُجد `published_at` أو [legacyStatus] يدل على إعلان حيّ،
  /// نعتبره **منشورًا** حتى لو بقي `workflow_stage` بقيمة مرحلة سابقة (مثل
  /// `permit_issued`) — وهذا يوافق بيانات المرآة في `properties` أحيانًا.
  static ListingWorkflowStage resolve({
    String? workflowStage,
    String? legacyStatus,
    DateTime? publishedAt,
  }) {
    // مرحلة workflow صريحة «بانتظار المسوقين» تسبق legacy status قديم (active/published)
    // بعد إعادة طرح الطلب في السوق — كان يُعرض «منشور» ويُحظر تقديم العرض خطأً.
    final wsEarly = tryParse(workflowStage);
    if (wsEarly == ListingWorkflowStage.waitingMarketers ||
        wsEarly == ListingWorkflowStage.addedByOwner) {
      return wsEarly!;
    }

    final st = (legacyStatus ?? '').trim().toLowerCase();
    final publishedLike = publishedAt != null ||
        const {
          'published',
          'active',
          'approved',
          'live',
          'available',
          'listed',
          'open',
          'visible',
          'for_sale',
          'for_rent',
          'forsale',
          'forrent',
        }.contains(st);

    if (st == 'reserved') {
      return ListingWorkflowStage.reserved;
    }

    if (publishedLike) {
      final wsDirect = tryParse(workflowStage);
      if (wsDirect == ListingWorkflowStage.reserved) {
        return ListingWorkflowStage.reserved;
      }
      if (wsDirect != null &&
          const {
            ListingWorkflowStage.inactive72h,
            ListingWorkflowStage.cancelled,
            ListingWorkflowStage.terminated,
            ListingWorkflowStage.archived,
            ListingWorkflowStage.contractCancelled,
          }.contains(wsDirect)) {
        return wsDirect;
      }
      return ListingWorkflowStage.published;
    }

    final direct = tryParse(workflowStage);
    if (direct != null) return direct;

    // owner_action_required (v8 — أتمتة 72h) → يَظهر في تبويب «لم يُتَّخذ إجراء»
    final wsRaw = (workflowStage ?? '').trim().toLowerCase();
    if (wsRaw == 'owner_action_required') {
      return ListingWorkflowStage.inactive72h;
    }

    if (const {
      'inactive_72h',
      'inactive72h',
      'owner_action_required',
    }.contains(st)) {
      return ListingWorkflowStage.inactive72h;
    }
    if (st == 'contract_cancelled') {
      return ListingWorkflowStage.contractCancelled;
    }
    if (const {'cancelled', 'canceled'}.contains(st)) {
      return ListingWorkflowStage.cancelled;
    }
    if (st == 'terminated') return ListingWorkflowStage.terminated;
    if (const {'archived', 'deleted', 'closed', 'sold', 'completed'}
        .contains(st)) {
      return ListingWorkflowStage.archived;
    }

    // Legacy marketing path
    if (const {
      'waiting_mediator',
      'awaiting_mediator',
      'draft',
      'pending',
      'new',
      'invited',
    }.contains(st)) {
      return ListingWorkflowStage.waitingMarketers;
    }
    // وُجدت عروض / تعيين مسوّق (legacy). في «صفحتي» يُطبَّق شرط selected_offer_id
    // عبر [ListingWorkflowUnified.fromMergedOwnerHubRow] حتى لا ينتقل التبويب قبل قبول المالك.
    if (const {
      'offers_received',
      'assigned',
      'marketer_selected',
    }.contains(st)) {
      return ListingWorkflowStage.marketerSelected;
    }
    if (const {
      'contract',
      'pending_owner',
      'await_contract',
      'awaiting_contract',
    }.contains(st)) {
      return ListingWorkflowStage.contractSent;
    }
    if (const {
      'signed',
      'contract_signed',
    }.contains(st)) {
      return ListingWorkflowStage.contractSigned;
    }
    if (const {
      'awaiting_permits',
      'pending_permits',
      'permit_submitted',
      'permits_submitted',
      'submitted',
    }.contains(st)) {
      return ListingWorkflowStage.permitPending;
    }

    return ListingWorkflowStage.waitingMarketers;
  }
}
