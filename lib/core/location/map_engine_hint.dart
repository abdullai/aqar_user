import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_api_availability/google_api_availability.dart';

/// Where to lean for map UX on Android (Saudi / Huawei-heavy market).
enum MapEngineHint {
  /// Standard Google Maps Flutter path.
  googleMaps,

  /// Huawei/Honor device without working Google Play services — prefer Petal Maps / manual coords.
  huaweiPetalPreferred,
}

/// Resolves map backend hints. Does **not** embed Huawei Map SDK; opens Petal Maps / URLs instead.
abstract final class MapEngineHintResolver {
  static Future<MapEngineHint> resolve() async {
    if (kIsWeb) return MapEngineHint.googleMaps;
    if (defaultTargetPlatform != TargetPlatform.android) {
      return MapEngineHint.googleMaps;
    }

    try {
      final android = await DeviceInfoPlugin().androidInfo;
      final m = '${android.manufacturer} ${android.brand} ${android.model}'
          .toLowerCase();
      final huaweiLike = m.contains('huawei') || m.contains('honor');

      final gms = await GoogleApiAvailability.instance
          .checkGooglePlayServicesAvailability(false);
      final gmsOk = gms == GooglePlayServicesAvailability.success;

      if (huaweiLike && !gmsOk) {
        return MapEngineHint.huaweiPetalPreferred;
      }
    } catch (_) {}

    return MapEngineHint.googleMaps;
  }
}
