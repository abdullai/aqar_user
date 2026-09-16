import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/utils/app_money.dart';

void main() {
  test('Arabic money text places the riyal mark before the number', () {
    final s = AppMoney.sarPhrase('3,876', isAr: true);
    expect(s.contains('3,876'), isTrue);
    expect(s.contains(AppMoney.saudiRiyalSignCompat), isTrue);
    expect(s.contains('ر.س'), isFalse);
    expect(s, contains('${AppMoney.saudiRiyalSignCompat}3,876'));
  });

  test('English money text is the number then SAR', () {
    expect(AppMoney.sarPhrase('3,876', isAr: false), '3,876 SAR');
    expect(
      AppMoney.formatWithCurrencyCode(3876, isAr: false, maxFractionDigits: 0),
      '3,876 SAR',
    );
  });

  test('stripSarMarks removes riyal abbreviations and isolates', () {
    expect(AppMoney.stripSarMarks('ر.س 3,876').trim(), '3,876');
    expect(AppMoney.stripSarMarks('3,876 SAR').trim(), '3,876');
    expect(
      AppMoney.stripSarMarks(AppMoney.sarPhrase('1,279', isAr: true)).trim(),
      '1,279',
    );
  });
}
