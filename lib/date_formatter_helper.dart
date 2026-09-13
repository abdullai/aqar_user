import 'core/utils/date_helper.dart';

/// واجهة تسمية مطلوبة للتوحيد — المنطق الفعلي في [DateHelper].
/// الصيغة: `yyyy/MM/dd` و`yyyy/MM/dd    HH:mm` (24 ساعة افتراضياً).
class MyDateFormatter {
  MyDateFormatter._();

  static String formatGregorian(
    DateTime dateTime, {
    bool use24Hour = true,
    bool isAr = true,
    bool dateOnly = false,
  }) {
    final local = dateTime.toLocal();
    if (dateOnly) {
      return DateHelper.fmtCivilDate(local, isAr: isAr);
    }
    if (use24Hour) {
      return DateHelper.fmtCivilDateTime(local, isAr: isAr);
    }
    return _with12Hour(
      DateHelper.civilDigits(local),
      local,
      isAr: isAr,
    );
  }

  static String formatHijri(
    DateTime dateTime, {
    bool use24Hour = true,
    bool isAr = true,
    bool dateOnly = false,
  }) {
    final local = dateTime.toLocal();
    if (dateOnly) {
      return DateHelper.fmtHijriDate(local, isAr: isAr);
    }
    if (use24Hour) {
      return DateHelper.fmtHijriDateTime(local, isAr: isAr);
    }
    final datePart = isAr
        ? DateHelper.hijriDigits(local)
        : '${DateHelper.hijriDigits(local)} AH';
    return _with12Hour(datePart, local, isAr: isAr);
  }

  static String _with12Hour(
    String datePart,
    DateTime local, {
    required bool isAr,
  }) {
    var h = local.hour % 12;
    if (h == 0) h = 12;
    final mm = local.minute.toString().padLeft(2, '0');
    final hh = h.toString().padLeft(2, '0');
    final isPm = local.hour >= 12;
    final suffix = isAr ? (isPm ? 'م' : 'ص') : (isPm ? 'PM' : 'AM');
    final timePart = '$hh:$mm $suffix';
    return DateHelper.wrapCalendar(
      '$datePart${DateHelper.dateTimeGap}$timePart',
      isAr: isAr,
    );
  }
}
