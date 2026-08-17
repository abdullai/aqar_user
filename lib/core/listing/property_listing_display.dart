import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/market_property_request_row.dart';
import '../../models/property.dart';
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
    if (city.isNotEmpty) return city;
    final loc = (p.location ?? '').trim();
    if (loc.isEmpty) return '-';
    final i = loc.indexOf(' - ');
    if (i > 0) return loc.substring(0, i).trim();
    return loc;
  }

  /// ترتيب أنيق: منطقة → محافظة → مدينة → حي (بدون فراغات/تكرار).
  static List<String> locationHierarchyParts(Property p) {
    final seen = <String>{};
    final out = <String>[];
    void add(String? raw) {
      final v = (raw ?? '').trim();
      if (v.isEmpty) return;
      final key = v.toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(v);
    }

    add(p.region);
    add(p.province);
    add(p.city);
    add(p.location);
    return out;
  }

  static List<String> locationHierarchyPartsForRequest(
    MarketPropertyRequestRow r,
  ) {
    final seen = <String>{};
    final out = <String>[];
    void add(String? raw) {
      final v = (raw ?? '').trim();
      if (v.isEmpty) return;
      final key = v.toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(v);
    }

    add(r.regionLabel);
    add(r.governorateLabel);
    add(r.city);
    for (final d in r.districts) {
      add(d);
    }
    return out;
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
    final fromPreview = (row['preview_purpose'] ?? '').toString().trim().toLowerCase();
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
      return '';
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
    if (!p.canShowAdvertiserName) {
      return isAr ? 'معلن' : 'Advertiser';
    }
    final raw = (p.ownerDisplayName ?? '').trim();
    if (raw.isEmpty) return isAr ? 'معلن' : 'Advertiser';
    // الاسم كاملاً على البطاقة (فرد / جهة) — الواجهة تُقلّص بالتفاف حتى 3 أسطر.
    return raw;
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

  static IconData _areaIconForPurposeCode(String code, {required bool isAuction}) {
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
    final key = p.listingTypeKey.trim().isNotEmpty
        ? p.listingTypeKey
        : p.type.name;
    return PropertyTypeCatalog.label(key, isAr);
  }

  /// «فيلا للبيع بجدة» / «Villa for sale in Jeddah».
  static String composeListingHeadline({
    required String typeLabel,
    required String purposeBit,
    required String city,
    String? district,
    required bool isAr,
    bool asRequest = false,
  }) {
    final type = typeLabel.trim();
    final purpose = purposeBit.trim();
    final cityT = city.trim();
    final dist = (district ?? '').trim();
    final place = dist.isNotEmpty &&
            dist.toLowerCase() != cityT.toLowerCase()
        ? (cityT.isEmpty ? dist : '$cityT — $dist')
        : cityT;
    if (isAr) {
      final core = [
        if (asRequest) 'مطلوب',
        if (type.isNotEmpty) type,
        if (purpose.isNotEmpty) purpose,
      ].join(' ');
      if (place.isEmpty) return core.trim();
      return '$core ${placeWithBi(place)}'.trim();
    }
    final core = [
      if (asRequest) 'Wanted:',
      if (type.isNotEmpty) type,
      if (purpose.isNotEmpty) purpose,
    ].join(' ');
    if (place.isEmpty) return core.trim();
    return '$core in $place'.trim();
  }

  /// عنوان بطاقة إعلان: يفضّل العنوان المخزَّن إن كان واضحاً، وإلا تركيباً مرتّباً.
  static String displayListingTitle(Property p, bool isAr) {
    final type = typeLabelForProperty(p, isAr);
    final purpose = purposeBitShort(p, isAr);
    final city = cityLine(p);
    final district = (p.location ?? '').trim();
    final composed = composeListingHeadline(
      typeLabel: type,
      purposeBit: purpose,
      city: city == '-' ? '' : city,
      district: district.isNotEmpty &&
              district.toLowerCase() != city.toLowerCase()
          ? district
          : null,
      isAr: isAr,
    );
    final raw = sanitizeListingTitle(p.title.trim(), typeLabel: type, isAr: isAr);
    if (raw.isEmpty) return composed;
    if (type.isEmpty) return normalizePlacePrepositions(raw, isAr: isAr);
    // عنوان خام يخلط المدينة بين النوع والغرض → استبدل بالتركيب الأنيق.
    if (_titleLooksScrambled(raw, type: type, city: city, isAr: isAr)) {
      return composed.isNotEmpty
          ? composed
          : normalizePlacePrepositions(raw, isAr: isAr);
    }
    // إن تعارض النوع المخزَّن مع كلمات العنوان (فيلا…أرض) أبقِ العنوان المنقّى.
    if (_titleConflictsWithType(raw, type, isAr: isAr) && raw.isNotEmpty) {
      return normalizePlacePrepositions(raw, isAr: isAr);
    }
    return normalizePlacePrepositions(raw, isAr: isAr);
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
      t = t.replaceFirst(RegExp('\\s*-\\s*$esc\\s*\$', caseSensitive: false), '');
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

  static bool _titleConflictsWithType(
    String raw,
    String typeLabel, {
    required bool isAr,
  }) {
    final t = raw.toLowerCase();
    final type = typeLabel.trim().toLowerCase();
    if (t.isEmpty || type.isEmpty) return false;
    if (isAr) {
      final saysVilla = t.contains('فيلا') || t.contains('فله');
      final saysLand = t.contains('أرض') || t.contains('ارض');
      final typeIsLand = type.contains('أرض') || type.contains('ارض') || type == 'land';
      final typeIsVilla = type.contains('فيلا') || type.contains('فله') || type == 'villa';
      if (saysVilla && typeIsLand) return true;
      if (saysLand && typeIsVilla) return true;
    }
    return false;
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
        : (isAr ? 'للشراء' : 'to buy');
    final city = r.city.trim();
    String? district;
    for (final d in r.districts) {
      final t = d.trim();
      if (t.isNotEmpty) {
        district = t;
        break;
      }
    }
    final raw = sanitizeListingTitle(
      r.title.trim(),
      typeLabel: type,
      isAr: isAr,
    );
    if (raw.isNotEmpty &&
        (raw.contains(purpose) || raw.length >= 8) &&
        !_titleConflictsWithType(raw, type, isAr: isAr)) {
      return normalizePlacePrepositions(raw, isAr: isAr);
    }
    return composeListingHeadline(
      typeLabel: type,
      purposeBit: purpose,
      city: city,
      district: district,
      isAr: isAr,
      asRequest: true,
    );
  }

  /// استبدال «في المدينة» بـ «بالمدينة» عند العرض العربي.
  static String normalizePlacePrepositions(String title, {required bool isAr}) {
    var t = title.trim();
    if (!isAr || t.isEmpty) return t;
    t = t.replaceAllMapped(
      RegExp(r'\s+في\s+(\S+)'),
      (m) => ' ${placeWithBi(m.group(1)!)}',
    );
    return t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static bool _titleLooksScrambled(
    String raw, {
    required String type,
    required String city,
    required bool isAr,
  }) {
    if (!isAr) return false;
    final c = city.trim();
    if (c.isEmpty || c == '-' || type.isEmpty) return false;
    final lower = raw;
    final ti = lower.indexOf(type);
    final ci = lower.indexOf(c);
    if (ti < 0 || ci < 0) return false;
    // نوع … مدينة … غرض (المدينة بين النوع والغرض).
    final purposeMarks = ['للبيع', 'للإيجار', 'للمزاد', 'للاستثمار', 'للشراء'];
    var purposeIdx = -1;
    for (final m in purposeMarks) {
      final i = lower.indexOf(m);
      if (i >= 0 && (purposeIdx < 0 || i < purposeIdx)) purposeIdx = i;
    }
    if (purposeIdx < 0) return false;
    return ti < ci && ci < purposeIdx;
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

  static String get defaultListingThumbAsset => ListingMediaUrls.defaultThumbAsset;

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
