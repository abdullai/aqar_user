import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_challenge_service.dart';
import 'login_security_db.dart';
import '../input/input_normalizers.dart';
import '../utils/profile_greeting_from_row.dart';

/// تسليم فوري لرمز التحقق داخل التطبيق + بيانات الترحيب قبل فتح الشاشة.
abstract final class InAppOtpHandoff {
  static const int otpLen = 6;

  /// شريط علوي برمز التحقق على كل الأسطح (ويب سطح المكتب والجوال والتطبيق).
  static bool useDesktopOtpBanner(BuildContext context) => true;

  static String? digitsFromAny(String? raw, {int len = otpLen}) {
    final only = digitsOnly(normalizeAsciiDigits(raw ?? ''));
    if (only.isEmpty) return null;
    return only.length >= len ? only.substring(0, len) : only;
  }

  static String? codeFromNotificationRow(Map<String, dynamic> row) {
    final typeNorm = (row['type'] ?? '').toString().trim().toLowerCase();
    if (typeNorm != 'otp') return null;

    String code = '';
    final data = row['data'];
    if (data is Map) {
      code = (data['code'] ?? '').toString().trim();
    } else if (data != null) {
      final s = data.toString();
      final only = s.replaceAll(RegExp(r'\D'), '');
      if (only.length >= otpLen) code = only.substring(0, otpLen);
    }
    if (code.isEmpty) {
      final body = (row['body'] ?? '').toString();
      final only = body.replaceAll(RegExp(r'\D'), '');
      if (only.length >= otpLen) code = only.substring(0, otpLen);
    }
    return digitsFromAny(code);
  }

  static DateTime? createdAtOf(Map<String, dynamic> row) {
    return DateTime.tryParse((row['created_at'] ?? '').toString());
  }

  /// أحدث رمز OTP للمختبر في بيئة internal فقط عبر RPC peek — ليس من جدول الإشعارات.
  static Future<String?> fetchLatestCode({
    DateTime? notBeforeUtc,
    String? challengeId,
  }) async {
    try {
      if (Supabase.instance.client.auth.currentSession == null) return null;
      var id = (challengeId ?? '').trim();
      if (id.isEmpty) {
        final pending = await AuthChallengeService.readPending();
        id = (pending.challengeId ?? '').trim();
      }
      if (id.isEmpty) return null;
      final peeked = await AuthChallengeService.peekDevCode(id);
      if (peeked != null && peeked.length >= otpLen) return peeked;
    } catch (_) {}
    return null;
  }

  static Future<String?> pollLatestCode({
    required DateTime requestedAtUtc,
    String? challengeId,
    List<int> delaysMs = const [0, 70, 160, 280, 450, 700, 1100],
  }) async {
    for (final ms in delaysMs) {
      if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms));
      final code = await fetchLatestCode(
        notBeforeUtc: requestedAtUtc,
        challengeId: challengeId,
      );
      if (code != null && code.length >= otpLen) return code;
    }
    return fetchLatestCode(challengeId: challengeId);
  }

  static Future<InAppOtpGreeting> fetchGreeting({required bool isAr}) async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return const InAppOtpGreeting();
      final raw = await Supabase.instance.client
          .from('users_profiles')
          .select(LoginSecurityDb.usersProfilesSelectForVerifyGreeting)
          .eq('user_id', uid)
          .maybeSingle();
      if (raw == null) return const InAppOtpGreeting();
      final row = Map<String, dynamic>.from(raw);
      return InAppOtpGreeting(
        displayName: ProfileGreetingFromRow.displayName(row, isAr: isAr),
        lastLogin: ProfileGreetingFromRow.lastLoginAt(row),
        avatarUrl: (row['avatar_url'] ?? '').toString().trim(),
      );
    } catch (_) {
      return const InAppOtpGreeting();
    }
  }

  /// ختم بصري للجلسة — ليس الرمز، يمنع الخلط بين محاولتين.
  static String sessionSeal({
    required String sessionId,
    required String username,
  }) {
    final src = utf8.encode('$sessionId|$username');
    final digest = sha256.convert(src).toString().substring(0, 6).toUpperCase();
    return digest;
  }
}

@immutable
class InAppOtpGreeting {
  const InAppOtpGreeting({
    this.displayName,
    this.lastLogin,
    this.avatarUrl,
  });

  final String? displayName;
  final DateTime? lastLogin;
  final String? avatarUrl;
}
