import 'package:flutter/foundation.dart';

/// سياسة اكتمال الدخول — قرارات صرفة قابلة للاختبار بدون شبكة.
/// الخادم يبقى مصدر الحقيقة؛ هذه الطبقة تمنع الالتفاف من الواجهة.
abstract final class AuthCompletionPolicy {
  /// أندرويد/iOS أصلي فقط. كل ما عداه (ويب، ويندوز، ماك، لينكس) يُعامل كسطح OTP دائم.
  static bool isNativeMobileSurface({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) return false;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  static bool otpRequired({
    required bool isWeb,
    required TargetPlatform platform,
    required bool serverTrustedNativeDevice,
  }) {
    if (!isNativeMobileSurface(isWeb: isWeb, platform: platform)) {
      return true;
    }
    return !serverTrustedNativeDevice;
  }

  static bool allowFastLogin({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    return isNativeMobileSurface(isWeb: isWeb, platform: platform);
  }

  static bool allowPinOrBiometrics({
    required bool isWeb,
    required TargetPlatform platform,
  }) =>
      allowFastLogin(isWeb: isWeb, platform: platform);

  /// أعلام SharedPreferences / priorUid لا تُكمل المصادقة وحدها.
  static bool localFlagCanBypassOtp() => false;

  static String clientPlatformLabel({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) return 'web';
    switch (platform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }
}
