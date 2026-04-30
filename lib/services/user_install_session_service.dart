// lib/services/user_install_session_service.dart
//
// تسجيل الجهاز (حدّ جهازين) + مطابقة عند العودة للواجهة.
// SQL: supabase/sql/20260418210000_user_devices_two_slot_session_hints.sql

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../core/session/return_after_auth.dart';
import 'auth_service.dart';
import 'user_session_coordination_service.dart';

class RegisterDeviceSlotResult {
  const RegisterDeviceSlotResult._({required this.ok, this.code});

  final bool ok;
  final String? code;

  static RegisterDeviceSlotResult success() =>
      const RegisterDeviceSlotResult._(ok: true);

  static RegisterDeviceSlotResult deviceLimit() =>
      const RegisterDeviceSlotResult._(ok: false, code: 'device_limit');
}

class UserInstallSessionService {
  UserInstallSessionService._();

  static const _prefInstallKey = 'aqar_install_device_key';

  static Future<String> installDeviceKey() async {
    final p = await SharedPreferences.getInstance();
    var k = p.getString(_prefInstallKey);
    if (k == null || k.trim().isEmpty) {
      k = const Uuid().v4();
      await p.setString(_prefInstallKey, k);
    }
    return k;
  }

  static Future<bool> _isGuestMode() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool('guest_mode') ?? false) return true;
      final e = (p.getString('entry_mode') ?? '').trim().toLowerCase();
      return e == 'guest';
    } catch (_) {
      return false;
    }
  }

  /// حمولة JSON للـ RPC (install_id + منصة + وصف).
  static Future<String> devicePayloadForRpc() async => _devicePayload();

  static Future<String> _devicePayload() async {
    final key = await installDeviceKey();
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final label = await AuthService.devicePlatformModelLabel();
    return jsonEncode({
      'install_id': key,
      'platform': platform,
      'label': label,
    });
  }

  static Future<String?> _preferredCityDisplay() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(AppConfig.prefPreferredExploreDisplayKey);
    } catch (_) {
      return null;
    }
  }

  /// تلميحات لـ bump_user_session_epoch (مدينة تقريبية + وصف الجهاز).
  static Future<({String? city, String? label})> sessionHintsForBump() async {
    final city = await _preferredCityDisplay();
    final label = await AuthService.devicePlatformModelLabel();
    return (city: city, label: label);
  }

  /// بعد تسجيل الدخول: حجز خانة جهاز (حدّ 2) أو إرجاع device_limit.
  static Future<RegisterDeviceSlotResult>
      registerDeviceSlotAfterSignIn() async {
    if (await _isGuestMode()) return RegisterDeviceSlotResult.success();
    if (Supabase.instance.client.auth.currentSession == null) {
      return RegisterDeviceSlotResult.success();
    }

    final payload = await _devicePayload();
    final city = await _preferredCityDisplay();

    try {
      final raw = await Supabase.instance.client.rpc(
        'register_user_device_slot',
        params: {
          'p_device': payload,
          'p_city': city,
        },
      );
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        if (m['ok'] == false && '${m['code']}' == 'device_limit') {
          return RegisterDeviceSlotResult.deviceLimit();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[install_session] register_user_device_slot: $e');
      }
    }
    return RegisterDeviceSlotResult.success();
  }

  /// هل هذا التثبيت المحلي مسجل ضمن أجهزة الحساب الحالية؟
  ///
  /// يستخدمه مسار الدخول السريع بعد كلمة المرور حتى لا يتجاوز OTP إذا حذف
  /// المستخدم هذا الجهاز من إدارة الأجهزة.
  static Future<bool> isCurrentInstallRegistered() async {
    if (Supabase.instance.client.auth.currentSession == null) return false;
    try {
      final key = await installDeviceKey();
      final rows = await Supabase.instance.client
          .from('user_devices')
          .select('id')
          .eq('device_fingerprint', key)
          .limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// إعادة المحاولة من شاشة إدارة الأجهزة بعد حذف جهاز.
  static Future<RegisterDeviceSlotResult> retryRegisterDeviceSlot() async {
    return registerDeviceSlotAfterSignIn();
  }

  /// عند العودة للواجهة: تحديث أو اكتشاف أن هذا الجهاز لم يعد مسجّلاً.
  static Future<void> reconcileSlotOnForeground() async {
    if (await _isGuestMode()) return;
    if (Supabase.instance.client.auth.currentSession == null) return;

    try {
      final payload = await _devicePayload();
      final raw = await Supabase.instance.client.rpc(
        'reconcile_user_device_slot',
        params: {'p_device': payload},
      );

      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      if (m['ok'] == false && '${m['error']}' == 'device_not_registered') {
        await _kickLocalSessionReplaced();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[install_session] reconcile_user_device_slot: $e');
      }
    }
  }

  static Future<void> _kickLocalSessionReplaced() async {
    final navKey = UserSessionCoordinationService.navigatorKey;
    if (navKey != null) {
      await ReturnAfterAuth.saveFromNavigatorKey(navKey);
    }
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession != null) {
        await auth.signOut(scope: SignOutScope.local);
      }
    } catch (_) {}
    final nav = navKey?.currentState;
    if (nav == null) return;
    final ctx = navKey?.currentContext;
    if (ctx != null && ctx.mounted) {
      final name = ModalRoute.of(ctx)?.settings.name ?? '';
      if (name == '/login' ||
          name == '/fastLogin' ||
          name == '/' ||
          name == '/gate' ||
          name == '/verify' ||
          name == '/entryChoice' ||
          name == '/passwordSetup' ||
          name == '/deviceManagement') {
        return;
      }
    }
    nav.pushNamedAndRemoveUntil('/login', (r) => false);
  }
}
