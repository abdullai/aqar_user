/// نتيجة إغلاق نموذج الإضافة/الطلب بعد النشر — تُعيد اللوحة للرئيسية فوراً.
enum PostPublishKind {
  /// منشور/معتمد ويظهر في السوق أو الرئيسية.
  liveHome,

  /// طلب تسويق بانتظار مسوّق — لا يظهر في الرئيسية بعد.
  marketingDesk,
}

class PostPublishNavResult {
  const PostPublishNavResult({
    required this.kind,
    this.propertyId,
    this.listingPublicCode,
    this.listingRequestId,
    this.marketRequestId,
  });

  factory PostPublishNavResult.liveHome({
    String? propertyId,
    String? listingPublicCode,
    String? marketRequestId,
  }) {
    return PostPublishNavResult(
      kind: PostPublishKind.liveHome,
      propertyId: propertyId,
      listingPublicCode: listingPublicCode,
      marketRequestId: marketRequestId,
    );
  }

  factory PostPublishNavResult.marketingDesk({
    String? listingRequestId,
  }) {
    return PostPublishNavResult(
      kind: PostPublishKind.marketingDesk,
      listingRequestId: listingRequestId,
    );
  }

  final PostPublishKind kind;
  final String? propertyId;
  final String? listingPublicCode;
  final String? listingRequestId;
  final String? marketRequestId;

  bool get revealOnHome => kind == PostPublishKind.liveHome;
}
