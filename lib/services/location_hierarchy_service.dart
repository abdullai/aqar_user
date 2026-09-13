// lib/services/location_hierarchy_service.dart
//
// خدمة تدرّج الموقع لجعل البحث «المنطقة → المحافظة → المدينة → الحي» متاحاً
// لكامل التطبيق فوق ملفات JSON الموجودة في `assets/data/`:
//   - `saudi_locations.json`     (المدن الأساسية + المنطقة + إحداثيات)
//   - `saudi_locations_extra.json` (مدن وقرى وهجر ومراكز تحت المحافظة الرسمية)
//   - `saudi_districts.json`     (الأحياء لكل مدينة)
//
// نَستفيد من [SaudiLocationsService] الذي يقوم بالدمج وفولباك المحافظة، ومن
// [SaudiDistrictsService] لقائمة الأحياء. هنا نقدّم API هرمي للواجهة:
//   - regions(isAr)                        → كل المناطق
//   - governoratesIn(region)               → محافظات داخل المنطقة
//   - citiesIn(region, governorate)        → مدن داخل المحافظة
//   - districtsIn(city)                    → أحياء المدينة
//   - coordsOf(...)                        → إحداثيات لمركز الخريطة
//
// كل القوائم تُعاد بالاسم العربي أو الإنجليزي حسب [isAr]، ومُرتَّبة طبيعياً.

import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/geo/saudi_official_admin.dart';
import '../models/saudi_location.dart';
import 'saudi_districts_service.dart';
import 'saudi_locations_service.dart';

class LocationHierarchyService {
  LocationHierarchyService._();
  static final LocationHierarchyService instance =
      LocationHierarchyService._();

  List<SaudiLocation>? _cache;

  Future<List<SaudiLocation>> _all() async {
    return _cache ??=
        await SaudiLocationsService.instance.loadAll(includeExtra: true);
  }

  /// المناطق الثلاث عشرة الرسمية (لا تُخلط بمحافظات أو مدن).
  Future<List<String>> regions({required bool isAr}) async {
    return SaudiOfficialAdmin.officialRegionNames(isAr: isAr);
  }

  /// محافظات داخل [region] (يقبل اسماً عربياً أو إنجليزياً)، فريدة ومُرتّبة.
  Future<List<String>> governoratesIn({
    required String region,
    required bool isAr,
  }) async {
    final all = await _all();
    final r = region.trim();
    if (r.isEmpty) return const [];
    final official = SaudiOfficialAdmin.governorates(region: r, isAr: isAr);
    if (official.isNotEmpty) return official;
    final seen = <String>{};
    for (final e in all) {
      if (e.regionAr.trim() != r && e.regionEn.trim() != r) continue;
      final v = (isAr
              ? (e.governorateAr ?? '').trim()
              : (e.governorateEn ?? '').trim())
          .trim();
      if (v.isEmpty) continue;
      seen.add(v);
    }
    final out = seen.toList()..sort(_naturalCompare);
    return out;
  }

  /// مدن داخل [governorate] في [region]. عند غياب المحافظة نقبل أي مدينة في
  /// المنطقة (الفولباك التلقائي في [SaudiLocationsService]: cityAr ↔ governorateAr).
  Future<List<String>> citiesIn({
    required String region,
    required String governorate,
    required bool isAr,
  }) async {
    final all = await _all();
    final r = region.trim();
    final g = governorate.trim();
    if (r.isEmpty || g.isEmpty) return const [];
    if (!SaudiOfficialAdmin.isOfficialGovernorate(region: r, governorate: g)) {
      return const [];
    }
    final seen = <String>{};
    for (final e in all) {
      if (!SaudiOfficialAdmin.sameRegion(e.regionAr, r) &&
          !SaudiOfficialAdmin.sameRegion(e.regionEn, r)) {
        continue;
      }
      final ga = (e.governorateAr ?? '').trim();
      final ge = (e.governorateEn ?? '').trim();
      final cityAr = e.cityAr.trim();
      final cityEn = e.cityEn.trim();
      final underGov = ga == g ||
          ge == g ||
          (ga.isEmpty && ge.isEmpty && (cityAr == g || cityEn == g));
      if (!underGov) continue;
      final v = (isAr ? e.cityAr : e.cityEn).trim();
      if (v.isEmpty) continue;
      seen.add(v);
    }
    final out = seen.toList()..sort(_naturalCompare);
    return out;
  }

  /// أحياء [city] من `saudi_districts.json` (مع دمج الأسماء العربية/الإنجليزية).
  Future<List<String>> districtsIn({required String city}) async {
    final c = city.trim();
    if (c.isEmpty) return const [];
    final map =
        await SaudiDistrictsService.instance.loadMergedWithCityAliases();
    final direct = map[c];
    if (direct != null && direct.isNotEmpty) return direct;
    return const [];
  }

  /// إحداثيات لمركز [city] في [region]/[governorate] إن وُجدت.
  Future<LatLng?> coordsOf({
    required String region,
    required String governorate,
    required String city,
  }) async {
    final all = await _all();
    final r = region.trim();
    final g = governorate.trim();
    final c = city.trim();
    for (final e in all) {
      final regionMatches = r.isEmpty ||
          SaudiOfficialAdmin.sameRegion(e.regionAr, r) ||
          SaudiOfficialAdmin.sameRegion(e.regionEn, r);
      final govMatches = g.isEmpty ||
          (e.governorateAr ?? '').trim() == g ||
          (e.governorateEn ?? '').trim() == g;
      final cityMatches = c.isEmpty ||
          e.cityAr.trim() == c ||
          e.cityEn.trim() == c;
      if (!regionMatches || !govMatches || !cityMatches) continue;
      if (e.lat == 0 && e.lng == 0) continue;
      return LatLng(e.lat, e.lng);
    }
    return null;
  }

  /// خرائط التدرّج كاملة (منطقة → محافظات → مدن) دفعة واحدة للنماذج.
  Future<
      ({
        List<String> regions,
        Map<String, List<String>> governoratesByRegion,
        Map<String, List<String>> citiesByGovernorate,
      })> cascade({required bool isAr}) async {
    final all = await _all();
    final regionList = SaudiOfficialAdmin.officialRegionNames(isAr: isAr);
    final govs = <String, Set<String>>{};
    final cities = <String, Set<String>>{};
    for (final region in regionList) {
      govs[region] = {
        ...SaudiOfficialAdmin.governorates(region: region, isAr: isAr),
      };
    }
    for (final item in all) {
      final region = SaudiOfficialAdmin.canonicalRegionName(
            isAr ? item.regionAr : item.regionEn,
            isAr: isAr,
          ) ??
          '';
      if (region.isEmpty) continue;
      var gov = (isAr
              ? (item.governorateAr ?? '')
              : (item.governorateEn ?? ''))
          .trim();
      if (!SaudiOfficialAdmin.isOfficialGovernorate(
        region: region,
        governorate: gov,
      )) {
        final cityName = (isAr ? item.cityAr : item.cityEn).trim();
        gov = SaudiOfficialAdmin.isOfficialGovernorate(
              region: region,
              governorate: cityName,
            )
            ? cityName
            : '';
      }
      if (gov.isEmpty) continue;
      govs.putIfAbsent(region, () => <String>{}).add(gov);
      final city = (isAr ? item.cityAr : item.cityEn).trim();
      if (city.isEmpty) continue;
      cities.putIfAbsent(gov, () => <String>{}).add(city);
    }
    final govMap = <String, List<String>>{};
    for (final e in govs.entries) {
      final list = e.value.toList()..sort(_naturalCompare);
      govMap[e.key] = list;
    }
    final cityMap = <String, List<String>>{};
    for (final e in cities.entries) {
      final list = e.value.toList()..sort(_naturalCompare);
      cityMap[e.key] = list;
    }
    return (
      regions: regionList,
      governoratesByRegion: govMap,
      citiesByGovernorate: cityMap,
    );
  }

  /// لمواصلة استخدام نظام الإحداثيات في بقية المشروع — يستدعي الخدمة الأصلية.
  Future<SaudiLocation?> findNearest(double lat, double lng) {
    return SaudiLocationsService.instance.findNearest(lat, lng);
  }

  /// مقارنة طبيعية لتجنّب ترتيب «10 قبل 2» في الأسماء التي تحوي أرقاماً.
  int _naturalCompare(String a, String b) {
    final pa = _splitParts(a);
    final pb = _splitParts(b);
    final n = math.min(pa.length, pb.length);
    for (var i = 0; i < n; i++) {
      final ai = pa[i];
      final bi = pb[i];
      final ax = int.tryParse(ai);
      final bx = int.tryParse(bi);
      int cmp;
      if (ax != null && bx != null) {
        cmp = ax.compareTo(bx);
      } else {
        cmp = ai.compareTo(bi);
      }
      if (cmp != 0) return cmp;
    }
    return pa.length.compareTo(pb.length);
  }

  static final RegExp _digitsOrText = RegExp(r'\d+|\D+');
  List<String> _splitParts(String s) {
    return _digitsOrText
        .allMatches(s)
        .map((m) => m.group(0) ?? '')
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
  }
}
