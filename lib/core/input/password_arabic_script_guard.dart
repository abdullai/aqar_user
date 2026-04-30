import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'saudi_input_formatters.dart';

/// يمنع الحروف العربية (والسريانية/العرضية) في كلمة المرور ويستدعي [onBlocked] عند محاولة الإدخال.
class BlockArabicScriptInPasswordFormatter extends TextInputFormatter {
  BlockArabicScriptInPasswordFormatter({required this.onBlocked});

  final VoidCallback onBlocked;

  static final RegExp _arabicScript = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!_arabicScript.hasMatch(newValue.text)) return newValue;
    onBlocked();
    final cleaned = newValue.text.replaceAll(_arabicScript, '');
    final removed = newValue.text.length - cleaned.length;
    var end = newValue.selection.end - removed;
    end = end.clamp(0, cleaned.length);
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: end),
    );
  }
}

/// حوار يُغلق بالزر أو بالضغط خارج الإطار.
Future<void> showPasswordArabicNotAllowedDialog(
  BuildContext context, {
  required bool isAr,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        title: Text(
          isAr ? 'تنبيه' : 'Notice',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          isAr
              ? 'كلمة المرور لا تقبل الحروف العربية. استخدم الأحرف الإنجليزية مع الأرقام والرموز الآمنة.'
              : 'Passwords cannot include Arabic letters. Use Latin letters, numbers, and symbols.',
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isAr ? 'حسناً' : 'OK'),
          ),
        ],
      );
    },
  );
}

/// ترتيب: تحويل الأرقام العربية/الفارسية ثم منع الحروف العربية.
List<TextInputFormatter> passwordArabicGuardFormatters({
  required VoidCallback onArabicScriptBlocked,
}) {
  return [
    ArabicDigitsToLatinFormatter(),
    BlockArabicScriptInPasswordFormatter(onBlocked: onArabicScriptBlocked),
  ];
}
