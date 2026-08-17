/// عرض معرفات للمستخدم: أرقام فقط بدون بادئات رمزية (#، REQ، …).
abstract final class DisplayIds {
  DisplayIds._();

  /// يُبقي الأرقام فقط؛ إن لم يوجد رقم يُرجع النص بعد إزالة رموز شائعة.
  static String plainNumericOrClean(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    final digits = s.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isNotEmpty) return digits;
    return s
        .replaceAll(RegExp(r'^[#\-–—\s]+'), '')
        .replaceAll(RegExp(r'^[A-Za-z]{2,}[\s\-_:]*'), '');
  }

  /// رقم عرض ثابت من 10 خانات للبطاقات العامة.
  static String tenDigit(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    final digits = s.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 10) return digits.substring(digits.length - 10);
    if (digits.isNotEmpty) return digits.padLeft(10, '0');

    var hash = 0;
    for (final unit in s.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (hash % 10000000000).toString().padLeft(10, '0');
  }
}
