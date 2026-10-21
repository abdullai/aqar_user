import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/core/search/arabic_search_intent.dart';
import 'package:aqar_user/models/property.dart';

void main() {
  test('يفهم النوع والغرض والميزانية والغرف والكلمات المتبقية', () {
    final i = ArabicSearchIntent.parse(
        'أبي شقة للإيجار بميزانية 50 ألف 3 غرف الرياض');
    expect(i.type, PropertyType.apartment);
    expect(i.purpose, 'rent');
    expect(i.priceMax, 50000);
    expect(i.bedroomsMin, 3);
    expect(i.keywords, ['الرياض']);
  });

  test('نطاق سعري بالمليون', () {
    final i =
        ArabicSearchIntent.parse('فيلا للبيع من 1.5 مليون الى 2 مليون جدة');
    expect(i.type, PropertyType.villa);
    expect(i.purpose, 'sale');
    expect(i.priceMin, 1500000);
    expect(i.priceMax, 2000000);
    expect(i.keywords, ['جده']);
  });

  test('نص عادي لا يُعد منظماً', () {
    final i = ArabicSearchIntent.parse('حي النرجس');
    expect(i.isStructured, isFalse);
  });

  test('أرقام بالهندية', () {
    final i = ArabicSearchIntent.parse('ارض للبيع حتى ٨٠٠ الف');
    expect(i.type, PropertyType.land);
    expect(i.priceMax, 800000);
  });

  test('قريب من عملي مع نصف قطر', () {
    final i = ArabicSearchIntent.parse('شقة قريبة من عملي 5 كم');
    expect(i.nearWork, isTrue);
    expect(i.workRadiusKm, 5);
    expect(i.isStructured, isTrue);
  });
}
