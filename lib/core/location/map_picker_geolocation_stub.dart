import 'map_picker_geolocation_types.dart';

/// Web / Wasm: لا نستورد `geolocator` (dart:html) — يُرجع تعطيل الخدمة بأمان.
Future<MapPickerLocateOutcome> detectMapPickerLocation({
  required bool isWeb,
}) async {
  return const MapPickerLocateOutcome(MapPickerLocateStatus.serviceDisabled);
}
