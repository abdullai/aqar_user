import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// مناطق عرض ثابتة (بدون حزمة timezone) — كافية للسعودية والإمارات (بدون DST).
enum ListingDateDisplayZone {
  device,
  utcPlus3,
  utcPlus4,
  utc,
}

/// تفضيل المستخدم لعرض التواريخ في بطاقات الإعلانات والطلبات.
abstract final class ListingDateDisplay {
  static ListingDateDisplayZone zone = ListingDateDisplayZone.device;

  static Future<void> loadFromPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = (p.getString(AppConfig.prefListingDateZoneKey) ?? 'device')
          .trim()
          .toLowerCase();
      zone = switch (v) {
        'utc_plus_3' || 'riyadh' || 'ksa' => ListingDateDisplayZone.utcPlus3,
        'utc_plus_4' || 'dubai' || 'uae' => ListingDateDisplayZone.utcPlus4,
        'utc' || 'gmt' => ListingDateDisplayZone.utc,
        _ => ListingDateDisplayZone.device,
      };
    } catch (_) {
      zone = ListingDateDisplayZone.device;
    }
  }

  static Future<void> saveZone(ListingDateDisplayZone z) async {
    final p = await SharedPreferences.getInstance();
    final key = switch (z) {
      ListingDateDisplayZone.device => 'device',
      ListingDateDisplayZone.utcPlus3 => 'utc_plus_3',
      ListingDateDisplayZone.utcPlus4 => 'utc_plus_4',
      ListingDateDisplayZone.utc => 'utc',
    };
    await p.setString(AppConfig.prefListingDateZoneKey, key);
    zone = z;
  }

  static String zoneLabelAr(ListingDateDisplayZone z) => switch (z) {
        ListingDateDisplayZone.device => 'حسب جهازك',
        ListingDateDisplayZone.utcPlus3 => 'السعودية (UTC+3)',
        ListingDateDisplayZone.utcPlus4 => 'الإمارات (UTC+4)',
        ListingDateDisplayZone.utc => 'UTC',
      };

  static String zoneLabelEn(ListingDateDisplayZone z) => switch (z) {
        ListingDateDisplayZone.device => 'Device default',
        ListingDateDisplayZone.utcPlus3 => 'Saudi Arabia (UTC+3)',
        ListingDateDisplayZone.utcPlus4 => 'UAE (UTC+4)',
        ListingDateDisplayZone.utc => 'UTC',
      };

  /// يحوّل لحظة زمنية (مخزّنة غالباً UTC) إلى `DateTime` للعرض بمنطقة ثابتة.
  static DateTime toDisplayDateTime(DateTime value) {
    final u = value.toUtc();
    return switch (zone) {
      ListingDateDisplayZone.device => value.toLocal(),
      ListingDateDisplayZone.utcPlus3 => u.add(const Duration(hours: 3)),
      ListingDateDisplayZone.utcPlus4 => u.add(const Duration(hours: 4)),
      ListingDateDisplayZone.utc => u,
    };
  }

  /// تاريخ/وقت مختصر للبطاقات (يُستخدم تدريجياً في أنحاء التطبيق).
  static String formatCardDateTime(
    DateTime? value, {
    required bool isAr,
  }) {
    if (value == null) return '';
    final loc = isAr ? 'ar' : 'en';
    final d = toDisplayDateTime(value);
    try {
      return DateFormat.yMMMd(loc).add_Hm().format(d);
    } catch (_) {
      return d.toIso8601String();
    }
  }
}
