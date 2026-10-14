import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/core/market/instant_market_request_feed.dart';
import 'package:aqar_user/core/workflow/listing_permissions_helper.dart';
import 'package:aqar_user/models/market_property_request_priority.dart';
import 'package:aqar_user/models/market_property_request_row.dart';

void main() {
  MarketPropertyRequestRow request({
    required String id,
    required DateTime createdAt,
    required MarketPropertyRequestPriority priority,
    required String city,
    required double latitude,
    required double longitude,
    String status = 'published',
    DateTime? completedAt,
    String? selectedOfferId,
  }) {
    return MarketPropertyRequestRow(
      id: id,
      title: id,
      description: null,
      purpose: 'purchase',
      propertyType: 'apartment',
      city: city,
      districts: const [],
      budgetMin: null,
      budgetMax: null,
      areaMinM2: null,
      createdAt: createdAt,
      updatedAt: null,
      requesterId: 'requester-$id',
      showRequesterName: false,
      requesterPublicName: null,
      requestPriority: priority,
      status: status,
      completedAt: completedAt,
      selectedOfferId: selectedOfferId,
      details: {
        'region': city,
        'lat': latitude,
        'lng': longitude,
      },
    );
  }

  group('InstantMarketRequestFeed.compare', () {
    final recentStandard = request(
      id: 'recent',
      createdAt: DateTime.utc(2026, 10, 12),
      priority: MarketPropertyRequestPriority.standard,
      city: 'Riyadh',
      latitude: 24.7136,
      longitude: 46.6753,
    );

    test('local paid priority stays ahead of newer standard requests', () {
      final oldLocalPaid = request(
        id: 'local-paid',
        createdAt: DateTime.utc(2025, 1, 1),
        priority: MarketPropertyRequestPriority.urgent,
        city: 'Riyadh',
        latitude: 24.75,
        longitude: 46.7,
      );

      expect(
        InstantMarketRequestFeed.compare(
          oldLocalPaid,
          recentStandard,
          viewerRegion: 'Riyadh',
        ),
        lessThan(0),
      );
    });

    test('remote paid priority follows newer requests', () {
      final oldRemotePaid = request(
        id: 'remote-paid',
        createdAt: DateTime.utc(2025, 1, 1),
        priority: MarketPropertyRequestPriority.urgent,
        city: 'Jeddah',
        latitude: 21.4858,
        longitude: 39.1925,
      );

      expect(
        InstantMarketRequestFeed.compare(
          oldRemotePaid,
          recentStandard,
          viewerRegion: 'Riyadh',
        ),
        greaterThan(0),
      );
    });

    test('coordinates keep nearby paid requests local across language labels',
        () {
      final oldLocalPaid = request(
        id: 'local-paid',
        createdAt: DateTime.utc(2025, 1, 1),
        priority: MarketPropertyRequestPriority.urgent,
        city: 'Riyadh',
        latitude: 24.75,
        longitude: 46.7,
      );

      expect(
        InstantMarketRequestFeed.compare(
          oldLocalPaid,
          recentStandard,
          viewerRegion: 'الرياض',
          viewerLat: 24.7136,
          viewerLng: 46.6753,
        ),
        lessThan(0),
      );
    });
  });

  test('completed or selected requests are excluded from public home', () {
    final completed = request(
      id: 'completed',
      createdAt: DateTime.utc(2026, 10, 12),
      priority: MarketPropertyRequestPriority.immediate,
      city: 'Riyadh',
      latitude: 24.7136,
      longitude: 46.6753,
      status: 'completed',
    );
    final selected = request(
      id: 'selected',
      createdAt: DateTime.utc(2026, 10, 12),
      priority: MarketPropertyRequestPriority.urgent,
      city: 'Riyadh',
      latitude: 24.7136,
      longitude: 46.6753,
      selectedOfferId: 'offer-1',
    );

    expect(
      ListingPermissionsHelper.shouldShowMarketRequestWithoutDeal(completed),
      isFalse,
    );
    expect(
      ListingPermissionsHelper.shouldShowMarketRequestWithoutDeal(selected),
      isFalse,
    );
  });
}
