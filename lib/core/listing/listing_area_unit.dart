/// وحدة إدخال المساحة في النماذج؛ التخزين بالمتر المربع.
enum ListingAreaUnit {
  m2,
  cm2,
}

extension ListingAreaUnitX on ListingAreaUnit {
  /// يحوّل قيمة الحقل إلى م² (سم² → ÷ 10 000).
  double? toSquareMeters(double? rawInput) {
    if (rawInput == null || rawInput <= 0) return null;
    switch (this) {
      case ListingAreaUnit.cm2:
        return rawInput / 10000.0;
      case ListingAreaUnit.m2:
        return rawInput;
    }
  }
}
