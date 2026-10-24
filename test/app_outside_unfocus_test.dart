import 'package:aqar_user/core/gestures/app_outside_unfocus.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('touch scrolling outside a focused field keeps focus', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppOutsideUnfocus(
          child: Scaffold(
            body: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              child: Column(
                children: [
                  AqarTextFormField(focusNode: focusNode),
                  const SizedBox(height: 900),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.dragFrom(const Offset(180, 500), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('tapping outside a focused field dismisses focus',
      (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppOutsideUnfocus(
          child: Scaffold(
            body: Column(
              children: [
                AqarTextFormField(focusNode: focusNode),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(const Offset(180, 120));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  });
}
