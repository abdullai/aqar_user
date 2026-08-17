import 'package:flutter/foundation.dart';

/// تسميات عرض صديقة للغة لبيانات الجهاز/الجلسة (بدون رموز خام).
abstract final class DeviceDisplayLabels {
  static String platform(String? raw, {required bool isAr}) {
    final p = (raw ?? '').trim().toLowerCase();
    if (p.isEmpty) return isAr ? 'غير معروف' : 'Unknown';
    if (p.contains('web')) return isAr ? 'متصفح ويب' : 'Web browser';
    if (p.contains('android')) return isAr ? 'أندرويد' : 'Android';
    if (p.contains('ios') || p.contains('iphone') || p.contains('ipad')) {
      return isAr ? 'آيفون / آيباد' : 'iOS';
    }
    if (p.contains('windows') || p == 'win') {
      return isAr ? 'ويندوز' : 'Windows';
    }
    if (p.contains('macos') || p.contains('mac')) {
      return isAr ? 'ماك' : 'macOS';
    }
    if (p.contains('linux')) return isAr ? 'لينكس' : 'Linux';
    return raw!.trim();
  }

  static String browser(String? raw, {required bool isAr}) {
    final b = (raw ?? '').trim().toLowerCase();
    if (b.isEmpty) return '';
    if (b.contains('chrome') || b == 'chrome') {
      return isAr ? 'كروم' : 'Chrome';
    }
    if (b.contains('safari')) return isAr ? 'سفاري' : 'Safari';
    if (b.contains('firefox')) return isAr ? 'فايرفوكس' : 'Firefox';
    if (b.contains('edge')) return isAr ? 'إيدج' : 'Edge';
    if (b.contains('opera')) return isAr ? 'أوبرا' : 'Opera';
    if (b.contains('samsung')) return isAr ? 'سامسونج إنترنت' : 'Samsung Internet';
    return raw!.trim();
  }

  static String device(String? raw, {required bool isAr}) {
    final d = (raw ?? '').trim();
    if (d.isEmpty) return isAr ? 'جهاز غير معروف' : 'Unknown device';
    final lower = d.toLowerCase();
    if (lower == 'web' || lower == 'unknown') {
      return isAr ? 'متصفح ويب' : 'Web browser';
    }
    if (lower == 'windows') return isAr ? 'جهاز ويندوز' : 'Windows device';
    return d;
  }

  static String loginMethod(String? raw, {required bool isAr}) {
    final m = (raw ?? '').trim().toLowerCase();
    if (m.isEmpty) return '';
    if (m.contains('password') || m == 'password') {
      return isAr ? 'كلمة المرور' : 'Password';
    }
    if (m.contains('otp') || m.contains('code')) {
      return isAr ? 'رمز تحقق' : 'Verification code';
    }
    if (m.contains('nafath')) return isAr ? 'نفاذ' : 'Nafath';
    if (m.contains('fast') || m.contains('biometric') || m.contains('pin')) {
      return isAr ? 'دخول سريع' : 'Fast login';
    }
    if (m.contains('guest')) return isAr ? 'ضيف' : 'Guest';
    return raw!.trim();
  }

  static String os(String? raw, {required bool isAr}) {
    final o = (raw ?? '').trim();
    if (o.isEmpty) return '';
    final lower = o.toLowerCase();
    if (lower.contains('android')) {
      return o.replaceFirst(RegExp(r'[Aa]ndroid'), isAr ? 'أندرويد' : 'Android');
    }
    if (lower.startsWith('iphone') || lower.contains('ios')) {
      return isAr ? o.replaceAllMapped(RegExp(r'iPhone|iOS|iPad'), (m) {
        final v = m.group(0)!;
        if (v.toLowerCase() == 'iphone') return 'آيفون';
        if (v.toLowerCase() == 'ipad') return 'آيباد';
        return 'iOS';
      }) : o;
    }
    if (lower.contains('windows')) {
      return isAr ? o.replaceFirst(RegExp(r'[Ww]indows'), 'ويندوز') : o;
    }
    if (lower.contains('mac')) {
      return isAr ? o.replaceFirst(RegExp(r'macOS|Mac OS|mac', caseSensitive: false), 'ماك') : o;
    }
    return o;
  }

  static String shortFingerprint(String? fp, {required bool isAr}) {
    final s = (fp ?? '').trim();
    if (s.isEmpty) return isAr ? '—' : '—';
    if (s.length <= 12) return s;
    return '…${s.substring(s.length - 10)}';
  }

  static String currentInstallHint({required bool isAr}) =>
      isAr ? 'هذا الجهاز' : 'This device';
}
