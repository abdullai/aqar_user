import 'package:google_maps_flutter/google_maps_flutter.dart';

enum MapPickerLocateStatus {
  ok,
  serviceDisabled,
  permissionDenied,
  failed,
}

class MapPickerLocateOutcome {
  final MapPickerLocateStatus status;
  final LatLng? position;

  const MapPickerLocateOutcome(this.status, [this.position]);
}
