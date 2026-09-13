/// حالة Caps Lock بعد دمج المصادر — ليست قيمة كلمة المرور.
enum CapsLockSignal {
  on,
  off,
  unknown,
}

extension CapsLockSignalX on CapsLockSignal {
  bool get isOn => this == CapsLockSignal.on;
  bool get isOff => this == CapsLockSignal.off;
  bool get isUnknown => this == CapsLockSignal.unknown;
}

CapsLockSignal capsLockSignalFromBool(bool? value) {
  if (value == null) return CapsLockSignal.unknown;
  return value ? CapsLockSignal.on : CapsLockSignal.off;
}
