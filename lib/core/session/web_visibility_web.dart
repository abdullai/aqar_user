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

/// عند تجميد التبويب (Chrome Page Lifecycle) — ساعة الجدار تبقى المرجع عند العودة.
void listenDocumentFreeze(void Function() onFreeze) {
  html.document.on['freeze'].listen((_) => onFreeze());
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

/// عودة التبويب من bfcache (سهم الرجوع من موقع آخر).
void listenDocumentPageShow(
  void Function({required bool persisted}) onPageShow,
) {
  html.window.onPageShow.listen((html.Event e) {
    final persisted =
        e is html.PageTransitionEvent ? (e.persisted ?? false) : false;
    onPageShow(persisted: persisted);
  });
}

/// يمنع تمرير صفحة الويب خلف حوار الخمول حتى يبقى الحوار في المنتصف.
void setWebDocumentScrollLocked(bool locked) {
  try {
    final overflow = locked ? 'hidden' : '';
    html.document.documentElement?.style.overflow = overflow;
    html.document.body?.style.overflow = overflow;
  } catch (_) {}
}
