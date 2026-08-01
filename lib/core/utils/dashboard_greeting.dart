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

    final salute = salutationOnly(isAr: isAr);

    // بدون «شريكنا العقاري» في شريط العنوان — الاسم يظهر في السطر التالي في الواجهة.
    return '$salute، $name';
  }

  /// توقيت السعودية (UTC+3 بلا DST) — التحية لا تعتمد على ساعة الجهاز.
  static DateTime _nowSaudiArabia() {
    return DateTime.now().toUtc().add(const Duration(hours: 3));
  }

  /// تحية حسب وقت المملكة: صباح الخير (5–12) أو مساء الخير (باقي اليوم).
  static String salutationOnly({required bool isAr}) {
    final h = _nowSaudiArabia().hour;
    if (h >= 5 && h < 12) {
      return isAr ? 'صباح الخير' : 'Good morning';
    }
    return isAr ? 'مساء الخير' : 'Good evening';
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
