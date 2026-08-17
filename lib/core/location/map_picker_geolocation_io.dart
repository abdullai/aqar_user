import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_picker_geolocation_types.dart';

Future<MapPickerLocateOutcome> detectMapPickerLocation({
  required bool isWeb,
}) async {
  try {
    if (!isWeb) {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const MapPickerLocateOutcome(
          MapPickerLocateStatus.serviceDisabled,
        );
      }
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const MapPickerLocateOutcome(
          MapPickerLocateStatus.permissionDenied);
    }

    var accuracy = LocationAccuracy.high;
    if (kIsWeb) {
      accuracy = LocationAccuracy.best;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: accuracy,
      timeLimit: const Duration(seconds: 15),
    );

    return MapPickerLocateOutcome(
      MapPickerLocateStatus.ok,
      LatLng(pos.latitude, pos.longitude),
    );
  } catch (e) {
    if (kDebugMode) {
      print('[DBG][MAP] detectMapPickerLocation failed: $e');
    }
    return const MapPickerLocateOutcome(MapPickerLocateStatus.failed);
  }
}
