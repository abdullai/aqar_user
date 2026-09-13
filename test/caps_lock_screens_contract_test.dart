import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يمنع إعادة منطق Caps Lock داخل الشاشات — المصدر الوحيد CapsAwarePasswordField.
void main() {
  const screens = [
    'lib/screens/login_screen.dart',
    'lib/screens/password_setup.dart',
    'lib/screens/fast_login_screen.dart',
    'lib/screens/change_password_screen.dart',
    'lib/screens/reset_password_screen.dart',
    'lib/screens/register_screen.dart',
  ];

  test('account password screens use CapsAwarePasswordField, not local Caps Lock',
      () {
    final login = File('lib/screens/login_screen.dart').readAsStringSync();
    expect(login.contains('CapsAwarePasswordField'), isTrue);
    expect(login.contains('_capsLockPassword'), isFalse);
    expect(login.contains('_capsLockLatched'), isFalse);
    expect(login.contains('_liveUppercaseMode'), isFalse);
    expect(login.contains('_loginHardwareCapsKeyHandler'), isFalse);
    expect(login.contains('_syncCapsLockFromHardware'), isFalse);
    expect(login.contains('CapsLockTracker('), isFalse);
    expect(login.contains('lockModesEnabled'), isFalse);

    final field = File('lib/widgets/caps_aware_password_field.dart')
        .readAsStringSync();
    expect(field.contains('capsLockOn'), isTrue);
    expect(field.contains('Caps Lock مفعّل'), isFalse);
    expect(field.contains('Caps Lock is ON'), isFalse);

    for (final path in screens) {
      final src = File(path).readAsStringSync();
      if (path.endsWith('register_screen.dart')) {
        expect(src.contains('PasswordSetupScreen'), isTrue);
        continue;
      }
      expect(
        src.contains('CapsAwarePasswordField'),
        isTrue,
        reason: path,
      );
      expect(src.contains('CapsLockTracker('), isFalse, reason: path);
    }
  });
}
