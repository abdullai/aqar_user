import 'market_property_request_row.dart';
import 'property.dart';

/// عنصر في خليط الرئيسية (إعلان أو طلب) مرتب زمنياً.
class HomeMixedFeedEntry {
  final Property? listing;
  final MarketPropertyRequestRow? request;

  const HomeMixedFeedEntry._({this.listing, this.request});

  factory HomeMixedFeedEntry.listing(Property p) =>
      HomeMixedFeedEntry._(listing: p);

  factory HomeMixedFeedEntry.request(MarketPropertyRequestRow r) =>
      HomeMixedFeedEntry._(request: r);

  DateTime get sortAt {
    final p = listing;
    if (p != null) {
      return p.createdAt;
    }
    final r = request;
    if (r != null) {
      return r.homeFeedTimelineSortAt;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool get isListing => listing != null;
  bool get isRequest => request != null;
}
