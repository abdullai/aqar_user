import 'package:shared_preferences/shared_preferences.dart';

/// بصمة محتوى منشور حديثاً — تمنع إعادة نشر نفس البيانات خلال نافذة زمنية.
abstract final class PublishContentFingerprintStore {
  static const _kKey = 'publish_content_fp_v1';
  static const _kAtKey = 'publish_content_fp_at_v1';
  static const Duration window = Duration(hours: 24);

  static String build({
    required String title,
    required String city,
    required num? price,
    required num? area,
    required String deed,
    required String purpose,
  }) {
    return '${title.trim().toLowerCase()}|'
        '${city.trim().toLowerCase()}|'
        '${price ?? 0}|'
        '${area ?? 0}|'
        '${deed.trim()}|'
        '${purpose.trim().toLowerCase()}';
  }

  static Future<void> save(String fingerprint) async {
    final fp = fingerprint.trim();
    if (fp.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kKey, fp);
      await p.setInt(_kAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<String?> readIfFresh() async {
    try {
      final p = await SharedPreferences.getInstance();
      final fp = (p.getString(_kKey) ?? '').trim();
      final at = p.getInt(_kAtKey) ?? 0;
      if (fp.isEmpty || at <= 0) return null;
      final age = DateTime.now().millisecondsSinceEpoch - at;
      if (age > window.inMilliseconds) return null;
      return fp;
    } catch (_) {
      return null;
    }
  }
}
