import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/core/gestures/app_keyboard_inset.dart';

void main() {
  testWidgets('keyboard inset change keeps the focused field alive',
      (tester) async {
    final focus = FocusNode();
    final ctrl = TextEditingController();
    addTearDown(focus.dispose);
    addTearDown(ctrl.dispose);

    Widget app(double inset) => MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: AppKeyboardScope(
              inset: inset,
              child: AppKeyboardPad(
                child: Center(
                  child: TextField(controller: ctrl, focusNode: focus),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(0));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    final before = tester.state(find.byType(EditableText));

    await tester.pumpWidget(app(300));
    await tester.pump();

    expect(focus.hasFocus, isTrue);
    expect(tester.state(find.byType(EditableText)), same(before));
  });
}
