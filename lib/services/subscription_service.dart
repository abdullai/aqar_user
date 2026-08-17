import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/subscription/subscription_billing_context.dart';
import '../core/workflow/app_role_helper.dart';
import 'payment_service.dart';

/// اشتراكات الباقات + ربط وهمي بالدفع (حتى ربط بوابة معتمدة).
class SubscriptionService {
  SubscriptionService(this._sb);

  final SupabaseClient _sb;
  PaymentService? _pay;

  /// يمنع إغراق المتصفح/PostgREST عند فشل الاستعلام (مثلاً 500 من سياسة أو مخطط).
  static DateTime? _currentSubFetchCooldownUntil;
  static final Map<String, Future<Map<String, dynamic>?>> _currentSubInFlight =
      {};
  /// آخر اشتراك ناجح لكل مفتاح — يُعاد أثناء cooldown بدل null (كان يُظهر «التجربة مستنفذة» بعد التفعيل مباشرة).
  static final Map<String, Map<String, dynamic>?> _currentSubCache = {};

  /// قناة Realtime وحيدة لكل user_id — تبثّ تحديثات الاشتراك على كل
  /// أجهزة المستخدم (متصفحات/تطبيقات) فوراً بعد أي عملية دفع/تعديل/إنشاء.
  static RealtimeChannel? _subscriptionsRealtimeChannel;
  static String? _subscriptionsRealtimeUid;
  static final StreamController<Map<String, dynamic>>
      _subscriptionEventsController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// تيار تحديثات الاشتراك الفورية — يُستهلَك من lobby/dashboard لإعادة
  /// التحميل تلقائياً (لا polling).
  static Stream<Map<String, dynamic>> get subscriptionEvents =>
      _subscriptionEventsController.stream;

  /// يُشغَّل مرة واحدة عند الدخول (في main.dart أو dashboard) — لتفعيل
  /// قناة Realtime لاشتراكات هذا المستخدم.
  static void ensureRealtimeChannelFor(SupabaseClient client, String uid) {
    if (uid.isEmpty) return;
    // الويب: Realtime للاشتراكات كان يُشبّع main thread ويُجمّد التبويب بعد الدخول.
    if (kIsWeb) return;
    if (_subscriptionsRealtimeUid == uid &&
        _subscriptionsRealtimeChannel != null) {
      return;
    }
    try {
      _subscriptionsRealtimeChannel?.unsubscribe();
    } catch (_) {}
    _subscriptionsRealtimeUid = uid;
    final ch = client.channel('user_subscriptions_$uid');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_subscriptions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: uid,
      ),
      callback: (payload) {
        invalidateSubscriptionCache();
        _subscriptionEventsController.add({
          'event': payload.eventType.name,
          'row': payload.newRecord,
        });
      },
    );
    ch.subscribe();
    _subscriptionsRealtimeChannel = ch;
  }

  /// يُغلَق عند تسجيل الخروج لمنع تسريب الاشتراك بين المستخدمين على نفس التبويب.
  static void teardownRealtimeChannel() {
    try {
      _subscriptionsRealtimeChannel?.unsubscribe();
    } catch (_) {}
    _subscriptionsRealtimeChannel = null;
    _subscriptionsRealtimeUid = null;
  }

  PaymentService get _payments => _pay ??= PaymentService(_sb);

  static const _plans = 'subscription_plans';
  static const _subs = 'user_subscriptions';
  static const _extra = 'extra_seats_requests';
  static const _lifecycle = 'subscription_lifecycle_events';
  static const _retentionPrompts = 'user_subscription_retention_prompts';

  User? get _user => _sb.auth.currentUser;

  /// نهاية الفترة المدفوعة (حدّ علوي **حصري**): صالح ما دام [DateTime.now().toUtc().isBefore(endsAt)].
  static DateTime? subscriptionExclusiveEndUtc(Map<String, dynamic>? row) {
    if (row == null) return null;
    final raw = row['ends_at'];
    if (raw != null) {
      final p = _parseDateField(raw);
      return p?.toUtc();
    }
    final ed = _parseDateField(row['end_date']);
    if (ed == null) return null;
    final u = ed.isUtc ? ed : ed.toUtc();
    return DateTime.utc(u.year, u.month, u.day).add(const Duration(days: 1));
  }

  static DateTime? subscriptionStartsAtUtc(Map<String, dynamic>? row) {
    if (row == null) return null;
    final raw = row['starts_at'];
    if (raw != null) {
      final p = _parseDateField(raw);
      return p?.toUtc();
    }
    final sd = _parseDateField(row['start_date']);
    if (sd == null) return null;
    return sd.isUtc ? sd : sd.toUtc();
  }

  static DateTime? _parseDateField(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// اشتراك يسمح بميزات التسويق (نشر، تعاقد، تصاريح): مدفوع أو تجربة فعّالة.
  static bool subscriptionRowGrantsMarketingAccess(Map<String, dynamic>? row) {
    if (AppConfig.devBypassSubscriptionGate) return true;
    if (subscriptionRowInPaidAccess(row)) return true;
    return isActiveTrial(row);
  }

  /// اشتراك يسمح بتقديم عروض التسويق: `active` أو `cancelled` ما دامت [ends_at] لم تُتجاوَز (حصري بالثواني).
  ///
  /// يفضّل [resolve_subscription_billing_context] أولاً (يشمل اشتراك مالك المنشأة
  /// لأعضاء الفريق) ثم يُكمّل بجلب صف الاشتراك من العميل.
  Future<bool> hasActiveMarketingSubscriptionAccess({
    String? organizationId,
  }) async {
    if (AppConfig.devBypassSubscriptionGate) return true;
    try {
      final ctx = await resolveBillingContext();
      if (ctx.ok && ctx.hasMarketingFeatureAccess) return true;
    } catch (_) {}
    final row = await getCurrentSubscription(organizationId: organizationId);
    return subscriptionRowGrantsMarketingAccess(row);
  }

  Future<void> logLifecycleEvent({
    required String eventType,
    String? organizationId,
    String? subscriptionId,
    Map<String, dynamic>? payload,
  }) async {
    final uid = _user?.id;
    if (uid == null) return;
    try {
      await _sb.from(_lifecycle).insert({
        'user_id': uid,
        'organization_id': (organizationId != null && organizationId.isNotEmpty)
            ? organizationId
            : null,
        'subscription_id':
            (subscriptionId != null && subscriptionId.isNotEmpty)
                ? subscriptionId
                : null,
        'event_type': eventType,
        'payload': payload ?? const <String, dynamic>{},
      });
    } catch (_) {}
  }

  Future<bool> hasRetentionOfferBeenUsed() async {
    final uid = _user?.id;
    if (uid == null) return true;
    try {
      final row = await _sb
          .from(_retentionPrompts)
          .select('user_id')
          .eq('user_id', uid)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return true;
    }
  }

  Future<void> markRetentionOfferShown() async {
    final uid = _user?.id;
    if (uid == null) return;
    try {
      await _sb.from(_retentionPrompts).insert({'user_id': uid});
    } catch (_) {}
  }

  /// بعد الدفع أو من أي شاشة: إبطال تهدئة الاستعلام حتى يُعاد جلب الاشتراك فوراً.
  static void invalidateSubscriptionCache() {
    _currentSubFetchCooldownUntil = null;
    _currentSubInFlight.clear();
    _currentSubCache.clear();
  }

  /// يطابق أعمدة `subscription_plans.user_type` في قاعدة البيانات.
  static String planUserTypeForAccountType(String? accountType) {
    final k = AppRoleHelper.fromAccountType(accountType);
    switch (k) {
      case AppRoleKind.marketer:
        return 'marketer';
      case AppRoleKind.realEstateOffice:
      case AppRoleKind.agency:
        return 'office';
      case AppRoleKind.realEstateCompany:
        return 'company';
      case AppRoleKind.realEstateInstitution:
        return 'institution';
      case AppRoleKind.ownerIndividual:
      case AppRoleKind.publicUser:
        return 'individual';
    }
  }

  /// تسمية نوع الحساب في شاشة الباقات.
  static String planAudienceLabel({required bool isAr, String? accountType}) {
    switch (AppRoleHelper.fromAccountType(accountType)) {
      case AppRoleKind.marketer:
        return isAr ? 'مسوّق عقاري فردي' : 'Independent marketer';
      case AppRoleKind.realEstateOffice:
      case AppRoleKind.agency:
        return isAr ? 'مكتب عقاري' : 'Real estate office';
      case AppRoleKind.realEstateInstitution:
        return isAr ? 'مؤسسة عقارية' : 'Real estate institution';
      case AppRoleKind.realEstateCompany:
        return isAr ? 'شركة عقارية' : 'Real estate company';
      case AppRoleKind.ownerIndividual:
        return isAr ? 'شريك عقاري (مالك/معلن)' : 'Real estate partner (owner)';
      case AppRoleKind.publicUser:
        return isAr ? 'مستخدم' : 'User';
    }
  }

  /// أي رتب من sort_order تظهر لهذا الحساب — السياسة المعتمدة v6
  /// (2026-06-02): «باقة رئيسية + توب-أب الطلبات + تجريبية» لكل دور.
  ///
  ///   • المسوّق الفردي     → الأساسية (1) + الشامل (4) + توب-أب طلبات (21/22/23)
  ///   • المكتب / الوكالة   → الاحترافية (2) + الشامل (4) + توب-أب طلبات (21/22/23)
  ///   • المؤسسة            → الاحترافية (2) + الشامل (4) + توب-أب طلبات (21/22/23)
  ///   • الشركة             → المميّزة (3) + الشامل (4)
  ///   • المالك الفردي / المستخدم العام → لا باقات (مجاني + طلب فوري 30 ر.س)
  static List<int> allowedSortOrdersForAccountType(String? accountType) {
    final k = AppRoleHelper.fromAccountType(accountType);
    switch (k) {
      case AppRoleKind.marketer:
        return const [1, 4, 11, 12, 13, 21, 22, 23];
      case AppRoleKind.realEstateOffice:
      case AppRoleKind.realEstateInstitution:
      case AppRoleKind.agency:
        return const [2, 4, 11, 12, 13, 21, 22, 23];
      case AppRoleKind.realEstateCompany:
        return const [3, 4, 11, 12, 13];
      case AppRoleKind.ownerIndividual:
      case AppRoleKind.publicUser:
        return const [];
    }
  }

  /// باقة «الشامل» — فرد (14) أو أدوار تسويقية (4).
  static bool isComprehensivePlanSortOrder(int sortOrder) =>
      sortOrder == 4 || sortOrder == 14;

  /// باقة رئيسية (ليست توب-أب عروض/طلبات).
  static bool isMainPlanSortOrder(int sortOrder) {
    if (isMarketOffersTopUpSortOrder(sortOrder) ||
        isListingRequestsTopUpSortOrder(sortOrder)) {
      return false;
    }
    return sortOrder == 1 ||
        sortOrder == 2 ||
        sortOrder == 3 ||
        sortOrder == 4 ||
        sortOrder == 14;
  }

  /// هل هذا sort_order تَوب-أب طلبات عقارية إضافية؟
  static bool isListingRequestsTopUpSortOrder(int sortOrder) =>
      sortOrder == 21 || sortOrder == 22 || sortOrder == 23;

  /// هل هذا sort_order توب-أب عروض السوق (للفرد)؟
  static bool isMarketOffersTopUpSortOrder(int sortOrder) =>
      sortOrder == 11 || sortOrder == 12 || sortOrder == 13;

  /// يحوّل استجابة [list_subscription_catalog_plans] إلى قائمة صفوف.
  static List<Map<String, dynamic>> _plansFromCatalogRpc(dynamic raw) {
    if (raw is! Map) return const [];
    final m = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (m['ok'] != true) return const [];
    final plans = m['plans'];
    if (plans is! List) return const [];
    return plans
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((p) => p['is_trial_plan'] != true)
        .toList();
  }

  static List<Map<String, dynamic>> _dedupePlansBySortOrder(
    List<Map<String, dynamic>> rows,
  ) {
    final bySort = <int, Map<String, dynamic>>{};
    for (final p in rows) {
      if (p['is_trial_plan'] == true) continue;
      final n = int.tryParse('${p['sort_order'] ?? 0}') ?? 0;
      bySort.putIfAbsent(n, () => p);
    }
    final keys = bySort.keys.toList()..sort();
    return keys.map((k) => bySort[k]!).toList();
  }

  Future<List<Map<String, dynamic>>> fetchPlansByUserType(
    String? accountType,
  ) async {
    final t = planUserTypeForAccountType(accountType);
    final allowed = allowedSortOrdersForAccountType(accountType);
    if (allowed.isEmpty) return const [];

    // مصدر الحقيقة من الخادم — يتجاوز تعارضات RLS/فلتر العميل.
    try {
      final rpc = await _sb.rpc('list_subscription_catalog_plans');
      final fromRpc = _plansFromCatalogRpc(rpc);
      if (fromRpc.isNotEmpty) return _dedupePlansBySortOrder(fromRpc);
    } catch (_) {}

    try {
      final rows = await _sb
          .from(_plans)
          .select()
          .eq('user_type', t)
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // التجريبية تُعرض عبر بانر منفصل (`_showTrialBanner` في الشاشة) — لا
      // نُدرجها في قائمة الباقات حتى لا تتكرر.
      var filtered = list.where((p) {
        if (p['is_trial_plan'] == true) return false;
        final n = int.tryParse('${p['sort_order'] ?? 0}') ?? 0;
        return allowed.contains(n);
      }).toList();
      if (filtered.isEmpty && list.isNotEmpty) {
        filtered = list
            .where((p) => p['is_trial_plan'] != true)
            .where((p) {
              final n = int.tryParse('${p['sort_order'] ?? 0}') ?? 0;
              return allowed.isNotEmpty && n == allowed.first;
            })
            .toList();
      }
      if (filtered.isNotEmpty) return _dedupePlansBySortOrder(filtered);
      // احتياط: كل الباقات النشطة غير التجريبية لهذا الدور.
      final anyActive = list.where((p) => p['is_trial_plan'] != true).toList();
      if (anyActive.isNotEmpty) return _dedupePlansBySortOrder(anyActive);
    } catch (_) {}
    // Fallback A — جلب صفوف الدور حتى المعطّلة (إن كانت is_active=false بالخطأ)
    try {
      final rows = await _sb
          .from(_plans)
          .select()
          .eq('user_type', t)
          .order('sort_order', ascending: true);
      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((p) => p['is_trial_plan'] != true)
          .toList();
      final allowedRows = list.where((p) {
        final n = int.tryParse('${p['sort_order'] ?? 0}') ?? 0;
        return allowed.contains(n);
      }).toList();
      if (allowedRows.isNotEmpty) return allowedRows;
      if (list.isNotEmpty) return list;
    } catch (_) {}
    // Fallback B — جلب أي باقة أساسية متاحة لأي دور حتى لا تكون الشاشة فارغة
    try {
      final rows = await _sb
          .from(_plans)
          .select()
          .eq('is_active', true)
          .eq('sort_order', allowed.isNotEmpty ? allowed.first : 1)
          .order('sort_order', ascending: true);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((p) => p['is_trial_plan'] != true)
          .toList();
    } catch (_) {}
    return [];
  }

  /// هل استخدم المستخدم التجربة المجانية من قبل؟ (RPC has_user_used_trial)
  Future<bool> hasUserUsedTrial() async {
    if (_user?.id == null) return true;
    try {
      final res = await _sb.rpc('has_user_used_trial');
      if (res is bool) return res;
      return res?.toString().toLowerCase() == 'true';
    } catch (_) {
      // عند فشل RPC لا نُخفِ التجربة — يُعاد الفحص من سياق الفوترة.
      return false;
    }
  }

  /// تفعيل تجربة 3 أيام (مرة واحدة). يستدعي activate_marketing_trial_subscription.
  Future<Map<String, dynamic>> activateMarketingTrialSubscription() async {
    try {
      final res = await _sb.rpc('activate_marketing_trial_subscription');
      if (res is Map) {
        return Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'unexpected_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// هل هذا اشتراك تجريبي؟
  static bool isTrialSubscription(Map<String, dynamic>? row) {
    if (row == null) return false;
    final v = row['is_trial'];
    if (v is bool) return v;
    return '${v ?? ''}'.trim().toLowerCase() == 'true';
  }

  /// هل التجربة فعّالة الآن (is_trial=true وفي الفترة المدفوعة)؟
  static bool isActiveTrial(Map<String, dynamic>? row) {
    if (row == null) return false;
    if (!isTrialSubscription(row)) return false;
    final end = subscriptionExclusiveEndUtc(row);
    if (end == null) return false;
    return end.isAfter(DateTime.now().toUtc());
  }

  /// هل التجربة انتهت (is_trial=true لكن خارج الفترة)؟
  static bool isExpiredTrial(Map<String, dynamic>? row) {
    if (row == null) return false;
    if (!isTrialSubscription(row)) return false;
    final end = subscriptionExclusiveEndUtc(row);
    if (end == null) return true;
    return !end.isAfter(DateTime.now().toUtc());
  }

  Future<Map<String, dynamic>?> getPlanById(String planId) async {
    try {
      final row = await _sb.from(_plans).select().eq('id', planId).maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    } catch (_) {
      return null;
    }
  }

  /// أحدث اشتراك يخص المستخدم (شخصي أو منشأة محددة).
  Future<Map<String, dynamic>?> getCurrentSubscription({
    String? organizationId,
  }) async {
    final uid = _user?.id;
    if (uid == null) return null;

    final key =
        '$uid|${organizationId == null || organizationId.isEmpty ? '' : organizationId}';

    final cool = _currentSubFetchCooldownUntil;
    if (cool != null && DateTime.now().isBefore(cool)) {
      final cached = _currentSubCache[key];
      if (cached != null && subscriptionRowGrantsMarketingAccess(cached)) {
        return cached;
      }
    }

    final inflight = _currentSubInFlight[key];
    if (inflight != null) {
      return inflight;
    }

    final run = _fetchCurrentSubscriptionOnce(
      uid,
      organizationId: organizationId,
      cacheKey: key,
    );
    _currentSubInFlight[key] = run;
    try {
      return await run;
    } finally {
      _currentSubInFlight.remove(key);
    }
  }

  /// يفضّل اشتراكاً يمنح وصولاً فعلياً (مدفوع أو تجربة)؛ وإلا أحدث صف.
  static Map<String, dynamic>? pickPreferredSubscriptionRow(List<dynamic> rows) {
    if (rows.isEmpty) return null;
    Map<String, dynamic>? bestAccess;
    DateTime? bestEnd;
    Map<String, dynamic>? latest;
    DateTime? latestEnd;
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final end = subscriptionExclusiveEndUtc(row);
      if (end != null &&
          (latestEnd == null || end.isAfter(latestEnd))) {
        latestEnd = end;
        latest = row;
      }
      if (!subscriptionRowGrantsMarketingAccess(row) || end == null) {
        continue;
      }
      if (bestEnd == null || end.isAfter(bestEnd)) {
        bestEnd = end;
        bestAccess = row;
      }
    }
    return bestAccess ?? latest;
  }

  /// اشتراك شخصي (organization_id IS NULL) + اشتراك المنشأة إن وُجد.
  Future<List<dynamic>> _loadSubscriptionRowsForContext(
    String uid, {
    String? organizationId,
    bool withPlan = true,
  }) async {
    final personal = await _querySubscriptionRows(
      uid,
      organizationId: null,
      withPlan: withPlan,
    );
    if (organizationId == null || organizationId.isEmpty) {
      return personal;
    }
    final org = await _querySubscriptionRows(
      uid,
      organizationId: organizationId,
      withPlan: withPlan,
    );
    return [...personal, ...org];
  }

  Future<List<dynamic>> _querySubscriptionRows(
    String uid, {
    String? organizationId,
    bool withPlan = true,
  }) async {
    final select = withPlan ? '*, plan:subscription_plans(*)' : '*';
    var q = _sb.from(_subs).select(select).eq('user_id', uid);
    if (organizationId != null && organizationId.isNotEmpty) {
      q = q.eq('organization_id', organizationId);
    } else {
      q = q.filter('organization_id', 'is', 'null');
    }
    return await q
        .order('end_date', ascending: false)
        .limit(25)
        .timeout(const Duration(seconds: 5)) as List;
  }

  Future<Map<String, dynamic>?> _fetchCurrentSubscriptionOnce(
    String uid, {
    String? organizationId,
    required String cacheKey,
  }) async {
    void armCooldown() {
      _currentSubFetchCooldownUntil =
          DateTime.now().add(const Duration(seconds: 90));
    }

    void storeCache(Map<String, dynamic>? row) {
      _currentSubCache[cacheKey] = row;
    }

    try {
      final list = await _loadSubscriptionRowsForContext(
        uid,
        organizationId: organizationId,
        withPlan: true,
      );
      var picked = pickPreferredSubscriptionRow(list);
      if (picked != null && subscriptionRowGrantsMarketingAccess(picked)) {
        _currentSubFetchCooldownUntil = null;
        storeCache(picked);
        return picked;
      }
      if (picked != null) {
        _currentSubFetchCooldownUntil = null;
        storeCache(picked);
        return picked;
      }
      _currentSubFetchCooldownUntil = null;
      storeCache(null);
    } catch (_) {
      try {
        final list2 = await _loadSubscriptionRowsForContext(
          uid,
          organizationId: organizationId,
          withPlan: false,
        );
        final picked = pickPreferredSubscriptionRow(list2);
        if (picked != null) {
          _currentSubFetchCooldownUntil = null;
          storeCache(picked);
          return picked;
        }
        _currentSubFetchCooldownUntil = null;
        storeCache(null);
      } catch (_) {
        armCooldown();
        final cached = _currentSubCache[cacheKey];
        if (cached != null && subscriptionRowGrantsMarketingAccess(cached)) {
          return cached;
        }
        return null;
      }
    }
    return null;
  }

  /// 1 إذا منتهٍ أو يُنذر خلال 7 أيام.
  Future<int> subscriptionMenuBadge({
    String? organizationId,
  }) async {
    final row = await getCurrentSubscription(organizationId: organizationId);
    if (row == null) return 0;
    final status = '${row['status'] ?? ''}';
    final end = subscriptionExclusiveEndUtc(row) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final now = DateTime.now().toUtc();
    if (status == 'cancelled' && !now.isBefore(end)) return 1;
    if (!now.isBefore(end)) return 1;
    if (status == 'active' && end.difference(now).inDays <= 7) return 1;
    return 0;
  }

  /// ترتيب الباقة في الجدول — الأعلى = باقة أعلى (للترقية).
  static int planSortOrder(Map<String, dynamic>? plan) =>
      int.tryParse('${plan?['sort_order'] ?? 0}') ?? 0;

  /// حصة طلبات الإعلان (الباقة الرئيسية + الإضافات).
  Future<Map<String, dynamic>> fetchListingRequestsAllowance({
    String? organizationId,
  }) async {
    try {
      final dynamic res = await _sb.rpc(
        'listing_requests_unified_allowance',
        params: {
          if (organizationId != null && organizationId.trim().isNotEmpty)
            'p_organization_id': organizationId.trim(),
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// فترة مدفوعة فعّالة (نشط أو ملغى حتى [ends_at] حصرية: صالح ما دام now < ends_at.
  static bool subscriptionRowInPaidAccess(Map<String, dynamic>? row) {
    if (AppConfig.devBypassSubscriptionGate) return true;
    if (row == null) return false;
    final st = '${row['status'] ?? ''}'.trim().toLowerCase();
    if (st == 'pending' || st == 'expired') return false;
    final end = subscriptionExclusiveEndUtc(row);
    if (end == null) return false;
    final now = DateTime.now().toUtc();
    if (!now.isBefore(end)) return false;
    return st == 'active' || st == 'cancelled';
  }

  static bool subscriptionAutoRenewEnabled(Map<String, dynamic>? row) {
    if (row == null) return false;
    final v = row['auto_renew'];
    if (v is bool) return v;
    return '${v ?? ''}'.trim().toLowerCase() == 'true';
  }

  static bool subscriptionRenewalFailureFlag(Map<String, dynamic>? row) {
    if (row == null) return false;
    if (row['auto_renew_last_failure_at'] != null) return true;
    return '${row['auto_renew_last_failure_reason'] ?? ''}'.trim().isNotEmpty;
  }

  /// رصيد تقريبي للفترة المتبقية (نسبة الزمن المتبقي × سعر الفترة الحالية).
  static double prorationCreditRemaining(
    Map<String, dynamic> subscriptionRow,
    double fullPeriodPrice,
  ) {
    if (fullPeriodPrice <= 0) return 0;
    final end = subscriptionExclusiveEndUtc(subscriptionRow);
    final start = subscriptionStartsAtUtc(subscriptionRow);
    if (end == null || start == null) return 0;
    final now = DateTime.now().toUtc();
    if (!now.isBefore(end)) return 0;
    final totalSec = end.difference(start).inSeconds;
    if (totalSec <= 0) return 0;
    final remSec = end.difference(now).inSeconds.clamp(0, totalSec);
    return fullPeriodPrice * (remSec / totalSec);
  }

  /// مبلغ مستحق عند تغيير الباقة أو الفترة (سعر الجديد − رصيد المتبقي).
  static double computePlanChangeCharge({
    required Map<String, dynamic> subscriptionRow,
    required Map<String, dynamic> oldPlan,
    required Map<String, dynamic> newPlan,
    required String targetPeriod,
  }) {
    final curPeriod = '${subscriptionRow['period'] ?? 'monthly'}';
    final oldUnit = curPeriod == 'yearly'
        ? _toDouble(oldPlan['price_yearly'])
        : _toDouble(oldPlan['price_monthly']);
    final newUnit = targetPeriod == 'yearly'
        ? _toDouble(newPlan['price_yearly'])
        : _toDouble(newPlan['price_monthly']);
    final credit = prorationCreditRemaining(subscriptionRow, oldUnit);
    final raw = newUnit - credit;
    return double.parse(raw.clamp(0, 1e12).toStringAsFixed(2));
  }

  Future<Map<String, dynamic>> _validateNewSubscriptionEligibility({
    required String planId,
    required String period,
    String? organizationId,
  }) async {
    // طبقة 1: استدعِ RPC الحراسة في DB (مصدر الحقيقة) مع تمرير plan_id
    // ليَعرف الخادم إن كانت الباقة top-up (يُسمح بها مع رئيسية فعّالة).
    try {
      final res = await _sb.rpc(
        'subscription_can_subscribe',
        params: {'p_target_plan_id': planId},
      );
      if (res is Map) {
        final m = Map<String, dynamic>.from(res);
        if (m['can_subscribe'] != true) {
          final reason = '${m['reason'] ?? ''}';
          if (reason == 'team_member_uses_owner_subscription') {
            return {'ok': false, 'error': 'team_member_not_allowed_to_subscribe'};
          }
          if (reason == 'topup_requires_main_subscription') {
            return {'ok': false, 'error': 'topup_requires_main_subscription'};
          }
          if (reason == 'already_active_subscription') {
            final upgradeOnly = m['upgrade_only'] == true;
            return {
              'ok': false,
              'error': upgradeOnly ? 'use_upgrade_flow' : 'active_plan_conflict',
            };
          }
        } else {
          // top-up مسموح به → اقفز فوق الفحوص المحلية (تُعتبر باقات إضافية).
          if (m['topup_purchase'] == true) return {'ok': true, 'topup': true};
        }
      }
    } catch (_) {}

    // طبقة 2: مقارنة محلّية كاحتياط
    final cur = await getCurrentSubscription(organizationId: organizationId);
    if (!subscriptionRowInPaidAccess(cur)) return {'ok': true};
    final curPlanId = '${cur!['plan_id'] ?? ''}'.trim();
    if (curPlanId != planId) {
      final oldP = await getPlanById(curPlanId);
      final newP = await getPlanById(planId);
      final o = planSortOrder(oldP);
      final n = planSortOrder(newP);
      if (n > o) {
        return {'ok': false, 'error': 'use_upgrade_flow'};
      }
      return {'ok': false, 'error': 'active_plan_conflict'};
    }
    final curPeriod = '${cur['period'] ?? ''}'.trim();
    if (curPeriod == period) {
      return {'ok': false, 'error': 'duplicate_active_same_plan'};
    }
    return {'ok': false, 'error': 'use_period_switch_flow'};
  }

  /// خصم تفعيل الدفع التلقائي (10% — شهري فقط) — يقرأها من خطة الباقة.
  static double autoPayDiscountPercent(Map<String, dynamic>? plan) {
    final v = plan?['auto_pay_discount_percent'];
    if (v is num && v >= 0) return v.toDouble();
    return 10.0;
  }

  /// المبلغ المستحق بعد تطبيق خصم الدفع التلقائي إن كان مفعّلاً.
  static double computeAmountAfterAutoPayDiscount({
    required Map<String, dynamic> plan,
    required String period,
    required bool autoRenew,
  }) {
    final base = period == 'yearly'
        ? _toDouble(plan['price_yearly'])
        : _toDouble(plan['price_monthly']);
    if (!autoRenew || period != 'monthly') return base;
    final pct = autoPayDiscountPercent(plan);
    final factor = (1.0 - (pct / 100.0)).clamp(0.0, 1.0);
    return double.parse((base * factor).toStringAsFixed(2));
  }

  /// بوابة الميزات المدفوعة لأعضاء الفريق — تستدعي
  /// public.team_member_paid_feature_gate(). تُستخدم لفلترة الإجراءات في الواجهة.
  Future<Map<String, dynamic>> teamMemberPaidFeatureGate() async {
    try {
      final res = await _sb.rpc('team_member_paid_feature_gate');
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e', 'allow': false};
    }
    return const {'ok': false, 'allow': false};
  }

  /// عرض «خصم الاحتفاظ» مرّة واحدة لمالك الاشتراك عند ضغط «إلغاء».
  /// يُرجع: {ok, available, discount_percent, used_at, …}
  Future<Map<String, dynamic>> offerCancellationRetention(String subscriptionId) async {
    try {
      final res = await _sb.rpc(
        'subscription_offer_cancellation_retention',
        params: {'p_subscription_id': subscriptionId},
      );
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return const {'ok': false};
  }

  /// التحقّق سيرفر-سايد من نيّة الدفع قبل بدء أي تحصيل في Moyasar.
  /// يَفحص: الحد المعدّل، الأحقيّة، والمبلغ الكانوني.
  ///
  /// يُرجع `expected_amount` المُعتمَد من DB — استخدمه بدل أي حساب محلي.
  Future<Map<String, dynamic>> validatePaymentIntent({
    required String planId,
    required String period,
    required double amountSar,
    bool withAutoPay = false,
    String? upgradeSubscriptionId,
    String? idempotencyKey,
  }) async {
    try {
      final res = await _sb.rpc(
        'validate_payment_intent',
        params: {
          'p_plan_id': planId,
          'p_period': period,
          'p_amount_sar': amountSar,
          'p_with_auto_pay': withAutoPay,
          'p_upgrade_subscription_id': upgradeSubscriptionId,
          'p_idempotency_key': idempotencyKey,
        },
      );
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
    return const {'ok': false, 'error': 'unexpected'};
  }

  /// تسجيل نتيجة الدفع في سجل المراجعة (subscribe_ok / subscribe_failed / etc).
  Future<void> recordPaymentOutcome({
    required String event,
    String? planId,
    String? period,
    double? amountSar,
    Map<String, dynamic> payload = const {},
  }) async {
    try {
      await _sb.rpc(
        'record_payment_outcome',
        params: {
          'p_event': event,
          'p_plan_id': planId,
          'p_period': period,
          'p_amount_sar': amountSar,
          'p_payload': payload,
        },
      );
    } catch (_) {}
  }

  /// بعد دفع ميسّر: تحويل اشتراك شهري لنفس الباقة إلى سنوي مع تمديد [end_date].
  Future<Map<String, dynamic>> switchSubscriptionToYearlyAfterPayment({
    required String subscriptionId,
    required String verifiedBillingTransactionId,
    required double expectedChargeSar,
    String? organizationId,
    bool autoRenew = true,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    Map<String, dynamic>? row;
    try {
      final raw = await _sb
          .from(_subs)
          .select('*, plan:subscription_plans(*)')
          .eq('id', subscriptionId)
          .eq('user_id', uid)
          .maybeSingle();
      if (raw != null) row = Map<String, dynamic>.from(raw as Map);
    } catch (_) {}
    if (row == null) return {'ok': false, 'error': 'not_found'};
    if (!subscriptionRowInPaidAccess(row)) {
      return {'ok': false, 'error': 'subscription_not_active'};
    }
    if ('${row['period'] ?? ''}'.trim() != 'monthly') {
      return {'ok': false, 'error': 'period_switch_monthly_only'};
    }
    final plan = row['plan'] is Map
        ? Map<String, dynamic>.from(row['plan'] as Map)
        : <String, dynamic>{};
    final expected = computePlanChangeCharge(
      subscriptionRow: row,
      oldPlan: plan,
      newPlan: plan,
      targetPeriod: 'yearly',
    );
    if ((expected - expectedChargeSar).abs() > 0.05) {
      return {'ok': false, 'error': 'amount_mismatch_reopen_plans'};
    }
    final billingId = verifiedBillingTransactionId.trim();
    final v = await _payments.verifyBillingTransactionPaid(
      billingTransactionId: billingId,
      expectedAmountSar: expectedChargeSar,
    );
    if (v['ok'] != true) {
      return {'ok': false, 'error': v['error'] ?? 'billing_not_paid'};
    }
    final now = DateTime.now().toUtc();
    final prevEnd = subscriptionExclusiveEndUtc(row) ?? now;
    final base = prevEnd.isAfter(now) ? prevEnd : now;
    final newEnd = _periodExclusiveEndUtc(base, 'yearly');
    try {
      await _sb.from(_subs).update({
        'period': 'yearly',
        'starts_at': subscriptionStartsAtUtc(row)?.toIso8601String(),
        'ends_at': newEnd.toIso8601String(),
        'end_date': _dateOnly(
          newEnd.subtract(const Duration(microseconds: 1)),
        ),
        'status': 'active',
        'auto_renew': autoRenew,
      }).eq('id', subscriptionId).eq('user_id', uid);
      await _payments.linkBillingToSubscription(
        billingTransactionId: billingId,
        subscriptionId: subscriptionId,
      );
      await logLifecycleEvent(
        eventType: 'subscription_upgraded',
        organizationId: organizationId,
        subscriptionId: subscriptionId,
        payload: {
          'kind': 'period_to_yearly',
          'plan_id': '${row['plan_id']}',
          'end_date': _dateOnly(
            newEnd.subtract(const Duration(microseconds: 1)),
          ),
          'ends_at': newEnd.toIso8601String(),
          'charged_sar': expectedChargeSar,
        },
      );
      await _payments.notifyBillingSuccessForTransaction(
        billingTransactionId: billingId,
        amount: expectedChargeSar,
        titleAr: 'تحويل إلى سنوي',
        titleEn: 'Switched to yearly billing',
      );
      invalidateSubscriptionCache();
      return {
        'ok': true,
        'end_date': _dateOnly(
          newEnd.subtract(const Duration(microseconds: 1)),
        ),
      };
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> subscribeToPlan({
    required String planId,
    required String period,
    required String paymentMode,
    String? cardId,
    String? organizationId,
    String? titleAr,
    String? titleEn,
    String? verifiedBillingTransactionId,
    bool autoRenew = true,
    double? billedAmountSar,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    final plan = await getPlanById(planId);
    if (plan == null) return {'ok': false, 'error': 'plan'};
    final basePrice = period == 'yearly'
        ? _toDouble(plan['price_yearly'])
        : _toDouble(plan['price_monthly']);
    // خصم الدفع التلقائي 10% — شهري فقط
    final applyAutoPay = autoRenew && period == 'monthly';
    final amount = applyAutoPay
        ? computeAmountAfterAutoPayDiscount(
            plan: plan,
            period: period,
            autoRenew: true,
          )
        : basePrice;
    final verifyAmount = billedAmountSar ?? amount;
    final billingId = verifiedBillingTransactionId?.trim() ?? '';
    if (billingId.isEmpty) {
      final gate = await _validateNewSubscriptionEligibility(
        planId: planId,
        period: period,
        organizationId: organizationId,
      );
      if (gate['ok'] != true) return gate;

      // طبقة أمنية ثالثة: تحقّق سيرفر-سايد من المبلغ + الحد المعدّل + سجِّل النيّة.
      final intent = await validatePaymentIntent(
        planId: planId,
        period: period,
        amountSar: verifyAmount,
        withAutoPay: applyAutoPay,
      );
      if (intent['ok'] != true) {
        return {
          'ok': false,
          'error': intent['error'] ?? 'payment_intent_invalid',
          'detail': intent,
        };
      }
    }
    Map<String, dynamic> payRes;
    if (billingId.isNotEmpty) {
      final v = await _payments.verifyBillingTransactionPaid(
        billingTransactionId: billingId,
        expectedAmountSar: verifyAmount,
      );
      if (v['ok'] != true) {
        return {'ok': false, 'error': v['error'] ?? 'billing_not_paid'};
      }
      payRes = {'ok': true, 'transaction_id': billingId};
    } else if (paymentMode == 'apple_pay') {
      payRes = await _payments.processApplePay(
        amount: amount,
        titleAr: titleAr,
        titleEn: titleEn,
        subscriptionId: null,
      );
    } else if (paymentMode == 'mada_pay') {
      if (cardId != null && cardId.trim().isNotEmpty) {
        payRes = await _payments.processPayment(
          amount: amount,
          cardId: cardId,
          paymentMethod: 'mada_pay',
          titleAr: titleAr,
          titleEn: titleEn,
        );
      } else {
        payRes = await _payments.processMadaPay(
          amount: amount,
          titleAr: titleAr,
          titleEn: titleEn,
          subscriptionId: null,
        );
      }
    } else {
      payRes = await _payments.processPayment(
        amount: amount,
        cardId: cardId,
        paymentMethod: 'card',
        titleAr: titleAr,
        titleEn: titleEn,
      );
    }
    if (payRes['ok'] != true) {
      return {'ok': false, 'error': payRes['error'] ?? 'payment_failed'};
    }
    final paidBillingId =
        billingId.isNotEmpty
            ? billingId
            : '${payRes['transaction_id'] ?? ''}'.trim();
    final startUtc = DateTime.now().toUtc();
    final endUtc = _periodExclusiveEndUtc(startUtc, period);
    try {
      final ins = await _sb
          .from(_subs)
          .insert({
            'user_id': uid,
            'organization_id': organizationId,
            'plan_id': planId,
            'status': 'active',
            'period': period,
            'start_date': _dateOnly(startUtc),
            'end_date': _dateOnly(
              endUtc.subtract(const Duration(microseconds: 1)),
            ),
            'starts_at': startUtc.toIso8601String(),
            'ends_at': endUtc.toIso8601String(),
            'auto_renew': applyAutoPay,
            'auto_pay_discount_applied': applyAutoPay,
          })
          .select('id')
          .single();
      final sid = '${ins['id'] ?? ''}'.trim();
      if (paidBillingId.isNotEmpty && sid.isNotEmpty) {
        await _payments.linkBillingToSubscription(
          billingTransactionId: paidBillingId,
          subscriptionId: sid,
        );
        if (billingId.isNotEmpty) {
          await _payments.notifyBillingSuccessForTransaction(
            billingTransactionId: paidBillingId,
            amount: verifyAmount,
            titleAr: titleAr,
            titleEn: titleEn,
          );
        }
      }
      await logLifecycleEvent(
        eventType: 'subscription_started',
        organizationId: organizationId,
        subscriptionId: sid.isEmpty ? null : sid,
        payload: {
          'plan_id': planId,
          'period': period,
          'start_date': _dateOnly(startUtc),
          'end_date': _dateOnly(
            endUtc.subtract(const Duration(microseconds: 1)),
          ),
          'starts_at': startUtc.toIso8601String(),
          'ends_at': endUtc.toIso8601String(),
        },
      );
      invalidateSubscriptionCache();
      // سجِّل نجاح الاشتراك في سجل المراجعة الأمني.
      await recordPaymentOutcome(
        event: 'subscribe_ok',
        planId: planId,
        period: period,
        amountSar: verifyAmount,
        payload: {
          'subscription_id': sid,
          'auto_renew': applyAutoPay,
          'auto_pay_discount_applied': applyAutoPay,
        },
      );
      return {'ok': true, 'subscription_id': sid};
    } catch (e) {
      await recordPaymentOutcome(
        event: 'subscribe_failed',
        planId: planId,
        period: period,
        amountSar: verifyAmount,
        payload: {'error': e.toString()},
      );
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> cancelSubscription(
    String subscriptionId, {
    String? organizationId,
    String? churnReasonKey,
    String? churnDetail,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    try {
      await _sb.from(_subs).update({
        'status': 'cancelled',
        'auto_renew': false,
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', subscriptionId).eq('user_id', uid);
      await logLifecycleEvent(
        eventType: 'subscription_cancel_finalized',
        organizationId: organizationId,
        subscriptionId: subscriptionId,
        payload: const {},
      );
      final rk = churnReasonKey?.trim() ?? '';
      if (rk.isNotEmpty) {
        await logLifecycleEvent(
          eventType: 'churn_feedback',
          organizationId: organizationId,
          subscriptionId: subscriptionId,
          payload: {
            'reason_key': rk,
            'detail': churnDetail?.trim() ?? '',
          },
        );
      }
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> renewSubscription({
    required String subscriptionId,
    required String paymentMode,
    String? cardId,
    String? verifiedBillingTransactionId,
    bool autoRenewAfterPayment = true,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    Map<String, dynamic>? row;
    try {
      final raw = await _sb
          .from(_subs)
          .select('*, plan:subscription_plans(*)')
          .eq('id', subscriptionId)
          .eq('user_id', uid)
          .maybeSingle();
      if (raw != null) row = Map<String, dynamic>.from(raw as Map);
    } catch (_) {}
    if (row == null) return {'ok': false, 'error': 'not_found'};
    final plan = row['plan'] is Map
        ? Map<String, dynamic>.from(row['plan'] as Map)
        : <String, dynamic>{};
    final period = '${row['period'] ?? 'monthly'}';
    final amount = period == 'yearly'
        ? _toDouble(plan['price_yearly'])
        : _toDouble(plan['price_monthly']);
    Map<String, dynamic> payRes;
    final billingId = verifiedBillingTransactionId?.trim() ?? '';
    if (billingId.isNotEmpty) {
      final v = await _payments.verifyBillingTransactionPaid(
        billingTransactionId: billingId,
        expectedAmountSar: amount,
      );
      if (v['ok'] != true) {
        return {'ok': false, 'error': v['error'] ?? 'billing_not_paid'};
      }
      payRes = {'ok': true, 'transaction_id': billingId};
    } else if (paymentMode == 'apple_pay') {
      payRes = await _payments.processApplePay(
        amount: amount,
        subscriptionId: subscriptionId,
      );
    } else if (paymentMode == 'mada_pay') {
      if (cardId != null && cardId.trim().isNotEmpty) {
        payRes = await _payments.processPayment(
          amount: amount,
          cardId: cardId,
          subscriptionId: subscriptionId,
          paymentMethod: 'mada_pay',
        );
      } else {
        payRes = await _payments.processMadaPay(
          amount: amount,
          subscriptionId: subscriptionId,
        );
      }
    } else {
      payRes = await _payments.processPayment(
        amount: amount,
        cardId: cardId,
        subscriptionId: subscriptionId,
        paymentMethod: 'card',
      );
    }
    if (payRes['ok'] != true) {
      return {'ok': false, 'error': payRes['error'] ?? 'payment_failed'};
    }
    final nowUtc = DateTime.now().toUtc();
    final prevEnd = subscriptionExclusiveEndUtc(row) ?? nowUtc;
    final baseUtc = prevEnd.isAfter(nowUtc) ? prevEnd : nowUtc;
    final newEnd = _periodExclusiveEndUtc(baseUtc, period);
    try {
      await _sb.from(_subs).update({
        'status': 'active',
        'ends_at': newEnd.toIso8601String(),
        'end_date': _dateOnly(
          newEnd.subtract(const Duration(microseconds: 1)),
        ),
        'cancelled_at': null,
        'auto_renew': autoRenewAfterPayment,
        'auto_renew_last_failure_at': null,
        'auto_renew_last_failure_reason': null,
      }).eq('id', subscriptionId).eq('user_id', uid);
      await logLifecycleEvent(
        eventType: 'subscription_renewed',
        organizationId: '${row['organization_id'] ?? ''}'.trim().isEmpty
            ? null
            : '${row['organization_id']}',
        subscriptionId: subscriptionId,
        payload: {
          'end_date': _dateOnly(
            newEnd.subtract(const Duration(microseconds: 1)),
          ),
          'ends_at': newEnd.toIso8601String(),
        },
      );
      if (billingId.isNotEmpty) {
        await _payments.notifyBillingSuccessForTransaction(
          billingTransactionId: billingId,
          amount: amount,
        );
      }
      invalidateSubscriptionCache();
      return {
        'ok': true,
        'end_date': _dateOnly(
          newEnd.subtract(const Duration(microseconds: 1)),
        ),
      };
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> upgradePlan({
    required String subscriptionId,
    required String newPlanId,
    required String paymentMode,
    String? cardId,
    String? verifiedBillingTransactionId,
    double? billedAmountSar,
  }) async {
    final uid = _user?.id;
    if (uid == null) return {'ok': false, 'error': 'auth'};
    final newPlan = await getPlanById(newPlanId);
    if (newPlan == null) return {'ok': false, 'error': 'plan'};
    Map<String, dynamic>? row;
    try {
      final raw = await _sb
          .from(_subs)
          .select('*, plan:subscription_plans(*)')
          .eq('id', subscriptionId)
          .eq('user_id', uid)
          .maybeSingle();
      if (raw != null) row = Map<String, dynamic>.from(raw as Map);
    } catch (_) {}
    if (row == null) return {'ok': false, 'error': 'not_found'};
    if (!subscriptionRowInPaidAccess(row)) {
      return {'ok': false, 'error': 'subscription_not_active'};
    }
    final oldPlan = row['plan'] is Map
        ? Map<String, dynamic>.from(row['plan'] as Map)
        : <String, dynamic>{};
    if (planSortOrder(newPlan) <= planSortOrder(oldPlan)) {
      return {'ok': false, 'error': 'upgrade_only_higher_tier'};
    }
    final period = '${row['period'] ?? 'monthly'}';
    final diff = billedAmountSar ??
        computePlanChangeCharge(
          subscriptionRow: row,
          oldPlan: oldPlan,
          newPlan: newPlan,
          targetPeriod: period,
        );
    Map<String, dynamic> payRes;
    final billingId = verifiedBillingTransactionId?.trim() ?? '';
    if (billingId.isNotEmpty) {
      final v = await _payments.verifyBillingTransactionPaid(
        billingTransactionId: billingId,
        expectedAmountSar: diff,
      );
      if (v['ok'] != true) {
        return {'ok': false, 'error': v['error'] ?? 'billing_not_paid'};
      }
      payRes = {'ok': true, 'transaction_id': billingId};
    } else if (paymentMode == 'apple_pay') {
      payRes = await _payments.processApplePay(
        amount: diff,
        subscriptionId: subscriptionId,
        titleAr: 'ترقية باقة',
        titleEn: 'Plan upgrade',
      );
    } else if (paymentMode == 'mada_pay') {
      if (cardId != null && cardId.trim().isNotEmpty) {
        payRes = await _payments.processPayment(
          amount: diff,
          cardId: cardId,
          subscriptionId: subscriptionId,
          paymentMethod: 'mada_pay',
          titleAr: 'ترقية باقة',
          titleEn: 'Plan upgrade',
        );
      } else {
        payRes = await _payments.processMadaPay(
          amount: diff,
          subscriptionId: subscriptionId,
          titleAr: 'ترقية باقة',
          titleEn: 'Plan upgrade',
        );
      }
    } else {
      payRes = await _payments.processPayment(
        amount: diff,
        cardId: cardId,
        subscriptionId: subscriptionId,
        titleAr: 'ترقية باقة',
        titleEn: 'Plan upgrade',
      );
    }
    if (payRes['ok'] != true) {
      return {'ok': false, 'error': payRes['error'] ?? 'payment_failed'};
    }
    try {
      await _sb
          .from(_subs)
          .update({'plan_id': newPlanId})
          .eq('id', subscriptionId)
          .eq('user_id', uid);
      await logLifecycleEvent(
        eventType: 'subscription_upgraded',
        subscriptionId: subscriptionId,
        payload: {
          'new_plan_id': newPlanId,
          'charged_sar': diff,
          'proration': true,
        },
      );
      if (billingId.isNotEmpty) {
        await _payments.notifyBillingSuccessForTransaction(
          billingTransactionId: billingId,
          amount: diff,
          titleAr: 'ترقية باقة',
          titleEn: 'Plan upgrade',
        );
      }
      invalidateSubscriptionCache();
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> purchaseExtraSeats({
    required int extraSeats,
    int validityDays = 365,
  }) async {
    try {
      final raw = await _sb.rpc(
        'org_purchase_extra_seats',
        params: {
          'p_extra': extraSeats,
          'p_days': validityDays,
        },
      );
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'bad_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// شراء مقاعد إضافية بسعر العضو (خصم 50% تلقائي على السعر الشهري).
  /// يستدعي RPC `org_purchase_extra_seats_priced` الذي يحسب الكلفة + يسجّل
  /// طلب مقاعد في `extra_seats_requests` ويربطه بـ billing_transaction.
  Future<Map<String, dynamic>> purchaseExtraSeatsPriced({
    required int extraSeats,
    String? billingTransactionId,
  }) async {
    try {
      final raw = await _sb.rpc(
        'org_purchase_extra_seats_priced',
        params: {
          'p_extra': extraSeats,
          'p_billing_transaction_id': billingTransactionId,
        },
      );
      if (raw is Map) {
        invalidateSubscriptionCache();
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'bad_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// فحص فوري واحد: فردي/فريق/منشأة + أهلية التجربة + فال + خصم العضو.
  Future<SubscriptionBillingContext> resolveBillingContext() async {
    try {
      final raw = await _sb
          .rpc('resolve_subscription_billing_context')
          .timeout(const Duration(seconds: 8));
      return SubscriptionBillingContext.fromRpc(raw);
    } on TimeoutException {
      return const SubscriptionBillingContext(ok: false, error: 'timeout');
    } catch (e) {
      return SubscriptionBillingContext(ok: false, error: e.toString());
    }
  }

  /// يرجّع سعر العضو الإضافي + المتبقي من حد الفريق + معلومات الخصم.
  Future<Map<String, dynamic>> getSeatUnitPriceInfo() async {
    try {
      final raw = await _sb.rpc('org_seat_unit_price');
      if (raw is Map) {
        return Map<String, dynamic>.from(
          raw.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'bad_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// تسجيل طلب مقاعد إضافية مع صف دفع (اختياري — يكمّل RPC عند التفعيل الكامل).
  Future<Map<String, dynamic>> recordExtraSeatsRequest({
    required String organizationId,
    required int seats,
    required double amount,
    String? transactionId,
  }) async {
    try {
      await _sb.from(_extra).insert({
        'organization_id': organizationId,
        'seats_requested': seats,
        'amount': amount,
        'status': transactionId != null ? 'completed' : 'pending',
        'transaction_id': transactionId,
      });
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// بعد تسجيل الدخول أو تجديد الجلسة: يُعيد الطلبات التي تجاوز فيها المسوّق مهلة إنشاء العقد (٧٢ ساعة بعد قبول العرض).
  Future<int> syncMarketingContractCreationDeadlines72h() async {
    try {
      final raw = await _sb.rpc('sync_expired_accepted_offer_contract_windows');
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
    } catch (_) {}
    return 0;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// أول لحظة **بعد** انتهاء الفترة المدفوعة (حدّ علوي حصري لـ [ends_at]).
  static DateTime _periodExclusiveEndUtc(DateTime startUtc, String period) {
    final s = startUtc.toUtc();
    if (period == 'lifetime_one_time') {
      return DateTime.utc(s.year + 100, s.month, s.day, s.hour, s.minute, s.second,
          s.millisecond, s.microsecond);
    }
    if (period == 'yearly') {
      return DateTime.utc(
        s.year + 1,
        s.month,
        s.day,
        s.hour,
        s.minute,
        s.second,
        s.millisecond,
        s.microsecond,
      );
    }
    var y = s.year;
    var m = s.month + 1;
    while (m > 12) {
      m -= 12;
      y++;
    }
    final dim = DateTime.utc(y, m + 1, 0).day;
    final day = s.day > dim ? dim : s.day;
    return DateTime.utc(
      y,
      m,
      day,
      s.hour,
      s.minute,
      s.second,
      s.millisecond,
      s.microsecond,
    );
  }
}
