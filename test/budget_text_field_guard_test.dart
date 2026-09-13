import 'dart:ui' show BoxHeightStyle, BoxWidthStyle;

import 'package:aqar_user/core/input/aqar_editable_defaults.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:aqar_user/widgets/budget_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BudgetTextField uses AqarTextField tight selection and unfocus',
      (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BudgetTextField(controller: c, label: 'Amount'),
        ),
      ),
    );

    expect(find.byType(AqarTextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.selectionHeightStyle, AqarEditableDefaults.heightStyle);
    expect(field.selectionWidthStyle, AqarEditableDefaults.widthStyle);
    expect(field.selectionHeightStyle, BoxHeightStyle.tight);
    expect(field.selectionWidthStyle, BoxWidthStyle.tight);
    expect(field.onTapOutside, isNotNull);
    expect(field.enableInteractiveSelection, isTrue);
  });

  testWidgets('BudgetTextField with validator uses AqarTextFormField unfocus',
      (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: BudgetTextField(
              controller: c,
              label: 'Amount',
              validator: (v) => null,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AqarTextFormField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.selectionHeightStyle, BoxHeightStyle.tight);
    expect(field.onTapOutside, isNotNull);
  });
}
