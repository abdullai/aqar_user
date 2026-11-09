import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/branding/app_branding.dart';

void main() {
  testWidgets('login logo scales to a short phone viewport', (tester) async {
    late double logoWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 620)),
          child: Builder(
            builder: (context) {
              logoWidth = AppBranding.loginHeroLogoSize(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(logoWidth, closeTo(151.2, 0.1));
    expect(logoWidth / 3, lessThan(60));
  });

  testWidgets('login logo has a desktop size cap', (tester) async {
    late double logoWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1440, 1000)),
          child: Builder(
            builder: (context) {
              logoWidth = AppBranding.loginHeroLogoSize(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(logoWidth, 360);
  });

  testWidgets('login logo shrinks while the keyboard occupies the viewport',
      (tester) async {
    late double logoWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 800),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
          child: Builder(
            builder: (context) {
              logoWidth = AppBranding.loginHeroLogoSize(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(logoWidth, 108);
  });
}
