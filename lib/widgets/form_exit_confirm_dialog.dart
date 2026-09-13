import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../core/gestures/app_keyboard_popups.dart';

/// نتيجة نافذة الخروج من نموذج غير منشور.
enum FormExitChoice { keepEditing, saveDraft, discard }

SnackBar formExitNoticeSnackBar(String message, {Color? background}) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 8),
    backgroundColor: background,
    content: Text(
      message,
      maxLines: 8,
      style: const TextStyle(height: 1.45, fontWeight: FontWeight.w700),
    ),
  );
}

void showFormExitNotice(
  BuildContext context,
  String message, {
  Color? background,
}) {
  final root = Navigator.maybeOf(context, rootNavigator: true)?.context;
  final messenger = (root != null ? ScaffoldMessenger.maybeOf(root) : null) ??
      ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(formExitNoticeSnackBar(message, background: background));
}

Future<bool> showFormExitLeaveConfirmDialog({
  required BuildContext context,
  required bool isAr,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: false,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: cs.error, size: 32),
        title: Text(
          l10n?.formExitLeaveTitle ??
              (isAr ? 'الخروج ومسح الحقول؟' : 'Leave and clear the fields?'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n?.formExitLeaveBody ??
                  (isAr
                      ? 'سيُمسح كل ما أدخلته في الحقول. لن تُحفظ كمسودة على هذا الجهاز. أكّد للخروج، أو ألغِ للبقاء في موضعك الحالي.'
                      : 'Everything you typed will be cleared. Nothing will be kept as a draft on this device. Confirm to leave, or cancel to stay where you are.'),
              style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      l10n?.formExitCancel ?? (isAr ? 'إلغاء' : 'Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      l10n?.formExitConfirm ?? (isAr ? 'تأكيد' : 'Confirm'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return confirmed == true;
}

/// نافذة موحّدة: تحرير | حفظ في صف، وخروج بعرض الصفين.
Future<FormExitChoice?> showFormExitConfirmDialog({
  required BuildContext context,
  required bool isAr,
  String? title,
  String? body,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppDialog<FormExitChoice>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: false,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.edit_note_outlined, color: cs.primary, size: 32),
        title: Text(
          title ??
              (isAr ? 'هل تريد الإغلاق؟' : 'Leave this form?'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                body ??
                    l10n?.formExitBody ??
                    (isAr
                        ? 'لم يُنشر بعد. تابع التحرير من موضعك الحالي، أو احفظ المسودة على هذا الجهاز لهذه الجلسة فقط، أو اخرج وامسح الحقول.'
                        : 'This is not published yet. Continue from where you are, save a draft on this device for this session only, or leave and clear the fields.'),
                style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(ctx, FormExitChoice.keepEditing),
                    child: Text(
                      l10n?.formExitKeepEditing ??
                          (isAr ? 'تحرير' : 'Edit'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () =>
                        Navigator.pop(ctx, FormExitChoice.saveDraft),
                    child: Text(
                      l10n?.formExitSaveDraft ?? (isAr ? 'حفظ' : 'Save'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () async {
                final ok = await showFormExitLeaveConfirmDialog(
                  context: ctx,
                  isAr: isAr,
                );
                if (!ctx.mounted || !ok) return;
                Navigator.pop(ctx, FormExitChoice.discard);
              },
              child: Text(
                l10n?.formExitLeave ?? (isAr ? 'خروج' : 'Leave'),
              ),
            ),
          ],
          ),
        ),
      );
    },
  );
}
