/// درجة إلحاح طلب السوق (`market_property_requests.request_priority`).
enum MarketPropertyRequestPriority {
  /// جدول زمني مرن
  flexible,

  /// عادي
  standard,

  /// ذو أولوية
  priority,

  /// مستعجل
  urgent,

  /// طلب فوري
  immediate;

  static const String wireFlexible = 'flexible';
  static const String wireStandard = 'standard';
  static const String wirePriority = 'priority';
  static const String wireUrgent = 'urgent';
  static const String wireImmediate = 'immediate';

  static MarketPropertyRequestPriority parse(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    switch (s) {
      case wireFlexible:
        return MarketPropertyRequestPriority.flexible;
      case wirePriority:
        return MarketPropertyRequestPriority.priority;
      case wireUrgent:
        return MarketPropertyRequestPriority.urgent;
      case wireImmediate:
        return MarketPropertyRequestPriority.immediate;
      case wireStandard:
      case '':
      default:
        return MarketPropertyRequestPriority.standard;
    }
  }

  String get wireValue => switch (this) {
        MarketPropertyRequestPriority.flexible => wireFlexible,
        MarketPropertyRequestPriority.standard => wireStandard,
        MarketPropertyRequestPriority.priority => wirePriority,
        MarketPropertyRequestPriority.urgent => wireUrgent,
        MarketPropertyRequestPriority.immediate => wireImmediate,
      };

  /// ترتيب أعلى يظهر أولاً ضمن نفس الفئة الزمنية.
  int get feedRank => switch (this) {
        MarketPropertyRequestPriority.immediate => 5,
        MarketPropertyRequestPriority.urgent => 4,
        MarketPropertyRequestPriority.priority => 3,
        MarketPropertyRequestPriority.standard => 2,
        MarketPropertyRequestPriority.flexible => 1,
      };

  /// يُضاف إلى وقت الفرز للأولويات القديمة (غير «فوري» — يُدار عبر [InstantMarketRequestFeed]).
  int get mixedFeedTimeBoostMs => switch (this) {
        MarketPropertyRequestPriority.immediate => 0,
        MarketPropertyRequestPriority.urgent => 86400000 * 7,
        MarketPropertyRequestPriority.priority => 86400000 * 3,
        MarketPropertyRequestPriority.standard => 0,
        MarketPropertyRequestPriority.flexible => -86400000 * 2,
      };
}
