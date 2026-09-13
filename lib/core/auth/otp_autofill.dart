import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'in_app_otp_handoff.dart';
import 'otp_autofill_html_stub.dart'
    if (dart.library.js_interop) 'otp_autofill_html_web.dart'
    if (dart.library.html) 'otp_autofill_html_web.dart' as html_otp;

/// تلميح HTML `autocomplete` لحقول الرمز المؤقت على الويب (WHATWG).
abstract final class FormFieldHtmlAttribute {
  static const String oneTimeCode = 'one-time-code';
}

/// تلميحات النظام + توزيع الرمز على خانات OTP الست.
abstract final class OtpAutofill {
  static const int length = InAppOtpHandoff.otpLen;

  static const List<String> hints = [AutofillHints.oneTimeCode];

  static const String htmlAutocomplete = FormFieldHtmlAttribute.oneTimeCode;

  static String? digitsOf(String? raw, {int len = length}) =>
      InAppOtpHandoff.digitsFromAny(raw, len: len);

  /// قيمة واحدة تُوزَّع على الخانات 1…6 عبر المتحكّم المشترك لـ PinCode.
  static TextEditingValue sequentialValue(String raw, {int len = length}) {
    final only = digitsOf(raw, len: len) ?? '';
    final take = only.length > len ? only.substring(0, len) : only;
    return TextEditingValue(
      text: take,
      selection: TextSelection.collapsed(offset: take.length),
    );
  }

  static void stampFocusedHtmlField({int maxLength = length}) {
    html_otp.stampFocusedOtpField(
      autocomplete: htmlAutocomplete,
      maxLength: maxLength,
    );
  }
}
