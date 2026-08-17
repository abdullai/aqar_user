import 'package:flutter/material.dart';

/// نتيجة نافذة الخروج من نموذج غير منشور.
enum FormExitChoice { keepEditing, saveDraft, discard }

/// نافذة موحّدة: هل تريد الإغلاق؟ — حفظ كمسودة / نعم (تصفير) / متابعة.
Future<FormExitChoice?> showFormExitConfirmDialog({
  required BuildContext context,
  required bool isAr,
  String? title,
  String? body,
}) {
  return showDialog<FormExitChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.edit_note_outlined, color: cs.primary, size: 32),
        title: Text(
          title ??
              (isAr ? 'هل تريد الإغلاق؟' : 'Leave this form?'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          body ??
              (isAr
                  ? 'لم تُكمل النشر بعد. يمكنك حفظ ما أدخلته كمسودة والعودة لاحقاً، أو الخروج وتصفير الحقول.'
                  : 'You have not finished publishing yet. Save as draft to continue later, or leave and clear the fields.'),
          style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, FormExitChoice.keepEditing),
            child: Text(isAr ? 'متابعة التحرير' : 'Keep editing'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, FormExitChoice.saveDraft),
            child: Text(isAr ? 'حفظ كمسودة' : 'Save as draft'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.pop(ctx, FormExitChoice.discard),
            child: Text(isAr ? 'نعم — تصفير والخروج' : 'Yes — clear & leave'),
          ),
        ],
      );
    },
  );
}
