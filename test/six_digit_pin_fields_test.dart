import 'package:aqar_user/widgets/six_digit_pin_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pasting six digits fills the separate PIN fields', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SixDigitPinFields(
            controller: controller,
            label: 'PIN',
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pump();

    expect(controller.text, '123456');
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.map((field) => field.controller!.text).join(), '123456');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
