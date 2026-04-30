// lib/core/utils/geo_helper.dart
import 'dart:math' as math;

/// Geo helper utilities
/// يستخدم لحساب المسافة بين نقطتين على الأرض
class GeoHelper {
  static const double _earthRadiusKm = 6371.0;

  /// حساب المسافة بالكيلومتر بين نقطتين
  static double distanceKm({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    double toRad(double deg) => deg * math.pi / 180.0;

    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    final result = _earthRadiusKm * c;

    if (result.isNaN || result.isInfinite) {
      return double.infinity;
    }

    return result;
  }
}