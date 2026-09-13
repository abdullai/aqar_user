/// مسارات رفع وسائط الإعلان داخل دلو `property-images`.
///
/// سياسة التخزين الأساسية تسمح بـ `{auth.uid()}/%` فقط (مثل تعديل الإعلان
/// والفيديو). المسارات التي تبدأ بـ `listings/` أو `requests/` تُرفض بـ 403.
abstract final class ListingStoragePaths {
  static String listingImagesFolder({
    required String ownerId,
    String? propertyId,
    String? requestId,
    required String batchId,
  }) {
    final oid = ownerId.trim();
    final pid = (propertyId ?? '').trim();
    final rid = (requestId ?? '').trim();
    if (pid.isNotEmpty) return '$oid/listings/$pid';
    if (rid.isNotEmpty) return '$oid/requests/$rid';
    return '$oid/listings/${batchId.trim()}';
  }

  static String licensePdfPath({
    required String ownerId,
    required String fileId,
  }) {
    return '${ownerId.trim()}/licenses/${fileId.trim()}.pdf';
  }

  static bool looksLikePermissionDenied(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('403') ||
        s.contains('unauthorized') ||
        s.contains('row-level security') ||
        s.contains('not allowed') ||
        s.contains('permission denied') ||
        s.contains('violates row-level');
  }
}
