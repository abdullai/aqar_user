// lib/models/ad_item.dart

import 'property.dart';

/// نموذج إعلان/عقار موحّد لاستخدامه في القائمة (Dashboard) وفي التفاصيل.
///
/// ✅ متوافق مع نسختك الحالية (Backward compatible):
/// - يحافظ على الحقول القديمة كما هي.
/// - يضيف حقول “العقار” المطلوبة في مثال.txt بشكل Optional (لا تكسر بياناتك الحالية).
///
/// 🎯 الهدف:
/// - بطاقة إعلان/عقار تعرض: صورة + عنوان + مدينة/حي + مساحة + سعر + حالة + موثوقية الرخصة.
/// - دعم RTL/LTR يتم في الـ UI، هنا فقط بيانات.
///
/// ملاحظة:
/// - هذا الموديل يُستخدم للإعلانات/العقارات في الواجهة.
/// - يمكن تغذيته من Supabase من جدول ads/properties أو View موحّد لاحقًا.
class AdItem {
  // ===== الأساسي =====
  final String id;

  String titleAr;
  String titleEn;

  String subtitleAr;
  String subtitleEn;

  /// ✅ إما صورة من الأصول (assets/...) أو URL من قاعدة البيانات
  /// - إذا كانت URL: ضعها هنا
  /// - إذا كانت Asset: ضعها في assetImage
  String? imageUrl;
  String? linkUrl;

  String assetImage;
  bool enabled;

  // ===== حقول “العقار” المطلوبة (New / Optional) =====

  /// معرف العقار الحقيقي (إن كان الإعلان يمثل عقارًا)
  String? propertyId;

  /// المدينة
  String? cityAr;
  String? cityEn;

  /// الحي
  String? districtAr;
  String? districtEn;

  /// المساحة بالمتر
  double? areaSqm;

  /// السعر (إن وجد) - تركته num لتفادي اختلاف int/double
  num? price;

  /// العملة (SAR افتراضيًا)
  String currency;

  /// حالة العقار: available | reserved | sold | unknown
  /// - تُستخدم لمنع الحجز وإظهار الشارة.
  String status;

  /// رقم رخصة الإعلان (REGA)
  String? licenseNumber;

  /// هل الرخصة موثوقة/تم التحقق منها
  bool isVerified;

  /// وقت آخر تحقق (اختياري)
  DateTime? verifiedAt;

  /// صور العقار (للواجهة: بطاقة + تفاصيل)
  /// - إن كانت فارغة يستخدم imageUrl/assetImage
  List<String> images;

  /// رابط فيديو الغلاف/العقار (مثل `properties.video_url`)
  String? videoUrl;

  /// مصدر حالة العقار (اختياري): internal | external | mixed
  String statusSource;

  /// سبب عدم التوفر/ملاحظة خارجية (اختياري)
  String? statusNote;

  AdItem({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.subtitleAr,
    required this.subtitleEn,
    required this.assetImage,
    this.imageUrl,
    this.linkUrl,
    required this.enabled,

    // new fields
    this.propertyId,
    this.cityAr,
    this.cityEn,
    this.districtAr,
    this.districtEn,
    this.areaSqm,
    this.price,
    this.currency = 'SAR',
    this.status = 'unknown',
    this.licenseNumber,
    this.isVerified = false,
    this.verifiedAt,
    List<String>? images,
    this.videoUrl,
    this.statusSource = 'internal',
    this.statusNote,
  }) : images = images ?? const [];

  /// مساعد: اختيار عنوان مناسب حسب اللغة
  String title(String lang) => (lang == 'ar') ? titleAr : titleEn;

  /// مساعد: اختيار وصف مناسب حسب اللغة
  String subtitle(String lang) => (lang == 'ar') ? subtitleAr : subtitleEn;

  /// مساعد: المدينة/الحي حسب اللغة
  String? city(String lang) => (lang == 'ar') ? cityAr : cityEn;
  String? district(String lang) => (lang == 'ar') ? districtAr : districtEn;

  /// مساعد: أفضل صورة للبطاقة
  /// - images[0] إن وجدت
  /// - else imageUrl
  /// - else assetImage (تتعامل معها الواجهة)
  String? bestCoverUrl() {
    if (images.isNotEmpty) {
      return images.first.trim().isEmpty ? null : images.first.trim();
    }
    final u = imageUrl?.trim();
    if (u != null && u.isNotEmpty) return u;
    return null; // إذا null فالواجهة تستخدم assetImage
  }

  /// رابط فيديو للبطاقة إن وُجد (لا يستبدل صورة الغلاف إلا إذا رغبت الواجهة بذلك)
  String? bestVideoUrl() {
    final v = videoUrl?.trim();
    if (v != null && v.isNotEmpty) return v;
    return null;
  }

  /// مساعد: هل يمكن حجز العقار؟
  bool get isReservable => status == 'available';

  /// مساعد: هل العقار غير متاح
  bool get isUnavailable => status == 'reserved' || status == 'sold';

  Map<String, dynamic> toJson() => {
        // القديم
        'id': id,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'subtitleAr': subtitleAr,
        'subtitleEn': subtitleEn,
        'assetImage': assetImage,
        'imageUrl': imageUrl,
        'linkUrl': linkUrl,
        'enabled': enabled,

        // الجديد
        'propertyId': propertyId,
        'cityAr': cityAr,
        'cityEn': cityEn,
        'districtAr': districtAr,
        'districtEn': districtEn,
        'areaSqm': areaSqm,
        'price': price,
        'currency': currency,
        'status': status,
        'licenseNumber': licenseNumber,
        'isVerified': isVerified,
        'verifiedAt': verifiedAt?.toIso8601String(),
        'images': images,
        'videoUrl': videoUrl,
        'statusSource': statusSource,
        'statusNote': statusNote,
      };

  factory AdItem.fromJson(Map<String, dynamic> j) {
    // old parsing helpers
    String? trimOrNull(dynamic v) {
      final s = (v as String?)?.trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }

    double? toDoubleOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return double.tryParse(s);
    }

    num? toNumOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return num.tryParse(s);
    }

    DateTime? toDateTimeOrNull(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    List<String> toStringList(dynamic v) {
      if (v == null) return const [];
      if (v is List) {
        return v
            .map((e) => e?.toString().trim())
            .where((e) => e != null && e.isNotEmpty)
            .map((e) => e!)
            .toList();
      }
      return const [];
    }

    return AdItem(
      // القديم (لا نكسره)
      id: (j['id'] ?? '').toString(),
      titleAr: (j['titleAr'] ?? '').toString(),
      titleEn: (j['titleEn'] ?? '').toString(),
      subtitleAr: (j['subtitleAr'] ?? '').toString(),
      subtitleEn: (j['subtitleEn'] ?? '').toString(),
      assetImage: (j['assetImage'] ?? '').toString(),
      imageUrl: trimOrNull(j['imageUrl']),
      linkUrl: trimOrNull(j['linkUrl']),
      enabled: (j['enabled'] ?? true) as bool,

      // الجديد
      propertyId: trimOrNull(j['propertyId']),
      cityAr: trimOrNull(j['cityAr']),
      cityEn: trimOrNull(j['cityEn']),
      districtAr: trimOrNull(j['districtAr']),
      districtEn: trimOrNull(j['districtEn']),
      areaSqm: toDoubleOrNull(j['areaSqm'] ?? j['area'] ?? j['sqm']),
      price: toNumOrNull(j['price']),
      currency: (j['currency'] ?? 'SAR').toString(),
      status: (j['status'] ?? 'unknown').toString(),
      licenseNumber: trimOrNull(j['licenseNumber'] ?? j['license_number']),
      isVerified: (j['isVerified'] ?? j['is_verified'] ?? false) as bool,
      verifiedAt: toDateTimeOrNull(j['verifiedAt'] ?? j['verified_at']),
      images: toStringList(j['images']),
      videoUrl: trimOrNull(j['videoUrl'] ?? j['video_url']),
      statusSource:
          (j['statusSource'] ?? j['status_source'] ?? 'internal').toString(),
      statusNote: trimOrNull(j['statusNote'] ?? j['status_note']),
    );
  }

  /// جسر عرض من [Property] لشاشات تفضّل [AdItem].
  factory AdItem.fromProperty(Property p) {
    final city = p.city.trim();
    final district = (p.location ?? '').trim();
    final bits = <String>[
      if (p.area > 0) '${p.area.toStringAsFixed(0)} m²',
      if (city.isNotEmpty) city,
    ];
    final sub = bits.join(' · ');
    final priceVal = p.isAuction ? (p.currentBid ?? p.price) : p.price;
    var st = 'unknown';
    if (p.isDeletedLike) {
      st = 'sold';
    } else if (p.normalizedStatus == 'reserved' ||
        (p.reservationStatus ?? '').toLowerCase().contains('pending')) {
      st = 'reserved';
    } else if (p.isActive) {
      st = 'available';
    }
    String? httpCover;
    for (final u in p.images) {
      final t = u.trim();
      if (t.startsWith('http://') || t.startsWith('https://')) {
        httpCover = t;
        break;
      }
    }
    return AdItem(
      id: p.id,
      titleAr: p.title,
      titleEn: p.title,
      subtitleAr: sub,
      subtitleEn: sub,
      assetImage: '',
      imageUrl: httpCover,
      linkUrl: null,
      enabled: true,
      propertyId: p.id,
      cityAr: city.isNotEmpty ? city : null,
      cityEn: city.isNotEmpty ? city : null,
      districtAr: district.isNotEmpty ? district : null,
      districtEn: district.isNotEmpty ? district : null,
      areaSqm: p.area > 0 ? p.area : null,
      price: priceVal,
      currency: p.currency.trim().isEmpty ? 'SAR' : p.currency.trim(),
      status: st,
      licenseNumber: null,
      isVerified: false,
      verifiedAt: null,
      images: List<String>.from(p.images),
      videoUrl: (p.videoUrl ?? '').trim().isEmpty ? null : p.videoUrl!.trim(),
      statusSource: 'internal',
      statusNote: null,
    );
  }
}
