import 'package:aqar_user/core/utils/date_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateHelper deed field', () {
    test('fmtDeedFieldPair has no clock and both calendars', () {
      final dt = DateTime(2026, 12, 9, 15, 45);
      final ar = DateHelper.fmtDeedFieldPair(dt, isAr: true);
      final en = DateHelper.fmtDeedFieldPair(dt, isAr: false);
      expect(ar.contains(':'), isFalse);
      expect(en.contains(':'), isFalse);
      expect(ar, contains('2026/12/09'));
      expect(en, contains('2026/12/09'));
      expect(DateHelper.civilDigits(dt), '2026/12/09');
    });

    test('civil date-time uses yyyy/MM/dd and wide gap', () {
      final dt = DateTime(2026, 8, 1, 23, 7);
      final raw = DateHelper.fmtCivilDateTime(dt, isAr: true);
      expect(raw.contains('2026/08/01'), isTrue);
      expect(raw.contains('23:07'), isTrue);
      expect(raw.contains(DateHelper.dateTimeGap), isTrue);
      expect(raw.contains('م'), isFalse);
    });
  });
}
