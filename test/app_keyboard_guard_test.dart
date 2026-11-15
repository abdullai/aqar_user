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

  test('numeric formatters preserve active IME composing text', () {
    const value = TextEditingValue(
      text: '١٢٫٥',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );

    expect(
      const ArabicDigitsToLatinFormatter().formatEditUpdate(
        TextEditingValue.empty,
        value,
      ),
      value,
    );
    expect(
      const LatinDecimalNumberFormatter().formatEditUpdate(
        TextEditingValue.empty,
        value,
      ),
      value,
    );
  });

  testWidgets(
      'layoutPadBottomOf is zero when layout height is the visible lane',
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

  testWidgets('keyboard scope reports open when MediaQuery insets are zero',
      (tester) async {
    late bool keyboardOpen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 800),
          viewInsets: EdgeInsets.zero,
        ),
        child: AppKeyboardScope(
          inset: 320,
          child: Builder(
            builder: (context) {
              keyboardOpen = AppKeyboardInset.isOpen(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(keyboardOpen, isTrue);
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

  test('visible field is left in place before the keyboard opens', () {
    expect(
      AppKeyboardFieldLane.scrollDelta(
        fieldTop: 80,
        fieldHeight: 48,
        visibleTop: 24,
        visibleBottom: 400,
      ),
      isNull,
    );
  });

  test('visible field is centered in the lane when the keyboard opens', () {
    const fieldTop = 30.0;
    const fieldHeight = 48.0;
    const visibleTop = 24.0;
    const visibleBottom = 400.0;
    final delta = AppKeyboardFieldLane.scrollDelta(
      fieldTop: fieldTop,
      fieldHeight: fieldHeight,
      visibleTop: visibleTop,
      visibleBottom: visibleBottom,
      centerWhenVisible: true,
    );

    expect(delta, isNotNull);
    expect(
      fieldTop - delta! + fieldHeight / 2,
      closeTo((visibleTop + visibleBottom) / 2, 0.5),
    );
  });

  test('covered field scrolls up into the visible lane', () {
    final delta = AppKeyboardFieldLane.scrollDelta(
      fieldTop: 520,
      fieldHeight: 48,
      visibleTop: 24,
      visibleBottom: 400,
    );
    expect(delta, isNotNull);
    expect(delta!, greaterThan(8));
  });

  test('tall field aligns to the top when it cannot fit in the lane', () {
    const fieldTop = 60.0;
    const visibleTop = 24.0;
    final delta = AppKeyboardFieldLane.scrollDelta(
      fieldTop: fieldTop,
      fieldHeight: 420,
      visibleTop: visibleTop,
      visibleBottom: 400,
      centerWhenVisible: true,
    );

    expect(delta, isNotNull);
    expect(fieldTop - delta!, visibleTop);
  });
}
