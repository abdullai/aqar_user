import 'package:flutter/foundation.dart';

import 'compound_display_name.dart';

/// Localized time-of-day greeting for the dashboard app bar.
@immutable
abstract final class DashboardGreeting {
  /// [displayName] — first name or short display string; empty falls back to generic home title.
  static String appBarLine({
    required bool isAr,
    required String displayName,
  }) {
    final name = displayName.trim();
    if (name.isEmpty) {
      return isAr ? 'الرئيسية' : 'Home';
    }

    // سطر واحد احتياطي: تحية + شريكنا + الاسم.
    return '${partnerSalutationLine(isAr: isAr)} — $name';
  }

  /// توقيت السعودية (UTC+3 بلا DST) — التحية لا تعتمد على ساعة الجهاز.
  static DateTime nowSaudiArabia() {
    return DateTime.now().toUtc().add(const Duration(hours: 3));
  }

  static DateTime _nowSaudiArabia() => nowSaudiArabia();

  /// تحية حسب وقت المملكة: صباح الخير (5–12) أو مساء الخير (باقي اليوم).
  static String salutationOnly({required bool isAr}) {
    final h = _nowSaudiArabia().hour;
    if (h >= 5 && h < 12) {
      return isAr ? 'صباح الخير' : 'Good morning';
    }
    return isAr ? 'مساء الخير' : 'Good evening';
  }

  static String partnerBrand({required bool isAr}) =>
      isAr ? 'شريكنا العقاري' : 'Real estate partner';

  /// سطر التحية العلوي: «صباح الخير شريكنا العقاري».
  static String partnerSalutationLine({required bool isAr}) {
    return '${salutationOnly(isAr: isAr)} ${partnerBrand(isAr: isAr)}';
  }

  static String firstChunk(String fullName) {
    final u = CompoundDisplayName.units(fullName);
    return u.isNotEmpty ? u.first : fullName.trim();
  }

  /// For narrow toolbars: first + last **compound unit**; otherwise full normalized name.
  static String displayNameForAppBar(String fullName, {required bool compact}) {
    return CompoundDisplayName.forToolbar(fullName, compact: compact);
  }
}
