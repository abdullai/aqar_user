import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// حفظ فلاتر التصفح السريع وخريطة المشاهدة (مع سقف وإعادة عرض).
abstract final class ShortsFeedPrefs {
  static const scopeKey = 'shorts_feed_scope_v1';
  static const purposeKey = 'shorts_feed_purpose_v1';
  static const cityKey = 'shorts_feed_city_v1';
  static const typeKey = 'shorts_feed_type_v1';
  static const _seenMapPrefix = 'shorts_seen_map_v2_';
  static const _seenListPrefix = 'shorts_seen_ids_v1_';
  static const sessionActiveKey = 'shorts_session_active_v1';
  static const sessionUidKey = 'shorts_session_uid_v1';

  static const maxSeen = 400;
  static const recycleAfter = Duration(hours: 48);

  static Future<String> loadScope() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = (p.getString(scopeKey) ?? 'all').trim();
      if (v == 'mine' || v == 'listings' || v == 'requests' || v == 'all') {
        return v;
      }
    } catch (_) {}
    return 'all';
  }

  static Future<void> saveScope(String v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(scopeKey, v);
    } catch (_) {}
  }

  static Future<String> loadPurpose() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = (p.getString(purposeKey) ?? 'all').trim();
      if (v == 'sale' || v == 'rent' || v == 'all') return v;
    } catch (_) {}
    return 'all';
  }

  static Future<void> savePurpose(String v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(purposeKey, v);
    } catch (_) {}
  }

  static Future<String> loadCity() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getString(cityKey) ?? '').trim();
    } catch (_) {}
    return '';
  }

  static Future<void> saveCity(String v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(cityKey, v.trim());
    } catch (_) {}
  }

  static Future<String> loadType() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getString(typeKey) ?? '').trim();
    } catch (_) {}
    return '';
  }

  static Future<void> saveType(String v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(typeKey, v.trim());
    } catch (_) {}
  }

  static Future<Map<String, DateTime>> loadSeen(String uid) async {
    final out = <String, DateTime>{};
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_seenMapPrefix$uid');
      if (raw != null && raw.isNotEmpty) {
        final dec = jsonDecode(raw);
        if (dec is Map) {
          for (final e in dec.entries) {
            final id = e.key.toString();
            final ms = e.value is int
                ? e.value as int
                : int.tryParse('${e.value}') ?? 0;
            if (id.isEmpty || ms <= 0) continue;
            out[id] = DateTime.fromMillisecondsSinceEpoch(ms);
          }
        }
      } else {
        final legacy = p.getStringList('$_seenListPrefix$uid') ?? const [];
        if (legacy.isNotEmpty) {
          final recycled = DateTime.now().subtract(recycleAfter);
          for (final id in legacy) {
            if (id.trim().isEmpty) continue;
            out[id.trim()] = recycled;
          }
        }
      }
    } catch (_) {}
    return out;
  }

  static Future<void> saveSeen(String uid, Map<String, DateTime> seen) async {
    try {
      var map = Map<String, DateTime>.from(seen);
      if (map.length > maxSeen) {
        final entries = map.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        map = Map<String, DateTime>.fromEntries(entries.take(maxSeen));
        seen
          ..clear()
          ..addAll(map);
      }
      final encoded = <String, int>{
        for (final e in map.entries) e.key: e.value.millisecondsSinceEpoch,
      };
      final p = await SharedPreferences.getInstance();
      await p.setString('$_seenMapPrefix$uid', jsonEncode(encoded));
    } catch (_) {}
  }

  static bool _memoryActive = false;
  static String _memoryUid = '';
  static bool _userClosed = false;

  /// أُغلق التصفح السريع عمداً في هذه الجلسة — لا تُعد فتحه تلقائياً.
  static bool get userClosedThisSession => _userClosed;

  static void markUserClosed() {
    _userClosed = true;
    _memoryActive = false;
    _memoryUid = '';
  }

  static void clearUserClosed() {
    _userClosed = false;
  }

  static Future<bool> isSessionActiveFor(String uid) async {
    if (_userClosed) return false;
    final want = uid.trim();
    if (_memoryActive) return _memoryUid == want;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(sessionActiveKey) != true) return false;
      final stored = (p.getString(sessionUidKey) ?? '').trim();
      return stored == want;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setSessionActive(bool v, {String uid = ''}) async {
    if (v) {
      _userClosed = false;
      _memoryActive = true;
      _memoryUid = uid.trim();
    } else {
      _memoryActive = false;
      _memoryUid = '';
    }
    try {
      final p = await SharedPreferences.getInstance();
      if (v) {
        await p.setBool(sessionActiveKey, true);
        await p.setString(sessionUidKey, uid.trim());
      } else {
        await p.remove(sessionActiveKey);
        await p.remove(sessionUidKey);
      }
    } catch (_) {}
  }
}
