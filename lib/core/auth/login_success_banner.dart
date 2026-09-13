import 'package:flutter/material.dart';

import '../../services/user_session_coordination_service.dart';

/// شريط نجاح الدخول — يُعرض فوراً أو يُؤجَّل حتى يتوفر سياق التنقّل.
abstract final class LoginSuccessBanner {
  static bool _pending = false;
  static bool _pendingIsAr = true;

  static Future<void> showOrQueue(
    BuildContext? context, {
    required bool isAr,
  }) async {
    _pendingIsAr = isAr;
    final ctx = context ??
        UserSessionCoordinationService.navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) {
      _pending = true;
      return;
    }
    _pending = false;
    final msg = isAr ? 'تم تسجيل الدخول بنجاح' : 'Signed in successfully';
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  static Future<void> consumeIfPending(BuildContext context) async {
    if (!_pending) return;
    await showOrQueue(context, isAr: _pendingIsAr);
  }
}
