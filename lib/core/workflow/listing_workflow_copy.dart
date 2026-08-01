import 'listing_workflow_stage.dart';
import 'listing_workflow_ui_context.dart';

/// نصوص موحّدة لمرحلة التسويق/العروض (عربي + إنجليزي جاهزة للتوسعة).
abstract final class ListingWorkflowCopy {

  static String t(bool isAr, String ar, String en) => isAr ? ar : en;

  /// نص جولة التسويق (بدل الرقم وحده).
  static String marketingRoundLabel(bool isAr, dynamic roundRaw) {
    final n = roundRaw is num
        ? roundRaw.toInt()
        : int.tryParse(roundRaw?.toString().trim() ?? '') ?? 0;
    if (n <= 0) {
      return isAr ? 'جولة التسويق' : 'Marketing round';
    }
    if (isAr) {
      switch (n) {
        case 1:
          return 'الجولة الأولى';
        case 2:
          return 'الجولة الثانية';
        case 3:
          return 'الجولة الثالثة';
        case 4:
          return 'الجولة الرابعة';
        case 5:
          return 'الجولة الخامسة';
        default:
          return 'الجولة رقم $n';
      }
    }
    switch (n) {
      case 1:
        return 'First round';
      case 2:
        return 'Second round';
      case 3:
        return 'Third round';
      default:
        return 'Round $n';
    }
  }

  // ---------------------------------------------------------------------------
  // أزرار مشتركة
  // ---------------------------------------------------------------------------
  static String btnAcceptOffer(bool isAr) =>
      t(isAr, 'قبول العرض', 'Accept offer');

  static String btnDeclineOffer(bool isAr) =>
      t(isAr, 'رفض هذا العرض', 'Decline this offer');

  static String btnRefresh(bool isAr) => t(isAr, 'تحديث', 'Refresh');

  static String btnRetry(bool isAr) => t(isAr, 'إعادة المحاولة', 'Retry');

  static String btnSendOffer(bool isAr) =>
      t(isAr, 'إرسال عرض تسويقي', 'Send marketing offer');

  static String btnSubmit(bool isAr) => t(isAr, 'إرسال', 'Submit');

  static String btnDoneReview(bool isAr) =>
      t(isAr, 'أنهيت المراجعة', 'Done reviewing');

  static String btnStartContract(bool isAr) =>
      t(isAr, 'بدء العقد', 'Start contract');

  /// مسوّق: العقد بحالة `pending_owner` (workflow contract_sent).
  static String marketerAwaitingContractTitle(bool isAr) =>
      t(isAr, 'بانتظار مراجعة المالك', 'Awaiting owner review');

  static String marketerAwaitingContractBody(bool isAr) => t(
        isAr,
        'أُرسل العقد للمالك. بانتظار مراجعته أو توقيعه أو إعادته للتعديل.',
        'The contract was sent to the owner. Waiting for review, signature, or return.',
      );

  static String snackContractFromOfferCreated(bool isAr) => t(
        isAr,
        'تم إنشاء مسودة العقد وربطها بالعرض. سيقوم المسوق بإرسالها لك من تبويب التعاقد.',
        'Draft contract created and linked to the offer. The marketer will send it from the contracting tab.',
      );

  // ---------------------------------------------------------------------------
  // عقد التسويق (contract_status)
  // ---------------------------------------------------------------------------
  static String btnSendContract(bool isAr) =>
      t(isAr, 'إرسال العقد', 'Send contract');

  static String btnReviewContract(bool isAr) =>
      t(isAr, 'مراجعة العقد', 'Review contract');

  static String btnReturnContract(bool isAr) =>
      t(isAr, 'إعادة العقد', 'Return contract');

  static String lblReturnReason(bool isAr) =>
      t(isAr, 'سبب إعادة العقد', 'Return reason');

  static String btnSignContract(bool isAr) =>
      t(isAr, 'توقيع العقد', 'Sign contract');

  static String ownerAwaitingMarketerEdit(bool isAr) => t(
        isAr,
        'العقد بانتظار تعديل المسوق',
        'The contract is waiting for the marketer to revise it',
      );

  static String marketerContractReturnedTitle(bool isAr) =>
      t(isAr, 'تم إعادة العقد من المالك', 'Contract returned by owner');

  static String contractSignedDone(bool isAr) =>
      t(isAr, 'تم توقيع العقد', 'Contract signed');

  static String contractCancelledDone(bool isAr) =>
      t(isAr, 'تم إلغاء العقد', 'Contract cancelled');

  static String contractCannotSendStage(bool isAr) => t(
        isAr,
        'لا يمكن إرسال العقد في هذه المرحلة',
        'The contract cannot be sent at this stage',
      );

  static String contractCannotSignStage(bool isAr) => t(
        isAr,
        'لا يمكن توقيع العقد في هذه المرحلة',
        'The contract cannot be signed at this stage',
      );

  static String btnResendContract(bool isAr) =>
      t(isAr, 'إعادة الإرسال للمالك', 'Resend to owner');

  static String btnCancelContract(bool isAr) =>
      t(isAr, 'إلغاء العقد', 'Cancel contract');

  static String ownerDraftContractHint(bool isAr) => t(
        isAr,
        'توجد مسودة عقد: بانتظار أن يرسلها المسوق إليك للمراجعة.',
        'There is a draft contract: waiting for the marketer to send it to you.',
      );

  // ---------------------------------------------------------------------------
  // حالات العرض (قصيرة للشارة / طويلة للوصف)
  // ---------------------------------------------------------------------------
  static String offerStatusShort(bool isAr, String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'submitted':
        return t(isAr, 'تم إرسال العرض', 'Offer sent');
      case 'pending':
        return t(isAr, 'قيد المراجعة', 'Under review');
      case 'owner_accepted':
        return t(isAr, 'تم قبول العرض', 'Owner accepted');
      case 'owner_rejected':
        return t(isAr, 'لم يُختر', 'Not selected');
      case 'expired':
        return t(isAr, 'انتهت المهلة', 'Expired');
      case 'cancelled':
        return t(isAr, 'مُلغى', 'Cancelled');
      case 'converted_to_contract':
        return t(isAr, 'تحويل لعقد', 'Contract');
      case 'rejected':
        return t(isAr, 'مرفوض', 'Rejected');
      case 'withdrawn':
        return t(isAr, 'مسحوب', 'Withdrawn');
      case 'marketer_revised':
        return t(isAr, 'معدَّل', 'Revised');
      case 'marketer_accepted_rejection_reason':
        return t(isAr, 'قُبل سبب الرفض', 'Rejection reason accepted');
      case 'selected':
        return t(isAr, 'تم اختياره', 'Selected');
      // بيانات قديمة أو غير متوقعة — عرض مقروء دون كسر الواجهة
      case 'viewed':
        return t(isAr, 'قيد المراجعة', 'Under review');
      case 'accepted':
        return offerStatusShort(isAr, 'owner_accepted');
      case 'auto_closed':
        return offerStatusShort(isAr, 'owner_rejected');
      case 'closed':
        return offerStatusShort(isAr, 'cancelled');
      case 'declined':
        return offerStatusShort(isAr, 'rejected');
      default:
        return s.isEmpty ? '—' : raw;
    }
  }

  /// وصف أوضح تحت الشارة أو في تفاصيل البطاقة.
  static String offerStatusLong(bool isAr, String raw) {
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'submitted':
        return t(
          isAr,
          'تم إرسال العرض — يمكنك قبوله أو رفضه.',
          'The offer was submitted — you can accept or decline.',
        );
      case 'pending':
        return t(
          isAr,
          'العرض قيد المراجعة.',
          'This offer is under review.',
        );
      case 'owner_accepted':
        return t(
          isAr,
          'تم اختيار هذا العرض.',
          'This offer was selected.',
        );
      case 'owner_rejected':
        return t(
          isAr,
          'لم يتم اختيار هذا العرض (جرى اختيار عرض آخر في نفس الجولة).',
          'This offer was not selected (another offer was chosen in this round).',
        );
      case 'expired':
        return t(
          isAr,
          'انتهت مهلة الرد على هذا العرض.',
          'The response window for this offer has expired.',
        );
      case 'cancelled':
        return t(
          isAr,
          'تم إلغاء هذا العرض.',
          'This offer was cancelled.',
        );
      case 'converted_to_contract':
        return t(
          isAr,
          'تم تحويل هذا العرض إلى عقد.',
          'This offer was converted to a contract.',
        );
      case 'rejected':
        return t(
          isAr,
          'تم رفض هذا العرض.',
          'This offer was rejected.',
        );
      case 'withdrawn':
        return t(
          isAr,
          'سحب المسوق هذا العرض.',
          'The marketer withdrew this offer.',
        );
      case 'marketer_revised':
        return t(
          isAr,
          'قام المسوق بتعديل العرض.',
          'The marketer revised this offer.',
        );
      case 'marketer_accepted_rejection_reason':
        return t(
          isAr,
          'وافق المسوق على سبب الرفض.',
          'The marketer accepted the rejection reason.',
        );
      case 'selected':
        return t(
          isAr,
          'تم اختيار هذا العرض (سجل قديم).',
          'This offer was selected (legacy record).',
        );
      case 'viewed':
        return offerStatusLong(isAr, 'pending');
      case 'accepted':
        return offerStatusLong(isAr, 'owner_accepted');
      case 'auto_closed':
        return offerStatusLong(isAr, 'owner_rejected');
      case 'closed':
        return offerStatusLong(isAr, 'cancelled');
      case 'declined':
        return offerStatusLong(isAr, 'rejected');
      default:
        return offerStatusShort(isAr, raw);
    }
  }

  // ---------------------------------------------------------------------------
  // شارات / عناوين المالك — عروض
  // ---------------------------------------------------------------------------
  static String ownerSelectedMarketerBadge(bool isAr) => t(
        isAr,
        'التعاقد — يُكمل المسوّق إصدار التصريح عبر الهيئة العامة للعقار ثم النشر',
        'Contracting — the marketer completes REGA permits externally, then publishes',
      );

  static String ownerOffersTitle(bool isAr) =>
      t(isAr, 'عروض المسوقين', 'Marketer offers');

  static String ownerOffersIntro(bool isAr) => t(
        isAr,
        'راجع العروض واضغط «قبول العرض» لمسوّق واحد فقط. بعد القبول تُسجَّل العروض الأخرى في الجولة كـ «لم يُختر هذا العرض».',
        'Review offers and tap «Accept offer» for one marketer only. Other offers in the round are marked as not selected.',
      );

  static String ownerOffersEmptyTitle(bool isAr) =>
      t(isAr, 'لا توجد عروض بعد', 'No offers yet');

  static String ownerOffersEmptyBody(bool isAr) => t(
        isAr,
        'عندما يقدّم المسوقون عروضهم ستظهر هنا. يمكنك سحب الشاشة للتحديث.',
        'When marketers complete deals they will appear here. Pull to refresh.',
      );

  static String loadFailedTitle(bool isAr) =>
      t(isAr, 'تعذّر تحميل البيانات', 'Could not load data');

  static String loadFailedBody(bool isAr) => t(
        isAr,
        'تحقق من الاتصال ثم أعد المحاولة. إن استمر الخطأ قد تكون هناك صلاحية أو مشكلة في الخادم.',
        'Check your connection and try again. If it persists, check permissions or server.',
      );

  static String rpcFailed(bool isAr, Object error) => t(
        isAr,
        'تعذّر تنفيذ العملية: $error',
        'Action failed: $error',
      );

  static String listingBannedUnderReview(bool isAr) => t(
        isAr,
        'الطلب موقوف للمراجعة ولا يقبل عروضاً أو إعادة طرحاً حتى تُعالج الإدارة.',
        'This request is paused for review. Offers and relisting are blocked until cleared.',
      );

  static String rpcFailedFriendly(bool isAr, Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('listing_banned_under_review')) {
      return listingBannedUnderReview(isAr);
    }
    if (s.contains('round_no') &&
        (s.contains('does not exist') ||
            s.contains('undefined_column') ||
            s.contains('42703'))) {
      return t(
        isAr,
        'تحديث قاعدة البيانات مطلوب لإعادة الطلب للسوق. تواصل مع الدعم أو طبّق ترحيل round_no.',
        'A database update is required to return this request to market. Contact support or apply the round_no migration.',
      );
    }
    if (s.contains('no_owner_action_pending') ||
        s.contains('invalid_stage_for_relist')) {
      return t(
        isAr,
        'لا يمكن إعادة الطلب من حالته الحالية. حدّث الصفحة أو تواصل مع الدعم.',
        'This request cannot be returned to market from its current state. Refresh or contact support.',
      );
    }
    return rpcFailed(isAr, error);
  }

  static String ownerOfferDeclineCounter(bool isAr, int declined, int maxDistinct) =>
      t(
        isAr,
        'رفضت عروض $declined مسوّقين مميزين (الحد $maxDistinct). عند بلوغ الحد يُوقف الطلب للمراجعة.',
        'You declined offers from $declined distinct marketers (max $maxDistinct). At the limit the request is paused for review.',
      );

  static String ownerOfferDeclineLimitReached(bool isAr) => t(
        isAr,
        'توقّف الطلب: وصلتَ لحد رفض ثلاثة مسوّقين مميزين في هذه الجولة. تواصل مع الدعم أو انتظر معالجة المراجعة.',
        'This request stopped: three distinct marketers were declined this round. Contact support or wait for a review.',
      );

  // ---------------------------------------------------------------------------
  // رسائل نجاح / فشل (SnackBar)
  // ---------------------------------------------------------------------------
  static String snackOfferAccepted(bool isAr) => t(
        isAr,
        'تم قبول العرض واختيار المسوق. العروض الأخرى في الجولة أصبحت «لم يُختر هذا العرض».',
        'Offer accepted and marketer selected. Other offers in this round were marked as not selected.',
      );

  static String snackOfferDeclined(bool isAr) =>
      t(isAr, 'تم رفض العرض.', 'Offer declined.');

  static String snackOfferSubmitted(bool isAr) => t(
        isAr,
        'تم إتمام صفقتك بنجاح.',
        'Your deal was submitted.',
      );

  static String snackInviteAccepted(bool isAr) =>
      t(isAr, 'تم قبول الدعوة.', 'Invite accepted.');

  static String snackRelistSuccess(bool isAr) => t(
        isAr,
        'تم إعادة طرح الطلب للتسويق بنجاح.',
        'The request was relisted for marketing.',
      );

  static String btnPublishFromContract(bool isAr) => t(
        isAr,
        'نشر الإعلان',
        'Publish listing',
      );

  /// بعد ناجح النشر (مسار تصريح أو عقد — دون تمييز «من العقد» في واجهة المستخدم).
  static String snackPublishedListingSuccess(bool isAr) => t(
        isAr,
        'تم نشر الإعلان وربطه بالطلب.',
        'The listing was published and linked to the request.',
      );

  static String snackPublishedFromContract(bool isAr) =>
      snackPublishedListingSuccess(isAr);

  static String publishedBannerTitle(bool isAr) => t(
        isAr,
        'تم نشر العقار',
        'Property published',
      );

  static String publishedBannerSubtitle(bool isAr) => t(
        isAr,
        'الإعلان منشور الآن - هذا الإعلان أصبح عامًا',
        'Listing is now public',
      );

  static String btnOpenPublishedProperty(bool isAr) => t(
        isAr,
        'فتح العقار المنشور',
        'Open published property',
      );

  // ---------------------------------------------------------------------------
  // مسوّق — سبب منع التقديم
  // ---------------------------------------------------------------------------
  static String marketerOfferAlreadyInRound(bool isAr) => t(
        isAr,
        'لديك عرض مسجّل في جولة التسويق الحالية لهذا الطلب. لا يمكن تكرار العرض في نفس الجولة؛ انتظر جولة لاحقة أو إعادة طرح الطلب.',
        'You already have an offer in the current marketing round for this request. Duplicate offers in the same round are not allowed.',
      );

  static String hintAdminOfferReviewWhenOfferLocked(bool isAr) => t(
        isAr,
        'إن احتجت مراجعة استثنائية لتعديل العرض أو إعادة طرحه، تواصل مع الإدارة من مركز الدعم.',
        'If you need an exceptional review to adjust or relist your offer, contact admin support.',
      );

  static String btnRequestAdminOfferReview(bool isAr) => t(
        isAr,
        'طلب مراجعة من الإدارة',
        'Request admin review',
      );

  static String marketerOfferBlockedByStage(bool isAr, ListingWorkflowStage stage) {
    switch (stage) {
      case ListingWorkflowStage.marketerSelected:
        return t(
          isAr,
          'تم اختيار مسوّق لهذا الطلب — لا يقبل إتمام صفقات جديدة في هذه المرحلة.',
          'A marketer has been selected — new deals are not accepted at this stage.',
        );
      case ListingWorkflowStage.contractPending:
      case ListingWorkflowStage.contractSent:
      case ListingWorkflowStage.contractReturned:
      case ListingWorkflowStage.contractSigned:
        return t(
          isAr,
          'الطلب في مرحلة التعاقد — لا يمكن إتمام صفقة تسويق جديدة الآن.',
          'The request is in the contracting stage — you cannot complete a new marketing deal now.',
        );
      case ListingWorkflowStage.permitPending:
        return t(
          isAr,
          'الطلب في مرحلة التصريح — لا يقبل عروض تسويق جديدة.',
          'The request is in the permit stage — new marketing offers are not accepted.',
        );
      case ListingWorkflowStage.permitIssued:
        return t(
          isAr,
          'الطلب في مرحلة إصدار التصريح — لا يقبل عروض تسويق جديدة.',
          'The request is in the permit issuing stage — new marketing offers are not accepted.',
        );
      case ListingWorkflowStage.published:
      case ListingWorkflowStage.reserved:
        return t(
          isAr,
          'هذا الطلب تجاوز مرحلة جمع العروض (منشور أو محجوز).',
          'This request has passed the offer stage (published or reserved).',
        );
      case ListingWorkflowStage.inactive72h:
        return t(
          isAr,
          'الطلب متوقف (مهلة 72 ساعة). قد يحتاج المالك لإعادة طرحه للتسويق.',
          'The request is inactive (72h). The owner may need to relist it.',
        );
      case ListingWorkflowStage.contractCancelled:
        return t(
          isAr,
          'أُلغي عقد التسويق لهذا الطلب — لا يمكن إتمام صفقة جديدة حتى يعيد المالك طرح الطلب إن لزم.',
          'The marketing contract was cancelled — you cannot submit a new offer until the owner relists if needed.',
        );
      case ListingWorkflowStage.cancelled:
      case ListingWorkflowStage.terminated:
        return t(
          isAr,
          'هذا الطلب ملغى أو مُنهى — لا يمكن إتمام الصفقة.',
          'This request is cancelled or terminated.',
        );
      case ListingWorkflowStage.archived:
        return t(
          isAr,
          'هذا الطلب غير متاح للتقديم.',
          'This request is not available for offers.',
        );
      case ListingWorkflowStage.addedByOwner:
      case ListingWorkflowStage.waitingMarketers:
        return t(
          isAr,
          'لا يمكن إتمام الصفقة حاليًا — راجع حالة الطلب أو الدعوة.',
          'You cannot complete a deal right now — check the request or invite status.',
        );
    }
  }

  static String inviteBlocksOffer(bool isAr, String inviteStatusLower) {
    switch (inviteStatusLower) {
      case 'declined':
        return t(
          isAr,
          'هذه الدعوة مرفوضة — لا يمكن إتمام الصفقة منها.',
          'This invite was declined — you cannot complete a deal.',
        );
      case 'expired':
        return t(
          isAr,
          'انتهت صلاحية هذه الدعوة.',
          'This invite has expired.',
        );
      default:
        return t(
          isAr,
          'لا يمكن إتمام الصفقة من حالة الدعوة الحالية.',
          'You cannot complete a deal for this invite in its current state.',
        );
    }
  }

  /// أولوية: عرض موجود → ثم مرحلة الطلب.
  static String? marketerSubmitBlockedExplanation(
    bool isAr, {
    required bool hasLiveOfferThisRound,
    required ListingWorkflowUiContext? ctx,
  }) {
    if (hasLiveOfferThisRound) return marketerOfferAlreadyInRound(isAr);
    if (ctx == null) return null;
    if (ctx.showMarketerSubmitOffer) return null;
    return marketerOfferBlockedByStage(isAr, ctx.stage);
  }

  // ---------------------------------------------------------------------------
  // Permit flow (contract -> permit -> publish)
  // ---------------------------------------------------------------------------
  static String btnEnterPermitDetails(bool isAr) => t(
        isAr,
        'إدخال بيانات التصريح',
        'Enter permit details',
      );

  static String txtPermitPending(bool isAr) => t(
        isAr,
        'التصريح قيد المعالجة',
        'Permit is being processed',
      );

  static String txtPermitIssued(bool isAr) => t(
        isAr,
        'تم إصدار التصريح',
        'Permit issued',
      );

  static String errCannotIssuePermitHere(bool isAr) => t(
        isAr,
        'لا يمكن إصدار التصريح في هذه المرحلة',
        'Cannot issue permit in this stage',
      );

  static String btnIssuePermit(bool isAr) => t(
        isAr,
        'إصدار التصريح',
        'Issue permit',
      );

  static String errPermitDataIncomplete(bool isAr) => t(
        isAr,
        'بيانات التصريح غير مكتملة',
        'Permit data is incomplete',
      );

  static String btnPublishAd(bool isAr) => t(
        isAr,
        'نشر الإعلان',
        'Publish listing',
      );

  static String errCannotPublishBeforePermit(bool isAr) => t(
        isAr,
        'لا يمكن نشر الإعلان قبل التصريح',
        'Cannot publish before permit',
      );

  static String errRegaPackageIncomplete(bool isAr) => t(
        isAr,
        'يُشترط رقم التصريح مع رفع مستندات REGA (رمز QR أو ملف PDF) قبل الإصدار أو النشر.',
        'A permit number plus REGA proof (QR or PDF upload) is required before issuing or publishing.',
      );

  static String txtWaitingRegaProof(bool isAr) => t(
        isAr,
        'بانتظار المسوّق لرفع مستندات REGA ورقم التصريح.',
        'Waiting for the marketer to upload REGA documents and permit details.',
      );
}
