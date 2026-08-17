import 'package:aqar_user/core/input/input_normalizers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('input_normalizers', () {
    test('normalizeAsciiDigits', () {
      expect(normalizeAsciiDigits('٠١٢'), '012');
      expect(normalizeAsciiDigits('۱۲۳'), '123');
    });

    test('normalizeUnifiedNationalInput strips noon', () {
      expect(normalizeUnifiedNationalInput('ن7001234567'), '7001234567');
      expect(normalizeUnifiedNationalInput('7001234567'), '7001234567');
    });

    test('isValidUnifiedNationalNumberDigits', () {
      expect(isValidUnifiedNationalNumberDigits('7001234567'), true);
      expect(isValidUnifiedNationalNumberDigits('8001234567'), false);
      expect(isValidUnifiedNationalNumberDigits('700123456'), false);
    });

    test('emailContainsArabicScript', () {
      expect(emailContainsArabicScript('a@b.com'), false);
      expect(emailContainsArabicScript('test@ميل.com'), true);
    });

    test('suggestEmailDomainFix', () {
      expect(suggestEmailDomainFix('x@gmailcom'), 'x@gmail.com');
      expect(suggestEmailDomainFix('x@gmail.com'), null);
    });
  });
}
