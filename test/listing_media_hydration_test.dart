import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/listing/listing_media_hydration.dart';
import 'package:aqar_user/models/property.dart';

void main() {
  test('resolves request and approved photographer media into one property row',
      () {
    final row = ListingMediaHydration.resolveRow(
      property: {
        'id': 'property-1',
        'video_url': '',
        'deed_number': '',
        'deed_date': '',
        'property_images': [
          {'path': 'owner/cover.jpg', 'sort_order': 0},
        ],
        'listing_guidance': {
          'virtual_tour_url': 'https://tour.example/property-1',
          'photographer_media_deliveries': [
            {
              'image_paths': ['photographer/front.jpg'],
              'video_path': 'photographer/tour.mp4',
            },
          ],
        },
      },
      request: {
        'payload_json': jsonEncode({
          'request_image_paths': ['requests/extra.jpg'],
          'deed_number': '2641096137',
          'deed_date': '2026-06-12',
        }),
      },
    );

    expect(
      row['images'],
      containsAll([
        'owner/cover.jpg',
        'photographer/front.jpg',
        'requests/extra.jpg',
      ]),
    );
    expect(row['video_url'], 'photographer/tour.mp4');
    expect(row['virtual_tour_url'], 'https://tour.example/property-1');
    expect(row['deed_number'], '2641096137');
    expect(row['deed_date'], '2026-06-12');
  });

  test('prefers approved photographer video in property details and shorts',
      () {
    final property = Property.fromJson({
      'id': 'property-1',
      'video_url': 'owner/original.mp4',
      'listing_guidance': {
        'photographer_media_deliveries': [
          {'video_path': 'photographer/final.mp4'},
        ],
      },
    });

    expect(property.displayVideoUrl, 'photographer/final.mp4');
  });
}
