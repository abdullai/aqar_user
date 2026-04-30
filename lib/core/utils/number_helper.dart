// lib/core/utils/number_helper.dart

class NumberHelper {
  static String normalizeAsciiDigits(String input) {
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    var out = input;
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
    }
    return out;
  }

  /// تحويل أي قيمة إلى double
  static double? toDouble(dynamic v) {
    if (v == null) return null;

    if (v is double) return v;

    if (v is int) return v.toDouble();

    if (v is num) return v.toDouble();

    final s = normalizeAsciiDigits(v.toString())
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll('٫', '.')
        .trim();
    if (s.isEmpty) return null;

    return double.tryParse(s);
  }

  /// تحويل آمن إلى double مع fallback
  static double toDouble0(dynamic v, [double fallback = 0.0]) {
    final d = toDouble(v);

    if (d == null) return fallback;

    if (d.isNaN || d.isInfinite) return fallback;

    return d;
  }
}
