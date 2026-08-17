import 'package:flutter/material.dart';

import '../core/haptics/app_haptics.dart';
import '../core/config/app_config.dart';

/// Standard Yes/No confirmation for sensitive actions (delete, exit, publish, …).
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Yes',
  String cancelLabel = 'No',
  bool isDanger = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(
                AppConfig.minInteractiveTarget,
                AppConfig.minInteractiveTarget,
              ),
            ),
            onPressed: () {
              AppHaptics.light();
              Navigator.of(ctx).pop(false);
            },
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(
                AppConfig.minInteractiveTarget,
                AppConfig.minInteractiveTarget,
              ),
              backgroundColor: isDanger ? cs.error : cs.primary,
              foregroundColor: isDanger ? cs.onError : cs.onPrimary,
            ),
            onPressed: () {
              AppHaptics.light();
              Navigator.of(ctx).pop(true);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return r == true;
}
