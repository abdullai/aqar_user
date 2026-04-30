import 'package:flutter/foundation.dart';

/// Localized time-of-day greeting for the dashboard app bar.
@immutable
abstract final class DashboardGreeting {
  /// [displayName] — first name or short display string; empty falls back to generic home title.
  static String appBarLine({
    required bool isAr,
    required String displayName,
    required bool isMarketingAccountType,
  }) {
    final name = displayName.trim();
    if (name.isEmpty) {
      return isAr ? 'الرئيسية' : 'Home';
    }

    final salute = salutationOnly(isAr: isAr);

    final broker = isMarketingAccountType
        ? (isAr ? '، شريكنا العقاري' : ', real estate partner')
        : '';

    return '$salute، $name$broker';
  }

  /// توقيت السعودية (UTC+3 بلا DST) — التحية لا تعتمد على ساعة الجهاز.
  static DateTime _nowSaudiArabia() {
    return DateTime.now().toUtc().add(const Duration(hours: 3));
  }

  /// تحية حسب وقت المملكة (للعرض في سطر منفصل عن الاسم الرباعي).
  static String salutationOnly({required bool isAr}) {
    final h = _nowSaudiArabia().hour;
    if (h >= 5 && h < 12) {
      return isAr ? 'صباح الخير' : 'Good morning';
    }
    if (h >= 12 && h < 18) {
      return isAr ? 'طاب يومك' : 'Good afternoon';
    }
    return isAr ? 'مساء الخير' : 'Good evening';
  }

  static String firstChunk(String fullName) {
    final t = fullName.trim();
    if (t.isEmpty) return '';
    final parts = t.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.first : t;
  }

  /// For narrow toolbars (phone / small web): first + last token; single token unchanged.
  /// When [compact] is false, returns the full trimmed string.
  static String displayNameForAppBar(String fullName, {required bool compact}) {
    final t = fullName.trim();
    if (t.isEmpty) return '';
    if (!compact) return t;
    final parts = t.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.length <= 1) return parts.first;
    return '${parts.first} ${parts.last}';
  }
}
