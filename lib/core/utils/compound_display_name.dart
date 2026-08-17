/// تقسيم وعرض الأسماء العربية والإنجليزية المركّبة كوحدات منطقية.
///
/// أمثلة:
/// - `آل سعود` → وحدة واحدة (تُحفظ المسافة داخل الوحدة)
/// - `أبو حيه` / `ابو حيه` → `أبوحيه` (بدون مسافة في العرض)
/// - `Van Der Berg` → وحدة واحدة في الإنجليزية
abstract final class CompoundDisplayName {
  CompoundDisplayName._();

  /// بادئات عربية تُلصق بالكلمة التالية بلا مسافة في العرض.
  static const Set<String> _arGluePrefixes = {
    'أبو',
    'ابو',
    'أبا',
    'ابا',
    'أبي',
    'ابي',
    'أب',
    'اب',
    'أم',
    'ام',
    'ابن',
    'بن',
    'بنت',
    'ابنة',
    'إبن',
  };

  /// بادئات عربية تبقى مع الكلمة التالية كمساحة داخل الوحدة.
  static const Set<String> _arSpacePrefixes = {
    'آل',
    'ال',
    'عبد',
  };

  static const Set<String> _enGluePrefixes = {
    'mc',
    'mac',
    'o\'',
  };

  static const Set<String> _enSpacePrefixes = {
    'van',
    'von',
    'de',
    'da',
    'di',
    'del',
    'della',
    'der',
    'den',
    'la',
    'le',
    'st',
    'st.',
    'saint',
    'al',
  };

  static String _normWs(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _isArGlue(String t) => _arGluePrefixes.contains(t);
  static bool _isArSpace(String t) => _arSpacePrefixes.contains(t);

  static bool _isEnGlue(String t) {
    final l = t.toLowerCase();
    return _enGluePrefixes.contains(l);
  }

  static bool _isEnSpace(String t) {
    final l = t.toLowerCase().replaceAll('.', '');
    return _enSpacePrefixes.contains(l) ||
        _enSpacePrefixes.contains(t.toLowerCase());
  }

  /// وحدات الاسم بعد دمج المركّبات (كل عنصر = جزء منطقي واحد).
  static List<String> units(String fullName) {
    final raw = _normWs(fullName);
    if (raw.isEmpty) return const [];

    final tokens = raw.split(' ').where((e) => e.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];

    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      final t = tokens[i];

      if (i + 1 < tokens.length && _isArGlue(t)) {
        // أبو حيه → أبوحيه
        out.add('$t${tokens[i + 1]}');
        i += 2;
        continue;
      }
      if (i + 1 < tokens.length && _isArSpace(t)) {
        // آل سعود / عبد الله
        final buf = StringBuffer(t);
        i++;
        // عبد الله محمد → عبد الله كوحدة أولى فقط مع الكلمة التالية
        buf.write(' ');
        buf.write(tokens[i]);
        i++;
        // عبد الرحمن → تم؛ لا تبتلع بقية الاسم
        out.add(buf.toString());
        continue;
      }
      if (i + 1 < tokens.length && _isEnGlue(t)) {
        out.add('$t${tokens[i + 1]}');
        i += 2;
        continue;
      }
      if (i + 1 < tokens.length && _isEnSpace(t)) {
        // Van Der Berg → Van Der + Berg كوحدات متتابعة من البادئات ثم الاسم
        final buf = StringBuffer(t);
        i++;
        while (i < tokens.length && _isEnSpace(tokens[i])) {
          buf.write(' ');
          buf.write(tokens[i]);
          i++;
        }
        if (i < tokens.length) {
          buf.write(' ');
          buf.write(tokens[i]);
          i++;
        }
        out.add(buf.toString());
        continue;
      }

      out.add(t);
      i++;
    }
    return out;
  }

  /// الاسم كاملاً بعد تطبيع المركّبات (أبوحيه بدل أبو حيه).
  static String normalize(String fullName) {
    final u = units(fullName);
    return u.join(' ');
  }

  /// للشريط العلوي: ضيق = أول+آخر وحدة | متوسط = أول+ثاني+آخر | كامل = الكل.
  static String forToolbar(
    String fullName, {
    required bool compact,
    bool medium = false,
  }) {
    final u = units(fullName);
    if (u.isEmpty) return '';
    if (u.length == 1) return u.first;
    if (compact) {
      return u.length >= 2 ? '${u.first} ${u.last}' : u.first;
    }
    if (medium && u.length >= 4) {
      return '${u.first} ${u[1]} ${u.last}';
    }
    if (medium && u.length >= 3) {
      return '${u.first} ${u[1]} ${u.last}';
    }
    return u.join(' ');
  }

  /// هل يبدو «اسم المستخدم» أرقاماً فقط (هوية) وليس اسم عرض؟
  static bool looksLikeNumericUsername(String? raw) {
    final s = (raw ?? '').replaceAll(RegExp(r'\s+'), '').trim();
    if (s.length < 8) return false;
    // كل المحارف أرقام عربية/لاتينية/فارسية فقط
    return RegExp(r'^[0-9٠-٩۰-۹]+$').hasMatch(s);
  }
}
