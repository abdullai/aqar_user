import 'package:aqar_user/core/utils/app_money.dart';
import 'package:aqar_user/widgets/aqar_money_range_field.dart';
import 'package:aqar_user/widgets/budget_text_field.dart';
import 'package:aqar_user/widgets/saudi_riyal_symbol_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Arabic amount shows the symbol left of the number', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AppMoneyLine(
              amount: 1234,
              currencyCode: 'SAR',
              isAr: true,
              maxFractionDigits: 0,
            ),
          ),
        ),
      ),
    );

    final symbol = tester.getRect(find.byType(SaudiRiyalSymbolIcon));
    final amount = tester.getRect(find.text('1,234'));
    expect(symbol.center.dx, lessThan(amount.center.dx));
  });

  testWidgets('Arabic budget field places its symbol at the left end', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: BudgetTextField(
              controller: controller,
              label: 'السعر',
              isAr: true,
            ),
          ),
        ),
      ),
    );

    final field = tester.getRect(find.byType(TextField));
    final symbol = tester.getRect(find.byType(SaudiRiyalSymbolIcon));
    expect(symbol.center.dx, lessThan(field.center.dx));
  });

  testWidgets('English budget field places SAR at the right end', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            body: BudgetTextField(
              controller: controller,
              label: 'Price',
              isAr: false,
            ),
          ),
        ),
      ),
    );

    final field = tester.getRect(find.byType(TextField));
    final currency = tester.getRect(find.text('SAR'));
    expect(currency.center.dx, greaterThan(field.center.dx));
  });

  testWidgets('Arabic amount hint uses the riyal glyph instead of a label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AqarMoneyRangeField(
              isAr: true,
              minInitial: '',
              maxInitial: '',
              onMinChanged: (_) {},
              onMaxChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('نطاق المبلغ المحدد: الرقم ثم ﷼ — بدون لفّ'),
      findsOneWidget,
    );
    expect(find.textContaining('ريال'), findsNothing);
  });
}
