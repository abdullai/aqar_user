import 'package:shared_preferences/shared_preferences.dart';

/// اسم التحية في شريط الرئيسية — يظهر فوراً من الكاش دون انتظار الملف الشخصي.
abstract final class DashboardGreetingCache {
  static const _kKey = 'dash_greeting_display_name_v1';
  static const _kUidKey = 'dash_greeting_uid_v1';

  static String? _memoryName;
  static String? _memoryUid;

  static String? memoryFor(String uid) {
    final u = uid.trim();
    if (u.isEmpty || _memoryUid != u) return null;
    final n = (_memoryName ?? '').trim();
    return n.isEmpty ? null : n;
  }

  static Future<String?> read(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    final mem = memoryFor(u);
    if (mem != null) return mem;
    final p = await SharedPreferences.getInstance();
    final savedUid = (p.getString(_kUidKey) ?? '').trim();
    if (savedUid != u) return null;
    final name = (p.getString(_kKey) ?? '').trim();
    if (name.isEmpty) return null;
    _memoryUid = u;
    _memoryName = name;
    return name;
  }

  static Future<void> save(String uid, String name) async {
    final u = uid.trim();
    final n = name.trim();
    if (u.isEmpty || n.isEmpty) return;
    _memoryUid = u;
    _memoryName = n;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUidKey, u);
    await p.setString(_kKey, n);
  }

  static Future<void> clear() async {
    _memoryUid = null;
    _memoryName = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
    await p.remove(_kUidKey);
  }
}
