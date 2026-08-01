import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// حفظ مسودات نماذج متعددة الخطوات محلياً (حتى إغلاق التطبيق/المتصفح أو تسجيل الخروج).
class WizardFormDraft {
  WizardFormDraft._();

  static String _key(String namespace, String userId) =>
      'wizard_draft_${namespace}_$userId';

  static Future<void> save({
    required String namespace,
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    if (userId.trim().isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key(namespace, userId),
      jsonEncode({
        ...data,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<Map<String, dynamic>?> load({
    required String namespace,
    required String userId,
  }) async {
    if (userId.trim().isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(namespace, userId));
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clear({
    required String namespace,
    required String userId,
  }) async {
    if (userId.trim().isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(namespace, userId));
  }

  static Future<bool> exists({
    required String namespace,
    required String userId,
  }) async {
    final d = await load(namespace: namespace, userId: userId);
    return d != null && d.isNotEmpty;
  }
}
