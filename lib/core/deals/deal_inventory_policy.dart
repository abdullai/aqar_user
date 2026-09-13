/// حدود بطاقات الصفقات والمخزون (طلباتي/إعلاناتي) — مصدر واحد للواجهة والخادم.
abstract final class DealInventoryPolicy {
  /// صفقاتي الجارية: حجوزات المشتري + عروض السوق المقدَّمة.
  static const int maxActiveDeals = 10;

  /// متقدّمو «إتمام الصفقة» على بطاقة واحدة في الرئيسية (طلب أو إعلان).
  static const int maxApplicantsPerCard = 10;

  /// طلباتي/إعلاناتي الجارية (غير المباعة/غير المكتملة).
  static const int maxActiveListingsAndRequests = 20;

  static bool dealsAtCap(int active) => active >= maxActiveDeals;

  static bool inventoryAtCap(int active) =>
      active >= maxActiveListingsAndRequests;
}
