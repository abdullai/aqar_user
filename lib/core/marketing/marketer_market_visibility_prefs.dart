import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// طلبات تسويق أخفاها المسوّق من «السوق العقاري» بعد إلغاء عرضه.
abstract final class MarketerMarketVisibilityPrefs {
  static String _key(String uid) => 'marketer_market_hidden_v1_${uid.trim()}';

  static Future<Set<String>> hiddenRequestIds(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(u));
      if (raw == null || raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> setHidden({
    required String marketerUid,
    required String requestId,
    required bool hidden,
  }) async {
    final u = marketerUid.trim();
    final rid = requestId.trim();
    if (u.isEmpty || rid.isEmpty) return;
    final set = await hiddenRequestIds(u);
    if (hidden) {
      set.add(rid);
    } else {
      set.remove(rid);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(u), jsonEncode(set.toList()));
  }
}
