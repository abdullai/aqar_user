import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/payment_service.dart';
import '../platform/viewport_scroll_policy.dart';
import '../security/web_user_agent.dart';

/// الاسم المطلوب في مواصفات الدفع — نفس كاشف المنصة الحالي (لا نسخة ثانية).
typedef PaymentCapabilityDetector = PaymentPlatformDetector;

/// طرق الدفع الذكية — مصدر واحد للحقيقة.
enum SmartPaymentMethod {
  savedCard,
  applePay,
  samsungPay,
  mada,
  newCardMoyasar,
  googlePay,
  stcPay,
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

  /// واجهة دفع متاحة عند تفعيل ميسّر أو بوابة الجهاز.
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

  /// Google Pay — غير مفعّل حتى يوجد مصدر Moyasar حقيقي (لا خلط مع Samsung Pay).
  static bool supportsGooglePay() => false;

  /// Apple Pay — تطبيق iOS/iPad، أو Safari، مع Merchant ID مضبوط.
  static bool supportsApplePay() {
    if (!paymentsUiEnabled) return false;
    final merchant = PaymentService.moyasarApplePayMerchantId;
    if (merchant == null || merchant.isEmpty) return false;
    if (isIosApp) return true;
    if (kIsWeb && browser == BrowserType.safari) return true;
    return false;
  }

  /// Samsung Pay — أندرويد أصلي فقط مع Service ID من Moyasar.
  static bool supportsSamsungPay() {
    if (!moyasarEnabled) return false;
    if (!isAndroidApp) return false;
    final sid = PaymentService.moyasarSamsungPayServiceId;
    return sid != null && sid.isNotEmpty;
  }

  /// STC Pay — لا يُعرض بدون مسار مصدر حقيقي.
  static bool supportsStcPay() => false;

  /// مدى — شبكة داخل نموذج البطاقة، وليست محفظة منفصلة.
  static bool supportsMada() => paymentsUiEnabled;

  static bool supportsTabby() => false;

  static bool supportsTamara() => false;

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
    if (supportsApplePay()) out.add(SmartPaymentMethod.applePay);
    if (supportsSamsungPay()) out.add(SmartPaymentMethod.samsungPay);
    out.add(SmartPaymentMethod.newCardMoyasar);

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
      case SmartPaymentMethod.samsungPay:
        return 'samsung_pay';
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
      case SmartPaymentMethod.samsungPay:
        return 'Samsung Pay';
      case SmartPaymentMethod.stcPay:
        return 'STC Pay';
      case SmartPaymentMethod.mada:
        return isAr ? 'مدى (داخل البطاقة)' : 'mada (on card)';
      case SmartPaymentMethod.newCardMoyasar:
        return isAr ? 'بطاقة ائتمان / مدى' : 'Credit / mada card';
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
      case SmartPaymentMethod.samsungPay:
        return Icons.phone_android_outlined;
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
