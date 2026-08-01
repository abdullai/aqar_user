import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'app_session.dart';

/// انتهاء جلسة الويب بعد خمول (آخر نشاط) لتفادي فتح `#/userDashboard` كآخر مستخدم
/// إلى أجل غير مسمى عند العودة لاحقاً.
///
/// يُحدَّث [touchActivity] من [InactivityService.userActivity] وعند عرض لوحة المستخدم.
const String kPrefWebLastActivityMs = 'web_last_activity_ms';

/// آخر نشاط لجلسة **الضيف** على الويب (منفصل عن جلسة المستخدم المسجّل).
const String kPrefWebGuestLastActivityMs = AppConfig.prefWebGuestLastActivityMs;

/// حد أقصى للخمول بالساعات (1–720). الافتراضي 24 ساعة.
const String kPrefWebMaxIdleHours = 'web_max_idle_hours';
const int kWebMaxIdleHoursDefault = 24;

Future<int> readWebMaxIdleHours() async {
  final p = await SharedPreferences.getInstance();
  final h = p.getInt(kPrefWebMaxIdleHours) ?? kWebMaxIdleHoursDefault;
  return h.clamp(1, 720);
}

Future<void> setWebMaxIdleHours(int hours) async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(kPrefWebMaxIdleHours, hours.clamp(1, 720));
}

/// يسجّل آخر تفاعل (لمستخدم مسجّل فقط).
Future<void> touchWebSessionActivity() async {
  if (!kIsWeb) return;
  try {
    if (Supabase.instance.client.auth.currentSession == null) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(
      kPrefWebLastActivityMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  } catch (_) {}
}

/// يحدّد نشاط الضيف على الويب (يُستدعى من لوحة الضيف ومسارات النشاط).
Future<void> touchWebGuestActivity() async {
  if (!kIsWeb) return;
  try {
    final p = await SharedPreferences.getInstance();
    final guest = p.getBool(AppSession.kPrefGuestMode) ?? false;
    final entry = (p.getString(AppSession.kPrefEntryMode) ?? '').trim().toLowerCase();
    if (!guest && entry != 'guest') return;
    await p.setInt(
      kPrefWebGuestLastActivityMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  } catch (_) {}
}

/// true إذا تجاوز ضيف الويب حد الخمول → يُعاد لشاشة اختيار الدخول.
Future<bool> shouldForceWebGuestEndDueToIdle() async {
  if (!kIsWeb) return false;
  try {
    final p = await SharedPreferences.getInstance();
    final guest = p.getBool(AppSession.kPrefGuestMode) ?? false;
    final entry = (p.getString(AppSession.kPrefEntryMode) ?? '').trim().toLowerCase();
    if (!guest && entry != 'guest') return false;

    final last = p.getInt(kPrefWebGuestLastActivityMs);
    if (last == null) return false;

    final maxHours = await readWebMaxIdleHours();
    final deadline = DateTime.fromMillisecondsSinceEpoch(last).add(
      Duration(hours: maxHours),
    );
    return DateTime.now().isAfter(deadline);
  } catch (_) {
    return false;
  }
}

Future<void> clearWebGuestIdleStamp() async {
  if (!kIsWeb) return;
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove(kPrefWebGuestLastActivityMs);
  } catch (_) {}
}

/// true إذا تجاوز الخمول الحد → يجب تسجيل خروج وإظهار الدخول.
Future<bool> shouldForceWebReauthDueToIdle() async {
  if (!kIsWeb) return false;
  try {
    if (Supabase.instance.client.auth.currentSession == null) return false;

    final p = await SharedPreferences.getInstance();
    final last = p.getInt(kPrefWebLastActivityMs);
    if (last == null) return false;

    final maxHours = await readWebMaxIdleHours();
    final deadline = DateTime.fromMillisecondsSinceEpoch(last).add(
      Duration(hours: maxHours),
    );
    return DateTime.now().isAfter(deadline);
  } catch (_) {
    return false;
  }
}

/// بعد قرار إجبار الخروج: امسح الطوابع المحلية المرتبطة بالجلسة على الويب.
Future<void> clearWebSessionAfterForcedLogout(String? uid) async {
  if (!kIsWeb) return;
  try {
    final p = await SharedPreferences.getInstance();
    await p.remove(kPrefWebLastActivityMs);
    if (uid != null && uid.isNotEmpty) {
      await p.remove(AppSession.otpVerifiedKey(uid));
    }
  } catch (_) {}
}
