import 'dart:io';

import 'package:aqar_user/core/auth/auth_completion_policy.dart';
import 'package:aqar_user/core/auth/in_app_otp_handoff.dart';
import 'package:aqar_user/core/auth/otp_pin_layout.dart';
import 'package:aqar_user/core/auth/login_method_policy.dart';
import 'package:aqar_user/services/fast_login_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthCompletionPolicy matrix', () {
    test('web always requires OTP even if a device looks trusted', () {
      expect(
        AuthCompletionPolicy.otpRequired(
          isWeb: true,
          platform: TargetPlatform.android,
          serverTrustedNativeDevice: true,
        ),
        isTrue,
      );
      expect(
        AuthCompletionPolicy.otpRequired(
          isWeb: true,
          platform: TargetPlatform.windows,
          serverTrustedNativeDevice: true,
        ),
        isTrue,
      );
    });

    test('native first login requires OTP', () {
      expect(
        AuthCompletionPolicy.otpRequired(
          isWeb: false,
          platform: TargetPlatform.android,
          serverTrustedNativeDevice: false,
        ),
        isTrue,
      );
      expect(
        AuthCompletionPolicy.otpRequired(
          isWeb: false,
          platform: TargetPlatform.iOS,
          serverTrustedNativeDevice: false,
        ),
        isTrue,
      );
    });

    test('native trusted device skips OTP', () {
      expect(
        AuthCompletionPolicy.otpRequired(
          isWeb: false,
          platform: TargetPlatform.android,
          serverTrustedNativeDevice: true,
        ),
        isFalse,
      );
    });

    test('windows/mac/linux native treated as always-OTP surfaces', () {
      expect(
        AuthCompletionPolicy.isNativeMobileSurface(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
      expect(
        AuthCompletionPolicy.otpRequired(
          isWeb: false,
          platform: TargetPlatform.windows,
          serverTrustedNativeDevice: true,
        ),
        isTrue,
      );
      expect(
        AuthCompletionPolicy.allowFastLogin(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        isFalse,
      );
    });

    test('trusted-session PIN is available on web; biometrics stay native-only',
        () {
      expect(
        AuthCompletionPolicy.allowFastLogin(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        AuthCompletionPolicy.allowTrustedSessionPinUnlock(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        AuthCompletionPolicy.allowPinOrBiometrics(
          isWeb: true,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
      expect(
        AuthCompletionPolicy.allowFastLogin(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('trusted browser still needs OTP for a new login', () {
      expect(
        AuthCompletionPolicy.otpRequired(
          isWeb: true,
          platform: TargetPlatform.windows,
          serverTrustedNativeDevice: true,
        ),
        isTrue,
      );
    });

    test('local flags cannot bypass OTP', () {
      expect(AuthCompletionPolicy.localFlagCanBypassOtp(), isFalse);
    });
  });

  group('LoginMethodSnapshot web lock', () {
    test('trusted web session exposes PIN but not biometrics', () {
      const snap = LoginMethodSnapshot(
        host: LoginHostKind.webDesktop,
        trustedThisInstall: true,
        firstPasswordDone: true,
        hasSession: true,
        hasKnownUser: true,
        pinEnabled: true,
        faceEnabled: true,
        fingerprintEnabled: true,
        preferPassword: false,
        unlockMode: FastUnlockMode.pinWithBiometric,
      );
      expect(snap.showPin, isTrue);
      expect(snap.showFace, isFalse);
      expect(snap.showFingerprint, isFalse);
      expect(snap.showAnyQuickUnlock, isTrue);
      expect(snap.visibleMethods, contains(LoginMethodKind.pin));
      expect(snap.visibleMethods, isNot(contains(LoginMethodKind.face)));
      expect(
        snap.visibleMethods,
        isNot(contains(LoginMethodKind.fingerprint)),
      );
    });

    test('native mobile snapshot can show pin when trusted', () {
      const snap = LoginMethodSnapshot(
        host: LoginHostKind.nativeMobile,
        trustedThisInstall: true,
        firstPasswordDone: true,
        hasSession: true,
        hasKnownUser: true,
        pinEnabled: true,
        faceEnabled: false,
        fingerprintEnabled: false,
        preferPassword: false,
        unlockMode: FastUnlockMode.pinOnly,
      );
      expect(snap.showPin, isTrue);
    });
  });

  test('OTP length is 6 digits', () {
    expect(InAppOtpHandoff.otpLen, 6);
  });

  test('quick PIN accepts exactly six normalized digits', () {
    expect(FastLoginService.isValidPin('123456'), isTrue);
    expect(FastLoginService.isValidPin('١٢٣٤٥٦'), isTrue);
    expect(FastLoginService.isValidPin('12345'), isFalse);
    expect(FastLoginService.isValidPin('12345a'), isFalse);
  });

  test('six OTP boxes fit equally on small phone and web widths', () {
    for (final width in <double>[280, 320, 360, 390, 412]) {
      final metrics = OtpPinLayout.of(width);
      expect(metrics.fieldWidth, greaterThanOrEqualTo(28));
      expect(metrics.fits(width), isTrue);
    }
  });

  test('device OTP uses in-app challenge peek and equal pin boxes', () {
    final src = File('lib/screens/device_management_page.dart').readAsStringSync();
    expect(src.contains('requestOtpDetailed'), isTrue);
    expect(src.contains('AuthChallengeService.verify'), isTrue);
    expect(src.contains('pollLatestCode'), isTrue);
    expect(src.contains('OtpPinLayout.of'), isTrue);
    expect(src.contains('otpAttemptsRemaining'), isTrue);
  });

  test('verify screen no longer accepts AQAR_DEV_OTP bypass', () {
    final src = File('lib/screens/verify_screen.dart').readAsStringSync();
    expect(src.contains('AQAR_DEV_OTP'), isFalse);
    expect(src.contains('_matchesEnvDevOtp'), isFalse);
  });

  test('login screen does not skip OTP via priorUid or local install flag', () {
    final src = File('lib/screens/login_screen.dart').readAsStringSync();
    expect(src.contains('priorUid == uid'), isFalse);
    expect(src.contains('isCurrentInstallRegistered()'), isFalse);
    expect(src.contains('AuthChallengeService.start'), isTrue);
  });

  test('verified web login refreshes idle activity before dashboard routing',
      () {
    final src = File('lib/screens/verify_screen.dart').readAsStringSync();
    final verifiedFlag =
        src.indexOf('await prefs.setBool(_otpVerifiedKey(uid), true);');
    final refreshedActivity = src.indexOf(
      'await touchWebSessionActivity();',
      verifiedFlag,
    );
    final dashboardRouting = src.indexOf(
        'PostAuthNavigation.openRouteReplacingStack(', verifiedFlag);

    expect(verifiedFlag, isNonNegative);
    expect(refreshedActivity, greaterThan(verifiedFlag));
    expect(dashboardRouting, greaterThan(refreshedActivity));
  });

  test('SQL migration defines hashed challenges and denies client table access',
      () {
    final sql = File(
      'supabase/migrations/20260909223000_auth_login_challenges.sql',
    ).readAsStringSync();
    expect(sql.contains('auth_login_challenges'), isTrue);
    expect(sql.contains('otp_hash'), isTrue);
    expect(sql.contains('peek_dev_login_otp'), isTrue);
    expect(sql.contains('start_login_challenge'), isTrue);
    expect(sql.contains('verify_login_otp'), isTrue);
    expect(sql.contains('get_auth_gate_status'), isTrue);
    expect(sql.contains('auth_generate_otp6'), isTrue);
    expect(sql.contains('FOR ALL TO authenticated, anon'), isTrue);
    expect(sql.contains("USING (false)"), isTrue);
    expect(sql.contains('rate_limited'), isTrue);
    expect(sql.contains('fast_login_forbidden'), isTrue);
    expect(sql.contains('nafath_skip_otp_web'), isTrue);
  });

  test('browser quick unlock requires server-registered device trust', () {
    final sql = File(
      'supabase/migrations/20261115020000_allow_trusted_browser_quick_unlock.sql',
    ).readAsStringSync();
    expect(
        sql.contains('public._auth_device_trusted(uid, p_device_fingerprint)'),
        isTrue);
    expect(sql.contains("IF method = 'fast_unlock' AND NOT trusted"), isTrue);
    expect(sql.contains("'otp_required', true"), isTrue);
  });
}
