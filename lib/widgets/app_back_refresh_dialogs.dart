import 'package:flutter/material.dart';

/// حوارات موحّدة: رجوع المتصفح/النظام، وتحديث الصفحة على الويب.
abstract final class AppBackRefreshDialogs {
  static Future<bool> confirmLeaveGuest(BuildContext context, bool isAr) {
    return _confirm(
      context,
      isAr: isAr,
      title: isAr ? 'الخروج من وضع الضيف' : 'Leave guest mode',
      message: isAr
          ? 'هل تريد الخروج والعودة إلى شاشة اختيار الدخول؟'
          : 'Do you want to leave and return to the entry screen?',
    );
  }

  static Future<bool> confirmSignOut(BuildContext context, bool isAr) {
    return _confirm(
      context,
      isAr: isAr,
      title: isAr ? 'تسجيل الخروج' : 'Sign out',
      message: isAr
          ? 'هل تريد تسجيل الخروج والعودة إلى شاشة تسجيل الدخول؟'
          : 'Do you want to sign out and return to the login screen?',
    );
  }

  static Future<bool> confirmSoftRefresh(BuildContext context, bool isAr) {
    return _confirm(
      context,
      isAr: isAr,
      title: isAr ? 'تحديث الصفحة' : 'Refresh page',
      message: isAr
          ? 'هل تريد تحديث هذه الصفحة؟ لن يتم تسجيل خروجك.'
          : 'Refresh this page? You will not be signed out.',
    );
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required bool isAr,
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isAr ? 'لا' : 'No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isAr ? 'نعم' : 'Yes'),
          ),
        ],
      ),
    );
    return result == true;
  }
}
