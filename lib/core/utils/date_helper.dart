// lib/core/utils/date_helper.dart
import 'dart:ui' show TextDirection;

import 'package:hijri/hijri_calendar.dart';

class DateHelper {
  /// محاولة تحويل أي قيمة إلى DateTime
  static DateTime? tryParse(dynamic v) {
    if (v == null) return null;

    if (v is DateTime) return v;

    if (v is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(v);
      } catch (_) {
        return null;
      }
    }

    final s = v.toString().trim();
    if (s.isEmpty) return null;

    return DateTime.tryParse(s);
  }

  /// يمنع انقلاب نسب مثل 1/10 داخل اتجاه RTL (ليس لتواريخ التقويم).
  static String ltrIsolate(String s) => '\u2066$s\u2069';

  /// أرقام التقويم لاتينية داخل عازل LTR فقط.
  /// لا نستخدم RLI (U+2067) لأن خطوط PDF ترسمه مربعاً ☒.
  static String wrapCalendar(String core, {required bool isAr}) =>
      ltrIsolate(core);

  static TextDirection calendarTextDirection({required bool isAr}) =>
      isAr ? TextDirection.rtl : TextDirection.ltr;

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _four(int v) => v.toString().padLeft(4, '0');

  /// مسافة ثابتة بين التاريخ والوقت حتى لا يلتصقا.
  static const String dateTimeGap = '    ';

  /// ميلادي: yyyy/MM/dd
  static String civilDigits(DateTime dt) =>
      '${_four(dt.year)}/${_two(dt.month)}/${_two(dt.day)}';

  /// هجري: yyyy/MM/dd
  static String hijriDigits(DateTime dt) {
    final h = HijriCalendar.fromDate(dt);
    return '${_four(h.hYear)}/${_two(h.hMonth)}/${_two(h.hDay)}';
  }

  static String _civilCore(DateTime dt, {required bool isAr}) => civilDigits(dt);

  static String _hijriCore(DateTime dt, {required bool isAr}) => hijriDigits(dt);

  /// تاريخ الصك: ميلادي ثم هجري — بلا وقت.
  static String fmtDeedFieldPair(DateTime dt, {required bool isAr}) {
    final d = DateTime(dt.year, dt.month, dt.day);
    return '${civilDigits(d)}  ·  ${hijriDigits(d)}';
  }

  static String _clockCore(DateTime dt, {bool withSeconds = false}) =>
      withSeconds
          ? '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}'
          : '${_two(dt.hour)}:${_two(dt.minute)}';

  /// yyyy/MM/dd
  static String fmtCivilDate(DateTime dt, {required bool isAr}) {
    return wrapCalendar(_civilCore(dt, isAr: isAr), isAr: isAr);
  }

  /// yyyy/MM/dd    HH:mm من قيمة خام (ISO / DateTime).
  static String fmtCivilDateTimeRaw(
    dynamic raw, {
    required bool isAr,
    bool withSeconds = false,
    String fallback = '',
  }) {
    final dt = tryParse(raw);
    if (dt == null) return fallback;
    return fmtCivilDateTime(
      dt.toLocal(),
      isAr: isAr,
      withSeconds: withSeconds,
    );
  }

  /// yyyy/MM/dd من قيمة خام.
  static String fmtCivilDateRaw(
    dynamic raw, {
    required bool isAr,
    String fallback = '',
  }) {
    final dt = tryParse(raw);
    if (dt == null) return fallback;
    return fmtCivilDate(dt.toLocal(), isAr: isAr);
  }

  /// yyyy/MM/dd    HH:mm
  static String fmtCivilDateTime(
    DateTime dt, {
    required bool isAr,
    bool withSeconds = false,
  }) {
    final core =
        '${_civilCore(dt, isAr: isAr)}$dateTimeGap${_clockCore(dt, withSeconds: withSeconds)}';
    return wrapCalendar(core, isAr: isAr);
  }

  /// هجري: yyyy/MM/dd
  static String fmtHijriDate(DateTime dt, {required bool isAr}) {
    return wrapCalendar(_hijriCore(dt, isAr: isAr), isAr: isAr);
  }

  /// هجري: yyyy/MM/dd    HH:mm
  static String fmtHijriDateTime(
    DateTime dt, {
    required bool isAr,
    bool withSeconds = false,
  }) {
    final core =
        '${_hijriCore(dt, isAr: isAr)}$dateTimeGap${_clockCore(dt, withSeconds: withSeconds)}';
    return wrapCalendar(core, isAr: isAr);
  }

  /// ساعة:دقيقة فقط (أرقام لاتينية).
  static String fmtClock(DateTime dt, {bool withSeconds = false}) =>
      _clockCore(dt, withSeconds: withSeconds);

  /// تنسيق التاريخ للواجهة — سنة/شهر/يوم ثم الوقت.
  static String fmtDateTime(DateTime dt, {bool isAr = true}) {
    return fmtCivilDateTime(dt.toLocal(), isAr: isAr);
  }

  static String _toArabicIndicDigits(String input) {
    const map = {
      '0': '٠',
      '1': '١',
      '2': '٢',
      '3': '٣',
      '4': '٤',
      '5': '٥',
      '6': '٦',
      '7': '٧',
      '8': '٨',
      '9': '٩',
    };
    final b = StringBuffer();
    for (final c in input.split('')) {
      b.write(map[c] ?? c);
    }
    return b.toString();
  }

  /// منذ كم وقت — «قبل» للدقائق، «منذ» للساعات والأيام (بدون تكرار البادئة في الواجهة).
  static String timeAgo(DateTime dt, {required bool isAr}) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    String ar(String s) => isAr ? _toArabicIndicDigits(s) : s;

    if (diff.inSeconds < 60) {
      return isAr ? 'الآن' : 'Now';
    }

    if (diff.inMinutes < 60) {
      final m = diff.inMinutes <= 1 ? 1 : diff.inMinutes;
      return isAr ? 'قبل ${ar('$m')} دقيقة' : '$m min ago';
    }

    if (diff.inHours < 24) {
      final h = diff.inHours <= 1 ? 1 : diff.inHours;
      return isAr ? 'منذ ${ar('$h')} ساعة' : '$h h ago';
    }

    if (diff.inDays < 7) {
      final d = diff.inDays <= 1 ? 1 : diff.inDays;
      return isAr ? 'منذ ${ar('$d')} يوم' : '$d days ago';
    }

    final days = diff.inDays;
    final weeks = days ~/ 7;

    if (weeks < 5) {
      return isAr ? 'منذ ${ar('$weeks')} أسبوع' : '$weeks weeks ago';
    }

    final months = days ~/ 30;
    final remWeeks = (days % 30) ~/ 7;
    if (months < 12) {
      if (remWeeks > 0) {
        return isAr
            ? 'منذ ${ar('$months')} شهر و ${ar('$remWeeks')} أسبوع'
            : '$months mo $remWeeks wk ago';
      }
      return isAr ? 'منذ ${ar('$months')} شهر' : '$months mo ago';
    }

    final years = days ~/ 365;
    final remMonths = (days % 365) ~/ 30;
    if (remMonths > 0) {
      return isAr
          ? 'منذ ${ar('$years')} سنة و ${ar('$remMonths')} شهر'
          : '$years yr $remMonths mo ago';
    }
    return isAr ? 'منذ ${ar('$years')} سنة' : '$years yr ago';
  }
}
