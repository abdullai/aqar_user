import 'package:flutter/services.dart';

/// يمنع تسرّب أرقام حقل الهوية إلى كلمة المرور عند الانتقال السريع بين الحقلين.
class PasswordLeadingDigitBleedGuard extends TextInputFormatter {
  PasswordLeadingDigitBleedGuard({required this.isActive});

  final bool Function() isActive;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!isActive()) return newValue;
    if (oldValue.text.isNotEmpty) return newValue;
    final t = newValue.text;
    if (t.length <= 2 && RegExp(r'^\d+$').hasMatch(t)) {
      return oldValue;
    }
    return newValue;
  }
}
