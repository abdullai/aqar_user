import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'saudi_locations_service.dart';

/// أحياء اختيارية لكل مدينة (مفتاح = اسم المدينة كما يظهر في القائمة).
/// يمكن توسيع `assets/data/saudi_districts.json` دون تعديل الكود — أضف مفتاحاً
/// لكل مدينة بالعربية و/أو بالإنجليزية كما تُعرض في القائمة (انظر الملف للأمثلة).
class SaudiDistrictsService {
  SaudiDistrictsService._();
  static final SaudiDistrictsService instance = SaudiDistrictsService._();

  Map<String, List<String>>? _cache;

  Future<Map<String, List<String>>> loadAll() async {
    if (_cache != null) return _cache!;
    try {
      final raw =
          await rootBundle.loadString('assets/data/saudi_districts.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _cache = {};
        return _cache!;
      }
      final out = <String, List<String>>{};
      decoded.forEach((k, v) {
        final key = k.toString().trim();
        if (key.isEmpty) return;
        if (v is List) {
          final list = v
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          if (list.isNotEmpty) out[key] = list;
        }
      });
      _cache = out;
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  /// يدمج أسماء المدن العربية/الإنجليزية من [saudi_locations.json] حتى تُحمَل الأحياء
  /// سواء اختُيرت «الرياض» أو «Riyadh» دون تكرار القوائم يدوياً في JSON.
  Future<Map<String, List<String>>> loadMergedWithCityAliases() async {
    final base = Map<String, List<String>>.from(await loadAll());
    try {
      final all = await SaudiLocationsService.instance.loadAll();
      for (final loc in all) {
        final ar = loc.cityAr.trim();
        final en = loc.cityEn.trim();
        if (ar.isEmpty || en.isEmpty || ar == en) continue;
        final listAr = base[ar];
        final listEn = base[en];
        // AR → EN
        if (listAr != null &&
            listAr.isNotEmpty &&
            (listEn == null || listEn.isEmpty)) {
          base[en] = List<String>.from(listAr);
        }
        // EN → AR (ملف الأحياء غالباً بمفاتيح إنجليزية فقط)
        if (listEn != null &&
            listEn.isNotEmpty &&
            (listAr == null || listAr.isEmpty)) {
          base[ar] = List<String>.from(listEn);
        }
      }
    } catch (_) {}
    return base;
  }

  /// [cityLabel] نفس النص المختار في قائمة المدينة (عربي أو إنجليزي حسب الواجهة).
  Future<List<String>> districtsForCity(String cityLabel) async {
    final c = cityLabel.trim();
    if (c.isEmpty) return const [];
    final all = await loadMergedWithCityAliases();
    final direct = all[c];
    if (direct != null && direct.isNotEmpty) return direct;
    final norm = _norm(c);
    for (final e in all.entries) {
      if (_norm(e.key) == norm) return e.value;
    }
    return const [];
  }

  static String _norm(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ');
}
