import 'package:aqar_user/core/listing/property_type_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('infers suitability from the property type group', () {
    expect(
      PropertyTypeCatalog.suitabilityForCode('villa'),
      (residential: true, commercial: false),
    );
    expect(
      PropertyTypeCatalog.suitabilityForCode('shop'),
      (residential: false, commercial: true),
    );
    expect(
      PropertyTypeCatalog.suitabilityForCode('land'),
      (residential: false, commercial: false),
    );
    expect(
      PropertyTypeCatalog.suitabilityForCode('project'),
      (residential: false, commercial: true),
    );
    expect(
      PropertyTypeCatalog.suitabilityForCode('other'),
      (residential: true, commercial: true),
    );
  });
}
