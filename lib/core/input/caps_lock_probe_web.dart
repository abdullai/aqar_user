// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

bool? _cachedCaps;
bool _listening = false;

void _readCapsFromEvent(html.KeyboardEvent e) {
  try {
    _cachedCaps = e.getModifierState('CapsLock');
  } catch (_) {
    // بعض لوحات الجوال لا تدعم getModifierState.
  }
}

/// محاولة قراءة Caps Lock عبر حدث اصطناعي عند التركيز (ويب ويندوز).
void _probeCapsViaActiveElement() {
  try {
    // لا يوجد API مباشر؛ نعتمد على آخر قراءة من أحداث المفاتيح.
    // إن وُجدت نافذة نشطة، نُبقي الكاش كما هو حتى أول keydown.
  } catch (_) {}
}

void _ensureDomCapsListener() {
  if (_listening) return;
  _listening = true;
  void onKey(html.Event e) {
    if (e is! html.KeyboardEvent) return;
    _readCapsFromEvent(e);
  }

  // capture=true يلتقط الحالة حتى قبل تركيز حقل كلمة المرور.
  html.document.addEventListener('keydown', onKey, true);
  html.document.addEventListener('keyup', onKey, true);
  html.document.addEventListener('keypress', onKey, true);
  html.window.addEventListener('keydown', onKey, true);
  html.window.addEventListener('keyup', onKey, true);

  // عند أي تفاعل بالفأرة قبل الكتابة: لا نعرف Caps بعد، لكن نجهّز المستمع.
  html.document.addEventListener('mousedown', (_) {
    _probeCapsViaActiveElement();
  }, true);
  html.document.addEventListener('focusin', (_) {
    _probeCapsViaActiveElement();
  }, true);
}

/// حالة Caps Lock من DOM (أكثر دقة على ويب ويندوز من lockModes وحدها).
/// على ويب الجوال غالباً null حتى أول ضغطة — الاعتماد على استدلال الأحرف الكبيرة.
bool? probeBrowserCapsLock() {
  _ensureDomCapsListener();
  return _cachedCaps;
}

/// يفرض تحديث الكاش من حدث لوحة مفاتيح إن وُجد؛ يُستدعى بعد التركيز.
void refreshBrowserCapsLockCache() {
  _ensureDomCapsListener();
}
