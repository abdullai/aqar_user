import 'package:flutter_dotenv/flutter_dotenv.dart';

/// دمج مفاتيح وقت التشغيل (ويب: من [supabase_config.json]) في [dotenv].
class AppRuntimeEnv {
  AppRuntimeEnv._();

  static void mergeFromWebConfig(Map<String, dynamic> json) {
    void put(String key) {
      final v = (json[key] ?? '').toString().trim();
      if (v.isNotEmpty) {
        dotenv.env[key] = v;
      }
    }

    put('MOYASAR_PUBLISHABLE_KEY');
    put('MOYASAR_CALLBACK_URL');
    put('MOYASAR_APPLE_PAY_MERCHANT_ID');
    put('MOYASAR_SAMSUNG_PAY_SERVICE_ID');
  }

  static bool get moyasarConfigured {
    final k = (dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '').trim();
    return k.startsWith('pk_test_') || k.startsWith('pk_live_');
  }
}
