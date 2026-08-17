/// تطبيع نصوص البحث في القوائم الطويلة (مطابقة خفيفة بين العربية/الإنجليزية).
String normalizeForListSearch(String? v) {
  var s = (v ?? '').trim().toLowerCase();
  if (s.isEmpty) return '';
  s = s
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s;
}
