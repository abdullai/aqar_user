import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// تتبع جلسات الدخول/الخروج عبر RPCs آمنة (`log_user_session_*`).
class SessionTrackingService {
  SessionTrackingService._();

  static const _kPrefSessionId = 'tracked_user_session_row_v1';

  static Future<({String device, String browser, String os})> _deviceContext() async {
    final plugin = DeviceInfoPlugin();
    if (kIsWeb) {
      final w = await plugin.webBrowserInfo;
      final browser = w.browserName.name;
      return (
        device: 'Web',
        browser: browser,
        os: (w.platform ?? '').trim(),
      );
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await plugin.androidInfo;
        return (
          device: '${a.manufacturer} ${a.model}'.trim(),
          browser: '',
          os: 'Android ${a.version.release}',
        );
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await plugin.iosInfo;
        return (
          device: i.name.isNotEmpty ? i.name : i.model,
          browser: '',
          os: '${i.systemName} ${i.systemVersion}',
        );
      }
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final w = await plugin.windowsInfo;
        return (
          device: w.computerName.isNotEmpty ? w.computerName : 'Windows',
          browser: '',
          os: w.productName,
        );
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final m = await plugin.macOsInfo;
        return (
          device: m.computerName.isNotEmpty ? m.computerName : m.model,
          browser: '',
          os: 'macOS ${m.osRelease}',
        );
      }
      if (defaultTargetPlatform == TargetPlatform.linux) {
        final l = await plugin.linuxInfo;
        return (
          device: l.prettyName.isNotEmpty ? l.prettyName : l.name,
          browser: '',
          os: l.version ?? 'Linux',
        );
      }
    } catch (_) {}
    return (device: 'Unknown', browser: '', os: '');
  }

  /// مدينة/منطقة تقريبية فقط (بدون تخزين إحداثيات دقيقة في التطبيق).
  static Future<String?> coarseLocationLabel() async {
    // على الويب [Geolocator] قد يطيل أو يعلّق أول إطار بعد الدخول.
    if (kIsWeb) return null;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 12),
      );
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isEmpty) return null;
      final m = marks.first;
      final parts = <String>[
        (m.locality ?? '').trim(),
        (m.subAdministrativeArea ?? '').trim(),
        (m.administrativeArea ?? '').trim(),
      ].where((e) => e.isNotEmpty).toList();
      if (parts.isEmpty) return null;
      return parts.take(3).join(', ');
    } catch (_) {
      return null;
    }
  }

  static Future<void> recordLoginStart(
    SupabaseClient client, {
    required String loginMethod,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ctx = await _deviceContext().timeout(
        const Duration(seconds: 3),
        onTimeout: () => (device: 'Unknown', browser: '', os: ''),
      );
      final loc = await coarseLocationLabel().timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );
      // الويب والجوال: نفس الـ RPC عند توفره على المشروع — الفشل صامت ولا يعيق الدخول.
      final raw = await client
          .rpc(
            'log_user_session_start',
            params: {
              'p_device_info': ctx.device,
              'p_browser_info': ctx.browser,
              'p_os_info': ctx.os,
              'p_ip': null,
              'p_location': loc,
              'p_login_method': loginMethod,
            },
          )
          .timeout(const Duration(seconds: 4));
      if (raw is Map && raw['ok'] == true) {
        final id = raw['session_id']?.toString() ?? '';
        if (id.isNotEmpty) await prefs.setString(_kPrefSessionId, id);
      }
    } catch (_) {
      if (kDebugMode && kIsWeb) {
        // ignore: avoid_print
        print('[session_tracking] log_user_session_start skipped: RPC or network');
      }
    }
  }

  static Future<void> recordLogoutEnd(
    SupabaseClient client, {
    String reason = 'user_logout',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kPrefSessionId);
      if (id == null || id.isEmpty) return;
      await client
          .rpc(
            'log_user_session_end',
            params: {
              'p_session_id': id,
              'p_reason': reason,
            },
          )
          .timeout(const Duration(seconds: 6));
      await prefs.remove(_kPrefSessionId);
    } catch (_) {}
  }

  static Future<String?> currentTrackedSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPrefSessionId);
  }

  /// إزالة معرف الجلسة المحلي دون استدعاء الشبكة (آمن عند الخروج على الويب).
  static Future<void> clearLocalTrackingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefSessionId);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> revokeOtherSessions(
    SupabaseClient client, {
    String? keepSessionId,
  }) async {
    try {
      final raw = await client.rpc(
        'revoke_my_other_sessions',
        params: {
          'p_keep_session_id': keepSessionId,
        },
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return {'ok': false};
  }
}
