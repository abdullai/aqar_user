import 'package:aqar_user/core/auth/otp_autofill.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FormFieldHtmlAttribute.oneTimeCode is the WHATWG autocomplete value', () {
    expect(FormFieldHtmlAttribute.oneTimeCode, 'one-time-code');
    expect(OtpAutofill.htmlAutocomplete, FormFieldHtmlAttribute.oneTimeCode);
  });

  test('OtpAutofill hints keep AutofillHints.oneTimeCode', () {
    expect(OtpAutofill.hints, contains(AutofillHints.oneTimeCode));
    expect(OtpAutofill.length, 6);
  });

  test('sequentialValue spreads six digits without dumping all in one cell', () {
    final v = OtpAutofill.sequentialValue('١٢٣٤٥٦');
    expect(v.text, '123456');
    expect(v.text.length, 6);
    expect(v.selection.isCollapsed, isTrue);
    expect(v.selection.baseOffset, 6);
  });

  test('sequentialValue clips longer codes and ignores junk', () {
    expect(OtpAutofill.sequentialValue('ab12-34-56-99').text, '123456');
    expect(OtpAutofill.sequentialValue('12').text, '12');
    expect(OtpAutofill.sequentialValue('no-digits').text, isEmpty);
  });
}
