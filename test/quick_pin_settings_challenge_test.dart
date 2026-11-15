import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quick PIN settings OTP is action and device bound', () {
    final sql = File(
      'supabase/migrations/20261115030000_secure_fast_pin_settings_otp.sql',
    ).readAsStringSync();

    expect(sql, contains('request_fast_pin_settings_otp'));
    expect(sql, contains('verify_fast_pin_settings_otp'));
    expect(sql, contains("'fast_pin_settings_' || action"));
    expect(sql, contains('public._auth_device_trusted(uid, fingerprint)'));
    expect(sql,
        contains('challenge.device_fingerprint IS DISTINCT FROM fingerprint'));
  });

  test('development OTP plaintext is cleared after use or expiry', () {
    final sql = File(
      'supabase/migrations/20261115030000_secure_fast_pin_settings_otp.sql',
    ).readAsStringSync();

    expect(sql, contains('CREATE TRIGGER auth_login_challenges_clear_dev_otp'));
    expect(sql, contains('otp_dev_plain = NULL'));
    expect(sql, contains('clear_inactive_auth_dev_otp'));
  });

  test('cleanup cron job is unscheduled only when owned job exists', () {
    final sql = File(
      'supabase/migrations/20261115030000_secure_fast_pin_settings_otp.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains(RegExp(
        r"IF EXISTS\s*\(\s*SELECT 1 FROM cron\.job\s*"
        r"WHERE jobname = 'clear_inactive_auth_dev_otp'\s*"
        r"AND username = current_user\s*\)\s*THEN\s*"
        r"PERFORM cron\.unschedule\('clear_inactive_auth_dev_otp'\);\s*"
        r"END IF;\s*PERFORM cron\.schedule",
      )),
    );
  });
}
