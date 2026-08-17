import 'map_picker_geolocation_types.dart';

import 'map_picker_geolocation_io.dart' as impl;

export 'map_picker_geolocation_types.dart';

Future<MapPickerLocateOutcome> detectMapPickerLocation({
  required bool isWeb,
}) =>
    impl.detectMapPickerLocation(isWeb: isWeb);
