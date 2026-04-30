/// نطاقات لإكمال البريد بعد كتابة @ (عالمية + سعودية + حكومية/تعليمية).
class EmailDomainCatalog {
  EmailDomainCatalog._();

  /// ترتيب: شائعة عالمياً ثم سعودية ثم نطاقات رسمية (.sa).
  static const List<String> completionDomains = [
    // عالمي
    'gmail.com',
    'googlemail.com',
    'hotmail.com',
    'outlook.com',
    'live.com',
    'msn.com',
    'yahoo.com',
    'yahoo.co.uk',
    'ymail.com',
    'icloud.com',
    'me.com',
    'mac.com',
    'proton.me',
    'protonmail.com',
    'zoho.com',
    'mail.com',
    'aol.com',
    'gmx.com',
    'gmx.net',
    'fastmail.com',
    'hey.com',
    // سعودية — مشغلين وخدمات
    'stc.com.sa',
    'stc.sa',
    'mobily.com.sa',
    'zain.com',
    'zain.sa',
    'outlook.sa',
    // سعودية — نطاقات عامة
    'com.sa',
    'net.sa',
    'org.sa',
    'edu.sa',
    'sch.sa',
    'gov.sa',
    'mil.sa',
    'med.sa',
    'cloud.sa',
  ];

  /// بعد @: `domainTyped` = ما كتبه المستخدم بعد @ (بدون تطبيع إضافي).
  static List<String> completionSuggestions({
    required String localPart,
    required String domainTyped,
    int maxItems = 24,
  }) {
    final local = localPart.trim();
    if (local.isEmpty) return const [];

    var needle = domainTyped.trim().toLowerCase();
    // كتابة شائعة: orq → org (مثل org.sa الحكومي/المؤسسي)
    if (needle.startsWith('orq')) {
      needle = 'org${needle.substring(3)}';
    }
    final out = <String>[];

    for (final d in completionDomains) {
      final dl = d.toLowerCase();
      if (needle.isEmpty || dl.startsWith(needle)) {
        out.add('$local@$d');
        if (out.length >= maxItems) break;
      }
    }
    return out;
  }
}
