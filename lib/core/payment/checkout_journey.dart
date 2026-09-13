import '../../services/subscription_service.dart';
import 'payment_platform_detector.dart';

/// نيّة شاشة الدفع — تُشتق من الزر/التبويب الذي فتح الملخص.
enum SubscriptionCheckoutKind {
  newSubscribe,
  upgrade,
  renew,
  periodSwitch,
  addOn,
}

class CheckoutJourney {
  CheckoutJourney._();

  static bool isAddOnPlan(Map<String, dynamic> plan) {
    final sort = SubscriptionService.planSortOrder(plan);
    return SubscriptionService.isListingRequestsTopUpSortOrder(sort) ||
        SubscriptionService.isMarketOffersTopUpSortOrder(sort);
  }

  static SubscriptionCheckoutKind resolve({
    required Map<String, dynamic> plan,
    String? renewSubscriptionId,
    String? upgradeSubscriptionId,
    String? periodSwitchSubscriptionId,
  }) {
    if ((renewSubscriptionId ?? '').trim().isNotEmpty) {
      return SubscriptionCheckoutKind.renew;
    }
    if ((periodSwitchSubscriptionId ?? '').trim().isNotEmpty) {
      return SubscriptionCheckoutKind.periodSwitch;
    }
    if ((upgradeSubscriptionId ?? '').trim().isNotEmpty) {
      return SubscriptionCheckoutKind.upgrade;
    }
    if (isAddOnPlan(plan)) return SubscriptionCheckoutKind.addOn;
    return SubscriptionCheckoutKind.newSubscribe;
  }

  static String title({
    required bool isAr,
    required SubscriptionCheckoutKind kind,
  }) {
    switch (kind) {
      case SubscriptionCheckoutKind.upgrade:
        return isAr ? 'ترقية الباقة' : 'Plan upgrade';
      case SubscriptionCheckoutKind.renew:
        return isAr ? 'تجديد الاشتراك' : 'Renew subscription';
      case SubscriptionCheckoutKind.periodSwitch:
        return isAr ? 'تحويل للفترة السنوية' : 'Switch to yearly';
      case SubscriptionCheckoutKind.addOn:
        return isAr ? 'إضافة باقة / رصيد صفقات' : 'Add-on / deal credit';
      case SubscriptionCheckoutKind.newSubscribe:
        return isAr ? 'اشتراك جديد' : 'New subscription';
    }
  }

  static String body({
    required bool isAr,
    required SubscriptionCheckoutKind kind,
  }) {
    switch (kind) {
      case SubscriptionCheckoutKind.upgrade:
        return isAr
            ? 'المبلغ هو فرق الترقية بعد احتساب المتبقي من باقتك الحالية — لا يُحتسب اشتراكاً جديداً.'
            : 'You pay the upgrade difference after unused time credit — not a second subscription.';
      case SubscriptionCheckoutKind.renew:
        return isAr
            ? 'تجديد للفترة التالية لنفس الباقة عند قرب الانتهاء أو فشل التجديد التلقائي.'
            : 'Renews the same plan for the next period when it is ending or auto-renew failed.';
      case SubscriptionCheckoutKind.periodSwitch:
        return isAr
            ? 'تحويل من شهري إلى سنوي لنفس الباقة مع خصم المتبقي.'
            : 'Switch the same plan from monthly to yearly with remaining credit applied.';
      case SubscriptionCheckoutKind.addOn:
        return isAr
            ? 'شراء إضافة فوق اشتراكك الفعّال (صفقات أو طلبات). لا يلغي الباقة الرئيسية.'
            : 'An add-on on top of your active plan (deals or requests). It does not replace the main plan.';
      case SubscriptionCheckoutKind.newSubscribe:
        return isAr
            ? 'تفعيل باقة رئيسية جديدة. إن كان لديك اشتراك ساري استخدم الترقية أو الإضافة.'
            : 'Activates a new main plan. If you already have one, use upgrade or an add-on.';
    }
  }

  static String surfaceHint({required bool isAr}) {
    final methods = <String>[];
    if (PaymentPlatformDetector.supportsApplePay()) {
      methods.add('Apple Pay');
    }
    if (PaymentPlatformDetector.supportsGooglePay()) {
      methods.add('Google Pay');
    }
    if (PaymentPlatformDetector.supportsStcPay()) {
      methods.add('STC Pay');
    }
    if (PaymentPlatformDetector.supportsMada()) {
      methods.add(isAr ? 'مدى' : 'mada');
    }
    methods.add(isAr ? 'بطاقة' : 'card');

    String device;
    if (PaymentPlatformDetector.isIosApp) {
      device = isAr ? 'تطبيق آيفون' : 'iPhone app';
    } else if (PaymentPlatformDetector.isAndroidApp) {
      device = isAr ? 'تطبيق أندرويد' : 'Android app';
    } else if (PaymentPlatformDetector.isMobileWeb()) {
      device = isAr ? 'متصفح الجوال' : 'mobile browser';
    } else if (PaymentPlatformDetector.isDesktop) {
      device = isAr ? 'متصفح ويندوز / سطح المكتب' : 'Windows / desktop browser';
    } else {
      device = isAr ? 'هذا الجهاز' : 'this device';
    }

    final joined = methods.join(isAr ? ' · ' : ' · ');
    return isAr
        ? 'طرق مناسبة لـ$device: $joined'
        : 'Best methods on $device: $joined';
  }
}
