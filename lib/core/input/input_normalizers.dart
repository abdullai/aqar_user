// lib/core/input/input_normalizers.dart
// تطبيع موحد للأرقام والرقم الوطني الموحّد (700…) وللبريد — للاستخدام في النماذج والمصادقة.

import 'email_domain_catalog.dart';

/// تحويل الأرقام العربية/الفارسية إلى 0-9
String normalizeAsciiDigits(String input) {
  const a = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  const e = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var out = input;
  for (int i = 0; i < 10; i++) {
    out = out.replaceAll(a[i], i.toString());
    out = out.replaceAll(e[i], i.toString());
  }
  return out;
}

/// أرقام إنجليزية فقط (إزالة كل غير الرقم)
String digitsOnly(String input) {
  return normalizeAsciiDigits(input).replaceAll(RegExp(r'[^0-9]'), '');
}

/// يزيل بادئة [ن] الاختيارية ثم يعيد الأرقام فقط.
String stripLeadingArabicNoonPrefix(String input) {
  var s = normalizeAsciiDigits(input.trim());
  // حرف النون العربي الشائع في النماذج
  if (s.startsWith('\u0646')) {
    s = s.substring(1).trimLeft();
  }
  return s;
}

/// الرقم الوطني الموحّد: بعد التطبيع يجب أن يكون 10 أرقام تبدأ بـ 700.
bool isValidUnifiedNationalNumberDigits(String tenDigits) {
  return RegExp(r'^700[0-9]{7}$').hasMatch(tenDigits);
}

/// يجهّز مدخلاً للتحقق: ن+700… أو 700… → سلسلة 10 أرقام أو أقصر إن ناقص.
String normalizeUnifiedNationalInput(String raw) {
  final withoutNoon = stripLeadingArabicNoonPrefix(raw);
  return digitsOnly(withoutNoon);
}

/// مفتاح تسجيل الدخول: 10 أرقام (هوية/إقامة/فال/أو الرقم الوطني الموحّد 700…).
bool isTenDigitLoginKey(String digits) => RegExp(r'^\d{10}$').hasMatch(digits);

/// فحص وجود حروف عربية في نص البريد — ممنوع في خانة البريد.
bool emailContainsArabicScript(String email) {
  return RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
  ).hasMatch(email);
}

/// اقتراح نطاق شائع عند نسيان النقطة قبل com (مثلاً gmailcom → gmail.com)
String? suggestEmailDomainFix(String email) {
  final t = email.trim().toLowerCase();
  final at = t.indexOf('@');
  if (at <= 0 || at >= t.length - 1) return null;
  final local = t.substring(0, at);
  var host = t.substring(at + 1).replaceAll(RegExp(r'\s'), '');
  if (local.isEmpty || host.isEmpty) return null;
  if (host.contains('.')) return null;

  for (final d in EmailDomainCatalog.completionDomains) {
    final compact = d.replaceAll('.', '');
    if (host == compact) {
      return '$local@$d';
    }
  }
  return null;
}
