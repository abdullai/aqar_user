import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/fast_login_service.dart';

/// اقتراح تفعيل الدخول السريع بعد اجتياز البوابات.
/// على الويب: PIN فقط. على الجوال: إعدادات + بصمة إن توفرت.
class FastLoginOfferDialog {
  static Future<void> show(BuildContext context, {required bool isAr}) async {
    final t = AppLocalizations.of(context);
    final bioOk = !kIsWeb && await FastLoginService.canCheckBiometrics();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final narrow = MediaQuery.sizeOf(ctx).width < 420;

        Widget stretchBtn({
          required VoidCallback onPressed,
          required Widget child,
          required bool filled,
          bool outlined = false,
        }) {
          final button = filled
              ? FilledButton(
                  onPressed: onPressed,
                  child: child,
                )
              : outlined
                  ? OutlinedButton(
                      onPressed: onPressed,
                      child: child,
                    )
                  : TextButton(
                      onPressed: onPressed,
                      child: child,
                    );
          return SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: narrow ? 160 : 220,
                  maxWidth: narrow
                      ? MediaQuery.sizeOf(ctx).width - 72
                      : 360,
                ),
                child: button,
              ),
            ),
          );
        }

        return AlertDialog(
          title: Text(
            t?.fastLoginOfferTitle ??
                (isAr ? 'تفعيل الدخول السريع' : 'Enable quick unlock'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  kIsWeb
                      ? (isAr
                          ? 'فعّل رمز PIN لإعادة فتح جلستك بعد انقضاء المهلة دون إدخال اسم المستخدم من جديد. هذا أكثر أماناً من ترك الجلسة مفتوحة.'
                          : 'Enable a PIN to unlock after idle timeout without re-entering your username. Safer than leaving the session open.')
                      : (t?.fastLoginOfferBody ?? ''),
                  style: const TextStyle(height: 1.35),
                ),
                const SizedBox(height: 18),
                stretchBtn(
                  filled: true,
                  onPressed: () async {
                    await FastLoginService.markPromptLater();
                    await FastLoginService.setPromptLastShownNow();
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    Navigator.of(context, rootNavigator: true)
                        .pushNamed('/settings');
                  },
                  child: Text(
                    t?.fastLoginOfferOpenSettings ??
                        (isAr ? 'فتح الإعدادات' : 'Open settings'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (bioOk) ...[
                  const SizedBox(height: 8),
                  stretchBtn(
                    filled: false,
                    outlined: true,
                    onPressed: () async {
                      final ok = await FastLoginService.authenticateBiometric(
                        isAr: isAr,
                      );
                      if (ok) {
                        await FastLoginService.setBiometricEnabled(true);
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: Text(
                      t?.fastLoginOfferBiometric ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                stretchBtn(
                  filled: false,
                  onPressed: () async {
                    await FastLoginService.markPromptLater();
                    await FastLoginService.setPromptLastShownNow();
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: Text(
                    t?.fastLoginOfferRemindLater ??
                        (isAr ? 'ذكرني لاحقاً' : 'Remind me later'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                ),
                stretchBtn(
                  filled: false,
                  onPressed: () async {
                    await FastLoginService.markPromptNever();
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: Text(
                    t?.fastLoginOfferNotNow ??
                        (isAr ? 'لا شكراً' : 'No thanks'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          actions: const <Widget>[],
        );
      },
    );
  }
}
