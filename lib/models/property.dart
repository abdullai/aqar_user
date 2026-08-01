import '../core/workflow/listing_workflow_stage.dart';
import '../core/listing/property_type_catalog.dart';

enum PropertyType { villa, apartment, land }

class Property {
  final String id;
  final String ownerId;

  /// رمز الإعلان العام (فريد للعرض على البطاقة والتفاصيل)
  final String? listingPublicCode;

  /// اسم المعلن
  final String? ownerDisplayName;

  /// جوال المعلن
  final String? ownerPhone;

  final String title;
  final PropertyType type;

  /// المفتاح الخام من قاعدة البيانات (`type`) لألوان البطاقة والتسمية الدقيقة.
  final String listingTypeKey;
  final String description;

  /// المدينة
  final String city;

  /// المنطقة
  final String? region;

  /// المحافظة
  final String? province;

  /// Alias للمحافظة إذا استُخدم اسم governorate في أي مكان
  String? get governorate => province;

  /// الحي (يدوي) — المحافظة في [province]/governorate
  final String? location;

  final double area;

  /// المبلغ الذي أدخله المعلن في حقل «السعر الإجمالي».
  /// — قاعدة العرض الموحّدة لكل **بطاقات الإعلان العقاري** في التطبيق
  ///   (الرئيسية، صفحتي، إعلاناتي/طلباتي للمسوّق، السلة، صفقاتي، نتائج البحث،
  ///   وأي مكان آخر فيه بطاقة): تُعرض قيمة `price` كما أدخلها المعلن **دون**
  ///   إضافة أو خصم أي ضريبة أو عمولة تسويق.
  /// — تفصيل الفاتورة (الأساسي/الضريبة/العمولة/المجموع النهائي) يُعرض **فقط**
  ///   داخل صفحة تفاصيل الإعلان عند الضغط على البطاقة، وفي صفحات الفوترة
  ///   والإيصالات. لاستخراج المبلغ النهائي استخدم `finalTotalPrice`.
  final double price;

  /// هل `price` يحوي ضريبة القيمة المضافة 5%؟
  /// — `true`  → السعر الأساسي = price / (1 + vatRate)؛ الضريبة ضمن المبلغ.
  /// — `false` → السعر الأساسي = price؛ تُضاف الضريبة على الإجمالي.
  final bool priceIncludesVat;

  /// نسبة ضريبة القيمة المضافة المعتمدة لهذا العقار (افتراضي 5%).
  /// نخزّنها لكل عقار لضمان استرجاع الفاتورة كما كانت لحظة النشر إن تغيّرت النسبة.
  final double vatRate;

  /// طريقة احتساب عمولة التسويق: `none` | `percent` | `fixed`.
  final String marketingCommissionKind;

  /// نسبة العمولة عند `marketingCommissionKind == 'percent'` (افتراضي 0.025 = 2.5%).
  final double marketingCommissionRate;

  /// مبلغ مقطوع عند `marketingCommissionKind == 'fixed'`.
  final double marketingCommissionAmount;

  /// `true` عندما تُحقن صورة افتراضية (شعار التطبيق) لأن المعلن لم يرفع وسائط.
  final bool defaultCoverUsed;

  final String currency;
  final bool negotiable;

  final bool isAuction;
  final double? currentBid;

  final List<String> images;
  final String? videoUrl;
  final String? virtualTourUrl;

  final int views;
  final DateTime createdAt;

  /// تاريخ النشر الفعلي إن وجد
  final DateTime? publishedAt;

  /// هل يسمح المعلن بإظهار اسمه
  final bool showAdvertiserName;

  /// طلب المالك إظهار اسمه حتى لو عطّل المسوق [showAdvertiserName].
  final bool ownerRequestsPublicName;

  final double? latitude;
  final double? longitude;

  final String? addressLine;
  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpots;
  final bool? furnished;
  final int? yearBuilt;
  final int? floor;
  final int? totalFloors;

  final Map<String, bool>? amenities;

  /// رقم التواصل الموجود على العقار نفسه
  final String? contactPhone;

  final DateTime? availabilityDate;

  final bool? isFeatured;

  /// إخفاء من الرئيسية/المميز بسبب تصعيد بلاغات (من الخادم، ليس إخفاء المستخدم).
  final bool homeFeedSuppressed;

  /// نظام التعديلات
  final int editCount;
  final int maxEdits;
  final String? lastEditReason;
  final bool editExhausted;

  /// نظام طلب الحذف
  final bool deleteRequested;
  final bool deleteApproved;
  final bool deletedByUser;

  final DateTime? deleteRequestedAt;
  final DateTime? deleteApprovedAt;

  final String? deleteRequestReason;
  final String? deleteReviewReason;

  /// حالة الإعلان
  final String? status;

  /// مصدر الحقيقة للمرحلة (يتفوق على [status] في الواجهة)
  final String? workflowStage;

  final int marketingRound;
  final String? selectedOfferId;
  final String? selectedMarketerId;
  final String? publishedByMarketerId;
  final bool allowPreviousMarketersRetry;
  final int relistCount;

  final DateTime? waitingMarketersSince;
  final DateTime? marketerResponseDeadlineAt;
  final DateTime? contractStartedAt;
  final DateTime? contractSentAt;
  final DateTime? contractSignedAt;
  final DateTime? permitPendingSince;
  final DateTime? permitDeadlineAt;
  final DateTime? permitIssuedAt;

  final String? reservationStatus;
  final DateTime? reservationStartedAt;
  final DateTime? reservationExpiresAt;

  final DateTime? inactive72hAt;
  final DateTime? cancelledAt;
  final DateTime? terminatedAt;

  /// الغرض من الإعلان (بيع، إيجار، مزاد، استثمار...)
  final String? purpose;

  /// رقم الصك
  final String? deedNumber;

  /// تاريخ الصك
  final DateTime? deedDate;

  /// الجهة المصدرة للصك
  final String? deedIssuer;

  /// رقم المبنى (للفيلا/الشقة/المحل...)
  final String? buildingNumber;

  /// لقطة بيانات ترخيص الإعلان/QR (من مسار التسويق) للعرض حتى اكتمال التكامل مع الهيئة
  final Map<String, dynamic>? marketingLicenseSnapshot;

  /// دلائلية/إرشادات منظّمة للعقار (JSON من الخادم، مثلاً items[])
  final Map<String, dynamic>? listingGuidance;

  /// بيانات المنشأة المرتبطة بالإعلان (org_unit_id، أسماء، رمز فال المعروض، العدد…).
  final Map<String, dynamic>? orgListingSnapshot;

  /// من [listingGuidance.usage]: { residential, commercial } — يختارهما المالك عند الإنشاء.
  bool get usageSuitableResidential {
    final g = listingGuidance;
    if (g == null) return false;
    final u = g['usage'];
    if (u is Map) {
      return u['residential'] == true;
    }
    return g['usage_residential'] == true;
  }

  bool get usageSuitableCommercial {
    final g = listingGuidance;
    if (g == null) return false;
    final u = g['usage'];
    if (u is Map) {
      return u['commercial'] == true;
    }
    return g['usage_commercial'] == true;
  }

  /// غلاف القائمة/التفاصيل يفضّل الفيديو (من [listingGuidance.cover_primary]).
  bool get coverPrimaryPrefersVideo {
    final g = listingGuidance;
    final v = (g?['cover_primary'] ?? 'image').toString().trim().toLowerCase();
    return v == 'video';
  }

  /// عرض الفيديو كغلاف البطاقة عندما لا توجد صور أو عند تفضيل الفيديو.
  bool get showVideoAsListingCover =>
      (videoUrl ?? '').trim().isNotEmpty &&
      (images.isEmpty || coverPrimaryPrefersVideo);

  /// أوّل صورة مُخزَّنة كرابط شبكة مباشر (`http/https`) في [images] إن وُجدت.
  /// للمسارات النسبية في التخزين: حوّلها إلى رابط عام عبر دلو `property-images` في Supabase.
  String? get primaryNetworkImageUrl {
    for (final raw in images) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
    }
    return null;
  }

  const Property({
    required this.id,
    required this.ownerId,
    this.listingPublicCode,
    required this.title,
    required this.type,
    this.listingTypeKey = '',
    required this.description,
    required this.city,
    required this.area,
    required this.price,
    this.priceIncludesVat = true,
    this.vatRate = 0.05,
    this.marketingCommissionKind = 'none',
    this.marketingCommissionRate = 0.025,
    this.marketingCommissionAmount = 0.0,
    this.defaultCoverUsed = false,
    required this.isAuction,
    required this.images,
    required this.views,
    required this.createdAt,
    this.ownerDisplayName,
    this.ownerPhone,
    this.region,
    this.province,
    this.location,
    this.publishedAt,
    this.showAdvertiserName = true,
    this.ownerRequestsPublicName = false,
    this.latitude,
    this.longitude,
    this.currentBid,
    this.videoUrl,
    this.virtualTourUrl,
    this.addressLine,
    this.bedrooms,
    this.bathrooms,
    this.parkingSpots,
    this.furnished,
    this.yearBuilt,
    this.floor,
    this.totalFloors,
    this.amenities,
    this.contactPhone,
    this.availabilityDate,
    this.isFeatured,
    this.homeFeedSuppressed = false,
    this.currency = 'SAR',
    this.negotiable = false,
    this.editCount = 0,
    this.maxEdits = 3,
    this.lastEditReason,
    this.editExhausted = false,
    this.deleteRequested = false,
    this.deleteApproved = false,
    this.deletedByUser = false,
    this.deleteRequestedAt,
    this.deleteApprovedAt,
    this.deleteRequestReason,
    this.deleteReviewReason,
    this.status,
    this.workflowStage,
    this.marketingRound = 1,
    this.selectedOfferId,
    this.selectedMarketerId,
    this.publishedByMarketerId,
    this.allowPreviousMarketersRetry = false,
    this.relistCount = 0,
    this.waitingMarketersSince,
    this.marketerResponseDeadlineAt,
    this.contractStartedAt,
    this.contractSentAt,
    this.contractSignedAt,
    this.permitPendingSince,
    this.permitDeadlineAt,
    this.permitIssuedAt,
    this.reservationStatus,
    this.reservationStartedAt,
    this.reservationExpiresAt,
    this.inactive72hAt,
    this.cancelledAt,
    this.terminatedAt,
    this.purpose,
    this.deedNumber,
    this.deedDate,
    this.deedIssuer,
    this.buildingNumber,
    this.marketingLicenseSnapshot,
    this.listingGuidance,
    this.orgListingSnapshot,
  });

  /// هل يظهر اسم المالك/المعلن للجمهور (موافقة المسوق أو طلب المالك).
  bool get canShowAdvertiserName =>
      showAdvertiserName || ownerRequestsPublicName;

  /// اسم المعلن الظاهر
  String get visibleAdvertiserName {
    if (!canShowAdvertiserName) return '';
    return (ownerDisplayName ?? '').trim();
  }

  /// اسم الجهة المسوقة (مكتب/شركة) من لقطة الترخيص أو أرقام الترخيص كبديل.
  static String? marketerEntityLineFromLicenseSnapshot(
    Map<String, dynamic>? snap,
    bool isAr,
  ) {
    if (snap == null || snap.isEmpty) return null;

    const nameKeys = <String>[
      'marketer_entity_display_name',
      'marketer_display_name',
      'marketer_office_name',
      'marketer_entity_name',
      'broker_name',
      'broker_full_name',
      'fal_broker_name',
      'fal_broker_full_name',
      'brokerage_name',
      'company_name',
      'organization_name',
      'office_name',
      'fal_entity_name',
      'entity_name',
    ];

    for (final k in nameKeys) {
      final s = snap[k]?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }

    return null;
  }

  String? marketerEntityPublicLine(bool isAr) =>
      marketerEntityLineFromLicenseSnapshot(marketingLicenseSnapshot, isAr);

  /// شعار/صورة المسوق على البطاقة عند تفعيلها في بيانات الترخيص المخزّنة.
  String? get marketerBrandImagePublicUrl {
    final snap = marketingLicenseSnapshot;
    if (snap == null || snap.isEmpty) return null;
    final show = snap['marketer_show_brand_on_listing'];
    if (show == false || show == 'false' || show == '0' || show == 0) {
      return null;
    }
    final u = snap['marketer_brand_image_url']?.toString().trim();
    if (u == null || u.isEmpty) return null;
    return u;
  }

  // -- بداية حسابات الفاتورة (الأساسي/الضريبة/العمولة/الإجمالي) -------------------
  //
  // المنطق متطابق مع `fn_listing_invoice_breakdown` في الترحيل v9 على Supabase،
  // وتستهلكه شاشات تفاصيل الإعلان وبطاقات «صفحتي» والمعاينة الحيّة عند الإضافة.
  // الإعلانات القديمة (قبل تطبيق الترحيل) تأتي بقيم افتراضية: شامل ضريبة + بدون عمولة،
  // فيعود `finalTotalPrice == price` تماماً لضمان عدم تغيّر المبالغ المعروضة سابقاً.

  static double _round2(double v) {
    if (v.isNaN || v.isInfinite) return 0;
    return (v * 100).round() / 100.0;
  }

  /// السعر الأساسي قبل الضريبة (مبلغ المالك الفعلي).
  double get effectiveBasePrice {
    final p = price.toDouble();
    if (priceIncludesVat) {
      return _round2(p / (1.0 + vatRate));
    }
    return _round2(p);
  }

  /// قيمة ضريبة القيمة المضافة (موجبة دائماً).
  double get vatAmount => _round2(effectiveBasePrice * vatRate);

  /// الإجمالي الشامل للضريبة فقط (قبل عمولة التسويق).
  /// — عند `priceIncludesVat == true`: يساوي `price` (الذي أدخله المعلن).
  /// — عند `priceIncludesVat == false`: يساوي `price + VAT`.
  double get totalWithVat => _round2(effectiveBasePrice + vatAmount);

  /// قيمة عمولة التسويق (مبلغ سعودي/عملة الإعلان).
  double get marketingCommissionTotal {
    switch (marketingCommissionKind) {
      case 'percent':
        return _round2(effectiveBasePrice * marketingCommissionRate);
      case 'fixed':
        return _round2(marketingCommissionAmount);
      case 'none':
      default:
        return 0.0;
    }
  }

  /// الإجمالي النهائي: الأساسي ± الضريبة + عمولة التسويق (المبلغ الذي يستحقّه البائع/المسوّق).
  /// — لا تستخدمه في عرض البطاقات؛ هو خاص بصفحة تفاصيل الإعلان والفواتير
  ///   والإيصالات فقط حسب القاعدة الموحَّدة لعرض الأسعار.
  double get finalTotalPrice => _round2(totalWithVat + marketingCommissionTotal);

  /// السعر المعروض على **كل** بطاقات الإعلان في التطبيق (الرئيسية، صفحتي،
  /// إعلاناتي/طلباتي للمسوّق، السلة، صفقاتي، نتائج البحث، …).
  /// — قيمة `price` نفسها (المبلغ الذي أدخله المعلن في حقل «السعر الإجمالي»)،
  ///   دون أي إضافة أو خصم لضريبة أو عمولة. تفصيل الفاتورة يظهر فقط داخل
  ///   صفحة تفاصيل الإعلان وفي الإيصالات.
  double get displayTotalPrice => price.toDouble();

  /// المرادف الواضح لقاعدة عرض البطاقات (نفس `displayTotalPrice`).
  /// — يُترك للأماكن التي تحتاج تسمية صريحة («سعر بطاقة الرئيسية»).
  double get homeCardPrice => price.toDouble();

  /// `true` عندما يوجد فعلاً عنصر إضافي (ضريبة مضافة أو عمولة) ليُعرَض في الفاتورة.
  /// — يبقى `true` أيضاً عند «شامل الضريبة» لأن سطر الضريبة الداخلية يظهر للمستفيد.
  bool get hasInvoiceDetails =>
      vatAmount > 0 || marketingCommissionTotal > 0;

  // -- نهاية حسابات الفاتورة ---------------------------------------------------

  /// تاريخ العرض المعتمد: النشر ثم الإنشاء
  DateTime get displayDate => publishedAt ?? createdAt;

  /// تطبيع حالة الإعلان
  String get normalizedStatus => (status ?? '').trim().toLowerCase();

  ListingWorkflowStage get effectiveWorkflowStage =>
      ListingWorkflowStage.resolve(
        workflowStage: workflowStage,
        legacyStatus: status,
        publishedAt: publishedAt,
      );

  /// هل يعتبر محذوفًا/مؤرشفًا منطقيًا
  bool get isDeletedLike {
    if (deletedByUser) return true;
    if (deleteApproved) return true;

    const archivedStatuses = <String>{
      'archived',
      'archive',
      'deleted',
      'removed',
      'inactive',
      'closed',
      'hidden',
    };

    return archivedStatuses.contains(normalizedStatus);
  }

  /// هل الإعلان نشط
  bool get isActive {
    if (isDeletedLike) return false;

    const activeStatuses = <String>{
      'active',
      'published',
      'approved',
      'live',
      'available',
      'reserved',
    };

    if (activeStatuses.contains(normalizedStatus)) return true;

    final ws = (workflowStage ?? '').trim().toLowerCase();
    if (ws == 'published' || ws == 'reserved') return true;

    return false;
  }

  /// هل الإعلان معلق/بانتظار المراجعة
  bool get isPending {
    if (isDeletedLike) return false;
    if (isActive) return false;

    const pendingStatuses = <String>{
      'pending',
      'waiting',
      'under_review',
      'under-review',
      'in_review',
      'in-review',
      'review',
      'draft',
      'queued',
      'processing',
    };

    if (pendingStatuses.contains(normalizedStatus)) return true;

    if (deleteRequested && !deleteApproved && !deletedByUser) return true;

    return false;
  }

  /// هل الإعلان مؤرشف
  bool get isArchived => isDeletedLike;

  /// عرض الموقع: المنطقة - المحافظة - المدينة - الحي
  String get locationText {
    final reg = (region ?? '').trim();
    final prov = (province ?? '').trim();
    final cityValue = city.trim();
    final loc = (location ?? '').trim();

    final parts = <String>[];
    if (reg.isNotEmpty) parts.add(reg);
    if (prov.isNotEmpty) parts.add(prov);
    if (cityValue.isNotEmpty) parts.add(cityValue);
    if (loc.isNotEmpty) parts.add(loc);

    return parts.join(' - ');
  }

  /// عنوان أكثر تفصيلاً
  String get fullAddressText {
    final base = locationText.trim();
    final addr = (addressLine ?? '').trim();

    if (base.isEmpty && addr.isEmpty) return '';
    if (base.isEmpty) return addr;
    if (addr.isEmpty) return base;

    return '$base - $addr';
  }

  /// الهاتف المعروض للمعلن
  String get advertiserPhone {
    final a = (ownerPhone ?? '').trim();
    if (a.isNotEmpty) return a;
    return (contactPhone ?? '').trim();
  }

  String get locationLower {
    return [
      city,
      region ?? '',
      province ?? '',
      location ?? '',
      addressLine ?? '',
      title,
      description,
    ].join(' ').trim().toLowerCase();
  }

  String get citySlug {
    final s = city.trim().toLowerCase();
    if (s.isEmpty) return 'unknown';

    return s
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه');
  }

  static PropertyType parseType(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    switch (v) {
      case 'apartment':
        return PropertyType.apartment;
      case 'land':
        return PropertyType.land;
      case 'villa':
      default:
        return PropertyType.villa;
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static double _toDouble0(dynamic v, [double fallback = 0.0]) {
    return _toDouble(v) ?? fallback;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;

    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;

    return null;
  }

  /// تطبيع قيمة عمود `marketing_commission_kind` (يحرس من قيم غريبة).
  static String _normalizeCommissionKind(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'percent':
      case 'percentage':
      case '%':
        return 'percent';
      case 'fixed':
      case 'flat':
      case 'amount':
        return 'fixed';
      case '':
      case 'none':
      case 'null':
        return 'none';
      default:
        return 'none';
    }
  }

  static DateTime? _tryParseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  static DateTime _parseDt0(dynamic v) {
    return _tryParseDt(v) ?? DateTime.now();
  }

  static Map<String, bool>? _toBoolMap(dynamic v) {
    if (v == null) return null;

    if (v is Map) {
      final out = <String, bool>{};
      v.forEach((k, val) {
        final b = _toBool(val);
        if (b == true) out[k.toString()] = true;
      });
      return out.isEmpty ? null : out;
    }

    return null;
  }

  static String? _trimOrNull(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  static Map<String, dynamic>? _objectMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) {
      return Map<String, dynamic>.from(v);
    }
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    return null;
  }

  static String? _nestedString(dynamic parent, String key) {
    if (parent is Map) {
      final v = parent[key];
      return _trimOrNull(v);
    }
    return null;
  }

  static List<String> _extractImages(
    dynamic propertyImages,
    dynamic images,
    dynamic imageUrls, {
    dynamic legacyImageUrl,
  }) {
    final out = <String>[];

    void pushFromImageMap(Map<String, dynamic> row) {
      final path = row['path']?.toString().trim();
      final fileName = row['file_name']?.toString().trim();
      final url = row['url']?.toString().trim();
      if (path != null && path.isNotEmpty) {
        out.add(path);
      } else if (fileName != null && fileName.isNotEmpty) {
        out.add(fileName);
      } else if (url != null && url.isNotEmpty) {
        out.add(url);
      }
    }

    if (propertyImages is Map) {
      pushFromImageMap(Map<String, dynamic>.from(propertyImages));
    } else if (propertyImages is List) {
      final rows = List<Map<String, dynamic>>.from(
        propertyImages.map((e) => Map<String, dynamic>.from(e as Map)),
      );

      rows.sort((a, b) {
        final sa = (a['sort_order'] as num?)?.toInt() ?? 0;
        final sb = (b['sort_order'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sb);
      });

      for (final row in rows) {
        pushFromImageMap(row);
      }
    }

    if (out.isEmpty && images is List) {
      out.addAll(
        images.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
      );
    }

    if (out.isEmpty && imageUrls is List) {
      out.addAll(
        imageUrls.map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
      );
    }

    if (out.isEmpty) {
      final u = (legacyImageUrl ?? '').toString().trim();
      if (u.isNotEmpty) out.add(u);
    }

    return out;
  }

  factory Property.fromJson(Map<String, dynamic> json) {
    var imgs = _extractImages(
      json['property_images'],
      json['images'],
      json['image_urls'],
      legacyImageUrl: json['image_url'],
    );
    if (imgs.isEmpty) {
      final primary = (json['primary_image'] ?? json['primaryImage'] ?? '')
          .toString()
          .trim();
      if (primary.isNotEmpty) {
        imgs = [primary];
      }
    }

    final rawType = PropertyTypeCatalog.normalize(
      (json['type'] ?? '').toString(),
    );
    return Property(
      id: (json['id'] ?? '').toString(),
      ownerId: (json['owner_id'] ?? '').toString(),
      listingPublicCode: _trimOrNull(json['listing_public_code']),
      ownerDisplayName: _trimOrNull(json['owner_display_name']) ??
          _trimOrNull(json['username']),
      ownerPhone: _trimOrNull(json['owner_phone']),
      title: (json['title'] as String?) ?? '',
      type: parseType(json['type']),
      listingTypeKey: rawType,
      description: (json['description'] as String?) ?? '',
      city: ((json['city'] as String?) ?? '').trim(),
      region: _trimOrNull(json['region']),
      province: _trimOrNull(json['province'] ?? json['governorate']),
      location: _trimOrNull(json['location']),
      addressLine: _trimOrNull(json['address_line']),
      area: _toDouble0(json['area']),
      price: _toDouble0(json['price']),
      priceIncludesVat: _toBool(json['price_includes_vat']) ?? true,
      vatRate: _toDouble(json['vat_rate']) ?? 0.05,
      marketingCommissionKind:
          _normalizeCommissionKind(json['marketing_commission_kind']),
      marketingCommissionRate:
          _toDouble(json['marketing_commission_rate']) ?? 0.025,
      marketingCommissionAmount:
          _toDouble(json['marketing_commission_amount']) ?? 0.0,
      defaultCoverUsed: _toBool(json['default_cover_used']) ?? false,
      currency: ((json['currency'] as String?) ?? 'SAR').trim(),
      negotiable: _toBool(json['negotiable']) ?? false,
      isAuction: _toBool(json['is_auction']) ?? false,
      currentBid: _toDouble(json['current_bid']),
      images: imgs,
      views: _toInt(json['views']) ?? 0,
      createdAt: _parseDt0(json['created_at']),
      publishedAt: _tryParseDt(json['published_at']),
      showAdvertiserName: _toBool(json['show_advertiser_name']) ??
          _toBool(json['show_owner_name']) ??
          true,
      ownerRequestsPublicName:
          _toBool(json['owner_requests_public_name']) ?? false,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      bedrooms: _toInt(json['bedrooms']),
      bathrooms: _toInt(json['bathrooms']),
      parkingSpots: _toInt(json['parking_spots']),
      furnished: _toBool(json['furnished']),
      yearBuilt: _toInt(json['year_built']),
      floor: _toInt(json['floor']),
      totalFloors: _toInt(json['total_floors']),
      amenities: _toBoolMap(json['amenities']),
      videoUrl: _trimOrNull(json['video_url']),
      virtualTourUrl: _trimOrNull(json['virtual_tour_url']),
      contactPhone: _trimOrNull(json['contact_phone']),
      availabilityDate: _tryParseDt(json['availability_date']),
      purpose: _trimOrNull(json['purpose']),
      deedNumber: _trimOrNull(json['deed_number']),
      deedDate: _tryParseDt(json['deed_date']),
      deedIssuer: _trimOrNull(json['deed_issuer']),
      buildingNumber: _trimOrNull(json['building_number']),
      marketingLicenseSnapshot: () {
        final rega = _objectMap(json['rega_payload']);
        final legacy = _objectMap(json['marketing_license_snapshot']);
        if (legacy != null && legacy.isNotEmpty) {
          if (rega != null && rega.isNotEmpty) {
            return {...rega, ...legacy};
          }
          return legacy;
        }
        return rega;
      }(),
      listingGuidance: _objectMap(json['listing_guidance']),
      orgListingSnapshot: () {
        final o = _objectMap(json['org_listing']);
        if (o != null && o.isNotEmpty) return o;
        return _objectMap(json['org_unit']);
      }(),
      isFeatured: _toBool(json['is_featured']),
      homeFeedSuppressed: _toBool(json['home_feed_suppressed']) ?? false,
      editCount: _toInt(json['edit_count']) ?? 0,
      maxEdits: _toInt(json['max_edits']) ?? 3,
      lastEditReason: _trimOrNull(json['last_edit_reason']),
      editExhausted: _toBool(json['edit_exhausted']) ?? false,
      deleteRequested: _toBool(json['delete_requested']) ?? false,
      deleteApproved: _toBool(json['delete_approved']) ?? false,
      deletedByUser: _toBool(json['deleted_by_user']) ?? false,
      deleteRequestedAt: _tryParseDt(json['delete_requested_at']),
      deleteApprovedAt: _tryParseDt(json['delete_approved_at']),
      deleteRequestReason: _trimOrNull(json['delete_request_reason']),
      deleteReviewReason: _trimOrNull(json['delete_review_reason']),
      status: _trimOrNull(json['status']),
      workflowStage: _trimOrNull(json['workflow_stage']),
      marketingRound: _toInt(json['marketing_round']) ?? 1,
      selectedOfferId: _trimOrNull(json['selected_offer_id']),
      selectedMarketerId: _trimOrNull(json['selected_marketer_id']),
      publishedByMarketerId: _trimOrNull(json['published_by_marketer_id']),
      allowPreviousMarketersRetry:
          _toBool(json['allow_previous_marketers_retry']) ?? false,
      relistCount: _toInt(json['relist_count']) ?? 0,
      waitingMarketersSince: _tryParseDt(json['waiting_marketers_since']),
      marketerResponseDeadlineAt:
          _tryParseDt(json['marketer_response_deadline_at']),
      contractStartedAt: _tryParseDt(json['contract_started_at']),
      contractSentAt: _tryParseDt(json['contract_sent_at']),
      contractSignedAt: _tryParseDt(json['contract_signed_at']),
      permitPendingSince: _tryParseDt(json['permit_pending_since']),
      permitDeadlineAt: _tryParseDt(json['permit_deadline_at']),
      permitIssuedAt: _tryParseDt(json['permit_issued_at']),
      reservationStatus: _trimOrNull(json['reservation_status']),
      reservationStartedAt: _tryParseDt(json['reservation_started_at']),
      reservationExpiresAt: _tryParseDt(json['reservation_expires_at']),
      inactive72hAt: _tryParseDt(json['inactive_72h_at']),
      cancelledAt: _tryParseDt(json['cancelled_at']),
      terminatedAt: _tryParseDt(json['terminated_at']),
    );
  }

  static Property fromDbRow(
    Map row, {
    required List<String> imageUrls,
    String? ownerDisplayName,
    String? ownerPhone,
    bool omitOwnerDisplayForPrivacy = false,
  }) {
    final map = Map<String, dynamic>.from(row);
    final typeStr = (map['type'] as String?) ?? 'villa';
    final accountProfiles = map['account_profiles'];

    final resolvedOwnerDisplayName = omitOwnerDisplayForPrivacy
        ? _trimOrNull(ownerDisplayName)
        : (_trimOrNull(ownerDisplayName) ??
            _trimOrNull(map['owner_display_name']) ??
            _trimOrNull(map['username']) ??
            _nestedString(accountProfiles, 'full_name'));

    final resolvedOwnerPhone = _trimOrNull(ownerPhone) ??
        _trimOrNull(map['owner_phone']) ??
        _nestedString(accountProfiles, 'phone');

    final rawLocation = _trimOrNull(map['location']);
    final rawAddress = _trimOrNull(map['address_line']);

    final resolvedImages = imageUrls.isNotEmpty
        ? imageUrls
        : _extractImages(
            map['property_images'],
            map['images'],
            map['image_urls'],
            legacyImageUrl: map['image_url'],
          );

    return Property(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      listingPublicCode: _trimOrNull(map['listing_public_code']),
      ownerDisplayName: resolvedOwnerDisplayName,
      ownerPhone: resolvedOwnerPhone,
      title: (map['title'] as String?) ?? '',
      type: parseType(typeStr),
      listingTypeKey: PropertyTypeCatalog.normalize(typeStr),
      description: (map['description'] as String?) ?? '',
      city: ((map['city'] as String?) ?? '').trim(),
      region: _trimOrNull(map['region']),
      province: _trimOrNull(map['province'] ?? map['governorate']),
      location: rawLocation ?? rawAddress,
      addressLine: rawAddress,
      area: _toDouble0(map['area']),
      price: _toDouble0(map['price']),
      priceIncludesVat: _toBool(map['price_includes_vat']) ?? true,
      vatRate: _toDouble(map['vat_rate']) ?? 0.05,
      marketingCommissionKind:
          _normalizeCommissionKind(map['marketing_commission_kind']),
      marketingCommissionRate:
          _toDouble(map['marketing_commission_rate']) ?? 0.025,
      marketingCommissionAmount:
          _toDouble(map['marketing_commission_amount']) ?? 0.0,
      defaultCoverUsed: _toBool(map['default_cover_used']) ?? false,
      currency: ((map['currency'] as String?) ?? 'SAR').trim(),
      negotiable: _toBool(map['negotiable']) ?? false,
      isAuction: _toBool(map['is_auction']) ?? false,
      currentBid: _toDouble(map['current_bid']),
      images: resolvedImages,
      views: _toInt(map['views']) ?? 0,
      createdAt: _parseDt0(map['created_at']),
      publishedAt: _tryParseDt(map['published_at']),
      showAdvertiserName: _toBool(map['show_advertiser_name']) ??
          _toBool(map['show_owner_name']) ??
          true,
      ownerRequestsPublicName:
          _toBool(map['owner_requests_public_name']) ?? false,
      latitude: _toDouble(map['latitude']),
      longitude: _toDouble(map['longitude']),
      bedrooms: _toInt(map['bedrooms']),
      bathrooms: _toInt(map['bathrooms']),
      parkingSpots: _toInt(map['parking_spots']),
      furnished: _toBool(map['furnished']),
      yearBuilt: _toInt(map['year_built']),
      floor: _toInt(map['floor']),
      totalFloors: _toInt(map['total_floors']),
      amenities: _toBoolMap(map['amenities']),
      videoUrl: _trimOrNull(map['video_url']),
      virtualTourUrl: _trimOrNull(map['virtual_tour_url']),
      contactPhone: _trimOrNull(map['contact_phone']),
      availabilityDate: _tryParseDt(map['availability_date']),
      purpose: _trimOrNull(map['purpose']),
      deedNumber: _trimOrNull(map['deed_number']),
      deedDate: _tryParseDt(map['deed_date']),
      deedIssuer: _trimOrNull(map['deed_issuer']),
      buildingNumber: _trimOrNull(map['building_number']),
      marketingLicenseSnapshot: () {
        final rega = _objectMap(map['rega_payload']);
        final legacy = _objectMap(map['marketing_license_snapshot']);
        if (legacy != null && legacy.isNotEmpty) {
          if (rega != null && rega.isNotEmpty) {
            return {...rega, ...legacy};
          }
          return legacy;
        }
        return rega;
      }(),
      listingGuidance: _objectMap(map['listing_guidance']),
      orgListingSnapshot: () {
        final o = _objectMap(map['org_listing']);
        if (o != null && o.isNotEmpty) return o;
        return _objectMap(map['org_unit']);
      }(),
      isFeatured: _toBool(map['is_featured']),
      homeFeedSuppressed: _toBool(map['home_feed_suppressed']) ?? false,
      editCount: _toInt(map['edit_count']) ?? 0,
      maxEdits: _toInt(map['max_edits']) ?? 3,
      lastEditReason: _trimOrNull(map['last_edit_reason']),
      editExhausted: _toBool(map['edit_exhausted']) ?? false,
      deleteRequested: _toBool(map['delete_requested']) ?? false,
      deleteApproved: _toBool(map['delete_approved']) ?? false,
      deletedByUser: _toBool(map['deleted_by_user']) ?? false,
      deleteRequestedAt: _tryParseDt(map['delete_requested_at']),
      deleteApprovedAt: _tryParseDt(map['delete_approved_at']),
      deleteRequestReason: _trimOrNull(map['delete_request_reason']),
      deleteReviewReason: _trimOrNull(map['delete_review_reason']),
      status: _trimOrNull(map['status']),
      workflowStage: _trimOrNull(map['workflow_stage']),
      marketingRound: _toInt(map['marketing_round']) ?? 1,
      selectedOfferId: _trimOrNull(map['selected_offer_id']),
      selectedMarketerId: _trimOrNull(map['selected_marketer_id']),
      publishedByMarketerId: _trimOrNull(map['published_by_marketer_id']),
      allowPreviousMarketersRetry:
          _toBool(map['allow_previous_marketers_retry']) ?? false,
      relistCount: _toInt(map['relist_count']) ?? 0,
      waitingMarketersSince: _tryParseDt(map['waiting_marketers_since']),
      marketerResponseDeadlineAt:
          _tryParseDt(map['marketer_response_deadline_at']),
      contractStartedAt: _tryParseDt(map['contract_started_at']),
      contractSentAt: _tryParseDt(map['contract_sent_at']),
      contractSignedAt: _tryParseDt(map['contract_signed_at']),
      permitPendingSince: _tryParseDt(map['permit_pending_since']),
      permitDeadlineAt: _tryParseDt(map['permit_deadline_at']),
      permitIssuedAt: _tryParseDt(map['permit_issued_at']),
      reservationStatus: _trimOrNull(map['reservation_status']),
      reservationStartedAt: _tryParseDt(map['reservation_started_at']),
      reservationExpiresAt: _tryParseDt(map['reservation_expires_at']),
      inactive72hAt: _tryParseDt(map['inactive_72h_at']),
      cancelledAt: _tryParseDt(map['cancelled_at']),
      terminatedAt: _tryParseDt(map['terminated_at']),
    );
  }

  Property copyWith({
    String? id,
    String? ownerId,
    String? listingPublicCode,
    String? ownerDisplayName,
    String? ownerPhone,
    String? title,
    PropertyType? type,
    String? listingTypeKey,
    String? description,
    String? city,
    String? region,
    String? province,
    String? location,
    double? area,
    double? price,
    bool? priceIncludesVat,
    double? vatRate,
    String? marketingCommissionKind,
    double? marketingCommissionRate,
    double? marketingCommissionAmount,
    bool? defaultCoverUsed,
    String? currency,
    bool? negotiable,
    bool? isAuction,
    double? currentBid,
    List<String>? images,
    String? videoUrl,
    String? virtualTourUrl,
    int? views,
    DateTime? createdAt,
    DateTime? publishedAt,
    bool? showAdvertiserName,
    bool? ownerRequestsPublicName,
    double? latitude,
    double? longitude,
    String? addressLine,
    int? bedrooms,
    int? bathrooms,
    int? parkingSpots,
    bool? furnished,
    int? yearBuilt,
    int? floor,
    int? totalFloors,
    Map<String, bool>? amenities,
    String? contactPhone,
    DateTime? availabilityDate,
    bool? isFeatured,
    bool? homeFeedSuppressed,
    int? editCount,
    int? maxEdits,
    String? lastEditReason,
    bool? editExhausted,
    bool? deleteRequested,
    bool? deleteApproved,
    bool? deletedByUser,
    DateTime? deleteRequestedAt,
    DateTime? deleteApprovedAt,
    String? deleteRequestReason,
    String? deleteReviewReason,
    String? status,
    String? workflowStage,
    int? marketingRound,
    String? selectedOfferId,
    String? selectedMarketerId,
    String? publishedByMarketerId,
    bool? allowPreviousMarketersRetry,
    int? relistCount,
    DateTime? waitingMarketersSince,
    DateTime? marketerResponseDeadlineAt,
    DateTime? contractStartedAt,
    DateTime? contractSentAt,
    DateTime? contractSignedAt,
    DateTime? permitPendingSince,
    DateTime? permitDeadlineAt,
    DateTime? permitIssuedAt,
    String? reservationStatus,
    DateTime? reservationStartedAt,
    DateTime? reservationExpiresAt,
    DateTime? inactive72hAt,
    DateTime? cancelledAt,
    DateTime? terminatedAt,
    String? purpose,
    String? deedNumber,
    DateTime? deedDate,
    String? deedIssuer,
    String? buildingNumber,
    Map<String, dynamic>? marketingLicenseSnapshot,
    Map<String, dynamic>? listingGuidance,
    Map<String, dynamic>? orgListingSnapshot,
  }) {
    return Property(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      listingPublicCode: listingPublicCode ?? this.listingPublicCode,
      ownerDisplayName: ownerDisplayName ?? this.ownerDisplayName,
      ownerPhone: ownerPhone ?? this.ownerPhone,
      title: title ?? this.title,
      type: type ?? this.type,
      listingTypeKey: listingTypeKey ?? this.listingTypeKey,
      description: description ?? this.description,
      city: city ?? this.city,
      region: region ?? this.region,
      province: province ?? this.province,
      location: location ?? this.location,
      area: area ?? this.area,
      price: price ?? this.price,
      priceIncludesVat: priceIncludesVat ?? this.priceIncludesVat,
      vatRate: vatRate ?? this.vatRate,
      marketingCommissionKind:
          marketingCommissionKind ?? this.marketingCommissionKind,
      marketingCommissionRate:
          marketingCommissionRate ?? this.marketingCommissionRate,
      marketingCommissionAmount:
          marketingCommissionAmount ?? this.marketingCommissionAmount,
      defaultCoverUsed: defaultCoverUsed ?? this.defaultCoverUsed,
      currency: currency ?? this.currency,
      negotiable: negotiable ?? this.negotiable,
      isAuction: isAuction ?? this.isAuction,
      currentBid: currentBid ?? this.currentBid,
      images: images ?? this.images,
      videoUrl: videoUrl ?? this.videoUrl,
      virtualTourUrl: virtualTourUrl ?? this.virtualTourUrl,
      views: views ?? this.views,
      createdAt: createdAt ?? this.createdAt,
      publishedAt: publishedAt ?? this.publishedAt,
      showAdvertiserName: showAdvertiserName ?? this.showAdvertiserName,
      ownerRequestsPublicName:
          ownerRequestsPublicName ?? this.ownerRequestsPublicName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      addressLine: addressLine ?? this.addressLine,
      bedrooms: bedrooms ?? this.bedrooms,
      bathrooms: bathrooms ?? this.bathrooms,
      parkingSpots: parkingSpots ?? this.parkingSpots,
      furnished: furnished ?? this.furnished,
      yearBuilt: yearBuilt ?? this.yearBuilt,
      floor: floor ?? this.floor,
      totalFloors: totalFloors ?? this.totalFloors,
      amenities: amenities ?? this.amenities,
      contactPhone: contactPhone ?? this.contactPhone,
      availabilityDate: availabilityDate ?? this.availabilityDate,
      isFeatured: isFeatured ?? this.isFeatured,
      homeFeedSuppressed: homeFeedSuppressed ?? this.homeFeedSuppressed,
      editCount: editCount ?? this.editCount,
      maxEdits: maxEdits ?? this.maxEdits,
      lastEditReason: lastEditReason ?? this.lastEditReason,
      editExhausted: editExhausted ?? this.editExhausted,
      deleteRequested: deleteRequested ?? this.deleteRequested,
      deleteApproved: deleteApproved ?? this.deleteApproved,
      deletedByUser: deletedByUser ?? this.deletedByUser,
      deleteRequestedAt: deleteRequestedAt ?? this.deleteRequestedAt,
      deleteApprovedAt: deleteApprovedAt ?? this.deleteApprovedAt,
      deleteRequestReason: deleteRequestReason ?? this.deleteRequestReason,
      deleteReviewReason: deleteReviewReason ?? this.deleteReviewReason,
      status: status ?? this.status,
      workflowStage: workflowStage ?? this.workflowStage,
      marketingRound: marketingRound ?? this.marketingRound,
      selectedOfferId: selectedOfferId ?? this.selectedOfferId,
      selectedMarketerId: selectedMarketerId ?? this.selectedMarketerId,
      publishedByMarketerId:
          publishedByMarketerId ?? this.publishedByMarketerId,
      allowPreviousMarketersRetry:
          allowPreviousMarketersRetry ?? this.allowPreviousMarketersRetry,
      relistCount: relistCount ?? this.relistCount,
      waitingMarketersSince:
          waitingMarketersSince ?? this.waitingMarketersSince,
      marketerResponseDeadlineAt:
          marketerResponseDeadlineAt ?? this.marketerResponseDeadlineAt,
      contractStartedAt: contractStartedAt ?? this.contractStartedAt,
      contractSentAt: contractSentAt ?? this.contractSentAt,
      contractSignedAt: contractSignedAt ?? this.contractSignedAt,
      permitPendingSince: permitPendingSince ?? this.permitPendingSince,
      permitDeadlineAt: permitDeadlineAt ?? this.permitDeadlineAt,
      permitIssuedAt: permitIssuedAt ?? this.permitIssuedAt,
      reservationStatus: reservationStatus ?? this.reservationStatus,
      reservationStartedAt: reservationStartedAt ?? this.reservationStartedAt,
      reservationExpiresAt: reservationExpiresAt ?? this.reservationExpiresAt,
      inactive72hAt: inactive72hAt ?? this.inactive72hAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      terminatedAt: terminatedAt ?? this.terminatedAt,
      purpose: purpose ?? this.purpose,
      deedNumber: deedNumber ?? this.deedNumber,
      deedDate: deedDate ?? this.deedDate,
      deedIssuer: deedIssuer ?? this.deedIssuer,
      buildingNumber: buildingNumber ?? this.buildingNumber,
      marketingLicenseSnapshot:
          marketingLicenseSnapshot ?? this.marketingLicenseSnapshot,
      listingGuidance: listingGuidance ?? this.listingGuidance,
      orgListingSnapshot: orgListingSnapshot ?? this.orgListingSnapshot,
    );
  }
}
