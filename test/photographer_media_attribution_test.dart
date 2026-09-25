import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/models/property.dart';

Property _propertyWithDeliveries(List<Map<String, dynamic>> deliveries) {
  return Property(
    id: 'property-1',
    ownerId: 'owner-1',
    title: 'Test property',
    type: PropertyType.villa,
    description: '',
    city: '',
    area: 100,
    price: 100000,
    isAuction: false,
    images: const [],
    views: 0,
    createdAt: DateTime.utc(2026),
    listingGuidance: {
      'photographer_media_paths': [
        'photographer/one/shoot-1/one.jpg',
        'photographer/two/shoot-2/two.jpg',
      ],
      'photographer_media_deliveries': deliveries,
    },
  );
}

void main() {
  test('attributes each approved media path to its delivering photographer',
      () {
    final property = _propertyWithDeliveries([
      {
        'photographer_name': 'Photographer One',
        'image_paths': ['photographer/one/shoot-1/one.jpg'],
      },
      {
        'photographer_name': 'Photographer Two',
        'image_paths': ['photographer/two/shoot-2/two.jpg'],
      },
    ]);

    expect(
      property.photographerAttributionForMedia(
        'https://storage.test/object/public/property-images/photographer/one/shoot-1/one.jpg',
      ),
      'Photographer One',
    );
    expect(
      property.photographerAttributionForMedia(
        'photographer/two/shoot-2/two.jpg',
      ),
      'Photographer Two',
    );
  });

  test('does not attribute existing owner media to a photographer', () {
    final property = _propertyWithDeliveries([
      {
        'photographer_name': 'Photographer One',
        'image_paths': ['photographer/one/shoot-1/one.jpg'],
      },
    ]);

    expect(
      property.photographerAttributionForMedia('owner/existing-photo.jpg'),
      isEmpty,
    );
    expect(
      property.isPhotographerMediaPath('owner/existing-photo.jpg'),
      isFalse,
    );
  });
}
