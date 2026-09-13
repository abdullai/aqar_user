// ignore_for_file: unused_element

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/market_property_request_row.dart';
import '../../models/property.dart';
import '../l10n/locale_content.dart';
import 'listing_media_urls.dart';
import 'property_type_catalog.dart';

/// عرض موحّد لغرض الإعلان على البطاقات والفلاتر.
abstract final class PropertyListingDisplay {
  /// سطر الموقع: المدينة فقط؛ بدون « - » وباقي التفاصيل.
  /// إجمالي يُعرض على البطاقة: أساس + ضريبة 5٪ + عمولة تسويق 2.5٪ من (الأساس+الضريبة).
  static double totalWithVatAndPlatformFee(double base) {
    if (base.isNaN || base.isInfinite || base < 0) return 0;
    final vat = base * 0.05;
    final afterVat = base + vat;
    final platform = afterVat * 0.025;
    return afterVat + platform;
  }

  static String cityLine(Property p) {
    final city = p.city.trim();
    if (city.isEmpty) return '-';
    final loc = (p.location ?? '').trim();
    // لا تستبدل المدينة بالحي إن تطابقا خطأً أو إن كان الحقل فارغاً من قبل.
    if (loc.isNotEmpty && city.toLowerCase() == loc.toLowerCase()) {
      // المدينة والحي نفس النص — ما زال نعرضه كمدينة إن لم توجد منطقة أوضح.
      return city;
    }
    return city;
  }

  /// سطر العنوان للعرض: منطقة - مدينة - حي (حسب المتوفر). المحافظة فقط إن غابت المدينة.
  static String addressLine(
    Property p, {
    required bool isAr,
    String separator = ' - ',
  }) {
    final parts = cardLocationLinePartsForProperty(p, isAr: isAr);
    if (parts.isEmpty) return '';
    return parts.join(separator);
  }

  /// نفس [addressLine] من حقول خام (طلبات/خرائط).
  static String addressLineFromParts({
    required String region,
    required String city,
    required String district,
    String governorate = '',
    required bool isAr,
    String separator = ' - ',
  }) {
    final parts = cardLocationLineParts(
      region: region,
      city: city,
      district: district,
      governorate: governorate,
      isAr: isAr,
    );
    if (parts.isEmpty) return '';
    return parts.join(separator);
  }

  /// ترتيب أنيق: منطقة → محافظة → مدينة → حي (بدون فراغات/تكرار).
  static List<String> locationHierarchyParts(Property p) {
    final seen = <String>{};
    final out = <String>[];
    _addAdminLocationPart(p.region, seen, out);
    _addAdminLocationPart(p.province, seen, out);
    _addAdminLocationPart(p.city, seen, out);
    _addAdminLocationPart(p.location, seen, out);
    return out;
  }

  /// مكان يُحقَن في عنوان البطاقة فقط عند نقص التسلسل الإداري.
  /// إذا توفرت المنطقة والمدينة معاً يُتركان لسطر الموقع (لا يُكرَّران في العنوان).
  /// الحي لا يدخل العنوان — يظهر في سطر الموقع عند توفره.
  static String? cardTitlePlace({
    required String region,
    required String city,
    required String district,
  }) {
    final r = _normalizeAdminLocationToken(region);
    final c = _normalizeAdminLocationToken(city);
    final hasR = r.isNotEmpty;
    final hasC = c.isNotEmpty && c != '-';
    if (hasR && hasC) return null;
    if (hasC) return c;
    if (hasR) return r;
    return null;
  }

  /// سطر البطاقة: منطقة · مدينة · حي — حسب المتوفر (بدون محافظة إن وُجدت المدينة).
  static List<String> cardLocationLineParts({
    required String region,
    required String city,
    required String district,
    String governorate = '',
    bool isAr = true,
  }) {
    final seen = <String>{};
    final out = <String>[];
    _addAdminLocationPart(region, seen, out);
    final cityTok = _normalizeAdminLocationToken(city);
    if (cityTok.isEmpty) {
      _addAdminLocationPart(governorate, seen, out);
    }
    _addAdminLocationPart(city, seen, out);
    _addAdminLocationPart(district, seen, out);
    return LocaleContent.parts(out, isAr: isAr);
  }

  static List<String> cardLocationLinePartsForProperty(
    Property p, {
    bool isAr = true,
  }) {
    final city = cityLine(p);
    return cardLocationLineParts(
      region: (p.region ?? '').trim(),
      city: city == '-' ? '' : city,
      district: (p.location ?? '').trim(),
      governorate: (p.province ?? '').trim(),
      isAr: isAr,
    );
  }

  static List<String> cardLocationLinePartsForRequest(
    MarketPropertyRequestRow r, {
    bool isAr = true,
  }) {
    return cardLocationLineParts(
      region: r.regionLabel,
      city: r.city,
      district: r.districts
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(isAr ? '، ' : ', '),
      governorate: r.governorateLabel,
      isAr: isAr,
    );
  }

  /// منطقة / محافظة / مدينة / حي من صف العقار والحمولة والطلب — بدون خلط إعلان آخر.
  static ({
    String region,
    String governorate,
    String city,
    String district,
  }) locationSlotsFromMaps({
    Map<String, dynamic>? property,
    Map<String, dynamic>? payload,
    Map<String, dynamic>? request,
  }) {
    String pick(List<String> keys) {
      for (final src in [property, payload, request]) {
        if (src == null) continue;
        for (final k in keys) {
          final v = (src[k] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
      return '';
    }

    final region = pick(const ['region', 'region_label', 'request_region']);
    final governorate = pick(const [
      'governorate',
      'province',
      'governorate_label',
      'request_governorate',
    ]);
    final city = pick(const [
      'city',
      'preview_city',
      'request_city',
    ]);
    var district = pick(const [
      'district',
      'district_label',
      'neighborhood',
      'location',
    ]);
    if (district.isNotEmpty &&
        city.isNotEmpty &&
        district.toLowerCase() == city.toLowerCase()) {
      district = '';
    }
    return (
      region: region,
      governorate: governorate,
      city: city,
      district: district,
    );
  }

  static List<String> locationHierarchyPartsForRequest(
    MarketPropertyRequestRow r,
  ) {
    final seen = <String>{};
    final out = <String>[];
    _addAdminLocationPart(r.regionLabel, seen, out);
    _addAdminLocationPart(r.governorateLabel, seen, out);
    _addAdminLocationPart(r.city, seen, out);
    for (final d in r.districts) {
      _addAdminLocationPart(d, seen, out);
    }
    return out;
  }

  static String _normalizeAdminLocationToken(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    for (final prefix in const ['محافظة ', 'منطقة ', 'مدينة ', 'حي ']) {
      if (t.startsWith(prefix)) {
        final stripped = t.substring(prefix.length).trim();
        if (stripped.isNotEmpty) t = stripped;
        break;
      }
    }
    return t;
  }

  static void _addAdminLocationPart(
    String? raw,
    Set<String> seen,
    List<String> out,
  ) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return;
    if (v.contains(' - ')) {
      for (final piece in v.split(' - ')) {
        _addAdminLocationPart(piece, seen, out);
      }
      return;
    }
    if (v.contains('،')) {
      for (final piece in v.split('،')) {
        _addAdminLocationPart(piece, seen, out);
      }
      return;
    }
    final t = _normalizeAdminLocationToken(v);
    if (t.isEmpty) return;
    final key = t.toLowerCase();
    if (!seen.add(key)) return;
    out.add(t);
  }

  /// رمز الغرض للفلترة: sale | rent | auction | investment
  static String purposeFilterKey(Property p) {
    if (p.isAuction) return 'auction';
    final raw = (p.purpose ?? 'sale').toLowerCase().trim();
    if (raw.isEmpty) return 'sale';
    if (raw.contains('rent') ||
        raw == 'daily_rent' ||
        raw == 'monthly_rent' ||
        raw == 'yearly_rent') {
      return 'rent';
    }
    if (raw == 'investment') return 'investment';
    if (raw == 'auction') return 'auction';
    return 'sale';
  }

  static bool matchesPurposeFilter(Property p, String? filter) {
    if (filter == null || filter.isEmpty) return true;
    return purposeFilterKey(p) == filter;
  }

  static _PurposeTokens _tokensForProperty(Property p) {
    if (p.isAuction) {
      return const _PurposeTokens(
        labelAr: 'مزاد',
        labelEn: 'Auction',
        accent: Color(0xFFEA580C),
        areaIcon: Icons.gavel_outlined,
      );
    }
    final raw = (p.purpose ?? 'sale').toLowerCase().trim();
    switch (raw) {
      case 'rent':
      case 'daily_rent':
        return const _PurposeTokens(
          labelAr: 'إيجار يومي',
          labelEn: 'Daily rent',
          accent: Color(0xFF2563EB),
          areaIcon: Icons.calendar_today_outlined,
        );
      case 'monthly_rent':
        return const _PurposeTokens(
          labelAr: 'إيجار شهري',
          labelEn: 'Monthly rent',
          accent: Color(0xFF2563EB),
          areaIcon: Icons.date_range_outlined,
        );
      case 'yearly_rent':
        return const _PurposeTokens(
          labelAr: 'إيجار سنوي',
          labelEn: 'Yearly rent',
          accent: Color(0xFF1D4ED8),
          areaIcon: Icons.event_repeat_outlined,
        );
      case 'investment':
        return const _PurposeTokens(
          labelAr: 'استثمار',
          labelEn: 'Investment',
          accent: Color(0xFF7C3AED),
          areaIcon: Icons.trending_up_outlined,
        );
      case 'auction':
        return const _PurposeTokens(
          labelAr: 'مزاد',
          labelEn: 'Auction',
          accent: Color(0xFFEA580C),
          areaIcon: Icons.gavel_outlined,
        );
      default:
        return const _PurposeTokens(
          labelAr: 'للبيع',
          labelEn: 'For sale',
          accent: Color(0xFF0F766E),
          areaIcon: Icons.payments_outlined,
        );
    }
  }

  static String purposeLabel(Property p, bool isAr) {
    final t = _tokensForProperty(p);
    return isAr ? t.labelAr : t.labelEn;
  }

  static Color accentColor(Property p) => _tokensForProperty(p).accent;

  static IconData areaIcon(Property p) => _tokensForProperty(p).areaIcon;

  /// وجود بيانات ترخيص/هوية في اللقطة المخزّنة (rega_payload).
  /// أيقونة + نص لشارات الاستخدام (سكني/تجاري) على البطاقات.
  static List<(IconData, String)> usageBadgeTuples(Property p, bool isAr) {
    final r = <(IconData, String)>[];
    if (p.usageSuitableResidential) {
      r.add((
        Icons.home_work_outlined,
        isAr ? 'سكني' : 'Residential',
      ));
    }
    if (p.usageSuitableCommercial) {
      r.add((
        Icons.storefront_outlined,
        isAr ? 'تجاري' : 'Commercial',
      ));
    }
    return r;
  }

  static List<(IconData, String)> usageTuplesFromPayload(
    Map<String, dynamic>? payload,
    bool isAr,
  ) {
    if (payload == null) return [];
    Map<String, dynamic>? usageMap;
    final u = payload['usage'];
    if (u is Map) {
      usageMap = Map<String, dynamic>.from(u);
    } else {
      final lg = payload['listing_guidance'];
      if (lg is Map) {
        final inner = lg['usage'];
        if (inner is Map) {
          usageMap = Map<String, dynamic>.from(inner);
        }
      }
    }
    var res = false;
    var com = false;
    if (usageMap != null) {
      res = usageMap['residential'] == true;
      com = usageMap['commercial'] == true;
    }
    final r = <(IconData, String)>[];
    if (res) {
      r.add((
        Icons.home_work_outlined,
        isAr ? 'سكني' : 'Residential',
      ));
    }
    if (com) {
      r.add((
        Icons.storefront_outlined,
        isAr ? 'تجاري' : 'Commercial',
      ));
    }
    return r;
  }

  static bool showMarketerVerifiedBadge(Property p) {
    final snap = p.marketingLicenseSnapshot;
    if (snap == null || snap.isEmpty) return false;
    for (final k in [
      'rega_ad_license_number',
      'fal_broker_license_number',
      'marketer_entity_display_name',
      'marketer_office_name',
    ]) {
      final v = snap[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) return true;
    }
    return false;
  }

  static String? ownerNotesFromListingRequestRow(Map<String, dynamic>? r) {
    if (r == null) return null;
    final desc = (r['description'] ?? '').toString().trim();
    if (desc.isNotEmpty) return desc;
    final raw = r['payload_json'];
    if (raw == null) return null;
    try {
      Map<String, dynamic>? m;
      if (raw is String && raw.trim().isNotEmpty) {
        final d = jsonDecode(raw);
        if (d is Map) m = Map<String, dynamic>.from(d);
      } else if (raw is Map) {
        m = Map<String, dynamic>.from(raw);
      }
      final n = (m?['owner_notes'] ?? m?['notes'] ?? '').toString().trim();
      return n.isEmpty ? null : n;
    } catch (_) {
      return null;
    }
  }

  /// مدينة الطلب فقط (بدون تفاصيل بعد شرطة).
  static String cityLineFromRequestRow(Map<String, dynamic> row) {
    final city = (row['request_city'] ?? row['city'] ?? '').toString().trim();
    if (city.isNotEmpty) return city;
    return '-';
  }

  static String purposeCodeFromRequestRow(Map<String, dynamic> row) {
    final fromPreview =
        (row['preview_purpose'] ?? '').toString().trim().toLowerCase();
    if (fromPreview.isNotEmpty) return fromPreview;
    final raw = row['payload_json'];
    if (raw != null) {
      try {
        Map<String, dynamic>? m;
        if (raw is String && raw.trim().isNotEmpty) {
          final d = jsonDecode(raw);
          if (d is Map) m = Map<String, dynamic>.from(d);
        } else if (raw is Map) {
          m = Map<String, dynamic>.from(raw);
        }
        final p = (m?['purpose'] ?? '').toString().trim().toLowerCase();
        if (p.isNotEmpty) return p;
      } catch (_) {}
    }
    if (row['preview_is_auction'] == true) return 'auction';
    return 'sale';
  }

  static String purposeLabelForRequestRow(Map<String, dynamic> row, bool isAr) {
    return _labelForPurposeCode(
      purposeCodeFromRequestRow(row),
      isAuction: row['preview_is_auction'] == true,
      isAr: isAr,
    );
  }

  static Color accentForRequestRow(Map<String, dynamic> row) {
    return _accentForPurposeCode(
      purposeCodeFromRequestRow(row),
      isAuction: row['preview_is_auction'] == true,
    );
  }

  static IconData areaIconForRequestRow(Map<String, dynamic> row) {
    return _areaIconForPurposeCode(
      purposeCodeFromRequestRow(row),
      isAuction: row['preview_is_auction'] == true,
    );
  }

  static String purposeFilterKeyForRow(Map<String, dynamic> row) {
    if (row['preview_is_auction'] == true) return 'auction';
    final raw = purposeCodeFromRequestRow(row);
    if (raw.contains('rent') ||
        raw == 'daily_rent' ||
        raw == 'monthly_rent' ||
        raw == 'yearly_rent') {
      return 'rent';
    }
    if (raw == 'investment') return 'investment';
    if (raw == 'auction') return 'auction';
    return 'sale';
  }

  static List<String> _personNameTokens(String raw) {
    return raw
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  /// يكيّف الاسم للبطاقة: يُفضَّل الاسم كاملاً؛ وعلى الشاشات الضيقة يُبقى
  /// **ثلاثياً على الأقل** (إن وُجد) ويُصغَّر الخط عبر [FittedBox] في الواجهة.
  ///
  /// لا يُرجع الاسم الأول فقط — الاسم مهم للجذب (اسم أو معرّف).
  static String scaleDisplayNameParts(String raw, double width) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return '';
    // الاسم كاملاً دائماً (فرد / مكتب / مؤسسة / شركة) — الواجهة تلتف حتى 5 أسطر.
    return normalized;
  }

  static String _scaleOwnerDisplayNameParts(String raw, double cardWidth) =>
      scaleDisplayNameParts(raw, cardWidth);

  /// اسم المالك على البطاقة.
  ///
  /// [suppressPublicOwnerIdentity] على الرئيسية/الاستكشاف: لا يُعرض سطر المعلن للغير.
  /// [showFullLegalNameOnCard] للمسوّق في سياق التسويق: الاسم الرباعي كاملاً.
  /// [viewingAsPropertyOwner] «صفحتي»: يظهر للمالك حتى مع إخفاء الاسم عن العامة.
  static String ownerNameForListingCard(
    Property p,
    bool isAr,
    double cardWidth, {
    bool viewingAsPropertyOwner = false,
    bool suppressPublicOwnerIdentity = false,
    bool showFullLegalNameOnCard = false,
  }) {
    if (suppressPublicOwnerIdentity && !viewingAsPropertyOwner) {
      // الرئيسية: لا يُعرض الاسم الرباعي القانوني، ويظهر الاسم الذي اختار الناشر عرضه.
      return p.visibleAdvertiserName;
    }
    if (viewingAsPropertyOwner) {
      final raw = (p.ownerDisplayName ?? '').trim();
      if (raw.isEmpty) return isAr ? 'المعلن' : 'Advertiser';
      return raw;
    }
    if (showFullLegalNameOnCard) {
      final raw = (p.ownerDisplayName ?? '').trim();
      if (raw.isEmpty) return isAr ? 'معلن' : 'Advertiser';
      return raw;
    }
    // السوق العقاري: الاسم يظهر فقط إذا اختار الناشر إظهاره (معتمد أو مستعار).
    if (suppressPublicOwnerIdentity || !p.canShowAdvertiserName) {
      if (!p.canShowAdvertiserName) return '';
      final pub = p.visibleAdvertiserName;
      return pub;
    }
    final pub = p.visibleAdvertiserName;
    if (pub.isNotEmpty) return pub;
    return '';
  }

  /// اسم المالك: كلمة واحدة / ثنتان / ثلاث حسب عرض البطاقة.
  ///
  /// عند [viewingAsPropertyOwner] يُعرض اسم المالك الفعلي كما في «صفحتي» حتى لو كان
  /// الإعلان يخفي الاسم عن العامة.
  static String ownerNameScaled(
    Property p,
    bool isAr,
    double cardWidth, {
    bool viewingAsPropertyOwner = false,
  }) {
    return ownerNameForListingCard(
      p,
      isAr,
      cardWidth,
      viewingAsPropertyOwner: viewingAsPropertyOwner,
    );
  }

  static String _labelForPurposeCode(
    String code, {
    required bool isAuction,
    required bool isAr,
  }) {
    if (isAuction) {
      return isAr ? 'مزاد' : 'Auction';
    }
    switch (code) {
      case 'rent':
      case 'daily_rent':
        return isAr ? 'إيجار يومي' : 'Daily rent';
      case 'monthly_rent':
        return isAr ? 'إيجار شهري' : 'Monthly rent';
      case 'yearly_rent':
        return isAr ? 'إيجار سنوي' : 'Yearly rent';
      case 'investment':
        return isAr ? 'استثمار' : 'Investment';
      case 'auction':
        return isAr ? 'مزاد' : 'Auction';
      default:
        return isAr ? 'للبيع' : 'For sale';
    }
  }

  static Color _accentForPurposeCode(String code, {required bool isAuction}) {
    if (isAuction || code == 'auction') return const Color(0xFFEA580C);
    switch (code) {
      case 'rent':
      case 'daily_rent':
      case 'monthly_rent':
      case 'yearly_rent':
        return const Color(0xFF2563EB);
      case 'investment':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF0F766E);
    }
  }

  static IconData _areaIconForPurposeCode(String code,
      {required bool isAuction}) {
    if (isAuction || code == 'auction') return Icons.gavel_outlined;
    switch (code) {
      case 'rent':
      case 'daily_rent':
        return Icons.calendar_today_outlined;
      case 'monthly_rent':
        return Icons.date_range_outlined;
      case 'yearly_rent':
        return Icons.event_repeat_outlined;
      case 'investment':
        return Icons.trending_up_outlined;
      default:
        return Icons.payments_outlined;
    }
  }

  /// تسمية نوع العقار من كود التخزين (مثل `villa`) في بطاقات الطلبات والمسوقين.
  static String propertyTypeCodeLabel(String raw, bool isAr) {
    final c = raw.trim().toLowerCase();
    switch (c) {
      case 'villa':
        return isAr ? 'فيلا' : 'Villa';
      case 'apartment':
        return isAr ? 'شقة' : 'Apartment';
      case 'land':
        return isAr ? 'أرض' : 'Land';
      case 'floor':
        return isAr ? 'دور' : 'Floor';
      case 'building':
        return isAr ? 'مبنى' : 'Building';
      case 'commercial_building':
        return isAr ? 'مبنى تجاري' : 'Commercial building';
      case 'office':
        return isAr ? 'مكتب' : 'Office';
      case 'shop':
        return isAr ? 'محل' : 'Shop';
      case 'warehouse':
        return isAr ? 'مستودع' : 'Warehouse';
      case 'farm':
        return isAr ? 'مزرعة' : 'Farm';
      case 'rest_house':
        return isAr ? 'استراحة' : 'Rest house';
      case 'chalet':
        return isAr ? 'شاليه' : 'Chalet';
      case 'traditional_house':
        return isAr ? 'بيت شعبي' : 'Traditional house';
      case 'room':
        return isAr ? 'غرفة' : 'Room';
      case 'suite':
        return isAr ? 'جناح' : 'Suite';
      case 'showroom':
        return isAr ? 'معرض' : 'Showroom';
      case 'station':
        return isAr ? 'محطة' : 'Station';
      case 'project':
        return isAr ? 'مشروع' : 'Project';
      case 'other':
        return isAr ? 'أخرى' : 'Other';
      default:
        return raw.trim();
    }
  }

  static String typeCodeFromRequestRow(Map<String, dynamic> row) {
    var t = (row['preview_type'] ?? row['request_property_type'] ?? '')
        .toString()
        .trim();
    if (t.isNotEmpty) return t;
    final raw = row['payload_json'];
    if (raw != null) {
      try {
        Map<String, dynamic>? m;
        if (raw is String && raw.trim().isNotEmpty) {
          final d = jsonDecode(raw);
          if (d is Map) m = Map<String, dynamic>.from(d);
        } else if (raw is Map) {
          m = Map<String, dynamic>.from(raw);
        }
        t = (m?['type'] ?? '').toString().trim();
      } catch (_) {}
    }
    return t;
  }

  static String typeLabelForRequestRow(Map<String, dynamic> row, bool isAr) {
    final code = typeCodeFromRequestRow(row);
    if (code.isEmpty) return '';
    return propertyTypeCodeLabel(code, isAr);
  }

  // ---------------------------------------------------------------------------
  // عناوين العرض: نوع + غرض + بـالمدينة (بدون «فيلا جدة للبيع»)
  // ---------------------------------------------------------------------------

  /// حرف جر عربي للمكان: جدة → بجدة، الرياض → بالرياض.
  static String placeWithBi(String place) {
    final p = place.trim();
    if (p.isEmpty) return '';
    return 'ب$p';
  }

  static String purposeBitShort(Property p, bool isAr) {
    final key = purposeFilterKey(p);
    if (isAr) {
      return switch (key) {
        'rent' => 'للإيجار',
        'auction' => 'للمزاد',
        'investment' => 'للاستثمار',
        _ => 'للبيع',
      };
    }
    return switch (key) {
      'rent' => 'for rent',
      'auction' => 'for auction',
      'investment' => 'for investment',
      _ => 'for sale',
    };
  }

  static String typeLabelForProperty(Property p, bool isAr) {
    final key =
        p.listingTypeKey.trim().isNotEmpty ? p.listingTypeKey : p.type.name;
    return PropertyTypeCatalog.label(key, isAr);
  }

  /// عنوان تفاصيل الإعلان: «فيلا للبيع في جازان».
  static String detailsHeadline(Property p, bool isAr) {
    return displayListingTitle(p, isAr);
  }

  /// المدينة الرئيسية الحقيقية — لا تُستبدل بالحي أو المركز أو القرية.
  static String mainCityLabel(Property p) {
    final city = p.city.trim();
    if (city.isEmpty) return '';
    final loc = (p.location ?? '').trim();
    if (loc.isNotEmpty && city.toLowerCase() == loc.toLowerCase()) {
      return '';
    }
    return city;
  }

  /// سطر الموقع: المنطقة — المدينة — الحي دون تكرار.
  static String locationLineForDetails(Property p) {
    return addressLine(p, isAr: true, separator: ' — ');
  }

  /// «فيلا للبيع في جازان» / «Villa for sale in Jazan».
  /// الحي لا يُضمَّن في العنوان — يظهر في سطر الموقع تحت البطاقة.
  static String composeListingHeadline({
    required String typeLabel,
    required String purposeBit,
    required String city,
    String? district,
    required bool isAr,
    bool asRequest = false,
    bool includeCity = true,
  }) {
    final type = typeLabel.trim();
    final purpose = purposeBit.trim();
    final cityT = LocaleContent.forUi(city.trim(), isAr: isAr);
    final cityOk = includeCity &&
        cityT.isNotEmpty &&
        cityT != '-' &&
        cityT.toLowerCase() != 'null';
    if (isAr) {
      final core = [
        if (asRequest) 'مطلوب',
        if (type.isNotEmpty) type,
        if (purpose.isNotEmpty) purpose,
      ].join(' ');
      if (!cityOk) return core.trim();
      return '$core في $cityT'.trim();
    }
    final core = [
      if (asRequest) 'Wanted:',
      if (type.isNotEmpty) type,
      if (purpose.isNotEmpty) purpose,
    ].join(' ');
    if (!cityOk) return core.trim();
    return '$core in $cityT'.trim();
  }

  /// حقيقة ظاهرة أصلاً في العنوان المركّب (مدينة/غرض/نوع) — لا تُعاد في الجدول.
  static bool headlineContainsFact(String headline, String fact) {
    final h = headline.trim();
    final f = fact.trim();
    if (h.isEmpty || f.isEmpty || f == '-') return false;
    return h.contains(f);
  }

  /// سطر قصير للتصفح السريع: «فيلا للبيع بجدة» / «مطلوب شقة للبيع بالدمام».
  static String shortsHeadline({
    required bool isAr,
    Property? property,
    MarketPropertyRequestRow? request,
  }) {
    if (property != null) {
      return composeListingHeadline(
        typeLabel: typeLabelForProperty(property, isAr),
        purposeBit: purposeBitShort(property, isAr),
        city: cityLine(property) == '-' ? '' : cityLine(property),
        isAr: isAr,
      );
    }
    if (request != null) return displayRequestTitle(request, isAr);
    return '';
  }

  /// عنوان بطاقة إعلان: نوع + غرض. المكان في العنوان فقط إن نقصت المنطقة أو المدينة.
  static String displayListingTitle(Property p, bool isAr) {
    final type = typeLabelForProperty(p, isAr);
    final purpose = purposeBitShort(p, isAr);
    final city = cityLine(p);
    final place = cardTitlePlace(
      region: (p.region ?? '').trim(),
      city: city == '-' ? '' : city,
      district: (p.location ?? '').trim(),
    );
    final composed = composeListingHeadline(
      typeLabel: type,
      purposeBit: purpose,
      city: place ?? '',
      isAr: isAr,
      includeCity: place != null,
    );
    if (composed.trim().isNotEmpty) return composed.trim();
    final raw =
        sanitizeListingTitle(p.title.trim(), typeLabel: type, isAr: isAr);
    if (raw.isEmpty) {
      return [type, purpose].where((s) => s.trim().isNotEmpty).join(' ').trim();
    }
    return LocaleContent.forUi(
      normalizePlacePrepositions(raw, isAr: isAr),
      isAr: isAr,
    );
  }

  /// عنوان مضغوط للدبوس/الشاشات الضيقة: نوع + غرض بلا مدينة أو حي.
  static String compactListingTitle(Property p, bool isAr) {
    return composeListingHeadline(
      typeLabel: typeLabelForProperty(p, isAr),
      purposeBit: purposeBitShort(p, isAr),
      city: '',
      isAr: isAr,
      includeCity: false,
    );
  }

  static String compactRequestTitle(MarketPropertyRequestRow r, bool isAr) {
    return composeListingHeadline(
      typeLabel: PropertyTypeCatalog.label(r.propertyType, isAr),
      purposeBit: r.purpose == 'rent'
          ? (isAr ? 'للإيجار' : 'for rent')
          : (isAr ? 'للبيع' : 'for sale'),
      city: '',
      isAr: isAr,
      asRequest: true,
      includeCity: false,
    );
  }

  /// ينظّف لاحقات النوع المكررة مثل «فيلا للبيع - ارض».
  static String sanitizeListingTitle(
    String raw, {
    required String typeLabel,
    required bool isAr,
  }) {
    var t = raw.trim();
    if (t.isEmpty) return t;
    t = t.replaceAll(RegExp(r'\s*[-–—·|]\s*'), ' - ');
    final type = typeLabel.trim();
    if (type.isNotEmpty) {
      final esc = RegExp.escape(type);
      t = t.replaceFirst(
          RegExp('\\s*-\\s*$esc\\s*\$', caseSensitive: false), '');
      t = t.replaceFirst(RegExp('^$esc\\s*-\\s*', caseSensitive: false), '');
    }
    // أزل لاحقة نوع شائعة لا تطابق بقية العنوان (أو مرادف مثل فله↔فيلا).
    for (final bad in isAr
        ? const ['ارض', 'أرض', 'فله', 'فيلا', 'شقة', 'أرض فضاء', 'دور', 'عمارة']
        : const ['land', 'villa', 'apartment', 'floor', 'building']) {
      final low = t.toLowerCase();
      final suffix = ' - $bad';
      if (low.endsWith(suffix.toLowerCase())) {
        final head = t.substring(0, t.length - suffix.length).trim();
        if (head.isEmpty) continue;
        final headLow = head.toLowerCase();
        final synonymHit = isAr &&
            ((bad == 'فله' && headLow.contains('فيلا')) ||
                (bad == 'فيلا' && headLow.contains('فله')) ||
                (bad == 'ارض' && headLow.contains('أرض')) ||
                (bad == 'أرض' && headLow.contains('ارض')));
        if (!headLow.contains(bad.toLowerCase()) || synonymHit) {
          t = head;
        }
      }
    }
    return t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static String displayRequestTitle(
    MarketPropertyRequestRow r,
    bool isAr,
  ) {
    final typeCode = PropertyTypeCatalog.normalize(r.propertyType);
    final type = PropertyTypeCatalog.label(
      typeCode == 'فله' || typeCode == 'فله' ? 'villa' : r.propertyType,
      isAr,
    );
    final purpose = r.purpose == 'rent'
        ? (isAr ? 'للإيجار' : 'for rent')
        : (isAr ? 'للبيع' : 'for sale');
    final district =
        r.districts.map((e) => e.trim()).where((e) => e.isNotEmpty).join('، ');
    final place = cardTitlePlace(
      region: r.regionLabel,
      city: r.city.trim(),
      district: district,
    );
    return composeListingHeadline(
      typeLabel: type,
      purposeBit: purpose,
      city: place ?? '',
      isAr: isAr,
      asRequest: true,
      includeCity: place != null,
    );
  }

  /// يُبقي «في جازان» كما هي — لا تُحوَّل إلى «بجازان».
  static String normalizePlacePrepositions(String title, {required bool isAr}) {
    var t = title.trim();
    if (t.isEmpty) return t;
    return t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// أجزاء الموقع مع استبعاد ما يظهر أصلاً في العنوان (تفادي التكرار).
  static List<String> locationPartsWithoutTitleEcho(
    List<String> parts,
    String title,
  ) {
    final t = title.trim().toLowerCase();
    if (t.isEmpty) return parts;
    return parts.where((p) {
      final v = p.trim();
      if (v.isEmpty) return false;
      final low = v.toLowerCase();
      if (t.contains(low)) return false;
      // بجدة / في جدة
      if (t.contains('ب$low') || t.contains('في $low')) return false;
      return true;
    }).toList(growable: false);
  }

  /// شارات إضافية بدل تكرار المدينة: مفروش / مواقف / مرافق.
  static List<String> diversifySpecChips(
    Property p,
    bool isAr, {
    int max = 3,
  }) {
    final out = <String>[];
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty || out.contains(t) || out.length >= max) return;
      out.add(t);
    }

    if (p.furnished == true) {
      add(isAr ? 'مفروش' : 'Furnished');
    } else if (p.furnished == false) {
      add(isAr ? 'غير مفروش' : 'Unfurnished');
    }
    final park = p.parkingSpots;
    if (park != null && park > 0) {
      add(isAr ? '$park موقف' : '$park parking');
    }
    final am = p.amenities;
    if (am != null) {
      const keysAr = <String, String>{
        'pool': 'مسبح',
        'elevator': 'مصعد',
        'garden': 'حديقة',
        'maid_room': 'غرفة خادمة',
        'ac': 'تكييف',
        'security': 'حراسة',
        'gym': 'نادي رياضي',
        'balcony': 'شرفة',
        'kitchen': 'مطبخ',
      };
      const keysEn = <String, String>{
        'pool': 'Pool',
        'elevator': 'Elevator',
        'garden': 'Garden',
        'maid_room': 'Maid room',
        'ac': 'A/C',
        'security': 'Security',
        'gym': 'Gym',
        'balcony': 'Balcony',
        'kitchen': 'Kitchen',
      };
      for (final e in am.entries) {
        if (e.value != true) continue;
        final k = e.key.trim().toLowerCase();
        add(isAr ? (keysAr[k] ?? k) : (keysEn[k] ?? k));
        if (out.length >= max) break;
      }
    }
    for (final u in usageBadgeTuples(p, isAr)) {
      add(u.$2);
      if (out.length >= max) break;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // وسائط الإعلان / طلب السوق — مصدر موحّد [ListingMediaUrls]
  // ---------------------------------------------------------------------------

  static List<String> propertyCardImagePaths(Property p) =>
      ListingMediaUrls.propertyCardImagePaths(p);

  static bool propertyUsesSmartDefaultCover(Property p) =>
      ListingMediaUrls.propertyUsesSmartDefaultCover(p);

  static bool marketRequestUsesSmartDefaultCover(MarketPropertyRequestRow r) =>
      ListingMediaUrls.marketRequestUsesSmartDefaultCover(r);

  static String get defaultListingThumbAsset =>
      ListingMediaUrls.defaultThumbAsset;

  static String? propertyHeroNetworkUrl(Property p, SupabaseClient sb) =>
      ListingMediaUrls.propertyImageNetworkUrl(p, sb);

  static String? marketRequestCoverNetworkUrl(
    MarketPropertyRequestRow r,
    SupabaseClient sb,
  ) =>
      ListingMediaUrls.marketRequestCoverNetworkUrl(r, sb);

  static String propertySharePreviewUrl(Property p, SupabaseClient sb) =>
      ListingMediaUrls.propertySharePreviewHttpUrl(p, sb);

  static String marketRequestSharePreviewUrl(
    MarketPropertyRequestRow r,
    SupabaseClient sb,
  ) =>
      ListingMediaUrls.marketRequestSharePreviewHttpUrl(r, sb);
}

class _PurposeTokens {
  final String labelAr;
  final String labelEn;
  final Color accent;
  final IconData areaIcon;

  const _PurposeTokens({
    required this.labelAr,
    required this.labelEn,
    required this.accent,
    required this.areaIcon,
  });
}
