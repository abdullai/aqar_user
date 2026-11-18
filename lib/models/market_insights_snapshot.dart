// lib/models/market_insights_snapshot.dart

class MarketInsightsSnapshot {
  final DateTime generatedAt;
  final MarketListingsBlock listings;
  final MarketListingRequestsBlock listingRequests;
  final MarketOrgsBlock orgs;

  const MarketInsightsSnapshot({
    required this.generatedAt,
    required this.listings,
    required this.listingRequests,
    required this.orgs,
  });

  /// لقطة صفرية عند غياب الدالة أو عدم جاهزية الخادم — تعرض الواجهة بدل شاشة التعذر.
  factory MarketInsightsSnapshot.empty() {
    final now = DateTime.now().toUtc();
    return MarketInsightsSnapshot(
      generatedAt: now,
      listings: const MarketListingsBlock(
        publishedTotal: 0,
        newLast7d: 0,
        newLast30d: 0,
        featuredTotal: 0,
        byAccountType: {},
        byPropertyType: {},
      ),
      listingRequests: const MarketListingRequestsBlock(
        total: 0,
        byStatus: {},
      ),
      orgs: const MarketOrgsBlock(registered: 0),
    );
  }

  static MarketInsightsSnapshot? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();

    final gen = DateTime.tryParse((m['generated_at'] ?? '').toString());
    if (gen == null) return null;

    final listings = MarketListingsBlock.tryParse(m['listings']);
    final lr = MarketListingRequestsBlock.tryParse(m['listing_requests']);
    final orgs = MarketOrgsBlock.tryParse(m['orgs']);
    if (listings == null || lr == null || orgs == null) return null;

    return MarketInsightsSnapshot(
      generatedAt: gen.toUtc(),
      listings: listings,
      listingRequests: lr,
      orgs: orgs,
    );
  }
}

class MarketListingsBlock {
  final int publishedTotal;
  final int newLast7d;
  final int newLast30d;
  final int featuredTotal;
  final Map<String, int> byAccountType;
  final Map<String, int> byPropertyType;

  const MarketListingsBlock({
    required this.publishedTotal,
    required this.newLast7d,
    required this.newLast30d,
    required this.featuredTotal,
    required this.byAccountType,
    required this.byPropertyType,
  });

  static MarketListingsBlock? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    return MarketListingsBlock(
      publishedTotal: _asInt(m['published_total']),
      newLast7d: _asInt(m['new_last_7d']),
      newLast30d: _asInt(m['new_last_30d']),
      featuredTotal: _asInt(m['featured_total']),
      byAccountType: _stringIntMap(m['by_account_type']),
      byPropertyType: _stringIntMap(m['by_property_type']),
    );
  }
}

class MarketListingRequestsBlock {
  final int total;
  final Map<String, int> byStatus;

  const MarketListingRequestsBlock({
    required this.total,
    required this.byStatus,
  });

  static MarketListingRequestsBlock? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    return MarketListingRequestsBlock(
      total: _asInt(m['total']),
      byStatus: _stringIntMap(m['by_status']),
    );
  }
}

class MarketOrgsBlock {
  final int registered;

  const MarketOrgsBlock({required this.registered});

  static MarketOrgsBlock? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    return MarketOrgsBlock(registered: _asInt(m['registered']));
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

Map<String, int> _stringIntMap(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, int>{};
  for (final e in raw.entries) {
    final k = e.key?.toString() ?? '';
    if (k.isEmpty) continue;
    out[k] = _asInt(e.value);
  }
  return out;
}
