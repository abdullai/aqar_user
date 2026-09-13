import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'caps_lock_signal.dart';

/// هل يمكن الوثوق بـ [HardwareKeyboard.lockModesEnabled] لهذه المنصة؟
///
/// ويب ويندوز: غالباً `false` بينما Caps شغال — لا يُعتمد.
/// لوحات الجوال الناعمة: نفس المشكلة.
bool defaultHardwareCapsTrusted() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
      return true;
    default:
      return false;
  }
}

bool defaultPreferBrowserCaps() {
  if (!kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      // getModifierState('CapsLock') غالباً false على متصفح الجوال.
      return false;
    default:
      return true;
  }
}

CapsLockSignal readHardwareCapsLockSignal() {
  try {
    final on = HardwareKeyboard.instance.lockModesEnabled
        .contains(KeyboardLockMode.capsLock);
    return on ? CapsLockSignal.on : CapsLockSignal.off;
  } catch (_) {
    return CapsLockSignal.unknown;
  }
}
