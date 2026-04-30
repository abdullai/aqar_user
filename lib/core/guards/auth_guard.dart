// lib/core/guards/auth_guard.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session/app_session.dart';

Future<bool> requireAuth(
  BuildContext context, {
  required String reason,
  VoidCallback? onAuthed,
}) async {
  final session = context.read<AppSession>();
  if (session.isLoggedIn) {
    onAuthed?.call();
    return true;
  }

  // ✅ خزن Navigator قبل أي await حتى لا تستخدم context بعد async gap
  final nav = Navigator.of(context, rootNavigator: true);

  final go = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('تسجيل الدخول مطلوب'),
      content: Text(reason),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(_, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(_, true),
          child: const Text('تسجيل الدخول'),
        ),
      ],
    ),
  );

  if (go == true) {
    await nav.pushNamed('/login');

    // ✅ بعد الرجوع، اقرأ Provider (لن تحتاج context إذا أخذت المرجع مسبقًا)
    if (session.isLoggedIn) {
      onAuthed?.call();
      return true;
    }
  }

  return false;
}