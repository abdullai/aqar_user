import 'dart:html' as html;

/// إزالة `#splash` من [web/index.html] بعد جاهزية الواجهة.
void removeWebHtmlSplash() {
  try {
    html.document.getElementById('splash')?.remove();
    html.document.body?.style.background = 'transparent';
  } catch (_) {}
}
