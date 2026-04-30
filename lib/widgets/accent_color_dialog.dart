import 'package:flutter/material.dart';

import '../core/theme/app_accent.dart';
import '../core/config/app_config.dart';
import '../l10n/app_localizations.dart';

/// حوار اختيار لون التميّز (أول دخول أو من الإعدادات).
Future<void> showAccentColorFirstRunDialog(BuildContext context) async {
  final t = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: Text(t.accentColorDialogTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.accentColorDialogBody,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 10),
              Text(
                t.accentColorSkipKeepsDefault,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.88),
                  height: 1.3,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: List.generate(AppConfig.primaryAccentCount, (i) {
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        await setAppAccentIndex(i);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: Ink(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppConfig.accentSeedAt(i),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.accentColorLater),
          ),
        ],
      );
    },
  );
}
