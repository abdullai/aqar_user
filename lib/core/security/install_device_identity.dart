import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// معرّف تثبيت مستقر — مصدر واحد بدون اعتماد دائري بين الخدمات.
abstract final class InstallDeviceIdentity {
  static const prefKey = 'aqar_install_device_key';

  static Future<String>? _inFlight;

  static Future<String> key() async {
    final existing = _inFlight;
    if (existing != null) return existing;
    final fut = _impl();
    _inFlight = fut;
    try {
      return await fut;
    } finally {
      if (identical(_inFlight, fut)) _inFlight = null;
    }
  }

  static Future<String> _impl() async {
    final p = await SharedPreferences.getInstance();
    var k = p.getString(prefKey);
    if (k == null || k.trim().isEmpty || k.trim().length < 8) {
      k = const Uuid().v4();
      await p.setString(prefKey, k);
    }
    return k.trim();
  }
}
