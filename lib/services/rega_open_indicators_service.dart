import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/geo/saudi_official_admin.dart';
import '../core/listing/property_type_catalog.dart';

/// لقطة مدينة من مؤشرات الهيئة العامة للعقار (بيانات مفتوحة، ليست صفقات فردية).
class RegaOpenIndicatorHit {
  final String regionAr;
  final String cityAr;
  final String typeAr;
  final String classificationAr;
  final int deals;
  final double? avgM2;
  final double? avgRent;
  final bool isRent;

  const RegaOpenIndicatorHit({
    required this.regionAr,
    required this.cityAr,
    required this.typeAr,
    required this.classificationAr,
    required this.deals,
    required this.avgM2,
    required this.avgRent,
    required this.isRent,
  });
}

/// مؤشرات بيع/إيجار مجمّعة من بيانات الهيئة المفتوحة — بدون تضمين ملايين الصفقات.
class RegaOpenIndicatorsService {
  RegaOpenIndicatorsService._();
  static final RegaOpenIndicatorsService instance =
      RegaOpenIndicatorsService._();

  static const assetPath = 'assets/data/rega_open_indicators.json';

  Map<String, dynamic>? _raw;
  List<RegaOpenIndicatorHit>? _sales;
  List<RegaOpenIndicatorHit>? _rentals;

  Future<void> ensureLoaded() async {
    if (_raw != null) return;
    try {
      final txt = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(txt);
      if (decoded is! Map) return;
      _raw = Map<String, dynamic>.from(decoded);
      _sales = _parseList(_raw!['sales'], isRent: false);
      _rentals = _parseList(_raw!['rentals'], isRent: true);
    } catch (_) {
      _raw = {};
      _sales = const [];
      _rentals = const [];
    }
  }

  Map<String, int>? salesPeriod() {
    final p = _raw?['sales_period'];
    if (p is! Map) return null;
    final y = (p['year'] as num?)?.toInt();
    final q = (p['quarter'] as num?)?.toInt();
    if (y == null || q == null) return null;
    return {'year': y, 'quarter': q};
  }

  Map<String, int>? rentalPeriod() {
    final p = _raw?['rental_period'];
    if (p is! Map) return null;
    final y = (p['year'] as num?)?.toInt();
    final q = (p['quarter'] as num?)?.toInt();
    if (y == null || q == null) return null;
    return {'year': y, 'quarter': q};
  }

  List<RegaOpenIndicatorHit> topSalesCities({int limit = 8}) {
    final list = [...(_sales ?? const <RegaOpenIndicatorHit>[])];
    final byCity = <String, RegaOpenIndicatorHit>{};
    for (final e in list) {
      final prev = byCity[e.cityAr];
      if (prev == null || e.deals > prev.deals) byCity[e.cityAr] = e;
    }
    final out = byCity.values.toList()
      ..sort((a, b) => b.deals.compareTo(a.deals));
    if (out.length <= limit) return out;
    return out.sublist(0, limit);
  }

  RegaOpenIndicatorHit? lookup({
    required String city,
    required String typeCode,
    required bool isRent,
  }) {
    final rows = isRent ? (_rentals ?? const []) : (_sales ?? const []);
    if (rows.isEmpty || city.trim().isEmpty) return null;
    final cityN = _norm(city);
    final typeAr = PropertyTypeCatalog.label(typeCode, true);
    final typeN = _norm(typeAr);
    final aliases = _typeAliases(typeCode);

    RegaOpenIndicatorHit? best;
    for (final e in rows) {
      if (_norm(e.cityAr) != cityN && !_cityLoose(e.cityAr, cityN)) continue;
      final et = _norm(e.typeAr);
      final typeOk = et == typeN || aliases.contains(et);
      if (!typeOk) continue;
      if (best == null || e.deals > best.deals) best = e;
    }
    if (best != null) return best;
    for (final e in rows) {
      if (_norm(e.cityAr) != cityN && !_cityLoose(e.cityAr, cityN)) continue;
      if (best == null || e.deals > best.deals) best = e;
    }
    return best;
  }

  static List<RegaOpenIndicatorHit> _parseList(dynamic raw, {required bool isRent}) {
    if (raw is! List) return const [];
    final out = <RegaOpenIndicatorHit>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final city = (m['city'] ?? '').toString().trim();
      final type = (m['type'] ?? '').toString().trim();
      if (city.isEmpty || type.isEmpty) continue;
      final deals = (m['deals'] as num?)?.toInt() ?? 0;
      if (deals <= 0) continue;
      out.add(
        RegaOpenIndicatorHit(
          regionAr: (m['region'] ?? '').toString().trim(),
          cityAr: city,
          typeAr: type,
          classificationAr: (m['klass'] ?? '').toString().trim(),
          deals: deals,
          avgM2: (m['avg_m2'] as num?)?.toDouble(),
          avgRent: (m['avg_rent'] as num?)?.toDouble(),
          isRent: isRent,
        ),
      );
    }
    return out;
  }

  static String _norm(String s) => s
      .trim()
      .replaceAll('ة', 'ه')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll(RegExp(r'\s+'), '');

  static bool _cityLoose(String a, String cityN) {
    final n = _norm(a);
    if (n == cityN) return true;
    final en = SaudiOfficialAdmin.englishOf(a);
    if (en != null && _norm(en) == cityN) return true;
    return false;
  }

  static Set<String> _typeAliases(String code) {
    switch (code) {
      case 'villa':
        return {_norm('فيلا'), _norm('دوبلكس')};
      case 'apartment':
        return {_norm('شقة'), _norm('استديو'), _norm('ستوديو')};
      case 'land':
      case 'land_walled':
      case 'land_fenced':
        return {_norm('أرض'), _norm('ارض')};
      case 'floor':
        return {_norm('دور')};
      case 'office':
      case 'office_tower':
        return {_norm('مكتب')};
      case 'shop':
        return {_norm('محل')};
      case 'showroom':
        return {_norm('معرض'), _norm('معرض تجاري')};
      case 'farm':
        return {_norm('مزرعة')};
      case 'warehouse':
        return {_norm('مستودع')};
      default:
        return {PropertyTypeCatalog.label(code, true)}.map(_norm).toSet();
    }
  }
}
