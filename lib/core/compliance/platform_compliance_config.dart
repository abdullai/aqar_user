import 'package:flutter_dotenv/flutter_dotenv.dart';

/// روابط وقنوات الامتثال الحكومي والجهات — تُقرأ من `.env` عند التوفر مع قيم افتراضية آمنة.
///
/// **للمشغّل:** عيّن في `.env` (أو متغيرات بناء) القيم الفعلية للمنصة بعد اعتماد النطاق والربط.
abstract final class PlatformComplianceConfig {
  static String _env(String k, String fallback) {
    try {
      final v = dotenv.env[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return fallback;
  }

  /// الهيئة العامة للعقار (واجهة عامة / بوابات — حسب اعتمادكم لاحقاً).
  static String regaPublicUrl() =>
      _env('COMPLIANCE_REGA_PUBLIC_URL', 'https://rega.gov.sa');

  /// النفاذ الوطني الموحّد.
  static String nafathPublicUrl() =>
      _env('COMPLIANCE_NAFATH_PUBLIC_URL', 'https://www.nafath.sa');

  /// المركز السعودي للأعمال (شهادة التوثيق — صفحة عامة).
  static String mcBusinessCenterUrl() =>
      _env('COMPLIANCE_MC_BUSINESS_URL', 'https://mc.gov.sa');

  /// بريد الشكاوى والامتثال (يُعرض في الدعم ويُستخدم في mailto:).
  static String complaintsEmail() =>
      _env('COMPLIANCE_COMPLAINTS_EMAIL', 'compliance@aqar.com');

  /// بريد الدعم الفني العام.
  static String supportEmail() =>
      _env('COMPLIANCE_SUPPORT_EMAIL', 'support@aqar.com');

  /// رابط صفحة الشكاوى على الويب إن وُجدت (اختياري).
  static String? complaintsWebUrl() {
    try {
      final v = dotenv.env['COMPLIANCE_COMPLAINTS_WEB_URL']?.trim();
      if (v == null || v.isEmpty) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// **UAT / isolated demo only.** When true, operators may point the app at a
  /// synthetic Supabase project and optional seed data — never enable on real
  /// production tenants.
  ///
  /// Reads `GOVERNMENT_DEMO_MODE` first, then `COMPLIANCE_DEMO_GOV_MODE`
  /// (values: `1`, `true`, `yes`, `on` — case-insensitive).
  static bool governmentDemoMode() {
    String? raw;
    try {
      raw = dotenv.env['GOVERNMENT_DEMO_MODE']?.trim();
      if (raw == null || raw.isEmpty) {
        raw = dotenv.env['COMPLIANCE_DEMO_GOV_MODE']?.trim();
      }
    } catch (_) {
      return false;
    }
    if (raw == null || raw.isEmpty) return false;
    switch (raw.toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      default:
        return false;
    }
  }
}
