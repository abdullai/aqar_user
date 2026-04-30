import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/property.dart';

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

  static String _scaleOwnerDisplayNameParts(String raw, double cardWidth) {
    final parts =
        raw.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    var n = parts.length;
    if (cardWidth < 240) {
      n = 1;
    } else if (cardWidth < 360) {
      n = 2;
    } else if (cardWidth < 480) {
      n = 3;
    }
    final take = parts.length < n ? parts.length : n;
    return parts.take(take).join(' ');
  }

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
      final scaled = _scaleOwnerDisplayNameParts(raw, cardWidth);
      return scaled.isNotEmpty ? scaled : (isAr ? 'المعلن' : 'Advertiser');
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
    final scaled = _scaleOwnerDisplayNameParts(raw, cardWidth);
    return scaled.isNotEmpty ? scaled : (isAr ? 'معلن' : 'Advertiser');
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
