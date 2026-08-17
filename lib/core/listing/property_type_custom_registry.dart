import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// أنواع عقار يدخلها المستخدم ويُخزَّن محلياً (بدون تكرار بعد تطبيع المسافات).
abstract final class PropertyTypeCustomRegistry {
  static const String _kPrefKey = 'property_type_user_defined_v1';
  static const String codePrefix = 'ut_';

  static List<_CustomTypeRow> _rows = [];
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPrefKey);
    if (raw != null && raw.trim().startsWith('[')) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _rows = list
            .map((e) => _CustomTypeRow.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        _rows = [];
      }
    }
    _loaded = true;
  }

  static String normalizeLabel(String s) {
    var t = s.trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  static int _fnv1a(String s) {
    var h = 2166136261;
    for (final u in s.codeUnits) {
      h ^= u;
      h = (h * 16777619) & 0x7fffffff;
    }
    return h;
  }

  static String _codeForNormalized(String norm) {
    if (norm.isEmpty) return '';
    final h = _fnv1a(norm);
    return '$codePrefix${h.toRadixString(36)}';
  }

  /// يعيد الرمز نفسه إن وُجد نفس التسمية (بعد التطبيع).
  static Future<String?> addCustom({
    required String labelAr,
    required String labelEn,
    required String groupId,
  }) async {
    await ensureLoaded();
    final ar = normalizeLabel(labelAr);
    final en = normalizeLabel(labelEn.isNotEmpty ? labelEn : labelAr);
    if (ar.isEmpty && en.isEmpty) return null;
    final key = ar.isNotEmpty ? ar : en;
    final code = _codeForNormalized(key);

    final existing = _rows.indexWhere((r) => r.code == code);
    if (existing >= 0) {
      _rows[existing] = _CustomTypeRow(
        code: code,
        ar: ar.isNotEmpty ? ar : _rows[existing].ar,
        en: en.isNotEmpty ? en : _rows[existing].en,
        groupId: groupId,
      );
    } else {
      _rows.add(_CustomTypeRow(
        code: code,
        ar: ar.isNotEmpty ? ar : en,
        en: en.isNotEmpty ? en : ar,
        groupId: groupId,
      ));
    }
    await _persist();
    return code;
  }

  static Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kPrefKey,
      jsonEncode(_rows.map((e) => e.toJson()).toList()),
    );
  }

  static bool isUserType(String? code) =>
      (code ?? '').trim().startsWith(codePrefix);

  static String? label(String? code, bool isAr) {
    final c = (code ?? '').trim();
    if (!isUserType(c)) return null;
    for (final r in _rows) {
      if (r.code == c) return isAr ? r.ar : r.en;
    }
    return null;
  }

  static String? groupIdForCode(String? code) {
    final c = (code ?? '').trim();
    if (!isUserType(c)) return null;
    for (final r in _rows) {
      if (r.code == c) return r.groupId;
    }
    return 'other';
  }

  static List<Map<String, String>> mapsForGroup(String groupId) {
    return _rows
        .where((r) => r.groupId == groupId)
        .map(
          (r) => <String, String>{
            'code': r.code,
            'ar': r.ar,
            'en': r.en,
          },
        )
        .toList();
  }

  static bool hasCode(String code) =>
      _rows.any((r) => r.code == code.trim());
}

class _CustomTypeRow {
  final String code;
  final String ar;
  final String en;
  final String groupId;

  const _CustomTypeRow({
    required this.code,
    required this.ar,
    required this.en,
    required this.groupId,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'ar': ar,
        'en': en,
        'group': groupId,
      };

  factory _CustomTypeRow.fromJson(Map<String, dynamic> m) {
    return _CustomTypeRow(
      code: '${m['code'] ?? ''}'.trim(),
      ar: '${m['ar'] ?? ''}'.trim(),
      en: '${m['en'] ?? ''}'.trim(),
      groupId: '${m['group'] ?? 'other'}'.trim().isEmpty
          ? 'other'
          : '${m['group']}'.trim(),
    );
  }
}
