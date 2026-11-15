import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Next advances to the following field', (tester) async {
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AqarTextField(
                focusNode: firstFocus,
                textInputAction: TextInputAction.next,
              ),
              AqarTextField(
                focusNode: secondFocus,
                textInputAction: TextInputAction.next,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(firstFocus.hasFocus, isFalse);
    expect(secondFocus.hasFocus, isTrue);
  });

  testWidgets('Next dismisses focus when there is no following field',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AqarTextFormField(
            focusNode: focus,
            textInputAction: TextInputAction.next,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(focus.hasFocus, isFalse);
  });
}
