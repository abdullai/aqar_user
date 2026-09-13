/// حساب مدة الإيجار في طلب عقاري: نهاية تلقائية من البداية (تقويم ميلادي).
abstract final class MarketRequestRentSchedule {
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime addCalendarMonths(DateTime start, int months) {
    final s = dateOnly(start);
    var y = s.year;
    var m = s.month + months;
    y += (m - 1) ~/ 12;
    m = ((m - 1) % 12) + 1;
    final last = DateTime(y, m + 1, 0).day;
    final day = s.day > last ? last : s.day;
    return DateTime(y, m, day);
  }

  /// نهاية الفترة شاملة ليوم البداية.
  static DateTime? endOf({
    required String term,
    required DateTime start,
    int days = 1,
    int weeks = 1,
    int months = 1,
    int years = 1,
  }) {
    final s = dateOnly(start);
    switch (term) {
      case 'daily':
        final n = days.clamp(1, 6);
        return s.add(Duration(days: n - 1));
      case 'weekly':
        final n = weeks.clamp(1, 3);
        return s.add(Duration(days: n * 7 - 1));
      case 'monthly':
        final n = months.clamp(1, 12);
        return addCalendarMonths(s, n).subtract(const Duration(days: 1));
      case 'yearly':
        final n = years.clamp(1, 20);
        return addCalendarMonths(s, n * 12).subtract(const Duration(days: 1));
      default:
        return null;
    }
  }
}
