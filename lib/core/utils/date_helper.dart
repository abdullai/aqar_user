// lib/core/utils/date_helper.dart

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

  /// تنسيق التاريخ
  static String fmtDateTime(DateTime dt) {
    final d = dt.toLocal();

    String two(int v) => v.toString().padLeft(2, '0');

    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
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

  /// منذ كم وقت
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
      return isAr ? 'قبل ${ar('$h')} ساعة' : '$h h ago';
    }

    if (diff.inDays < 7) {
      final d = diff.inDays <= 1 ? 1 : diff.inDays;
      return isAr ? 'قبل ${ar('$d')} يومًا' : '$d days ago';
    }

    final days = diff.inDays;
    final weeks = days ~/ 7;

    if (weeks < 5) {
      return isAr ? 'قبل ${ar('$weeks')} أسبوعًا' : '$weeks weeks ago';
    }

    final months = days ~/ 30;
    final remWeeks = (days % 30) ~/ 7;
    if (months < 12) {
      if (remWeeks > 0) {
        return isAr
            ? 'قبل ${ar('$months')} شهر و ${ar('$remWeeks')} أسبوع'
            : '$months mo $remWeeks wk ago';
      }
      return isAr ? 'قبل ${ar('$months')} شهر' : '$months mo ago';
    }

    final years = days ~/ 365;
    final remMonths = (days % 365) ~/ 30;
    if (remMonths > 0) {
      return isAr
          ? 'قبل ${ar('$years')} سنة و ${ar('$remMonths')} شهر'
          : '$years yr $remMonths mo ago';
    }
    return isAr ? 'قبل ${ar('$years')} سنة' : '$years yr ago';
  }
}
