import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'one_time_prompt_coordinator.dart';

/// تفضيلات أول تشغيل: الجولة ولون التمييز مربوطان بالحساب قدر الإمكان.
abstract final class DeviceFirstRunPrefs {
  static const String _tourDoneDevice = 'device_dashboard_tour_done_v1';
  static const String _accentDoneDevice = 'device_accent_color_done_v1';
  static const String _replayPending = 'pending_dashboard_tour_replay_v1';

  static String? get _uid {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static String _tourDoneKeyFor(String? uid) {
    final u = (uid ?? '').trim();
    if (u.isEmpty) return _tourDoneDevice;
    return 'user_dashboard_tour_done_v1__$u';
  }

  static String _accentDoneKeyFor(String? uid) {
    final u = (uid ?? '').trim();
    if (u.isEmpty) return _accentDoneDevice;
    return 'user_accent_color_done_v1__$u';
  }

  static Future<bool> isDashboardTourDone({String? userId}) async {
    final p = await SharedPreferences.getInstance();
    final uid = userId ?? _uid;
    final key = _tourDoneKeyFor(uid);
    if (p.getBool(key) == true) return true;
    final u = (uid ?? '').trim();
    if (u.isEmpty) {
      // ضيف / بلا جلسة: مفتاح الجهاز فقط.
      return (p.getBool(_tourDoneDevice) ?? false) ||
          await OneTimePromptCoordinator.hasSeen('dashboard_onboarding_v3');
    }
    // حساب مسجّل: لا ترث جولة جهاز/حساب آخر — كل مستخدم يرى الجولة مرة.
    return false;
  }

  static Future<void> setDashboardTourDone({String? userId}) async {
    final p = await SharedPreferences.getInstance();
    final uid = userId ?? _uid;
    await p.setBool(_tourDoneKeyFor(uid), true);
    if ((uid ?? '').trim().isEmpty) {
      await p.setBool(_tourDoneDevice, true);
      await OneTimePromptCoordinator.markSeen('dashboard_onboarding_v3');
    }
  }

  /// لون التمييز: لكل مستخدم على حدة (لا يُورَّث بين الحسابات على نفس الجهاز).
  static Future<bool> isAccentPromptDone({String? userId}) async {
    final p = await SharedPreferences.getInstance();
    final uid = userId ?? _uid;
    final key = _accentDoneKeyFor(uid);
    if (p.getBool(key) == true) return true;

    final scoped = OneTimePromptCoordinator.idForUser(
      'accent_color_prompt_v1',
      uid,
    );
    if (await OneTimePromptCoordinator.hasSeen(scoped)) {
      await p.setBool(key, true);
      return true;
    }
    // لا تعتمد على المفتاح العالمي — يمنع حساباً جديداً من رؤية الحوار.
    return false;
  }

  static Future<void> setAccentPromptDone({String? userId}) async {
    final p = await SharedPreferences.getInstance();
    final uid = userId ?? _uid;
    final key = _accentDoneKeyFor(uid);
    await p.setBool(key, true);
    await OneTimePromptCoordinator.markSeen(
      OneTimePromptCoordinator.idForUser('accent_color_prompt_v1', uid),
    );
  }

  /// من الإعدادات: إعادة الجولة من الرئيسية ثم لون التمييز بعدها.
  static Future<void> requestDashboardTourReplay() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_replayPending, true);
  }

  /// يُستدعى من لوحة التحكم عند العودة/التحديث.
  static Future<bool> consumeReplayPending() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool(_replayPending) ?? false;
    if (v) await p.remove(_replayPending);
    return v;
  }

  static Future<void> clearTourAndAccentForReplay() async {
    final p = await SharedPreferences.getInstance();
    final uid = _uid;
    await p.remove(_tourDoneKeyFor(uid));
    await p.remove(_accentDoneKeyFor(uid));
    await OneTimePromptCoordinator.resetForDebug(
      OneTimePromptCoordinator.idForUser('accent_color_prompt_v1', uid),
    );
  }

  /// للترقية من مفاتيح [OneTimePromptCoordinator] القديمة دون إعادة إزعاج المستخدم الحالي فقط.
  static Future<void> syncLegacyOneTimeIntoDeviceFlags() async {
    final p = await SharedPreferences.getInstance();
    final uid = _uid;
    final u = (uid ?? '').trim();
    // لا تنسخ مفاتيح الجهاز العالمية إلى حساب جديد.
    if (u.isEmpty) return;

    final accentScoped = OneTimePromptCoordinator.idForUser(
      'accent_color_prompt_v1',
      uid,
    );
    if (await OneTimePromptCoordinator.hasSeen(accentScoped)) {
      final key = _accentDoneKeyFor(uid);
      if (p.getBool(key) != true) await p.setBool(key, true);
    }
  }
}
