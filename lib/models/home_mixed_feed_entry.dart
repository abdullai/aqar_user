import '../core/market/instant_market_request_feed.dart';
import 'market_property_request_row.dart';
import 'property.dart';

/// عنصر في خليط الرئيسية (إعلان أو طلب) مرتب زمنياً.
class HomeMixedFeedEntry {
  final Property? listing;
  final MarketPropertyRequestRow? request;
  final String? viewerRegion;

  const HomeMixedFeedEntry._({
    this.listing,
    this.request,
    this.viewerRegion,
  });

  factory HomeMixedFeedEntry.listing(Property p) =>
      HomeMixedFeedEntry._(listing: p);

  factory HomeMixedFeedEntry.request(
    MarketPropertyRequestRow r, {
    String? viewerRegion,
  }) =>
      HomeMixedFeedEntry._(request: r, viewerRegion: viewerRegion);

  DateTime get sortAt {
    final p = listing;
    if (p != null) {
      return p.createdAt;
    }
    final r = request;
    if (r != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        InstantMarketRequestFeed.sortEpochMs(
          r,
          viewerRegion: viewerRegion,
        ),
      );
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool get isListing => listing != null;
  bool get isRequest => request != null;
}
