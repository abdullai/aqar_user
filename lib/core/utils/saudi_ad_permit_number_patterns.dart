/// أنماط شائعة لأرقام تراخيص إعلان عقاري (فال / REGA — أرقام لاتينية فقط في الواجهة).
class SaudiAdPermitNumberPatterns {
  SaudiAdPermitNumberPatterns._();

  /// رقم نظيف: أحرف لاتينية وأرقام فقط.
  static String normalizeLatinDigits(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').trim();
  }

  /// تحقق شكلي (لا يغني عن التحقق عبر REGA).
  static bool isPlausiblePermitOrAdLicenseNo(String raw) {
    final s = normalizeLatinDigits(raw);
    if (s.length < 6 || s.length > 32) return false;
    return RegExp(r'^[0-9A-Za-z]+$').hasMatch(s);
  }

  /// ترخيص إعلان REGA — 10 أرقام تبدأ بـ 71 (فرد) أو 72 (منشأة).
  static bool isTenDigitAdLicenseNo(
    String raw, {
    required String requiredPrefix,
  }) {
    final s = normalizeLatinDigits(raw).replaceAll(RegExp(r'\D'), '');
    if (s.length != 10) return false;
    if (requiredPrefix.length != 2) return false;
    return s.startsWith(requiredPrefix) && RegExp(r'^\d{10}$').hasMatch(s);
  }
}
