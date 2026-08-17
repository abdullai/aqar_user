import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import '../models/saudi_location.dart';

class SaudiLocationsService {
  SaudiLocationsService._();
  static final SaudiLocationsService instance = SaudiLocationsService._();

  List<SaudiLocation>? _cache;
  bool _extraMerged = false;

  Future<List<SaudiLocation>> loadAll({bool? includeExtra}) async {
    final wantExtra = includeExtra ?? !kIsWeb;
    if (_cache != null && (!wantExtra || _extraMerged)) {
      return _cache!;
    }

    final merged = <SaudiLocation>[];
    if (_cache != null) {
      merged.addAll(_cache!);
    } else {
      await _mergePathInto(
        merged,
        'assets/data/saudi_locations.json',
      );
    }
    if (wantExtra && !_extraMerged) {
      await _mergePathInto(
        merged,
        'assets/data/saudi_locations_extra.json',
      );
      _extraMerged = true;
    }

    final seen = <String>{};
    final out = <SaudiLocation>[];
    for (final e in merged.map(_withGovernorateFallback)) {
      final k = '${e.regionAr.trim()}|${e.cityAr.trim()}';
      if (seen.contains(k)) continue;
      seen.add(k);
      out.add(e);
    }
    _cache = out;
    return _cache!;
  }

  static Future<void> _mergePathInto(
    List<SaudiLocation> merged,
    String path,
  ) async {
    try {
      final raw = await rootBundle.loadString(path);
      if (kIsWeb) {
        await Future<void>.delayed(Duration.zero);
      }
      final list = jsonDecode(raw) as List<dynamic>;
      for (final e in list) {
        merged.add(
          SaudiLocation.fromJson(Map<String, dynamic>.from(e as Map)),
        );
      }
    } catch (_) {
      // الملف الإضافي اختياري
    }
  }

  /// عند غياب المحافظة في البيانات: نستخدم المدينة كمفتاح محافظة لربط هرمي واضح.
  static SaudiLocation _withGovernorateFallback(SaudiLocation e) {
    final ga = e.governorateAr?.trim() ?? '';
    final ge = e.governorateEn?.trim() ?? '';
    if (ga.isNotEmpty && ge.isNotEmpty) return e;
    return SaudiLocation(
      cityAr: e.cityAr,
      cityEn: e.cityEn,
      regionAr: e.regionAr,
      regionEn: e.regionEn,
      governorateAr: ga.isNotEmpty ? ga : e.cityAr,
      governorateEn: ge.isNotEmpty ? ge : e.cityEn,
      lat: e.lat,
      lng: e.lng,
    );
  }

  Future<SaudiLocation?> findByCity(String city) async {
    final c = _normalize(city);
    if (c.isEmpty) return null;

    final all = await loadAll();

    for (final item in all) {
      if (_normalize(item.cityAr) == c || _normalize(item.cityEn) == c) {
        return item;
      }
    }

    return null;
  }

  /// أقرب مدينة من جدول الإحداثيات (مركز المدينة) — لاستنتاج المنطقة/المحافظة/المدينة من الخريطة.
  Future<SaudiLocation?> findNearest(double lat, double lng) async {
    if (lat.isNaN || lng.isNaN) return null;
    final all = await loadAll();
    SaudiLocation? best;
    var bestKm = double.infinity;

    for (final item in all) {
      if (item.lat == 0 && item.lng == 0) continue;
      final d = _haversineKm(lat, lng, item.lat, item.lng);
      if (d < bestKm) {
        bestKm = d;
        best = item;
      }
    }
    return best;
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthKm = 6371.0;
    const p = math.pi / 180.0;
    final r1 = lat1 * p;
    final r2 = lat2 * p;
    final dLat = (lat2 - lat1) * p;
    final dLon = (lon2 - lon1) * p;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(r1) * math.cos(r2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt((1 - h).clamp(0.0, 1.0)));
    return earthKm * c;
  }

  String _normalize(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
