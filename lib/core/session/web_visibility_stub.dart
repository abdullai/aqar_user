/// يُستبدل بـ [web_visibility_web] على المنصّة ذات `dart:html`.
void listenDocumentVisibilityHidden(void Function() onHidden) {}

/// عند إعادة إظهار التبويب (ويب فقط؛ الـ stub لا يفعل شيئاً).
void listenDocumentVisibilityShown(void Function() onShown) {}

/// عند تجميد التبويب (Page Lifecycle freeze) — ويب فقط.
void listenDocumentFreeze(void Function() onFreeze) {}

/// إغلاق التبويب/النافذة (ويب فقط).
void listenDocumentPageHide(
  void Function({required bool persisted}) onPageHide,
) {}

void listenDocumentPageShow(
  void Function({required bool persisted}) onPageShow,
) {}

void setWebDocumentScrollLocked(bool locked) {}
