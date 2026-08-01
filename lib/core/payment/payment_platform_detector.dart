import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/payment_service.dart';
import '../platform/viewport_scroll_policy.dart';
import '../security/web_user_agent.dart';

/// طرق الدفع الذكية — مصدر واحد للحقيقة.
enum SmartPaymentMethod {
  savedCard,
  googlePay,
  applePay,
  stcPay,
  mada,
  newCardMoyasar,
  tabby,
  tamara,
}

enum OperatingSystem {
  web,
  android,
  iOS,
  windows,
  macOS,
  linux,
  unknown,
}

enum BrowserType {
  native,
  chrome,
  safari,
  firefox,
  edge,
  unknown,
}

/// كشف المنصة / المتصفح / نوع الجهاز لطرق الدفع.
class PaymentPlatformDetector {
  PaymentPlatformDetector._();

  static bool get isWeb => kIsWeb;

  static bool get isNativeApp => !kIsWeb;

  static bool get moyasarEnabled => PaymentService.useMoyasarLiveFlow;

  /// واجهة دفع متاحة: ميسّر الحي، أو الوضع التجريبي المحلي.
  static bool get paymentsUiEnabled =>
      moyasarEnabled || PaymentService.allowMockGateway;

  static String _ua() => readWebUserAgentImpl().toLowerCase();

  static OperatingSystem get os {
    if (kIsWeb) return OperatingSystem.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return OperatingSystem.android;
      case TargetPlatform.iOS:
        return OperatingSystem.iOS;
      case TargetPlatform.windows:
        return OperatingSystem.windows;
      case TargetPlatform.macOS:
        return OperatingSystem.macOS;
      case TargetPlatform.linux:
        return OperatingSystem.linux;
      default:
        return OperatingSystem.unknown;
    }
  }

  static BrowserType get browser {
    if (!kIsWeb) return BrowserType.native;
    final ua = _ua();
    if (ua.contains('edg/') || ua.contains('edge/')) {
      return BrowserType.edge;
    }
    if (ua.contains('firefox') || ua.contains('fxios')) {
      return BrowserType.firefox;
    }
    final safari = ua.contains('safari') &&
        !ua.contains('chrome') &&
        !ua.contains('chromium') &&
        !ua.contains('crios') &&
        !ua.contains('edg');
    if (safari) return BrowserType.safari;
    if (ua.contains('chrome') ||
        ua.contains('chromium') ||
        ua.contains('crios')) {
      return BrowserType.chrome;
    }
    return BrowserType.unknown;
  }

  static bool get isAndroidApp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isIosApp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool isMobileWeb() =>
      kIsWeb && ViewportScrollPolicy.isMobileWebUserAgent();

  static bool get isMobile {
    if (isAndroidApp || isIosApp) return true;
    return isMobileWeb();
  }

  static bool get isTablet {
    if (kIsWeb) {
      final ua = _ua();
      if (ua.contains('ipad')) return true;
      if (ua.contains('android') && !ua.contains('mobile')) return true;
      return false;
    }
    return false;
  }

  static bool get isDesktop {
    if (kIsWeb) return !isMobile && !isTablet;
    return os == OperatingSystem.windows ||
        os == OperatingSystem.macOS ||
        os == OperatingSystem.linux;
  }

  static bool isChromiumBrowser() =>
      browser == BrowserType.chrome || browser == BrowserType.edge;

  /// Google Pay — تطبيق Android، أو Chrome/Edge على الويب (سطح مكتب/جوال).
  static bool supportsGooglePay() {
    if (!paymentsUiEnabled) return false;
    if (isAndroidApp) return true;
    if (kIsWeb && isChromiumBrowser()) return true;
    return false;
  }

  /// Apple Pay — تطبيق iOS/iPad، أو Safari على الويب (iPhone/iPad/macOS).
  static bool supportsApplePay() {
    if (!paymentsUiEnabled) return false;
    if (isIosApp) return true;
    if (kIsWeb && browser == BrowserType.safari) return true;
    return false;
  }

  /// STC Pay — تطبيق Android فقط، أو Chrome/Edge على ويب جوال Android (ليس iOS).
  static bool supportsStcPay() {
    if (!paymentsUiEnabled) return false;
    if (isAndroidApp) return true;
    if (kIsWeb && isMobileWeb()) {
      final ua = _ua();
      return ua.contains('android') && isChromiumBrowser();
    }
    return false;
  }

  /// مدى — متاحة في كل البيئات عند تفعيل الدفع (ميسّر أو تجريبي).
  static bool supportsMada() => paymentsUiEnabled;

  /// Tabby / Tamara — تطبيقات أصلية فقط مع ميسّر الحي (شركاء BNPL لاحقاً).
  static bool supportsTabby() =>
      moyasarEnabled && (isAndroidApp || isIosApp);

  static bool supportsTamara() =>
      moyasarEnabled && (isAndroidApp || isIosApp);

  /// ترتيب طرق الدفع بدون تكرار — لا Apple Pay مرتين على Safari iOS.
  static List<SmartPaymentMethod> prioritizedMethods({
    required BuildContext context,
    required bool hasSavedCard,
    required bool savedCardReady,
  }) {
    if (!paymentsUiEnabled) {
      return const [SmartPaymentMethod.newCardMoyasar];
    }

    final out = <SmartPaymentMethod>[];

    if (moyasarEnabled && hasSavedCard && savedCardReady) {
      out.add(SmartPaymentMethod.savedCard);
    }
    if (supportsGooglePay()) out.add(SmartPaymentMethod.googlePay);
    if (supportsApplePay()) out.add(SmartPaymentMethod.applePay);
    if (supportsStcPay()) out.add(SmartPaymentMethod.stcPay);
    if (supportsMada()) out.add(SmartPaymentMethod.mada);
    out.add(SmartPaymentMethod.newCardMoyasar);
    if (supportsTabby()) out.add(SmartPaymentMethod.tabby);
    if (supportsTamara()) out.add(SmartPaymentMethod.tamara);

    return out.toSet().toList();
  }

  static String methodToModeKey(SmartPaymentMethod m) {
    switch (m) {
      case SmartPaymentMethod.savedCard:
        return 'saved';
      case SmartPaymentMethod.googlePay:
        return 'google_pay';
      case SmartPaymentMethod.applePay:
        return 'apple_pay';
      case SmartPaymentMethod.stcPay:
        return 'stc_pay';
      case SmartPaymentMethod.mada:
        return 'mada_pay';
      case SmartPaymentMethod.newCardMoyasar:
        return 'new';
      case SmartPaymentMethod.tabby:
        return 'tabby';
      case SmartPaymentMethod.tamara:
        return 'tamara';
    }
  }

  static String labelFor(SmartPaymentMethod m, {required bool isAr}) {
    switch (m) {
      case SmartPaymentMethod.savedCard:
        return isAr ? 'بطاقة محفوظة' : 'Saved card';
      case SmartPaymentMethod.googlePay:
        return 'Google Pay';
      case SmartPaymentMethod.applePay:
        return 'Apple Pay';
      case SmartPaymentMethod.stcPay:
        return 'STC Pay';
      case SmartPaymentMethod.mada:
        return isAr ? 'مدى' : 'mada';
      case SmartPaymentMethod.newCardMoyasar:
        return isAr ? 'بطاقة جديدة' : 'New card';
      case SmartPaymentMethod.tabby:
        return 'Tabby';
      case SmartPaymentMethod.tamara:
        return 'Tamara';
    }
  }

  static IconData iconFor(SmartPaymentMethod m) {
    switch (m) {
      case SmartPaymentMethod.savedCard:
        return Icons.credit_card;
      case SmartPaymentMethod.newCardMoyasar:
        return Icons.add_card_outlined;
      case SmartPaymentMethod.applePay:
        return Icons.apple;
      case SmartPaymentMethod.googlePay:
        return Icons.account_balance_wallet_outlined;
      case SmartPaymentMethod.mada:
        return Icons.payment_outlined;
      case SmartPaymentMethod.stcPay:
        return Icons.phone_android_outlined;
      case SmartPaymentMethod.tabby:
      case SmartPaymentMethod.tamara:
        return Icons.payments_outlined;
    }
  }
}
