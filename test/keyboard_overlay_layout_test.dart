import 'package:aqar_user/core/gestures/app_keyboard_inset.dart';
import 'package:aqar_user/core/gestures/app_keyboard_stable.dart';
import 'package:aqar_user/widgets/nafath_login_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Nafath sheet scrolls within the visible keyboard lane',
      (tester) async {
    tester.view.physicalSize = const Size(390, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> openSheet(BuildContext context) =>
        showAppModalBottomSheet<void>(
          context: context,
          builder: (_) => const NafathLoginSheet(isAr: true),
        );

    Widget app(double inset) => AppKeyboardScope(
          inset: inset,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => openSheet(context),
                    child: const Text('Open Nafath'),
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(300));
    await tester.tap(find.text('Open Nafath'));
    await tester.pumpAndSettle();

    expect(find.text('الدخول عبر نفاذ'), findsOneWidget);
    final idField = tester.widget<TextField>(find.byType(TextField));
    expect(idField.controller!.text, isEmpty);
    await tester.enterText(find.byType(TextField), '۱۲٣45٦');
    await tester.pump();
    expect(idField.controller!.text, '123456');
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('متابعة عبر نفاذ'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
