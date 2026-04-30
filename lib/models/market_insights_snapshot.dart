// lib/models/market_insights_snapshot.dart

class MarketInsightsExtras {
  final int distinctListingPublishers;
  final int registeredProfiles;

  const MarketInsightsExtras({
    required this.distinctListingPublishers,
    required this.registeredProfiles,
  });

  static MarketInsightsExtras? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    return MarketInsightsExtras(
      distinctListingPublishers: _asInt(m['distinct_listing_publishers']),
      registeredProfiles: _asInt(m['registered_profiles']),
    );
  }
}

class MarketInsightsSnapshot {
  final DateTime generatedAt;
  final MarketListingsBlock listings;
  final MarketListingRequestsBlock listingRequests;
  final MarketOrgsBlock orgs;
  final List<MarketLeaderboardEntry> topPublishers;
  final MarketViewer? viewer;
  final MarketInsightsExtras? extras;

  const MarketInsightsSnapshot({
    required this.generatedAt,
    required this.listings,
    required this.listingRequests,
    required this.orgs,
    required this.topPublishers,
    required this.viewer,
    this.extras,
  });

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

    final lb = m['leaderboard'];
    final top = <MarketLeaderboardEntry>[];
    if (lb is Map) {
      final arr = lb['top_publishers'];
      if (arr is List) {
        for (final e in arr) {
          final row = MarketLeaderboardEntry.tryParse(e);
          if (row != null) top.add(row);
        }
      }
    }

    return MarketInsightsSnapshot(
      generatedAt: gen.toUtc(),
      listings: listings,
      listingRequests: lr,
      orgs: orgs,
      topPublishers: top,
      viewer: MarketViewer.tryParse(m['viewer']),
      extras: MarketInsightsExtras.tryParse(m['extras']),
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
  final List<MarketOrgTopEntry> top;

  const MarketOrgsBlock({
    required this.registered,
    required this.top,
  });

  static MarketOrgsBlock? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final top = <MarketOrgTopEntry>[];
    final arr = m['top'];
    if (arr is List) {
      for (final e in arr) {
        final row = MarketOrgTopEntry.tryParse(e);
        if (row != null) top.add(row);
      }
    }
    return MarketOrgsBlock(
      registered: _asInt(m['registered']),
      top: top,
    );
  }
}

class MarketOrgTopEntry {
  final String orgId;
  final String kind;
  final String label;
  final int listingCount;

  const MarketOrgTopEntry({
    required this.orgId,
    required this.kind,
    required this.label,
    required this.listingCount,
  });

  static MarketOrgTopEntry? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    return MarketOrgTopEntry(
      orgId: (m['org_id'] ?? '').toString(),
      kind: (m['kind'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
      listingCount: _asInt(m['listing_count']),
    );
  }
}

class MarketLeaderboardEntry {
  final int rank;
  final String userId;
  final String displayName;
  final String accountType;
  final int listingCount;

  const MarketLeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.accountType,
    required this.listingCount,
  });

  static MarketLeaderboardEntry? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    return MarketLeaderboardEntry(
      rank: _asInt(m['rank']),
      userId: (m['user_id'] ?? '').toString(),
      displayName: (m['display_name'] ?? '').toString(),
      accountType: (m['account_type'] ?? 'user').toString(),
      listingCount: _asInt(m['listing_count']),
    );
  }

  bool get isIndividualSegment {
    final t = accountType.toLowerCase().trim();
    return t == 'individual_seller' ||
        t == 'owner_individual' ||
        t == 'user' ||
        t.isEmpty;
  }

  bool get isMarketerSegment {
    final t = accountType.toLowerCase().trim();
    return t == 'marketer' ||
        t == 'agency' ||
        t == 'office' ||
        t == 'company' ||
        t == 'institution';
  }
}

class MarketViewer {
  final String userId;
  final int publishedListings;
  final int? rankGlobal;
  final String? accountType;

  const MarketViewer({
    required this.userId,
    required this.publishedListings,
    required this.rankGlobal,
    required this.accountType,
  });

  static MarketViewer? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final uid = (m['user_id'] ?? '').toString();
    if (uid.isEmpty) return null;
    final rg = m['rank_global'];
    return MarketViewer(
      userId: uid,
      publishedListings: _asInt(m['published_listings']),
      rankGlobal: rg == null ? null : _asInt(rg),
      accountType: m['account_type']?.toString(),
    );
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
