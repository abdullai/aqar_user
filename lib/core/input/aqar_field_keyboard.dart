import 'package:flutter/services.dart';

import 'saudi_input_formatters.dart';

/// لوحة أرقام ذكية: أرقام لاتينية دائماً + لوحة رقمية على الجوال.
abstract final class AqarFieldKeyboard {
  static bool isNumericType(TextInputType? type) {
    if (type == null) return false;
    return type.index == TextInputType.number.index ||
        type.index == TextInputType.phone.index;
  }

  static bool isDecimalType(TextInputType? type) {
    if (type == null) return false;
    return type.index == TextInputType.number.index && type.decimal == true;
  }

  static bool isPhoneType(TextInputType? type) {
    return type != null && type.index == TextInputType.phone.index;
  }

  /// لوحة الجوال: أرقام فقط (أو عشرية). سطح المكتب يبقى لوحة كاملة مع تحويل الأرقام.
  static TextInputType resolve(
    TextInputType? requested, {
    required bool compactTouch,
  }) {
    if (requested == null || !isNumericType(requested)) {
      return requested ?? TextInputType.text;
    }
    if (isPhoneType(requested)) return TextInputType.phone;
    if (isDecimalType(requested)) {
      return const TextInputType.numberWithOptions(
        decimal: true,
        signed: false,
      );
    }
    if (compactTouch) {
      return const TextInputType.numberWithOptions(
        decimal: false,
        signed: false,
      );
    }
    return const TextInputType.numberWithOptions(
      decimal: false,
      signed: false,
    );
  }

  static bool alreadyHasLatinDigits(List<TextInputFormatter> list) {
    return list.any(
      (f) =>
          f is ArabicDigitsToLatinFormatter || f is LatinDecimalNumberFormatter,
    );
  }

  /// أي حقل: الأرقام العربية/الفارسية تتحول فوراً إلى لاتينية.
  static List<TextInputFormatter> mergeLatinDigitsAlways({
    required List<TextInputFormatter> existing,
  }) {
    if (alreadyHasLatinDigits(existing)) return existing;
    return [const ArabicDigitsToLatinFormatter(), ...existing];
  }

  static List<TextInputFormatter> mergeNumericFormatters({
    required TextInputType? keyboardType,
    required List<TextInputFormatter> existing,
  }) {
    if (!isNumericType(keyboardType)) {
      return mergeLatinDigitsAlways(existing: existing);
    }
    if (alreadyHasLatinDigits(existing)) return existing;
    if (isDecimalType(keyboardType)) {
      return [const LatinDecimalNumberFormatter(), ...existing];
    }
    return [const ArabicDigitsToLatinFormatter(), ...existing];
  }

  /// حقل متعدد الأسطر: Enter ينزل سطراً (ويب ويندوز كان يُعامل كإرسال).
  static bool isMultilineField({
    required int? maxLines,
    required int? minLines,
    required bool obscureText,
  }) {
    if (obscureText) return false;
    if (maxLines == 1) return false;
    if (minLines != null && minLines > 1) return true;
    if (maxLines == null) return true;
    return maxLines > 1;
  }

  static TextInputType keyboardForField({
    required TextInputType? requested,
    required bool compactTouch,
    required bool multiline,
  }) {
    final resolved = resolve(requested, compactTouch: compactTouch);
    if (multiline && !isNumericType(resolved)) {
      return TextInputType.multiline;
    }
    return resolved;
  }

  static TextInputAction? actionForField({
    required TextInputAction? requested,
    required bool multiline,
  }) {
    if (requested != null) return requested;
    if (multiline) return TextInputAction.newline;
    return TextInputAction.next;
  }

  static TextDirection? textDirectionFor(
    TextInputType? keyboardType,
    TextDirection? requested,
  ) {
    if (requested != null) return requested;
    if (isNumericType(keyboardType)) return TextDirection.ltr;
    return null;
  }
}
