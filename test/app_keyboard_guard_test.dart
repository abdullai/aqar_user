import 'package:aqar_user/core/gestures/app_keyboard_inset.dart';
import 'package:aqar_user/core/gestures/soft_keyboard_ensure_visible.dart';
import 'package:aqar_user/core/input/saudi_input_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ArabicDigitsToLatinFormatter keeps promo letters and latinizes digits',
      () {
    const f = ArabicDigitsToLatinFormatter();
    final next = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: 'SAVE١٥۳',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    expect(next.text, 'SAVE153');
  });

  testWidgets('layoutPadBottomOf is zero when layout height is the visible lane',
      (tester) async {
    late double pad;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 500),
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
        child: Builder(
          builder: (context) {
            pad = AppKeyboardInset.layoutPadBottomOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(pad, 0);
  });

  testWidgets('scrollContentBottomOf adds slack while keyboard is open',
      (tester) async {
    late double slack;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 800),
          viewInsets: EdgeInsets.only(bottom: 320),
        ),
        child: Builder(
          builder: (context) {
            slack = AppKeyboardInset.scrollContentBottomOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(slack, greaterThanOrEqualTo(80));
    expect(slack, lessThanOrEqualTo(240));
  });

  test('field already in visible lane is not moved', () {
    expect(
      AppKeyboardFieldLane.scrollDelta(
        fieldTop: 80,
        fieldHeight: 48,
        visibleTop: 24,
        visibleBottom: 400,
        webSafe: true,
      ),
      isNull,
    );
  });

  test('covered field scrolls up into the visible lane', () {
    final delta = AppKeyboardFieldLane.scrollDelta(
      fieldTop: 520,
      fieldHeight: 48,
      visibleTop: 24,
      visibleBottom: 400,
      webSafe: true,
    );
    expect(delta, isNotNull);
    expect(delta!, greaterThan(8));
  });

  test('webSafe does not pull a visible field above the lane', () {
    expect(
      AppKeyboardFieldLane.scrollDelta(
        fieldTop: 30,
        fieldHeight: 48,
        visibleTop: 24,
        visibleBottom: 400,
        webSafe: true,
      ),
      isNull,
    );
  });
}
