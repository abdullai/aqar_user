import 'package:flutter/material.dart';

import 'property_type_custom_registry.dart';

/// مجموعة أنواع في مستوى أعلى (سكني / تجاري / أراضي / مشاريع) لعرض هرمي في النموذج.
class PropertyTypeGroup {
  final String id;
  final String ar;
  final String en;
  final List<String> codes;

  const PropertyTypeGroup({
    required this.id,
    required this.ar,
    required this.en,
    required this.codes,
  });
}

/// أنواع العقار (مفاتيح تُخزَّن في `properties.type`) + ألوان البطاقات + حقول النموذج.
class PropertyTypeCatalog {
  PropertyTypeCatalog._();

  static String normalize(String? raw) => (raw ?? '').trim().toLowerCase();

  /// مستوى أول: كل رمز يظهر في مجموعة واحدة فقط (يتوافق مع [entries]).
  static const List<PropertyTypeGroup> typeGroups = [
    PropertyTypeGroup(
      id: 'residential',
      ar: 'سكني',
      en: 'Residential',
      codes: [
        'villa',
        'apartment',
        'floor',
        'palace',
        'rest_house',
        'chalet',
        'traditional_house',
        'room',
        'suite',
        'residential_tower',
        'apartment_building',
      ],
    ),
    PropertyTypeGroup(
      id: 'commercial',
      ar: 'تجاري وإداري',
      en: 'Commercial & offices',
      codes: [
        'hotel',
        'warehouse',
        'station',
        'commercial_center',
        'commercial_market',
        'office_tower',
        'building',
        'commercial_building',
        'office',
        'shop',
        'showroom',
      ],
    ),
    PropertyTypeGroup(
      id: 'land',
      ar: 'أراضي ومزارع',
      en: 'Land & farms',
      codes: ['land', 'land_fenced', 'land_walled', 'farm'],
    ),
    PropertyTypeGroup(
      id: 'project',
      ar: 'مشاريع وأخرى',
      en: 'Projects & other',
      codes: ['project', 'other'],
    ),
  ];

  static String groupIdForCode(String? code) {
    final raw = (code ?? '').trim();
    if (PropertyTypeCustomRegistry.isUserType(raw)) {
      return PropertyTypeCustomRegistry.groupIdForCode(raw) ?? 'other';
    }
    final c = normalize(code);
    for (final g in typeGroups) {
      if (g.codes.contains(c)) return g.id;
    }
    return typeGroups.first.id;
  }

  static PropertyTypeGroup? groupById(String id) {
    for (final g in typeGroups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// عناصر [entries] بنفس ترتيب الرموز داخل المجموعة.
  static List<Map<String, String>> entriesForGroup(String groupId) {
    final g = groupById(groupId);
    if (g == null) return List<Map<String, String>>.from(entries);
    final out = <Map<String, String>>[];
    for (final code in g.codes) {
      for (final e in entries) {
        if (e['code'] == code) {
          out.add(e);
          break;
        }
      }
    }
    return out;
  }

  /// مثل [entriesForGroup] مع إضافة الأنواع التي أدخلها المستخدم محلياً.
  static List<Map<String, String>> entriesForGroupMerged(String groupId) {
    final base = entriesForGroup(groupId);
    final extra = PropertyTypeCustomRegistry.mapsForGroup(groupId);
    return [...base, ...extra];
  }

  /// نوع معروف في القائمة الثابتة أو نوع مخصص محفوظ.
  static Future<bool> isSelectableTypeAsync(String? code) async {
    await PropertyTypeCustomRegistry.ensureLoaded();
    return isSelectableTypeSync(code);
  }

  static bool isSelectableTypeSync(String? code) {
    final c = (code ?? '').trim();
    if (c.isEmpty) return false;
    if (PropertyTypeCustomRegistry.isUserType(c)) {
      return PropertyTypeCustomRegistry.hasCode(c);
    }
    return entries.any((e) => e['code'] == c);
  }

  static String groupLabel(String groupId, bool isAr) {
    final g = groupById(groupId);
    if (g == null) return groupId;
    return isAr ? g.ar : g.en;
  }

  /// قائمة موحّدة للقوائم المنسدلة (إضافة عقار / تعديل / عرض).
  static const List<Map<String, String>> entries = [
    {'code': 'villa', 'ar': 'فيلا', 'en': 'Villa'},
    {'code': 'apartment', 'ar': 'شقة', 'en': 'Apartment'},
    {'code': 'land', 'ar': 'أرض', 'en': 'Land'},
    {
      'code': 'land_walled',
      'ar': 'أرض مسوّرة',
      'en': 'Walled land parcel',
    },
    {'code': 'land_fenced', 'ar': 'أرض بسور (حوش)', 'en': 'Fenced land (courtyard)'},
    {'code': 'palace', 'ar': 'قصر', 'en': 'Palace'},
    {'code': 'hotel', 'ar': 'فندق', 'en': 'Hotel'},
    {'code': 'warehouse', 'ar': 'مستودع', 'en': 'Warehouse'},
    {'code': 'station', 'ar': 'محطة', 'en': 'Station'},
    {'code': 'commercial_center', 'ar': 'مركز تجاري', 'en': 'Commercial center'},
    {'code': 'commercial_market', 'ar': 'سوق تجاري', 'en': 'Commercial market'},
    {'code': 'office_tower', 'ar': 'برج مكتبي', 'en': 'Office tower'},
    {'code': 'residential_tower', 'ar': 'برج سكني', 'en': 'Residential tower'},
    {
      'code': 'apartment_building',
      'ar': 'عمارة سكنية',
      'en': 'Residential apartment building',
    },
    {'code': 'floor', 'ar': 'دور', 'en': 'Floor'},
    {'code': 'building', 'ar': 'مبنى', 'en': 'Building'},
    {
      'code': 'commercial_building',
      'ar': 'مبنى تجاري',
      'en': 'Commercial building',
    },
    {'code': 'office', 'ar': 'مكتب', 'en': 'Office'},
    {'code': 'shop', 'ar': 'محل', 'en': 'Shop'},
    {'code': 'farm', 'ar': 'مزرعة', 'en': 'Farm'},
    {'code': 'rest_house', 'ar': 'استراحة', 'en': 'Rest house'},
    {'code': 'chalet', 'ar': 'شاليه', 'en': 'Chalet'},
    {
      'code': 'traditional_house',
      'ar': 'بيت شعبي',
      'en': 'Traditional house',
    },
    {'code': 'room', 'ar': 'غرفة', 'en': 'Room'},
    {'code': 'suite', 'ar': 'جناح', 'en': 'Suite'},
    {'code': 'showroom', 'ar': 'معرض', 'en': 'Showroom'},
    {'code': 'project', 'ar': 'مشروع', 'en': 'Project'},
    {'code': 'other', 'ar': 'أخرى', 'en': 'Other'},
  ];

  static String label(String? code, bool isAr) {
    final raw = (code ?? '').trim();
    if (PropertyTypeCustomRegistry.isUserType(raw)) {
      final u = PropertyTypeCustomRegistry.label(raw, isAr);
      if (u != null && u.isNotEmpty) return u;
    }
    final c = normalize(code);
    for (final e in entries) {
      if (e['code'] == c) {
        return isAr ? (e['ar'] ?? c) : (e['en'] ?? c);
      }
    }
    if (c.isEmpty) return isAr ? 'غير محدد' : 'Unknown';
    return raw;
  }

  /// لون مميّز لبطاقات القائمة (حدود + خلفية خفيفة).
  static Color accentFor(String? code) {
    final c = normalize(code);
    switch (c) {
      case 'land':
      case 'land_fenced':
      case 'land_walled':
      case 'farm':
        return const Color(0xFF15803D);
      case 'villa':
      case 'rest_house':
      case 'chalet':
      case 'traditional_house':
        return const Color(0xFF0369A1);
      case 'apartment':
      case 'floor':
      case 'room':
      case 'suite':
      case 'residential_tower':
      case 'apartment_building':
        return const Color(0xFF7C3AED);
      case 'palace':
      case 'hotel':
        return const Color(0xFFC2410C);
      case 'warehouse':
      case 'station':
        return const Color(0xFF57534E);
      case 'commercial_center':
      case 'commercial_market':
      case 'shop':
      case 'showroom':
        return const Color(0xFF0D9488);
      case 'office':
      case 'office_tower':
      case 'building':
      case 'commercial_building':
        return const Color(0xFF1D4ED8);
      case 'project':
        return const Color(0xFFBE185D);
      case 'other':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF0F766E);
    }
  }

  static bool isLandLike(String? code) {
    final c = normalize(code);
    return c == 'land' ||
        c == 'land_fenced' ||
        c == 'land_walled' ||
        c == 'farm' ||
        c == 'station';
  }

  static bool isApartmentLike(String? code) {
    final c = normalize(code);
    return c == 'apartment' ||
        c == 'apartment_building' ||
        c == 'floor' ||
        c == 'office' ||
        c == 'shop' ||
        c == 'room' ||
        c == 'suite' ||
        c == 'showroom';
  }

  static bool isVillaLike(String? code) {
    final c = normalize(code);
    return c == 'villa' ||
        c == 'rest_house' ||
        c == 'chalet' ||
        c == 'traditional_house' ||
        c == 'palace';
  }

  /// غرف / حمامات / مواقف — غير مناسبة لأراضٍ ومزارع ومحطات وأرض محاطة بسور.
  static bool showsRoomCounts(String? code) {
    if (isLandLike(code)) return false;
    final c = normalize(code);
    return c != 'warehouse' &&
        c != 'commercial_market' &&
        c != 'commercial_center' &&
        c != 'office_tower' &&
        c != 'apartment_building' &&
        c != 'project';
  }

  /// واجهات «عمارة / برج» — غالباً تُعرَض كوحدة كاملة أو إجمالي وحدات لا كغرف نوم منزلية.
  static bool showsResidentialRoomBedCounts(String? code) {
    if (!showsRoomCounts(code)) return false;
    final c = normalize(code);
    return c != 'apartment_building';
  }

  /// الطابق وعدد الطوابق — وحدات عمودية أو أبراج أو فنادق.
  static bool showsFloorFields(String? code) {
    final c = normalize(code);
    if (isLandLike(code)) return false;
    return isApartmentLike(code) ||
        c == 'building' ||
        c == 'commercial_building' ||
        c == 'hotel' ||
        c == 'office_tower' ||
        c == 'residential_tower' ||
        c == 'apartment_building';
  }

  static bool showsBuildingNumber(String? code) {
    final c = normalize(code);
    if (isLandLike(code)) return false;
    return isVillaLike(code) ||
        isApartmentLike(code) ||
        c == 'warehouse' ||
        c == 'commercial_center' ||
        c == 'commercial_market' ||
        c == 'apartment_building';
  }

  /// مرافق منطقية للأرض (سوق سعودي: حوش، شوارع، استخدام أرض).
  static bool amenityKeyRelevantForLand(String amenityKey) {
    const k = {
      'yard',
      'storage',
      'security',
      'parking',
      'wifi',
      'roof',
    };
    return k.contains(amenityKey);
  }

  // --- أنواع مخصصة (ut_*) تتبع [group] المحفوظ ---

  static bool isLandLikeEffective(String? code) {
    final raw = (code ?? '').trim();
    if (PropertyTypeCustomRegistry.isUserType(raw)) {
      return (PropertyTypeCustomRegistry.groupIdForCode(raw) ?? '') == 'land';
    }
    return isLandLike(code);
  }

  static bool showsRoomCountsEffective(String? code) {
    final raw = (code ?? '').trim();
    if (PropertyTypeCustomRegistry.isUserType(raw)) {
      final g = PropertyTypeCustomRegistry.groupIdForCode(raw) ?? 'other';
      if (g == 'land' || g == 'project') return false;
      return true;
    }
    return showsRoomCounts(code);
  }

  static bool showsResidentialRoomBedCountsEffective(String? code) {
    if (!showsRoomCountsEffective(code)) return false;
    final raw = (code ?? '').trim();
    if (PropertyTypeCustomRegistry.isUserType(raw)) {
      return true;
    }
    return showsResidentialRoomBedCounts(code);
  }

  static bool showsFloorFieldsEffective(String? code) {
    final raw = (code ?? '').trim();
    if (PropertyTypeCustomRegistry.isUserType(raw)) {
      final g = PropertyTypeCustomRegistry.groupIdForCode(raw) ?? 'other';
      if (g == 'land' || g == 'project') return false;
      return g == 'residential' || g == 'commercial';
    }
    return showsFloorFields(code);
  }

  static bool showsParkingYearRowEffective(String? code) {
    if (isLandLikeEffective(code)) return false;
    final raw = (code ?? '').trim();
    if (PropertyTypeCustomRegistry.isUserType(raw)) {
      return (PropertyTypeCustomRegistry.groupIdForCode(raw) ?? '') != 'project';
    }
    final c = normalize(code);
    return c != 'project';
  }

  static bool showsFurnishedRowEffective(String? code) {
    if (isLandLikeEffective(code)) return false;
    if (PropertyTypeCustomRegistry.isUserType(code)) {
      final g = PropertyTypeCustomRegistry.groupIdForCode(code) ?? 'other';
      return g != 'project';
    }
    final c = normalize(code);
    return c != 'project' && c != 'warehouse';
  }

  /// أيقونة نوع العقار على البطاقات (بجوار النص).
  static IconData listingTypeIcon(String? code) {
    final raw = (code ?? '').trim();
    if (PropertyTypeCustomRegistry.isUserType(raw)) {
      final g = PropertyTypeCustomRegistry.groupIdForCode(raw) ?? 'other';
      switch (g) {
        case 'land':
          return Icons.landscape_outlined;
        case 'commercial':
          return Icons.storefront_outlined;
        case 'residential':
          return Icons.home_work_outlined;
        case 'project':
          return Icons.domain_add_outlined;
        default:
          return Icons.home_work_outlined;
      }
    }
    final c = normalize(code);
    if (isLandLike(code)) return Icons.landscape_outlined;
    if (isVillaLike(code)) return Icons.villa_outlined;
    if (isApartmentLike(code)) return Icons.apartment_outlined;
    if (c == 'hotel') return Icons.hotel_class_outlined;
    if (c == 'warehouse') return Icons.warehouse_outlined;
    if (c == 'farm') return Icons.agriculture_outlined;
    if (c == 'project') return Icons.domain_add_outlined;
    return Icons.home_work_outlined;
  }
}
