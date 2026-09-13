import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/install_device_identity.dart';
import 'auth_completion_policy.dart';

class AuthChallengeStart {
  const AuthChallengeStart({
    required this.ok,
    required this.needsOtp,
    required this.fullyAuthenticated,
    this.challengeId,
    this.expiresAt,
    this.devCode,
    this.error,
    this.otpProvider,
    this.trusted = false,
  });

  final bool ok;
  final bool needsOtp;
  final bool fullyAuthenticated;
  final String? challengeId;
  final DateTime? expiresAt;
  final String? devCode;
  final String? error;
  final String? otpProvider;
  final bool trusted;
}

class AuthGateStatus {
  const AuthGateStatus({
    required this.complete,
    required this.needsOtp,
    this.challengeId,
    this.error,
  });

  final bool complete;
  final bool needsOtp;
  final String? challengeId;
  final String? error;
}

class AuthOtpVerifyResult {
  const AuthOtpVerifyResult({
    required this.ok,
    this.locked = false,
    this.remainingAttempts,
    this.error,
  });

  final bool ok;
  final bool locked;
  final int? remainingAttempts;
  final String? error;
}

/// تحدّي تسجيل الدخول + بوابة الجلسة. الخادم هو مصدر الحقيقة.
abstract final class AuthChallengeService {
  static const pendingChallengeKey = 'auth_pending_challenge_id';
  static const pendingUsernameKey = 'auth_pending_username';

  static SupabaseClient get _sb => Supabase.instance.client;

  static String clientPlatform() => AuthCompletionPolicy.clientPlatformLabel(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );

  static bool allowQuickUnlockOnThisSurface() =>
      AuthCompletionPolicy.allowFastLogin(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  static DateTime? _parseTime(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  static AuthChallengeStart _parseStart(dynamic raw) {
    final m = _asMap(raw);
    final err = (m['error'] ?? '').toString().trim();
    return AuthChallengeStart(
      ok: m['ok'] != false && err.isEmpty,
      needsOtp: m['needs_otp'] == true,
      fullyAuthenticated: m['fully_authenticated'] == true,
      challengeId: (m['challenge_id'] ?? '').toString().trim().isEmpty
          ? null
          : (m['challenge_id'] ?? '').toString().trim(),
      expiresAt: _parseTime(m['expiresAt'] ?? m['expires_at']),
      devCode: () {
        final c = (m['dev_code'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
        return c.length >= 6 ? c.substring(0, 6) : null;
      }(),
      error: err.isEmpty ? null : err,
      otpProvider: (m['otp_provider'] ?? '').toString().trim().isEmpty
          ? null
          : (m['otp_provider'] ?? '').toString().trim(),
      trusted: m['trusted'] == true,
    );
  }

  static Future<void> persistPending({
    required String? challengeId,
    required String username,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      final id = (challengeId ?? '').trim();
      if (id.isEmpty) {
        await p.remove(pendingChallengeKey);
      } else {
        await p.setString(pendingChallengeKey, id);
      }
      final u = username.trim();
      if (u.isEmpty) {
        await p.remove(pendingUsernameKey);
      } else {
        await p.setString(pendingUsernameKey, u);
      }
    } catch (_) {}
  }

  static Future<void> clearPending() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(pendingChallengeKey);
      await p.remove(pendingUsernameKey);
    } catch (_) {}
  }

  static Future<({String? challengeId, String? username})> readPending() async {
    try {
      final p = await SharedPreferences.getInstance();
      final id = (p.getString(pendingChallengeKey) ?? '').trim();
      final u = (p.getString(pendingUsernameKey) ?? '').trim();
      return (
        challengeId: id.isEmpty ? null : id,
        username: u.isEmpty ? null : u,
      );
    } catch (_) {
      return (challengeId: null, username: null);
    }
  }

  static Future<AuthChallengeStart> start({
    required String username,
    String loginMethod = 'password',
    String purpose = 'login',
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      return const AuthChallengeStart(
        ok: false,
        needsOtp: true,
        fullyAuthenticated: false,
        error: 'not_authenticated',
      );
    }

    final fp = await InstallDeviceIdentity.key();
    try {
      final res = await _sb.rpc(
        'start_login_challenge',
        params: {
          'p_username': username,
          'p_platform': clientPlatform(),
          'p_device_fingerprint': fp,
          'p_login_method': loginMethod,
          'p_purpose': purpose,
        },
      );
      final parsed = _parseStart(res);
      if (parsed.needsOtp && parsed.challengeId != null) {
        await persistPending(
          challengeId: parsed.challengeId,
          username: username,
        );
      } else if (parsed.fullyAuthenticated) {
        await clearPending();
      }
      return parsed;
    } catch (e) {
      final raw = e.toString();
      final lower = raw.toLowerCase();
      String err = raw;
      if (lower.contains('not_authenticated')) err = 'not_authenticated';
      if (lower.contains('username_not_current_user')) {
        err = 'username_not_current_user';
      }
      if (lower.contains('rate')) err = 'rate_limited';
      return AuthChallengeStart(
        ok: false,
        needsOtp: true,
        fullyAuthenticated: false,
        error: err,
      );
    }
  }

  static Future<AuthGateStatus> gateStatus() async {
    try {
      if (_sb.auth.currentSession == null) {
        return const AuthGateStatus(complete: false, needsOtp: false);
      }
      final res = await _sb.rpc('get_auth_gate_status');
      final m = _asMap(res);
      final cid = (m['challenge_id'] ?? '').toString().trim();
      return AuthGateStatus(
        complete: m['complete'] == true,
        needsOtp: m['needs_otp'] == true,
        challengeId: cid.isEmpty ? null : cid,
        error: (m['error'] ?? '').toString().trim().isEmpty
            ? null
            : (m['error'] ?? '').toString().trim(),
      );
    } catch (_) {
      return const AuthGateStatus(
        complete: false,
        needsOtp: false,
        error: 'gate_unavailable',
      );
    }
  }

  /// فشل مغلق: إن تعذّر السؤال يُفترض أن OTP مطلوب (لا تُفتح اللوحة).
  static Future<bool> isFullyAuthenticated() async {
    final g = await gateStatus();
    return g.complete;
  }

  static Future<bool> isNativeDeviceTrustedOnServer() async {
    if (!allowQuickUnlockOnThisSurface()) return false;
    try {
      final fp = await InstallDeviceIdentity.key();
      final res = await _sb.rpc(
        'eval_login_trust',
        params: {
          'p_platform': clientPlatform(),
          'p_device_fingerprint': fp,
          'p_login_method': 'password',
        },
      );
      final m = _asMap(res);
      return m['trusted'] == true && m['otp_required'] != true;
    } catch (_) {
      return false;
    }
  }

  static Future<AuthOtpVerifyResult> verify({
    required String code,
    String? challengeId,
    String? username,
  }) async {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    var cid = (challengeId ?? '').trim();
    if (cid.isEmpty) {
      final pending = await readPending();
      cid = (pending.challengeId ?? '').trim();
    }

    if (cid.isNotEmpty) {
      try {
        final res = await _sb.rpc(
          'verify_login_otp',
          params: {
            'p_challenge_id': cid,
            'p_code': digits,
          },
        );
        final m = _asMap(res);
        final ok = m['ok'] == true;
        if (ok) await clearPending();
        return AuthOtpVerifyResult(
          ok: ok,
          locked: m['locked'] == true,
          remainingAttempts: int.tryParse('${m['remaining_attempts'] ?? ''}'),
          error: (m['error'] ?? '').toString().trim().isEmpty
              ? null
              : (m['error'] ?? '').toString().trim(),
        );
      } catch (e) {
        return AuthOtpVerifyResult(ok: false, error: e.toString());
      }
    }

    final u = (username ?? '').trim();
    if (u.isEmpty) {
      return const AuthOtpVerifyResult(ok: false, error: 'challenge_not_found');
    }
    try {
      final v = await _sb.rpc(
        'verify_inapp_otp',
        params: {'p_username': u, 'p_code': digits},
      );
      final legacy = (v is bool) ? v : (v?.toString() == 'true');
      if (legacy) await clearPending();
      return AuthOtpVerifyResult(
        ok: legacy,
        error: legacy ? null : 'invalid_code',
      );
    } catch (e) {
      return AuthOtpVerifyResult(ok: false, error: e.toString());
    }
  }

  static Future<String?> peekDevCode(String? challengeId) async {
    final id = (challengeId ?? '').trim();
    if (id.isEmpty) return null;
    try {
      final res = await _sb.rpc(
        'peek_dev_login_otp',
        params: {'p_challenge_id': id},
      );
      final m = _asMap(res);
      if (m['ok'] != true) return null;
      final c = (m['code'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (c.length >= 6) return c.substring(0, 6);
    } catch (_) {}
    return null;
  }

  static Future<AuthChallengeStart> confirmTrustedNativeUnlock() async {
    if (!allowQuickUnlockOnThisSurface()) {
      return const AuthChallengeStart(
        ok: false,
        needsOtp: true,
        fullyAuthenticated: false,
        error: 'fast_login_forbidden',
      );
    }
    try {
      final fp = await InstallDeviceIdentity.key();
      final res = await _sb.rpc(
        'confirm_trusted_native_unlock',
        params: {
          'p_platform': clientPlatform(),
          'p_device_fingerprint': fp,
        },
      );
      final parsed = _parseStart(res);
      if (parsed.fullyAuthenticated) await clearPending();
      return parsed;
    } catch (e) {
      return AuthChallengeStart(
        ok: false,
        needsOtp: true,
        fullyAuthenticated: false,
        error: e.toString(),
      );
    }
  }
}
