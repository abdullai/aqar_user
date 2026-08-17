// lib/services/user_install_session_service.dart
//
// تسجيل الجهاز (حدّ جهازين) + مطابقة عند العودة للواجهة.
// SQL: supabase/sql/20260418210000_user_devices_two_slot_session_hints.sql

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/auth/auth_local_sign_out.dart';
import '../core/security/install_device_identity.dart';
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

  /// معرّف تثبيت مستقر لكل متصفح/تطبيق — لا يتغيّر بتغيير الحساب على نفس الجهاز.
  static Future<String> installDeviceKey() => InstallDeviceIdentity.key();

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
    final map = <String, dynamic>{
      'install_id': key,
      'platform': platform,
      'label': label,
    };
    // إحداثيات اختيار الاستكشاف المحفوظة (إن وُجدت) — تُحسّن دقة «المدينة» على الخادم عند دعمها.
    try {
      final p = await SharedPreferences.getInstance();
      final lat = p.getDouble(AppConfig.prefPreferredExploreLatKey);
      final lng = p.getDouble(AppConfig.prefPreferredExploreLngKey);
      if (lat != null && lng != null && lat.abs() > 1e-6 && lng.abs() > 1e-6) {
        map['approx_lat'] = lat;
        map['approx_lng'] = lng;
      }
    } catch (_) {}
    return jsonEncode(map);
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
  static Future<RegisterDeviceSlotResult>? _registerInFlight;

  static Future<RegisterDeviceSlotResult>
      registerDeviceSlotAfterSignIn() async {
    final existing = _registerInFlight;
    if (existing != null) return existing;

    final fut = _registerDeviceSlotAfterSignInImpl();
    _registerInFlight = fut;
    try {
      return await fut;
    } finally {
      if (identical(_registerInFlight, fut)) {
        _registerInFlight = null;
      }
    }
  }

  static Future<RegisterDeviceSlotResult>
      _registerDeviceSlotAfterSignInImpl() async {
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

    // أثناء مسار الدخول/OTP الجهاز غالباً غير مسجّل بعد — لا تطرد الجلسة.
    if (_isAuthFlowRoute()) return;

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

  static bool _isAuthFlowRoute() {
    final ctx = UserSessionCoordinationService.navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    final name = ModalRoute.of(ctx)?.settings.name ?? '';
    return name == '/login' ||
        name == '/fastLogin' ||
        name == '/' ||
        name == '/gate' ||
        name == '/verify' ||
        name == '/entryChoice' ||
        name == '/passwordSetup' ||
        name == '/deviceManagement';
  }

  static Future<void> _kickLocalSessionReplaced() async {
    final navKey = UserSessionCoordinationService.navigatorKey;
    // مهم: افحص المسار قبل signOut — سابقاً كان يُلغي الجلسة أثناء /verify
    // فيفشل request_inapp_otp بـ not_authenticated (400 في سجلات Supabase).
    if (_isAuthFlowRoute()) return;

    if (navKey != null) {
      await ReturnAfterAuth.saveFromNavigatorKey(navKey);
    }
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession != null) {
        await AuthLocalSignOut.signOutLocal(Supabase.instance.client);
      }
    } catch (_) {}
    final nav = navKey?.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil('/login', (r) => false);
  }
}
