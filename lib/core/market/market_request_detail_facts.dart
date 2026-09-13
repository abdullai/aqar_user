import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/market_property_request_row.dart';
import '../l10n/locale_content.dart';
import '../listing/property_type_catalog.dart';
import '../utils/app_money.dart';
import '../utils/date_helper.dart';
import '../utils/display_ids.dart';
import '../utils/listing_date_display.dart';
import '../../models/market_property_request_priority.dart';

/// حقل تفاصيل طلب للعرض فقط إن كانت له قيمة.
class MarketRequestDetailFact {
  const MarketRequestDetailFact({
    required this.icon,
    required this.label,
    required this.value,
    this.copyText,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? copyText;
}

/// يجمع كل ما أدخله صاحب الطلب عند الإنشاء — يتخطّى الفارغ.
abstract final class MarketRequestDetailFacts {
  static List<MarketRequestDetailFact> build(
    MarketPropertyRequestRow row, {
    required bool isAr,
    required AppLocalizations? l10n,
  }) {
    final d = row.details;
    final out = <MarketRequestDetailFact>[];

    void add(IconData icon, String label, String? value, {String? copy}) {
      final v = (value ?? '').trim();
      if (v.isEmpty) return;
      out.add(
        MarketRequestDetailFact(
          icon: icon,
          label: label,
          value: v,
          copyText: copy,
        ),
      );
    }

    final code = (row.requestPublicCode ?? '').trim();
    final ten = code.isEmpty ? '' : DisplayIds.tenDigit(code);
    add(Icons.tag_rounded, isAr ? 'رقم الطلب' : 'Request no.', ten, copy: ten);

    final typeLabel = PropertyTypeCatalog.label(row.propertyType, isAr);
    add(Icons.home_work_outlined, isAr ? 'نوع العقار' : 'Property type', typeLabel);

    final purposeLabel = row.purpose == 'rent'
        ? (isAr ? 'للإيجار' : 'For rent')
        : (row.purpose == 'purchase' || row.purpose == 'sale'
            ? (isAr ? 'للبيع' : 'For sale')
            : '');
    add(Icons.swap_horiz_rounded, isAr ? 'نوع الطلب' : 'Request type', purposeLabel);

    add(
      Icons.flag_outlined,
      isAr ? 'الأولوية' : 'Priority',
      _priority(l10n, row.requestPriority, isAr),
    );

    add(
      Icons.location_city_outlined,
      isAr ? 'المدينة' : 'City',
      LocaleContent.forUi(row.city.trim(), isAr: isAr),
    );
    add(
      Icons.map_outlined,
      isAr ? 'المنطقة' : 'Region',
      LocaleContent.forUi(row.regionLabel, isAr: isAr),
    );
    add(
      Icons.account_balance_outlined,
      isAr ? 'المحافظة' : 'Governorate',
      LocaleContent.forUi(row.governorateLabel, isAr: isAr),
    );
    final districts = row.districts
        .map((e) => LocaleContent.forUi(e.trim(), isAr: isAr))
        .where((e) => e.isNotEmpty)
        .join(isAr ? '، ' : ', ');
    add(Icons.place_outlined, isAr ? 'الحي' : 'District', districts);

    if (row.areaMinM2 != null && row.areaMinM2! > 0) {
      add(
        Icons.square_foot_outlined,
        isAr ? 'المساحة من' : 'Area from',
        isAr
            ? '${AppMoney.formatNumber(row.areaMinM2!, isAr: isAr, maxFractionDigits: 0)} م²'
            : '${AppMoney.formatNumber(row.areaMinM2!, isAr: isAr, maxFractionDigits: 0)} m²',
      );
    }

    final beds = _int(d['bedrooms']);
    if (beds != null && beds > 0) {
      add(
        Icons.bed_outlined,
        isAr ? 'الغرف' : 'Bedrooms',
        isAr ? '$beds' : '$beds',
      );
    }
    final baths = _int(d['bathrooms']);
    if (baths != null && baths > 0) {
      add(
        Icons.bathtub_outlined,
        isAr ? 'دورات المياه' : 'Baths',
        isAr ? '$baths' : '$baths',
      );
    }

    final furnished = d['furnished'];
    if (furnished is bool) {
      add(
        Icons.chair_outlined,
        isAr ? 'الأثاث' : 'Furnishing',
        furnished
            ? (isAr ? 'مفروش' : 'Furnished')
            : (isAr ? 'غير مفروش' : 'Unfurnished'),
      );
    }

    final preferNew = d['prefer_new'];
    if (preferNew is bool) {
      add(
        Icons.new_releases_outlined,
        isAr ? 'حالة العقار' : 'Condition',
        preferNew
            ? (isAr ? 'جديد' : 'New')
            : (isAr ? 'مستعمل' : 'Used'),
      );
    }

    if (row.purpose == 'rent') {
      add(
        Icons.calendar_month_outlined,
        isAr ? 'مدة الإيجار' : 'Rent term',
        _rentTermLabel(d, isAr),
      );
      final start = DateHelper.tryParse(d['rent_start']);
      if (start != null) {
        add(
          Icons.event_available_outlined,
          isAr ? 'بداية الإيجار' : 'Rent start',
          DateHelper.fmtCivilDate(start.toLocal(), isAr: isAr),
        );
      }
      final end = DateHelper.tryParse(d['rent_end']);
      if (end != null) {
        add(
          Icons.event_busy_outlined,
          isAr ? 'نهاية الإيجار' : 'Rent end',
          DateHelper.fmtCivilDate(end.toLocal(), isAr: isAr),
        );
      }
    }

    final amenities = _amenityLabels(d['amenities'], isAr);
    add(
      Icons.spa_outlined,
      isAr ? 'المرافق' : 'Amenities',
      amenities,
    );

    if (row.latitude != null && row.longitude != null) {
      final approx = d['location_is_approximate'] == true ||
          (d['location'] is Map &&
              (d['location'] as Map)['approximate'] == true);
      add(
        Icons.my_location_outlined,
        isAr ? 'الموقع على الخريطة' : 'Map location',
        approx
            ? (isAr ? 'موقع تقريبي على الخريطة' : 'Approximate map pin')
            : (isAr ? 'تم تحديد موقع على الخريطة' : 'A map pin was set'),
      );
    }

    if (row.showRequesterName &&
        (row.requesterPublicName ?? '').trim().isNotEmpty) {
      add(
        Icons.person_outline,
        isAr ? 'منشئ الطلب' : 'Request creator',
        row.requesterPublicName!.trim(),
      );
    }

    if (row.createdAt != null) {
      add(
        Icons.event_note_outlined,
        isAr ? 'تاريخ الطلب' : 'Requested',
        ListingDateDisplay.formatCardDateTime(row.createdAt, isAr: isAr),
      );
    }

    return out;
  }

  static String _priority(
    AppLocalizations? l10n,
    MarketPropertyRequestPriority p,
    bool isAr,
  ) {
    if (l10n != null) {
      switch (p) {
        case MarketPropertyRequestPriority.flexible:
          return l10n.marketRequestPriorityFlexible;
        case MarketPropertyRequestPriority.standard:
          return l10n.marketRequestPriorityStandard;
        case MarketPropertyRequestPriority.priority:
          return l10n.marketRequestPriorityPriority;
        case MarketPropertyRequestPriority.urgent:
          return l10n.marketRequestPriorityUrgent;
        case MarketPropertyRequestPriority.immediate:
          return l10n.marketRequestPriorityImmediate;
      }
    }
    return isAr ? p.wireValue : p.wireValue;
  }

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  static String _rentTermLabel(Map<String, dynamic> d, bool isAr) {
    final term = (d['rent_term'] ?? '').toString().trim().toLowerCase();
    if (term.isEmpty) return '';
    final days = _int(d['rent_days']) ?? 1;
    final weeks = _int(d['rent_weeks']) ?? 1;
    final months = _int(d['rent_months']) ?? 1;
    final years = _int(d['rent_years']) ?? 1;
    switch (term) {
      case 'daily':
        return isAr ? 'يومي ($days يوم)' : 'Daily ($days day(s))';
      case 'weekly':
        return isAr ? 'أسبوعي ($weeks أسبوع)' : 'Weekly ($weeks week(s))';
      case 'monthly':
        return isAr ? 'شهري ($months شهر)' : 'Monthly ($months month(s))';
      case 'yearly':
        return isAr ? 'سنوي ($years سنة)' : 'Yearly ($years year(s))';
      default:
        return term;
    }
  }

  static String _amenityLabels(dynamic raw, bool isAr) {
    final keys = <String>[];
    if (raw is Map) {
      for (final e in raw.entries) {
        final on = e.value == true ||
            e.value == 1 ||
            '${e.value}'.toLowerCase() == 'true';
        if (on) keys.add(e.key.toString());
      }
    } else if (raw is List) {
      for (final e in raw) {
        keys.add(e.toString());
      }
    }
    final labels = keys
        .map((k) => _amenityLabel(k, isAr))
        .where((s) => s.isNotEmpty)
        .toList();
    if (labels.isEmpty) return '';
    return labels.join(isAr ? '، ' : ', ');
  }

  static String _amenityLabel(String key, bool isAr) {
    switch (key.trim().toLowerCase()) {
      case 'pool':
        return isAr ? 'مسبح' : 'Pool';
      case 'gym':
        return isAr ? 'صالة رياضية' : 'Gym';
      case 'elevator':
        return isAr ? 'مصعد' : 'Elevator';
      case 'security':
        return isAr ? 'أمن' : 'Security';
      case 'garden':
        return isAr ? 'حديقة' : 'Garden';
      case 'balcony':
        return isAr ? 'شرفة' : 'Balcony';
      case 'ac':
        return isAr ? 'تكييف' : 'A/C';
      case 'parking':
        return isAr ? 'موقف' : 'Parking';
      case 'maid_room':
        return isAr ? 'غرفة خادمة' : 'Maid room';
      case 'driver_room':
        return isAr ? 'غرفة سائق' : 'Driver room';
      default:
        return key.trim();
    }
  }
}
