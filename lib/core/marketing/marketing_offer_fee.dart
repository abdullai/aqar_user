/// أتعاب التسويق الثابتة: 2.5٪ من (قيمة العقار الأساسية + ضريبة القيمة المضافة 5٪ على تلك القيمة).
abstract final class MarketingOfferFee {
  static const double commissionRate = 0.025;
  static const double propertyVatRate = 0.05;

  /// للنصوص في الواجهة (مثلاً «2.5٪» / «2.5%»).
  static String commissionPercentLabel({required bool isAr}) {
    final v = commissionRate * 100;
    final s =
        (v == v.roundToDouble()) ? v.toInt().toString() : v.toStringAsFixed(1);
    return isAr ? '$s٪' : '$s%';
  }

  /// ضريبة 5٪ على أصل قيمة العقار (قبل احتساب نسبة التسويق).
  static double propertyVatAmount(double propertyBaseSar) =>
      propertyBaseSar * propertyVatRate;

  /// أصل القيمة + ضريبة 5٪ على العقار.
  static double propertySubtotalWithVat(double propertyBaseSar) =>
      propertyBaseSar + propertyVatAmount(propertyBaseSar);

  /// عمولة التسويق = [commissionRate] من [propertySubtotalWithVat].
  static double marketingFeeAmount(double propertyBaseSar) =>
      propertySubtotalWithVat(propertyBaseSar) * commissionRate;

  /// المبلغ المستحق من المسوق (يساوي [marketingFeeAmount] — لا ضريبة إضافية على العمولة).
  static double totalDue(double propertyBaseSar) =>
      marketingFeeAmount(propertyBaseSar);

  /// ما يُعرض على بطاقات «صفحتي»/السوق: أساس العقار + ضريبة 5٪ على الأصل + أتعاب التسويق 2.5٪ من (الأصل+الضريبة).
  static double listingDisplayTotalIncVatAndFee(double propertyBaseSar) {
    if (propertyBaseSar <= 0) return 0;
    final sub = propertySubtotalWithVat(propertyBaseSar);
    final fee = marketingFeeAmount(propertyBaseSar);
    return sub + fee;
  }
}
