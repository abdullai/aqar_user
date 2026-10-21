import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// موقع العمل: يُحفظ على جهاز المستخدم فقط (لا يُرسل للخادم) لدعم «قريب من عملي».
abstract final class WorkLocationPrefs {
  static const _kLat = 'aqar_work_lat_v1';
  static const _kLng = 'aqar_work_lng_v1';
  static const defaultRadiusKm = 10.0;

  static double? lat;
  static double? lng;
  static bool loaded = false;

  static bool get isSet => lat != null && lng != null;

  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    lat = sp.getDouble(_kLat);
    lng = sp.getDouble(_kLng);
    loaded = true;
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kLat);
    await sp.remove(_kLng);
    lat = null;
    lng = null;
  }

  /// يحفظ موقع الجهاز الحالي كموقع عمل. يعيد null عند النجاح أو رمز الخطأ.
  static Future<String?> saveFromCurrentPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return 'permission';
      }
      final pos = await Geolocator.getCurrentPosition();
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_kLat, pos.latitude);
      await sp.setDouble(_kLng, pos.longitude);
      lat = pos.latitude;
      lng = pos.longitude;
      loaded = true;
      return null;
    } catch (_) {
      return 'failed';
    }
  }
}
