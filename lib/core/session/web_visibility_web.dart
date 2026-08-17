// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// عند إخفاء التبويب أو تصغير النافذة (مثلاً تبديل تبويب في المتصفح).
void listenDocumentVisibilityHidden(void Function() onHidden) {
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'hidden') {
      onHidden();
    }
  });
}

/// عند إعادة إظهار التبويب (لاستئناف فحص قفل PIN/الدخول السريع).
void listenDocumentVisibilityShown(void Function() onShown) {
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      onShown();
    }
  });
}

/// مغادرة الصفحة (تحديث / إغلاق / انتقال تاريخ).
///
/// [persisted] = true عند bfcache.
/// لا نسجّل خروجاً هنا: تحديث F5 ورجوع المتصفح يجب أن يبقيا الجلسة.
/// الأمان عبر خمول الجلسة + الدخول السريع عند العودة بعد مهلة.
void listenDocumentPageHide(
  void Function({required bool persisted}) onPageHide,
) {
  html.window.onPageHide.listen((html.Event e) {
    final persisted =
        e is html.PageTransitionEvent ? (e.persisted ?? false) : false;
    onPageHide(persisted: persisted);
  });
  // لا نربط unload — يُطلق مع التحديث ويفرغ الجلسة خطأً.
}
