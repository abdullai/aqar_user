import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/subscription.dart';

/// خدمة باقات الاشتراك.
///
/// تحاول القراءة/الكتابة من جداول Supabase أولاً، وإن لم تكن الجداول جاهزة
/// تُستخدم الباقات المضمّنة + SharedPreferences حتى لا تتعطل الميزة.
class SubscriptionService {
  SubscriptionService._();

  static final SupabaseClient _sb = Supabase.instance.client;

  static const _prefsKeyPrefix = 'aqar_subscription_v1_';

  /// الباقات الافتراضية (مضمّنة في التطبيق).
  static const List<SubscriptionPlan> defaultPlans = [
    SubscriptionPlan(
      id: SubscriptionPlanId.free,
      nameAr: 'مجاني',
      nameEn: 'Free',
      descriptionAr: 'ابدأ بنشر إعلان واحد مجاناً.',
      descriptionEn: 'Start with one free active listing.',
      priceSar: 0,
      durationDays: 3650,
      maxActiveListings: 1,
      featuredListings: false,
      prioritySupport: false,
      featuresAr: [
        'إعلان نشط واحد',
        'حجز لمدة 72 ساعة',
        'دردشة مرتبطة بالعقار',
      ],
      featuresEn: [
        '1 active listing',
        '72-hour reservations',
        'Property-linked chat',
      ],
    ),
    SubscriptionPlan(
      id: SubscriptionPlanId.basic,
      nameAr: 'أساسي',
      nameEn: 'Basic',
      descriptionAr: 'مناسب للأفراد الذين ينشرون عدة عقارات.',
      descriptionEn: 'Ideal for individuals listing several properties.',
      priceSar: 49,
      durationDays: 30,
      maxActiveListings: 5,
      featuredListings: false,
      prioritySupport: false,
      featuresAr: [
        'حتى 5 إعلانات نشطة',
        'إدارة الحجوزات والدردشة',
        'أولوية ظهور أعلى من المجاني',
      ],
      featuresEn: [
        'Up to 5 active listings',
        'Reservations & chat management',
        'Higher visibility than Free',
      ],
    ),
    SubscriptionPlan(
      id: SubscriptionPlanId.pro,
      nameAr: 'احترافي',
      nameEn: 'Pro',
      descriptionAr: 'للوسطاء والمحترفين مع ظهور مميز.',
      descriptionEn: 'For brokers and pros with featured visibility.',
      priceSar: 149,
      durationDays: 30,
      maxActiveListings: 20,
      featuredListings: true,
      prioritySupport: true,
      isPopular: true,
      featuresAr: [
        'حتى 20 إعلاناً نشطاً',
        'إعلانات مميزة (Featured)',
        'دعم فني ذو أولوية',
        'شارة مشترك احترافي',
      ],
      featuresEn: [
        'Up to 20 active listings',
        'Featured listings',
        'Priority support',
        'Pro subscriber badge',
      ],
    ),
    SubscriptionPlan(
      id: SubscriptionPlanId.business,
      nameAr: 'أعمال',
      nameEn: 'Business',
      descriptionAr: 'للمكاتب والمؤسسات دون حد للإعلانات.',
      descriptionEn: 'For agencies with unlimited listings.',
      priceSar: 399,
      durationDays: 30,
      maxActiveListings: null,
      featuredListings: true,
      prioritySupport: true,
      featuresAr: [
        'إعلانات غير محدودة',
        'إعلانات مميزة',
        'دعم فني ذو أولوية',
        'لوحة متابعة موسّعة قريباً',
      ],
      featuresEn: [
        'Unlimited listings',
        'Featured listings',
        'Priority support',
        'Extended dashboard (coming soon)',
      ],
    ),
  ];

  static SubscriptionPlan planById(SubscriptionPlanId id) {
    return defaultPlans.firstWhere(
      (p) => p.id == id,
      orElse: () => defaultPlans.first,
    );
  }

  static Future<List<SubscriptionPlan>> fetchPlans() async {
    try {
      final rows = await _sb
          .from('subscription_plans')
          .select(
            'code,name_ar,name_en,description_ar,description_en,price_sar,duration_days,max_active_listings,featured_listings,priority_support,is_popular,features_ar,features_en,is_active',
          )
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      if (rows is List && rows.isNotEmpty) {
        final plans = <SubscriptionPlan>[];
        for (final r in rows) {
          if (r is! Map) continue;
          final m = Map<String, dynamic>.from(r);
          plans.add(
            SubscriptionPlan(
              id: SubscriptionPlan.idFromString('${m['code']}'),
              nameAr: '${m['name_ar'] ?? ''}',
              nameEn: '${m['name_en'] ?? ''}',
              descriptionAr: '${m['description_ar'] ?? ''}',
              descriptionEn: '${m['description_en'] ?? ''}',
              priceSar: _toDouble(m['price_sar']),
              durationDays: _toInt(m['duration_days'], 30),
              maxActiveListings: m['max_active_listings'] == null
                  ? null
                  : _toInt(m['max_active_listings'], 1),
              featuredListings: m['featured_listings'] == true,
              prioritySupport: m['priority_support'] == true,
              isPopular: m['is_popular'] == true,
              featuresAr: _toStringList(m['features_ar']),
              featuresEn: _toStringList(m['features_en']),
            ),
          );
        }
        if (plans.isNotEmpty) return plans;
      }
    } catch (_) {
      // الجداول غير جاهزة — نستخدم الباقات المضمّنة.
    }
    return defaultPlans;
  }

  static Future<UserSubscription> getCurrentSubscription(String userId) async {
    if (userId.trim().isEmpty) {
      return UserSubscription.free(userId);
    }

    try {
      final row = await _sb
          .from('user_subscriptions')
          .select(
            'user_id,plan_code,status,started_at,expires_at,requested_at',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row != null) {
        final m = Map<String, dynamic>.from(row);
        var status =
            UserSubscription.statusFromString('${m['status'] ?? ''}');
        final expiresAt = _tryParseDt(m['expires_at']);
        if (status == SubscriptionStatus.active &&
            expiresAt != null &&
            expiresAt.isBefore(DateTime.now())) {
          status = SubscriptionStatus.expired;
        }
        return UserSubscription(
          userId: '${m['user_id'] ?? userId}',
          planId: SubscriptionPlan.idFromString('${m['plan_code'] ?? 'free'}'),
          status: status,
          startedAt: _tryParseDt(m['started_at']),
          expiresAt: expiresAt,
          requestedAt: _tryParseDt(m['requested_at']),
        );
      }
    } catch (_) {
      // fallback to local
    }

    return _loadLocal(userId);
  }

  /// يطلب ترقية الباقة (حالة pending حتى يتم التفعيل/الدفع).
  /// الباقة المجانية تُفعّل فوراً.
  static Future<UserSubscription> requestPlan({
    required String userId,
    required SubscriptionPlanId planId,
  }) async {
    final plan = planById(planId);
    final now = DateTime.now();

    if (plan.isFree) {
      final sub = UserSubscription(
        userId: userId,
        planId: SubscriptionPlanId.free,
        status: SubscriptionStatus.active,
        startedAt: now,
        expiresAt: null,
        requestedAt: now,
      );
      await _persist(sub);
      return sub;
    }

    // تفعيل تجريبي محلي/DB لمدة الباقة حتى يتكامل الدفع لاحقاً.
    final sub = UserSubscription(
      userId: userId,
      planId: planId,
      status: SubscriptionStatus.active,
      startedAt: now,
      expiresAt: now.add(Duration(days: plan.durationDays)),
      requestedAt: now,
    );
    await _persist(sub);
    return sub;
  }

  /// إلغاء الاشتراك المدفوع والرجوع للمجاني.
  static Future<UserSubscription> cancelToFree(String userId) async {
    final sub = UserSubscription(
      userId: userId,
      planId: SubscriptionPlanId.free,
      status: SubscriptionStatus.active,
      startedAt: DateTime.now(),
      expiresAt: null,
      requestedAt: DateTime.now(),
    );
    await _persist(sub);
    return sub;
  }

  /// عدد الإعلانات النشطة للمستخدم من جدول properties.
  static Future<int> countActiveListings(String userId) async {
    if (userId.trim().isEmpty) return 0;
    try {
      final rows = await _sb
          .from('properties')
          .select('id')
          .eq('owner_id', userId)
          .eq('status', 'active');
      if (rows is List) return rows.length;
    } catch (_) {
      try {
        final rows = await _sb
            .from('properties')
            .select('id')
            .eq('owner_id', userId);
        if (rows is List) return rows.length;
      } catch (_) {}
    }
    return 0;
  }

  /// هل يُسمح بإضافة إعلان جديد حسب الباقة الحالية؟
  static Future<({bool allowed, String? reasonAr, String? reasonEn, SubscriptionPlan plan, int used})>
      canAddListing(String userId) async {
    final sub = await getCurrentSubscription(userId);
    final planId =
        sub.isActive ? sub.planId : SubscriptionPlanId.free;
    final plan = planById(planId);
    final used = await countActiveListings(userId);
    final max = plan.maxActiveListings;

    if (max == null || used < max) {
      return (allowed: true, reasonAr: null, reasonEn: null, plan: plan, used: used);
    }

    return (
      allowed: false,
      reasonAr:
          'وصلتَ إلى حد باقة «${plan.nameAr}» ($max إعلانات نشطة). رقِّ اشتراكك لإضافة المزيد.',
      reasonEn:
          'You reached the «${plan.nameEn}» plan limit ($max active listings). Upgrade to add more.',
      plan: plan,
      used: used,
    );
  }

  static Future<void> _persist(UserSubscription sub) async {
    var wroteRemote = false;
    try {
      await _sb.from('user_subscriptions').upsert({
        'user_id': sub.userId,
        'plan_code': SubscriptionPlan.idToDb(sub.planId),
        'status': UserSubscription.statusToDb(sub.status),
        'started_at': sub.startedAt?.toIso8601String(),
        'expires_at': sub.expiresAt?.toIso8601String(),
        'requested_at':
            (sub.requestedAt ?? DateTime.now()).toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
      wroteRemote = true;
    } catch (_) {
      try {
        await _sb.from('user_subscriptions').insert({
          'user_id': sub.userId,
          'plan_code': SubscriptionPlan.idToDb(sub.planId),
          'status': UserSubscription.statusToDb(sub.status),
          'started_at': sub.startedAt?.toIso8601String(),
          'expires_at': sub.expiresAt?.toIso8601String(),
          'requested_at':
              (sub.requestedAt ?? DateTime.now()).toIso8601String(),
        });
        wroteRemote = true;
      } catch (_) {}
    }

    await _saveLocal(sub);
    if (!wroteRemote) {
      // لا مشكلة — التخزين المحلي يكفي حتى تُنشأ الجداول.
    }
  }

  static Future<void> _saveLocal(UserSubscription sub) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'user_id': sub.userId,
      'plan_code': SubscriptionPlan.idToDb(sub.planId),
      'status': UserSubscription.statusToDb(sub.status),
      'started_at': sub.startedAt?.toIso8601String(),
      'expires_at': sub.expiresAt?.toIso8601String(),
      'requested_at': sub.requestedAt?.toIso8601String(),
    };
    await prefs.setString('$_prefsKeyPrefix${sub.userId}', jsonEncode(payload));
  }

  static Future<UserSubscription> _loadLocal(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsKeyPrefix$userId');
      if (raw == null || raw.isEmpty) {
        return UserSubscription.free(userId);
      }
      final m = jsonDecode(raw);
      if (m is! Map) return UserSubscription.free(userId);
      var status =
          UserSubscription.statusFromString('${m['status'] ?? 'active'}');
      final expiresAt = _tryParseDt(m['expires_at']);
      if (status == SubscriptionStatus.active &&
          expiresAt != null &&
          expiresAt.isBefore(DateTime.now())) {
        status = SubscriptionStatus.expired;
      }
      final planId = SubscriptionPlan.idFromString('${m['plan_code']}');
      if (status == SubscriptionStatus.expired) {
        return UserSubscription.free(userId);
      }
      return UserSubscription(
        userId: userId,
        planId: planId,
        status: status,
        startedAt: _tryParseDt(m['started_at']),
        expiresAt: expiresAt,
        requestedAt: _tryParseDt(m['requested_at']),
      );
    } catch (_) {
      return UserSubscription.free(userId);
    }
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static int _toInt(dynamic v, int fallback) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static DateTime? _tryParseDt(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static List<String> _toStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        return v.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
    }
    return const [];
  }
}
