import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/models/property.dart';
import 'package:aqar_user/screens/property_map_discovery_page.dart';

Property _property({
  DateTime? soldAt,
  DateTime? terminatedAt,
  String? status,
  String? workflowStage,
}) {
  return Property(
    id: 'property-1',
    ownerId: 'owner-1',
    title: 'Test listing',
    type: PropertyType.villa,
    description: '',
    city: '',
    area: 100,
    price: 100000,
    isAuction: false,
    images: const [],
    views: 0,
    createdAt: DateTime.utc(2026),
    soldAt: soldAt,
    terminatedAt: terminatedAt,
    status: status,
    workflowStage: workflowStage,
  );
}

void main() {
  test('public map excludes listings after sale or deal termination', () {
    expect(propertyEligibleForPublicMap(_property()), isTrue);
    expect(
      propertyEligibleForPublicMap(_property(soldAt: DateTime.utc(2026))),
      isFalse,
    );
    expect(
      propertyEligibleForPublicMap(
        _property(terminatedAt: DateTime.utc(2026)),
      ),
      isFalse,
    );
    expect(
      propertyEligibleForPublicMap(_property(status: 'completed')),
      isFalse,
    );
  });
}
