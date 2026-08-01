/// كاش فوريّ في الذاكرة لتبويبات «صفحتي» (مسوّق/معلن) — يَحفظ آخر نسخة من
/// `_mkInvites/_mkOffers/_mkContracts/_mkPermits/_mkPublished` و
/// `_ownerListingRequests` بحيث عند عودة المستخدم لتبويب «صفحتي» تَظهر
/// البطاقات فوراً (ثم يُحدِّثها loader في الخلفية).
///
/// لا يَتعدّى عمر هذا الكاش جلسة التطبيق الحالية (مفيد فقط بين تنقل التبويبات
/// والشاشات). للتسلسل المُستديم نُعيد الاستعلام من قاعدة البيانات.
class MarketingBucketsCache {
  MarketingBucketsCache._();
  static final MarketingBucketsCache instance = MarketingBucketsCache._();

  // Marketer buckets
  String? _marketerUid;
  List<Map<String, dynamic>>? _mkInvites;
  List<Map<String, dynamic>>? _mkOffers;
  List<Map<String, dynamic>>? _mkContracts;
  List<Map<String, dynamic>>? _mkPermits;
  List<Map<String, dynamic>>? _mkPublished;
  DateTime? _marketerLoadedAt;

  // Owner buckets
  String? _ownerUid;
  List<Map<String, dynamic>>? _ownerListingRequests;
  DateTime? _ownerLoadedAt;

  void saveMarketer({
    required String uid,
    required List<Map<String, dynamic>> invites,
    required List<Map<String, dynamic>> offers,
    required List<Map<String, dynamic>> contracts,
    required List<Map<String, dynamic>> permits,
    required List<Map<String, dynamic>> published,
  }) {
    _marketerUid = uid;
    _mkInvites = List<Map<String, dynamic>>.from(invites);
    _mkOffers = List<Map<String, dynamic>>.from(offers);
    _mkContracts = List<Map<String, dynamic>>.from(contracts);
    _mkPermits = List<Map<String, dynamic>>.from(permits);
    _mkPublished = List<Map<String, dynamic>>.from(published);
    _marketerLoadedAt = DateTime.now();
  }

  ({
    List<Map<String, dynamic>> invites,
    List<Map<String, dynamic>> offers,
    List<Map<String, dynamic>> contracts,
    List<Map<String, dynamic>> permits,
    List<Map<String, dynamic>> published,
    DateTime? loadedAt,
  })? readMarketer(String uid) {
    if (uid.isEmpty || _marketerUid != uid) return null;
    if (_mkInvites == null) return null;
    return (
      invites: List<Map<String, dynamic>>.from(_mkInvites ?? const []),
      offers: List<Map<String, dynamic>>.from(_mkOffers ?? const []),
      contracts: List<Map<String, dynamic>>.from(_mkContracts ?? const []),
      permits: List<Map<String, dynamic>>.from(_mkPermits ?? const []),
      published: List<Map<String, dynamic>>.from(_mkPublished ?? const []),
      loadedAt: _marketerLoadedAt,
    );
  }

  void saveOwner({
    required String uid,
    required List<Map<String, dynamic>> rows,
  }) {
    _ownerUid = uid;
    _ownerListingRequests = List<Map<String, dynamic>>.from(rows);
    _ownerLoadedAt = DateTime.now();
  }

  ({List<Map<String, dynamic>> rows, DateTime? loadedAt})? readOwner(
    String uid,
  ) {
    if (uid.isEmpty || _ownerUid != uid) return null;
    final rows = _ownerListingRequests;
    if (rows == null) return null;
    return (
      rows: List<Map<String, dynamic>>.from(rows),
      loadedAt: _ownerLoadedAt,
    );
  }

  /// مُسح ذاكرة الكاش — يُستدعى عند تسجيل الخروج/تبديل المستخدم.
  void clearAll() {
    _marketerUid = null;
    _mkInvites = null;
    _mkOffers = null;
    _mkContracts = null;
    _mkPermits = null;
    _mkPublished = null;
    _marketerLoadedAt = null;
    _ownerUid = null;
    _ownerListingRequests = null;
    _ownerLoadedAt = null;
  }

  /// إبطال كاش المالك — بعد موافقة/رفض/إعادة للسوق حتى لا تبقى البطاقة في تبويب قديم.
  void invalidateOwner([String? uid]) {
    if (uid != null && uid.isNotEmpty && _ownerUid != null && _ownerUid != uid) {
      return;
    }
    _ownerUid = null;
    _ownerListingRequests = null;
    _ownerLoadedAt = null;
  }

  /// إبطال كاش المسوّق — بعد عرض/نشر/إلغاء.
  void invalidateMarketer([String? uid]) {
    if (uid != null &&
        uid.isNotEmpty &&
        _marketerUid != null &&
        _marketerUid != uid) {
      return;
    }
    _marketerUid = null;
    _mkInvites = null;
    _mkOffers = null;
    _mkContracts = null;
    _mkPermits = null;
    _mkPublished = null;
    _marketerLoadedAt = null;
  }
}
