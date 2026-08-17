/// أنواع الإجراءات التسويقية التي تتطلب اشتراكاً فعّالاً ثم تُستأنف بعد الدفع.
enum MarketingSubscriptionResumeKind {
  submitOffer,
  createContract,
  submitPermit,
  linkRegaPermit,
  publishListing,
  reportRegaMismatch,
  contractChat,
  addPropertyListing,
  /// بعد الدفع من بوابة إرسال/إلغاء عقد أو RPC مشابه — لا يُعاد إلا تحديث القائمة.
  postPaidUnlock,
}

/// يُمرَّر إلى [SubscriptionsRootScreen] لإعادة تشغيل نفس الإجراء بعد إتمام الدفع.
class MarketingSubscriptionResumeIntent {
  const MarketingSubscriptionResumeIntent({
    required this.kind,
    this.requestId = '',
    this.inviteId,
    this.hubKind = '',
    this.offerId,
    this.contractId,
  });

  final MarketingSubscriptionResumeKind kind;
  final String requestId;
  final String? inviteId;
  final String hubKind;
  final String? offerId;
  final String? contractId;

  bool get isValid {
    switch (kind) {
      case MarketingSubscriptionResumeKind.addPropertyListing:
      case MarketingSubscriptionResumeKind.postPaidUnlock:
        return true;
      case MarketingSubscriptionResumeKind.contractChat:
        return (contractId ?? '').trim().isNotEmpty;
      case MarketingSubscriptionResumeKind.submitOffer:
        return requestId.trim().isNotEmpty;
      default:
        return requestId.trim().isNotEmpty;
    }
  }
}
