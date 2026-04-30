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
