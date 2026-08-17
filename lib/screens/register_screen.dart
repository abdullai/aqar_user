import 'package:flutter/material.dart';

import 'password_setup.dart';

/// إنشاء حساب — يفتح مباشرة نموذج البيانات الموحّد (بدون شاشة نوع الحساب/فال المنفصلة).
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PasswordSetupScreen();
  }
}
