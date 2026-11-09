import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/widgets/aqar_signature_home_banner.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('Arabic home identity works in $mode mode', (tester) async {
      var mapOpened = false;
      var compareOpened = false;
      final theme =
          mode == ThemeMode.dark ? ThemeData.dark() : ThemeData.light();

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: AqarSignatureHomeBanner(
              isArabic: true,
              listingCount: 2,
              requestCount: 3,
              onExploreMap: () => mapOpened = true,
              onCompareProperties: () => compareOpened = true,
            ),
          ),
        ),
      );

      expect(find.text('وجهتك العقارية،\nبرؤية أوضح.'), findsOneWidget);
      expect(find.text('2 عقار'), findsOneWidget);
      expect(find.text('3 طلب سوق'), findsOneWidget);
      await tester.tap(find.text('استكشف الخريطة'));
      expect(mapOpened, isTrue);
      await tester.tap(find.text('قارن العقارات'));
      expect(compareOpened, isTrue);
    });
  }
}
