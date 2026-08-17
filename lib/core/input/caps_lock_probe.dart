import 'caps_lock_probe_stub.dart'
    if (dart.library.html) 'caps_lock_probe_web.dart' as impl;

/// قراءة حالة Caps Lock من المتصفح عند توفرها (ويب).
bool? probeBrowserCapsLock() => impl.probeBrowserCapsLock();

/// تجهيز مستمع DOM قبل التركيز على حقل كلمة المرور.
void refreshBrowserCapsLockCache() {
  try {
    impl.refreshBrowserCapsLockCache();
  } catch (_) {}
}
