import 'caps_lock_probe_stub.dart'
    if (dart.library.js_interop) 'caps_lock_probe_web.dart'
    if (dart.library.html) 'caps_lock_probe_web.dart' as impl;

import 'caps_lock_signal.dart';

/// قراءة Caps Lock من المتصفح عند توفرها (ويب). وإلا [CapsLockSignal.unknown].
CapsLockSignal probeBrowserCapsLock() {
  try {
    return capsLockSignalFromBool(impl.probeBrowserCapsLock());
  } catch (_) {
    return CapsLockSignal.unknown;
  }
}

/// تجهيز مستمع DOM (ويب) — آمن للاستدعاء المتكرر.
void retainBrowserCapsLockProbe() {
  try {
    impl.retainBrowserCapsLockProbe();
  } catch (_) {}
}

void releaseBrowserCapsLockProbe() {
  try {
    impl.releaseBrowserCapsLockProbe();
  } catch (_) {}
}

/// توافق مع الاستدعاءات القديمة — لا يزيد مرجع المستمع.
void refreshBrowserCapsLockCache() {
  try {
    impl.refreshBrowserCapsLockCache();
  } catch (_) {}
}
