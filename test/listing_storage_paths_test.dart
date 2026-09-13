import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/listing/listing_storage_paths.dart';

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
}
