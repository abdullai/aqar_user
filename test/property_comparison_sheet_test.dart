import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/models/property.dart';
import 'package:aqar_user/widgets/property_comparison_sheet.dart';

Property _property({
  required String id,
  required String title,
  required double price,
  required double area,
  int? bedrooms,
}) {
  return Property(
    id: id,
    ownerId: 'owner-$id',
    title: title,
    type: PropertyType.villa,
    description: '',
    city: 'الرياض',
    location: 'الياسمين',
    area: area,
    price: price,
    isAuction: false,
    images: const [],
    views: 0,
    createdAt: DateTime(2026),
    bedrooms: bedrooms,
    bathrooms: 3,
    currency: 'SAR',
  );
}

void main() {
  testWidgets('compares two listings and exposes key decision facts',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: PropertyComparisonSheet(
            properties: [
              _property(
                id: 'one',
                title: 'فيلا الياسمين',
                price: 2000000,
                area: 400,
                bedrooms: 5,
              ),
              _property(
                id: 'two',
                title: 'فيلا النرجس',
                price: 1500000,
                area: 300,
                bedrooms: 4,
              ),
            ],
            isArabic: true,
          ),
        ),
      ),
    );

    expect(find.text('مقارنة العقارات'), findsOneWidget);
    expect(find.text('السعر الظاهر'), findsOneWidget);
    expect(find.text('السعر لكل م²'), findsOneWidget);
    expect(find.text('غرف النوم'), findsOneWidget);
    expect(find.textContaining('2,000,000'), findsOneWidget);
    expect(find.textContaining('1,500,000'), findsOneWidget);
  });
}
