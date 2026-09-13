import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../payment/payment_platform_detector.dart';
import '../platform/viewport_scroll_policy.dart';
import '../../services/fast_login_service.dart';
import 'auth_challenge_service.dart';
import 'auth_completion_policy.dart';

/// بيئة التشغيل الفعلية لخيارات الدخول.
enum LoginHostKind {
  nativeMobile,
  nativeDesktop,
  webMobile,
  webDesktop,
}

/// خيارات تبويب طريقة الدخول — لا تُعرض إلا إن كانت متاحة ومفعّلة ومعتمدة.
enum LoginMethodKind {
  password,
  nafath,
  pin,
  face,
  fingerprint,
  anotherUser,
}

/// لقطة جاهزة لشريط الدخول: منصة + ثقة الجهاز + ما فعّله المستخدم.
class LoginMethodSnapshot {
  const LoginMethodSnapshot({
    required this.host,
    required this.trustedThisInstall,
    required this.firstPasswordDone,
    required this.hasSession,
    required this.hasKnownUser,
    required this.pinEnabled,
    required this.faceEnabled,
    required this.fingerprintEnabled,
    required this.preferPassword,
    required this.unlockMode,
  });

  final LoginHostKind host;
  final bool trustedThisInstall;
  final bool firstPasswordDone;
  final bool hasSession;
  final bool hasKnownUser;
  final bool pinEnabled;
  final bool faceEnabled;
  final bool fingerprintEnabled;
  final bool preferPassword;
  final FastUnlockMode unlockMode;

  bool get isNativeApp =>
      host == LoginHostKind.nativeMobile || host == LoginHostKind.nativeDesktop;

  bool get isNativeMobile => host == LoginHostKind.nativeMobile;

  /// الاسم الرباعي + كلمة المرور فقط: جهاز معتمد بعد أول دخول ناجح.
  bool get nameOnlyPassword =>
      isNativeMobile && trustedThisInstall && firstPasswordDone && hasKnownUser;

  bool get _lockEligible =>
      isNativeMobile && trustedThisInstall && firstPasswordDone && hasSession;

  bool get showPin => _lockEligible && pinEnabled;

  bool get showFace => _lockEligible && faceEnabled;

  bool get showFingerprint => _lockEligible && fingerprintEnabled;

  bool get showAnyQuickUnlock => showPin || showFace || showFingerprint;

  bool get autoOpenFastLogin =>
      showAnyQuickUnlock && !preferPassword && hasSession;

  bool get quickUnlockActive =>
      !preferPassword && showAnyQuickUnlock && hasSession;

  IconData get tabIcon {
    if (!quickUnlockActive) return Icons.password_rounded;
    if (showFace && !showFingerprint && !showPin) {
      return Icons.face_retouching_natural_rounded;
    }
    if (showFingerprint && !showFace) return Icons.fingerprint_rounded;
    if (showPin && !showFace && !showFingerprint) return Icons.pin_rounded;
    return Icons.fingerprint_rounded;
  }

  String hostLabel({required bool isAr}) {
    switch (host) {
      case LoginHostKind.nativeMobile:
        return isAr ? 'تطبيق الجوال' : 'Mobile app';
      case LoginHostKind.nativeDesktop:
        return isAr ? 'تطبيق سطح المكتب' : 'Desktop app';
      case LoginHostKind.webMobile:
        return isAr ? 'متصفح الجوال' : 'Mobile browser';
      case LoginHostKind.webDesktop:
        return isAr ? 'متصفح سطح المكتب' : 'Desktop browser';
    }
  }

  List<LoginMethodKind> get visibleMethods {
    final out = <LoginMethodKind>[
      LoginMethodKind.password,
      LoginMethodKind.nafath,
    ];
    if (showPin) out.add(LoginMethodKind.pin);
    if (showFace) out.add(LoginMethodKind.face);
    if (showFingerprint) out.add(LoginMethodKind.fingerprint);
    if (hasKnownUser) out.add(LoginMethodKind.anotherUser);
    return out;
  }

  LoginMethodSnapshot copyWith({
    LoginHostKind? host,
    bool? trustedThisInstall,
    bool? firstPasswordDone,
    bool? hasSession,
    bool? hasKnownUser,
    bool? pinEnabled,
    bool? faceEnabled,
    bool? fingerprintEnabled,
    bool? preferPassword,
    FastUnlockMode? unlockMode,
  }) {
    return LoginMethodSnapshot(
      host: host ?? this.host,
      trustedThisInstall: trustedThisInstall ?? this.trustedThisInstall,
      firstPasswordDone: firstPasswordDone ?? this.firstPasswordDone,
      hasSession: hasSession ?? this.hasSession,
      hasKnownUser: hasKnownUser ?? this.hasKnownUser,
      pinEnabled: pinEnabled ?? this.pinEnabled,
      faceEnabled: faceEnabled ?? this.faceEnabled,
      fingerprintEnabled: fingerprintEnabled ?? this.fingerprintEnabled,
      preferPassword: preferPassword ?? this.preferPassword,
      unlockMode: unlockMode ?? this.unlockMode,
    );
  }
}

/// سياسة خيارات الدخول حسب المنصة والجهاز المعتمد وتفضيل المستخدم.
abstract final class LoginMethodPolicy {
  static LoginHostKind detectHost() {
    if (!kIsWeb) {
      final p = defaultTargetPlatform;
      if (p == TargetPlatform.android || p == TargetPlatform.iOS) {
        return LoginHostKind.nativeMobile;
      }
      return LoginHostKind.nativeDesktop;
    }
    if (ViewportScrollPolicy.isMobileWebUserAgent() ||
        PaymentPlatformDetector.isMobileWeb()) {
      return LoginHostKind.webMobile;
    }
    return LoginHostKind.webDesktop;
  }

  static Future<LoginMethodSnapshot> resolve({
    required bool hasKnownUser,
  }) async {
    final host = detectHost();
    var hasSession = false;
    try {
      hasSession = Supabase.instance.client.auth.currentSession != null;
    } catch (_) {}

    var trusted = false;
    var firstDone = false;
    var pin = false;
    var face = false;
    var fp = false;
    var preferPassword = false;
    var mode = FastUnlockMode.password;

    try {
      trusted = await FastLoginService.isThisInstallTrusted();
      firstDone = await FastLoginService.hasCompletedFirstPasswordLogin();
      preferPassword = await FastLoginService.preferPasswordSurface();
    } catch (_) {}

    if (trusted) {
      try {
        trusted = await AuthChallengeService.isNativeDeviceTrustedOnServer();
      } catch (_) {
        trusted = false;
      }
    }

    if (!AuthCompletionPolicy.allowFastLogin(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      trusted = false;
    }

    // الويب وسطح المكتب: لا بصمة أصلية ولا رمز تطبيق.
    if (host == LoginHostKind.nativeMobile) {
      try {
        pin = await FastLoginService.isPinEnabled();
        mode = await FastLoginService.resolveUnlockMode();
        switch (mode) {
          case FastUnlockMode.faceOnly:
            face = true;
            break;
          case FastUnlockMode.fingerprintOnly:
            fp = true;
            break;
          case FastUnlockMode.biometricOnly:
            face = true;
            fp = true;
            break;
          case FastUnlockMode.pinWithBiometric:
            face = true;
            fp = true;
            break;
          case FastUnlockMode.pinOnly:
          case FastUnlockMode.password:
            break;
        }
      } catch (_) {}
    }

    return LoginMethodSnapshot(
      host: host,
      trustedThisInstall: trusted,
      firstPasswordDone: firstDone,
      hasSession: hasSession,
      hasKnownUser: hasKnownUser,
      pinEnabled: pin,
      faceEnabled: face,
      fingerprintEnabled: fp,
      preferPassword: preferPassword,
      unlockMode: mode,
    );
  }
}
