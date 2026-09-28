import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/services/photographer_service.dart';

void main() {
  test('photo request parses its listing preview and offer count', () {
    final request = PhotoShootRequest.fromMap({
      'id': 'shoot-1',
      'requester_id': 'owner-1',
      'photographer_id': null,
      'status': 'open',
      'shoot_kinds': ['photos', 'video'],
      'listing_preview': {
        'title': 'North Villa',
        'city': 'Riyadh',
        'public_code': '1234567890',
      },
      'offer_count': 3,
    });

    expect(request.id, 'shoot-1');
    expect(request.status, 'open');
    expect(request.listingTitle, 'North Villa');
    expect(request.listingCity, 'Riyadh');
    expect(request.listingPublicCode, '1234567890');
    expect(request.offerCount, 3);
    expect(request.shootKinds, ['photos', 'video']);
  });
}
