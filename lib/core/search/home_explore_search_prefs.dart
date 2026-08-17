import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/property.dart';

/// تفضيلات بحث الرئيسية المحفوظة محلياً (ضيف أو مستخدم) — مصدر واحد للمفتاح حسب هوية الجلسة.
abstract final class HomeExploreSearchPrefs {
  static String _storageKey(String sessionKey) =>
      'aqar_home_explore_saved_v1_${sessionKey.trim()}';

  /// [sessionKey] = `'guest'` أو معرف المستخدم.
  static Future<void> save({
    required String sessionKey,
    required Map<String, dynamic> payload,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_storageKey(sessionKey), jsonEncode(payload));
  }

  static Future<Map<String, dynamic>?> load(String sessionKey) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_storageKey(sessionKey));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static Future<void> clear(String sessionKey) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_storageKey(sessionKey));
  }

  static Map<String, dynamic> snapshot({
    required String searchQuery,
    required String cityFilter,
    required PropertyType? typeFilter,
    required String? purposeFilter,
    required String sortBy,
    required String homeFeedKindName,
    required bool? furnishedFilter,
  }) {
    return <String, dynamic>{
      'v': 1,
      'searchQuery': searchQuery,
      'cityFilter': cityFilter,
      'type': typeFilter?.name,
      'purpose': purposeFilter,
      'sortBy': sortBy,
      'homeFeedKind': homeFeedKindName,
      'furnished': furnishedFilter,
    };
  }

  static PropertyType? parseType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    for (final t in PropertyType.values) {
      if (t.name == raw.trim()) return t;
    }
    return null;
  }

  static String? parsePurpose(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    const allowed = {'sale', 'rent', 'auction', 'investment'};
    return allowed.contains(s) ? s : null;
  }

  static bool? parseFurnished(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return null;
  }
}
