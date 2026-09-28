import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:aqar_user/core/branding/app_branding.dart';
import 'package:aqar_user/core/listing/listing_media_hydration.dart';
import 'package:aqar_user/core/listing/listing_media_urls.dart';
import 'package:aqar_user/core/listing/listing_storage_paths.dart';
import 'package:aqar_user/models/property.dart';
import 'package:aqar_user/widgets/listing_media_gallery.dart';

void main() {
  test('listing image folder starts with owner id', () {
    expect(
      ListingStoragePaths.listingImagesFolder(
        ownerId: 'user-1',
        propertyId: 'prop-9',
        batchId: 'batch',
      ),
      'user-1/listings/prop-9',
    );
    expect(
      ListingStoragePaths.listingImagesFolder(
        ownerId: 'user-1',
        requestId: 'req-3',
        batchId: 'batch',
      ),
      'user-1/requests/req-3',
    );
    expect(
      ListingStoragePaths.listingImagesFolder(
        ownerId: 'user-1',
        batchId: 'batch-4',
      ),
      'user-1/listings/batch-4',
    );
  });

  test('license pdf sits under owner prefix', () {
    expect(
      ListingStoragePaths.licensePdfPath(ownerId: 'user-1', fileId: 'abc'),
      'user-1/licenses/abc.pdf',
    );
  });

  test('permission errors are detected without retry', () {
    expect(
      ListingStoragePaths.looksLikePermissionDenied(
        Exception('StorageException: Unauthorized statusCode: 403'),
      ),
      isTrue,
    );
    expect(
      ListingStoragePaths.looksLikePermissionDenied(
        Exception('SocketException: failed host lookup'),
      ),
      isFalse,
    );
  });

  test('real listing photos replace a smart-cover sentinel in embedded media',
      () {
    final property = Property.fromJson({
      'id': 'property-1',
      'owner_id': 'user-1',
      'property_images': [
        {
          'path': AppBranding.smartDefaultCoverStorageSentinel,
          'media_type': 'image',
          'sort_order': 0,
        },
      ],
      'listing_guidance': {
        'image_paths': ['user-1/listings/property-1/cover.webp'],
      },
    });

    expect(
      ListingMediaUrls.propertyCardImagePaths(property),
      ['user-1/listings/property-1/cover.webp'],
    );
  });

  test('hydration keeps real media beside a smart-cover sentinel', () {
    final row = <String, dynamic>{
      'id': 'property-2',
      'property_images': [
        {
          'path': AppBranding.smartDefaultCoverStorageSentinel,
          'media_type': 'image',
          'sort_order': 0,
        },
        {
          'path': 'owner/listings/property-2/walkthrough.mp4',
          'media_type': 'video',
          'sort_order': 1,
        },
      ],
      'listing_guidance': {
        'image_paths': ['owner/listings/property-2/front.webp'],
        'video_path': 'owner/listings/property-2/tour.mp4',
        'virtual_tour_url': 'https://my.matterport.com/show/?m=abc123',
      },
    };

    ListingMediaHydration.stampRow(row);

    expect(row['images'], ['owner/listings/property-2/front.webp']);
    expect(
      row['video_url'],
      'owner/listings/property-2/walkthrough.mp4',
    );
    expect(
      row['virtual_tour_url'],
      'https://my.matterport.com/show/?m=abc123',
    );
  });

  test('request media merges arrays and nested guidance without duplicates',
      () {
    final payload = <String, dynamic>{
      'image_paths': ['owner/requests/request-1/front.webp'],
      'gallery': ['owner/requests/request-1/living-room.webp'],
      'video_path': '',
      'listing_guidance': {
        'image_paths': [
          'owner/requests/request-1/front.webp',
          'owner/requests/request-1/back.webp',
        ],
        'video_path': 'owner/requests/request-1/walkthrough.mp4',
        'virtual_tour_url': 'https://my.matterport.com/show/?m=request1',
        'in_app_tour': {
          'scenes': [
            {'image': 'owner/requests/request-1/front.webp'},
          ],
        },
      },
    };

    expect(
      ListingMediaUrls.imagePathsFromPayload(payload),
      [
        'owner/requests/request-1/front.webp',
        'owner/requests/request-1/living-room.webp',
        'owner/requests/request-1/back.webp',
      ],
    );
    expect(
      ListingMediaUrls.videoPathFromPayload(payload),
      'owner/requests/request-1/walkthrough.mp4',
    );
    expect(
      ListingMediaUrls.virtualTourFromPayload(payload),
      'https://my.matterport.com/show/?m=request1',
    );
    expect(
      ListingMediaUrls.inAppTourFromPayload(payload)?.scenes.length,
      1,
    );
  });

  testWidgets('mixed media card gallery resets when its owner changes',
      (tester) async {
    Widget gallery(String ownerId, {bool includeTour = true}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 228,
              child: ListingMediaGallery(
                key: const ValueKey<String>('reused-gallery'),
                imageUrls: const [],
                isAr: false,
                videoUrl: 'https://media.example.com/property.mp4',
                tourUrl: includeTour
                    ? 'https://my.matterport.com/show/?m=listing'
                    : null,
                onOpenTour: includeTour ? () {} : null,
                mediaOwnerKey: ownerId,
                fillAvailableHeight: true,
                aspectRatio: 2.2,
                maxHeight: 164,
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(gallery('listing-a'));
    expect(find.text('Play video'), findsOneWidget);
    expect(find.byTooltip('Tour'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Tour'));
    await tester.pumpAndSettle();
    expect(find.text('Open tour'), findsOneWidget);

    await tester.pumpWidget(gallery('listing-b', includeTour: false));
    await tester.pumpAndSettle();
    expect(find.text('Play video'), findsOneWidget);
    expect(find.text('Open tour'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
