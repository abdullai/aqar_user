import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:aqar_user/widgets/property_type_hierarchy_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('custom type input stays hidden until selected and uses Arabic',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PropertyTypeHierarchyPicker(
            value: 'villa',
            isAr: true,
            saving: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AqarTextField), findsOneWidget);
    expect(find.text('اسم النوع'), findsNothing);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(find.byType(AqarTextField), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AqarTextField &&
            widget.decoration?.labelText == 'اسم النوع',
      ),
      findsOneWidget,
    );
    expect(find.text('Type name'), findsNothing);
  });

  testWidgets('custom type input follows the English app language',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PropertyTypeHierarchyPicker(
            value: 'villa',
            isAr: false,
            saving: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AqarTextField &&
            widget.decoration?.labelText == 'Type name',
      ),
      findsOneWidget,
    );
    expect(find.text('اسم النوع'), findsNothing);
  });
}
