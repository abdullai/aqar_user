import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/fast_login_service.dart';

/// اقتراح تفعيل الدخول السريع / البيومتري (جوال فقط) بعد اجتياز البوابات.
class FastLoginOfferDialog {
  static Future<void> show(BuildContext context, {required bool isAr}) async {
    if (kIsWeb) return;
    final t = AppLocalizations.of(context);
    final bioOk = await FastLoginService.canCheckBiometrics();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t?.fastLoginOfferTitle ?? ''),
          content: SingleChildScrollView(
            child: Text(
              t?.fastLoginOfferBody ?? '',
              style: const TextStyle(height: 1.35),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await FastLoginService.markPromptLater();
                await FastLoginService.setPromptLastShownNow();
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                Navigator.of(context).pushNamed('/settings');
              },
              child: Text(t?.fastLoginOfferOpenSettings ?? ''),
            ),
            if (bioOk) ...[
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () async {
                  final ok = await FastLoginService.authenticateBiometric(
                    isAr: isAr,
                  );
                  if (ok) {
                    await FastLoginService.setBiometricEnabled(true);
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: Text(t?.fastLoginOfferBiometric ?? ''),
              ),
            ],
            const SizedBox(height: 6),
            TextButton(
              onPressed: () async {
                await FastLoginService.markPromptLater();
                await FastLoginService.setPromptLastShownNow();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(t?.fastLoginOfferRemindLater ?? ''),
            ),
            TextButton(
              onPressed: () async {
                await FastLoginService.markPromptNever();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(t?.fastLoginOfferNotNow ?? ''),
            ),
          ],
        );
      },
    );
  }
}
