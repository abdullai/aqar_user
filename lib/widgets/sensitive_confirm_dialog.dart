import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../core/gestures/app_keyboard_popups.dart';

/// حوار موحّد لخطوات لا رجعة فيها أو حساسة — النصوص من الترجمة.
Future<bool?> showSensitiveConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
}) {
  final t = AppLocalizations.of(context);
  return showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(message, style: const TextStyle(height: 1.35)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel ?? t?.sensitiveActionCancel ?? 'Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? t?.sensitiveActionConfirm ?? 'Confirm'),
          ),
        ],
      );
    },
  );
}
