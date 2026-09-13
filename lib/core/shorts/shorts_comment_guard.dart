/// يمنع أرقام التواصل والإيحاءات بالخروج من المنصة في تعليقات التصفح السريع.
abstract final class ShortsCommentGuard {
  static final _digitRun = RegExp(r'\d[\d\s\-().]{7,}\d');
  static final _latinHints = RegExp(
    r'(whats?\s*app|wa\.me|t\.me|telegram|snapchat|instagram|facebook|'
    r'call\s*me|my\s*number|phone\s*me|text\s*me|outside\s*(the)?\s*app|'
    r'contact\s*me|dm\s*me|whatsapp)',
    caseSensitive: false,
  );
  static final _arHints = RegExp(
    r'(واتس|واتساب|تليجرام|تلغرام|سناب|انستغرام|إنستقرام|'
    r'كلمني|كلّمني|رقمي|رقم الجوال|رقم الجوّال|تواصل معي|تواصل خاص|'
    r'برا التطبيق|خارج التطبيق|على الخاص|خاصني|راسلني)',
  );

  static bool looksLikeOffAppContact(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    final compact = t.replaceAll(RegExp(r'[\s\-().]'), '');
    if (RegExp(r'(?:\+?966|0)?5\d{8}').hasMatch(compact)) return true;
    if (RegExp(r'00?9665\d{8}').hasMatch(compact)) return true;
    if (_digitRun.hasMatch(t)) return true;
    if (_latinHints.hasMatch(t)) return true;
    if (_arHints.hasMatch(t)) return true;
    return false;
  }

  static String? blockReason({required String body, required bool isAr}) {
    if (!looksLikeOffAppContact(body)) return null;
    return isAr
        ? 'لا يُسمح بأرقام أو تلميحات تواصل خارج المنصة. استخدم الصفقة أو العرض داخل موثوق.'
        : 'Phone numbers or off-app contact hints are not allowed. Use in-app deal or offer.';
  }
}
