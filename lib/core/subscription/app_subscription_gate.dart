import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../workflow/app_role_helper.dart';
import '../../services/individual_market_offer_service.dart';
import '../../services/subscription_service.dart';
import 'listing_requests_allowance.dart';
import 'marketing_subscription_access.dart';
import 'subscription_billing_context.dart';

/// نوع الإجراء الذي يتطلب تحقق اشتراك/حصة.
enum SubscriptionGateAction {
  completeMarketDeal,
  addMarketPropertyRequest,
  addPropertyListing,
  marketingPaidWorkflow,
}

/// لقطة فورية لحالة الاشتراك — تُحمَّل في الخلفية وتنعكس على الأزرار.
class AppSubscriptionGate extends ChangeNotifier {
  AppSubscriptionGate(this._sb);

  final SupabaseClient _sb;
  StreamSubscription<Map<String, dynamic>>? _subEvents;
  StreamSubscription<AuthState>? _authSub;
  Future<void>? _refreshInFlight;
  String? _boundUid;

  bool loading = false;
  bool loaded = false;
  String accountType = 'user';
  String? organizationId;

  bool marketingFeatureAccess = false;
  Map<String, dynamic>? subscriptionRow;
  IndividualMarketOfferAllowance? marketOfferAllowance;
  ListingRequestsAllowance? listingRequestsAllowance;

  bool get isGuest => _sb.auth.currentUser == null;

  bool get isMarketingAccount =>
      AppRoleHelper.isMarketingAccountType(accountType);

  /// إتمام صفقة على طلبات الرئيسية —
  /// مجاني للمالك/المستخدم العادي؛ للمسوّق حسب حصة عروض الاشتراك.
  bool get canCompleteMarketDeal {
    if (AppConfig.devBypassSubscriptionGate) return true;
    if (isGuest) return false;
    if (!isMarketingAccount) return true;
    // أثناء التحميل لا نمنع الزر حتى لا تومض شاشة الاشتراك خطأً.
    if (!loaded) return true;
    final a = marketOfferAllowance;
    if (a == null) return false;
    return a.canSubmitNow;
  }

  /// هل نُظهر زر «اشترك» بدل «إتمام الصفقة» على بطاقة طلب في الرئيسية؟
  bool get shouldShowSubscribeInsteadOfDeal {
    if (isGuest || !isMarketingAccount) return false;
    if (!loaded) return false;
    return !canCompleteMarketDeal;
  }

  /// نشر «طلب عقاري» — مجاني للمالك/المستخدم العادي.
  bool get canAddMarketPropertyRequest {
    if (AppConfig.devBypassSubscriptionGate) return true;
    if (isGuest) return false;
    if (!isMarketingAccount) return true;
    final a = listingRequestsAllowance;
    if (a == null) return false;
    return a.canCreateNow;
  }

  /// إضافة إعلان عقاري — مجاني للمالك/المستخدم العادي.
  bool get canAddPropertyListing {
    if (AppConfig.devBypassSubscriptionGate) return true;
    if (isGuest) return false;
    if (!isMarketingAccount) return true;
    return marketingFeatureAccess;
  }

  /// مسار التسويق (عروض، تعاقد، تصاريح، سوق…).
  bool get canUseMarketingPaidWorkflow {
    if (AppConfig.devBypassSubscriptionGate) return true;
    if (isGuest || !isMarketingAccount) return true;
    return marketingFeatureAccess;
  }

  String alertTitleAr(SubscriptionGateAction action) {
    switch (action) {
      case SubscriptionGateAction.completeMarketDeal:
        return 'يلزم اشتراك لإتمام الصفقة';
      case SubscriptionGateAction.addMarketPropertyRequest:
        return 'يلزم اشتراك لنشر طلب عقاري';
      case SubscriptionGateAction.addPropertyListing:
        return 'يلزم اشتراك لإضافة إعلان';
      case SubscriptionGateAction.marketingPaidWorkflow:
        return 'يلزم اشتراك تسويق';
    }
  }

  String alertTitleEn(SubscriptionGateAction action) {
    switch (action) {
      case SubscriptionGateAction.completeMarketDeal:
        return 'Subscription required to complete deal';
      case SubscriptionGateAction.addMarketPropertyRequest:
        return 'Subscription required to post request';
      case SubscriptionGateAction.addPropertyListing:
        return 'Subscription required to add listing';
      case SubscriptionGateAction.marketingPaidWorkflow:
        return 'Marketing subscription required';
    }
  }

  String alertBodyAr(SubscriptionGateAction action) {
    switch (action) {
      case SubscriptionGateAction.completeMarketDeal:
        return isMarketingAccount
            ? (marketOfferAllowance?.shortStatusAr() ??
                'يلزم اشتراك لإتمام الصفقة.')
            : 'إتمام الصفقة على طلبات الآخرين مجاني — لا يلزم اشتراك.';
      case SubscriptionGateAction.addMarketPropertyRequest:
        return isMarketingAccount
            ? (listingRequestsAllowance?.shortStatusAr() ??
                'اشترك في الباقة المناسبة لنشر طلباتك في الرئيسية.')
            : 'نشر الطلب العقاري في الرئيسية مجاني — ادفع 30 ر.س فقط عند اختيار «فوري».';
      case SubscriptionGateAction.addPropertyListing:
        if (isMarketingAccount) {
          return 'اشترك في الباقة المناسبة لنوع حسابك (أساسية/احترافية/تميز) لنشر الإعلانات.';
        }
        return 'إضافة الإعلان العقاري مجانية — يُرسل للمسوقين في «صفحتي».';
      case SubscriptionGateAction.marketingPaidWorkflow:
        return 'هذا الإجراء يتطلب اشتراكاً تسويقياً فعّالاً.';
    }
  }

  String alertBodyEn(SubscriptionGateAction action) {
    switch (action) {
      case SubscriptionGateAction.completeMarketDeal:
        return isMarketingAccount
            ? (marketOfferAllowance?.shortStatusEn() ??
                'Subscription required to complete deals.')
            : 'Completing deals on others\' requests is free — no subscription needed.';
      case SubscriptionGateAction.addMarketPropertyRequest:
        return isMarketingAccount
            ? (listingRequestsAllowance?.shortStatusEn() ??
                'Subscribe to post property requests on the home feed.')
            : 'Posting on the home feed is free — pay SAR 30 only when you choose Instant.';
      case SubscriptionGateAction.addPropertyListing:
        if (isMarketingAccount) {
          return 'Subscribe to the plan for your account type to publish listings.';
        }
        return 'Adding a property listing is free — it is sent to marketers in My page.';
      case SubscriptionGateAction.marketingPaidWorkflow:
        return 'This action requires an active marketing subscription.';
    }
  }

  bool allows(SubscriptionGateAction action) {
    switch (action) {
      case SubscriptionGateAction.completeMarketDeal:
        return canCompleteMarketDeal;
      case SubscriptionGateAction.addMarketPropertyRequest:
        return canAddMarketPropertyRequest;
      case SubscriptionGateAction.addPropertyListing:
        return canAddPropertyListing;
      case SubscriptionGateAction.marketingPaidWorkflow:
        return canUseMarketingPaidWorkflow;
    }
  }

  void bindLifecycle() {
    final uid = _sb.auth.currentUser?.id;
    if (!kIsWeb && uid != null && uid.isNotEmpty) {
      SubscriptionService.ensureRealtimeChannelFor(_sb, uid);
    }
    _subEvents ??= SubscriptionService.subscriptionEvents.listen((_) {
      SubscriptionService.invalidateSubscriptionCache();
      if (kIsWeb) {
        _scheduleWebRefresh(force: true);
      } else {
        unawaited(refresh(force: true));
      }
    });
    _authSub ??= _sb.auth.onAuthStateChange.listen((state) {
      final e = state.event;
      if (e == AuthChangeEvent.signedIn ||
          e == AuthChangeEvent.initialSession ||
          e == AuthChangeEvent.tokenRefreshed) {
        if (kIsWeb) {
          _scheduleWebRefresh(force: true);
        } else {
          unawaited(refresh(force: true));
        }
      } else if (e == AuthChangeEvent.signedOut) {
        clear();
      }
    });
    if (uid != null && uid.isNotEmpty && uid != _boundUid) {
      _boundUid = uid;
      if (kIsWeb) {
        _scheduleWebRefresh(force: true);
      } else {
        unawaited(refresh(force: true));
      }
    } else if (uid == null) {
      clear();
    }
  }

  Timer? _webRefreshDebounce;

  void _scheduleWebRefresh({required bool force}) {
    if (!kIsWeb) return;
    _webRefreshDebounce?.cancel();
    _webRefreshDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(refresh(force: force));
    });
  }

  void clear() {
    if (!loaded &&
        !loading &&
        _boundUid == null &&
        accountType == 'user' &&
        organizationId == null &&
        !marketingFeatureAccess &&
        subscriptionRow == null &&
        marketOfferAllowance == null &&
        listingRequestsAllowance == null) {
      return;
    }
    _boundUid = null;
    loading = false;
    loaded = false;
    accountType = 'user';
    organizationId = null;
    marketingFeatureAccess = false;
    subscriptionRow = null;
    marketOfferAllowance = null;
    listingRequestsAllowance = null;
    notifyListeners();
  }

  /// جلب الحالة من الخادم — idempotent أثناء التحميل.
  Future<void> refresh({bool force = false}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      clear();
      return;
    }
    if (!force && loaded && !loading) return;
    if (_refreshInFlight != null) {
      await _refreshInFlight;
      return;
    }

    loading = true;
    notifyListeners();

    _refreshInFlight = _loadSnapshot(uid);
    try {
      await _refreshInFlight;
    } finally {
      _refreshInFlight = null;
      loading = false;
      loaded = true;
      notifyListeners();
    }
  }

  Future<void> _loadSnapshot(String uid) async {
    try {
      final (at, oid) = await MarketingSubscriptionAccess.loadBillingContext(_sb);
      accountType = at;
      organizationId = oid;

      final svc = SubscriptionService(_sb);
      SubscriptionService.invalidateSubscriptionCache();

      final results = await Future.wait<Object?>([
        svc.resolveBillingContext(),
        svc.getCurrentSubscription(organizationId: oid),
        IndividualMarketOfferService(_sb).currentAllowance(
          accountType: at,
          organizationId: oid,
        ),
        svc.fetchListingRequestsAllowance(organizationId: oid),
      ]);

      final ctx = results[0];
      subscriptionRow = results[1] as Map<String, dynamic>?;
      marketOfferAllowance = results[2] as IndividualMarketOfferAllowance;
      final listingRaw = results[3] as Map<String, dynamic>;

      if (ctx is SubscriptionBillingContext) {
        marketingFeatureAccess =
            ctx.ok && ctx.hasMarketingFeatureAccess;
      }
      if (!marketingFeatureAccess) {
        marketingFeatureAccess =
            SubscriptionService.subscriptionRowGrantsMarketingAccess(
          subscriptionRow,
        );
      }

      listingRequestsAllowance = ListingRequestsAllowance.fromRpc(listingRaw);
    } catch (_) {
      // احتفظ بآخر لقطة إن وُجدت؛ loaded=true لتجنّب حلقة إعادة المحاولة.
    }
  }

  @override
  void dispose() {
    _subEvents?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
