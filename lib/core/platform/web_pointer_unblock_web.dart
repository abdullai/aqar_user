// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

int _lastUnblockMs = 0;

/// يزيل placeholder semantics العالق فقط — نادراً ومحدوداً.
///
/// **لا** تلمس `flt-glass-pane` ولا `flt-semantics-host` بالكامل:
/// تعديلها مع كل نقرة كان يجمّد اللمس بعد الدخول/تبديل التبويب.
void webUnblockPointerDom() {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    // أقصى مرة كل ثانيتين — يكفي ضد #175119 دون عاصفة DOM.
    if (now - _lastUnblockMs < 2000) return;
    _lastUnblockMs = now;

    final w = html.window.innerWidth ?? 0;
    final h = html.window.innerHeight ?? 0;
    if (w <= 0 || h <= 0) return;

    for (final node
        in html.document.querySelectorAll('flt-semantics-placeholder')) {
      final rect = node.getBoundingClientRect();
      final covers = rect.width >= w * 0.85 && rect.height >= h * 0.85;
      if (!covers) continue;
      // pointer-events فقط — لا opacity:0 (كانت تُربك محرك الإيماءات).
      node.style.setProperty('pointer-events', 'none');
    }
  } catch (_) {}
}
