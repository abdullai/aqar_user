import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AqarLocaleScript { any, arabic, english }

/// يمنع إدخال حروف بلغة غير متوافقة مع واجهة المستخدم.
class LocaleTextInputFormatter extends TextInputFormatter {
  LocaleTextInputFormatter({
    required this.script,
    this.onRejected,
  });

  final AqarLocaleScript script;
  final VoidCallback? onRejected;

  static final RegExp _arabicBlock =
      RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]');
  static final RegExp _latinBlock = RegExp(r'[A-Za-z]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (script == AqarLocaleScript.any) return newValue;
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final reject = switch (script) {
      AqarLocaleScript.arabic => _latinBlock.hasMatch(text),
      AqarLocaleScript.english => _arabicBlock.hasMatch(text),
      AqarLocaleScript.any => false,
    };
    if (!reject) return newValue;

    onRejected?.call();
    return oldValue;
  }
}

AqarLocaleScript localeScriptFromLang(String langCode) {
  return langCode.toLowerCase() == 'en'
      ? AqarLocaleScript.english
      : AqarLocaleScript.arabic;
}

String localeInputRejectionMessage({
  required bool isAr,
  required AqarLocaleScript script,
}) {
  return switch (script) {
    AqarLocaleScript.arabic => isAr
        ? 'يُرجى الكتابة باللغة العربية في هذا الحقل.'
        : 'Please type in Arabic in this field.',
    AqarLocaleScript.english => isAr
        ? 'يُرجى الكتابة باللغة الإنجليزية في هذا الحقل.'
        : 'Please type in English in this field.',
    AqarLocaleScript.any => '',
  };
}

List<TextInputFormatter> mergeLocaleFormatters({
  required AqarLocaleScript script,
  required VoidCallback? onRejected,
  List<TextInputFormatter>? existing,
}) {
  if (script == AqarLocaleScript.any) return existing ?? const [];
  return [
    LocaleTextInputFormatter(script: script, onRejected: onRejected),
    ...?existing,
  ];
}
