import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/core/share/property_share_content.dart';
import 'package:aqar_user/models/property.dart';

void main() {
  test('builds concise listing content with unique media and safe details', () {
    final property = Property(
      id: 'listing-123',
      ownerId: 'owner-private',
      title: 'فيلا الياسمين',
      type: PropertyType.villa,
      listingTypeKey: 'villa',
      description: '',
      city: 'الرياض',
      location: 'الياسمين',
      area: 400,
      price: 2000000,
      isAuction: false,
      images: const [],
      views: 0,
      createdAt: DateTime(2026),
      bedrooms: 5,
      bathrooms: 4,
      latitude: 24.7,
      longitude: 46.6,
      contactPhone: '0500000000',
    );

    final text = PropertyShareContent.build(
      property: property,
      isArabic: true,
      listingUrl: 'https://example.test/?listing=listing-123',
      imageUrls: const [
        'https://cdn.test/photo.jpg?width=600',
        'https://cdn.test/photo.jpg?width=1200',
      ],
      videoUrls: const ['https://cdn.test/tour.mp4'],
      tourUrls: const ['https://cdn.test/matterport-tour'],
      hasInAppTour: true,
      description: 'وصف موجز',
      mediaAttributions: const {
        'https://cdn.test/photo.jpg?width=600': 'مصور عقاري',
      },
    );

    expect(text, contains('فيلا الياسمين'));
    expect(text, contains('2,000,000'));
    expect(text, contains('وصف موجز'));
    expect(text, contains('تصوير مصور عقاري'));
    expect(text, contains('tour.mp4'));
    expect(text, contains('matterport-tour'));
    expect(text, contains('جولة تفاعلية'));
    expect(text, contains('listing=listing-123'));
    expect(text, isNot(contains('24.7')));
    expect(text, isNot(contains('46.6')));
    expect(text, isNot(contains('0500000000')));
    expect(RegExp(r'cdn\.test/photo\.jpg').allMatches(text), hasLength(1));
  });

  test('truncates long description without changing listing link', () {
    final longDescription = List.filled(700, 'a').join();
    final property = Property(
      id: 'listing-456',
      ownerId: 'owner',
      title: 'شقة',
      type: PropertyType.apartment,
      description: '',
      city: 'جدة',
      area: 100,
      price: 500000,
      isAuction: false,
      images: const [],
      views: 0,
      createdAt: DateTime(2026),
    );
    final text = PropertyShareContent.build(
      property: property,
      isArabic: false,
      listingUrl: 'https://example.test/?listing=listing-456',
      imageUrls: const [],
      videoUrls: const [],
      tourUrls: const [],
      hasInAppTour: false,
      description: longDescription,
    );

    expect(text, contains('${List.filled(497, 'a').join()}...'));
    expect(text, isNot(contains(List.filled(501, 'a').join())));
    expect(text, contains('listing=listing-456'));
  });
}
