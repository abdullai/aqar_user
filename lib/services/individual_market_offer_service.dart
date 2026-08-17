import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/workflow/app_role_helper.dart';

/// حصة تقديم عروض على طلبات السوق من الرئيسية (فردي أو تسويق).
class IndividualMarketOfferAllowance {
  const IndividualMarketOfferAllowance({
    required this.ok,
    required this.hasSubscription,
    required this.used,
    required this.max,
    required this.remaining,
    required this.planProgram,
    required this.isTrial,
    required this.needsPaywall,
    required this.audience,
    this.periodStart,
    this.periodEnd,
    this.startsAt,
    this.endsAt,
    this.subscriptionId,
    this.planId,
    this.error,
  });

  final bool ok;
  final bool hasSubscription;
  final int used;
  final int max;
  final int remaining;
  final String? planProgram;
  final bool isTrial;
  final bool needsPaywall;

  /// `individual` | `marketing`
  final String audience;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? subscriptionId;
  final String? planId;
  final String? error;

  bool get isUnlimited =>
      (isTrial && audience == 'marketing') || max >= 999999;

  bool get canSubmitNow {
    if (!ok) return false;
    if (isUnlimited) return true;
    if (!hasSubscription) return false;
    if (isUnlimited) return true;
    return remaining > 0;
  }

  factory IndividualMarketOfferAllowance.fromRpc(Map<String, dynamic> m) {
    final maxRaw = m['max'];
    final remRaw = m['remaining'];
    int max = 0;
    int rem = 0;
    if (maxRaw == null) {
      max = 999999;
      rem = 999999;
    } else {
      max = int.tryParse('$maxRaw') ?? 0;
      rem = remRaw == null
          ? max
          : (int.tryParse('$remRaw') ?? 0);
    }
    return IndividualMarketOfferAllowance(
      ok: m['ok'] == true,
      hasSubscription: m['has_subscription'] == true,
      used: int.tryParse('${m['used'] ?? 0}') ?? 0,
      max: max,
      remaining: rem,
      planProgram: m['plan_program']?.toString(),
      isTrial: m['is_trial'] == true,
      needsPaywall: m['needs_paywall'] == true,
      audience: '${m['audience'] ?? 'individual'}',
      periodStart: _parseDate(m['period_start']),
      periodEnd: _parseDate(m['period_end']),
      startsAt: _parseTs(m['starts_at']),
      endsAt: _parseTs(m['ends_at']),
      subscriptionId: m['subscription_id']?.toString(),
      planId: m['plan_id']?.toString(),
      error: m['error']?.toString(),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  String shortStatusAr() {
    if (!ok) return 'تعذّر التحقق من الحصة.';
    if (isTrial && audience == 'marketing') {
      return 'الفترة التجريبية مفعّلة — يمكنك إتمام الصفقات.';
    }
    if (!hasSubscription) {
      if (audience != 'marketing') {
        return 'إتمام الصفقة على طلبات الآخرين مجاني — ادفع 30 ر.س فقط عند اختيار «فوري» لطلبك.';
      }
      return 'يلزم اشتراك الباقة المناسبة لنوع حسابك لإتمام الصفقات.';
    }
    if (planProgram == 'lifetime_one_time') {
      return 'رصيدك: $used من $max صفقات (دفعة واحدة). المتبقي: $remaining.';
    }
    return 'حصتك هذا الشهر: $used من $max صفقة. المتبقي: $remaining.';
  }

  String shortStatusEn() {
    if (!ok) return 'Could not verify quota.';
    if (isTrial && audience == 'marketing') {
      return 'Trial active — you can complete deals.';
    }
    if (!hasSubscription) {
      if (audience != 'marketing') {
        return 'Completing deals on others\' requests is free — pay SAR 30 only when you choose Instant for your request.';
      }
      return 'Subscribe to the plan for your account type to complete deals.';
    }
    if (planProgram == 'lifetime_one_time') {
      return 'Balance: $used of $max deals (one-time). Remaining: $remaining.';
    }
    return 'This month: $used of $max deals. Remaining: $remaining.';
  }
}

String individualOfferShortReasonAr(String code) {
  switch (code.trim().toLowerCase()) {
    case 'quota_exhausted':
      return 'استنفدت حصة العروض — اشترِ باقة شهرية أو لمرة واحدة.';
    case 'no_subscription':
      return 'لا يوجد اشتراك عروض فعّال.';
    case 'withdraw_limit_reached':
      return 'تجاوزت حد السحب على هذا الطلب.';
    case 'selected_for_deal':
      return 'لا يمكن السحب — صاحب الطلب اختار عرضك للصفقة.';
    case 'offer_accepted':
      return 'لا يمكن السحب — العرض مقبول.';
    default:
      return code.isEmpty ? 'تعذّر تنفيذ العملية.' : code;
  }
}

/// RPC حصص عروض السوق — فردي أو تسويق حسب نوع الحساب.
class IndividualMarketOfferService {
  IndividualMarketOfferService(this._sb);

  final SupabaseClient _sb;

  Future<IndividualMarketOfferAllowance> currentAllowance({
    String? accountType,
    String? organizationId,
  }) async {
    final at = accountType?.trim() ?? '';
    final isMarketing = AppRoleHelper.isMarketingAccountType(at);

    try {
      // الدالة الموحَّدة الجديدة: تجمع main + topups بأمانة لكل مستخدم.
      final dynamic res = await _sb.rpc(
        'market_offer_unified_allowance',
        params: {
          if (organizationId != null && organizationId.isNotEmpty)
            'p_organization_id': organizationId,
        },
      );
      if (res is Map) {
        final m = Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
        // تكييف نتيجة الدالة الموحَّدة إلى شكل IndividualMarketOfferAllowance.
        final unlimited = m['unlimited'] == true;
        final totalMax = m['total_max'];
        final totalUsed = int.tryParse('${m['total_used'] ?? 0}') ?? 0;
        final totalRem = m['total_remaining'];
        final main = m['main'] is Map
            ? Map<String, dynamic>.from(
                (m['main'] as Map).map((k, v) => MapEntry(k.toString(), v)),
              )
            : null;
        return IndividualMarketOfferAllowance(
          ok: m['ok'] == true,
          hasSubscription: m['has_subscription'] == true,
          used: totalUsed,
          max: unlimited ? 999999 : (int.tryParse('$totalMax') ?? 0),
          remaining: unlimited
              ? 999999
              : (totalRem == null ? 0 : (int.tryParse('$totalRem') ?? 0)),
          planProgram: main == null ? null : main['plan_program']?.toString(),
          isTrial: main?['is_trial'] == true,
          needsPaywall: m['needs_paywall'] == true,
          audience: '${m['audience'] ?? (isMarketing ? 'marketing' : 'individual')}',
          subscriptionId: main == null ? null : main['subscription_id']?.toString(),
          planId: main == null ? null : main['plan_id']?.toString(),
        );
      }
      // fallback للنسخ القديمة من القاعدة
      final dynamic legacy = isMarketing
          ? await _sb.rpc(
              'marketing_market_request_offer_allowance',
              params: {
                if (organizationId != null && organizationId.isNotEmpty)
                  'p_organization_id': organizationId,
              },
            )
          : await _sb.rpc('individual_market_request_offer_allowance');
      if (legacy is Map) {
        return IndividualMarketOfferAllowance.fromRpc(
          Map<String, dynamic>.from(
            legacy.map((k, v) => MapEntry(k.toString(), v)),
          ),
        );
      }
      return const IndividualMarketOfferAllowance(
        ok: false,
        hasSubscription: false,
        used: 0,
        max: 0,
        remaining: 0,
        planProgram: null,
        isTrial: false,
        needsPaywall: true,
        audience: 'individual',
      );
    } catch (e) {
      return IndividualMarketOfferAllowance(
        ok: false,
        hasSubscription: false,
        used: 0,
        max: 0,
        remaining: 0,
        planProgram: null,
        isTrial: false,
        needsPaywall: true,
        audience: isMarketing ? 'marketing' : 'individual',
        error: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> recordUsageOnSuccess(String requestId) async {
    try {
      final res = await _sb.rpc(
        'record_market_request_offer_usage',
        params: {'p_request_id': requestId},
      );
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

  Future<Map<String, dynamic>> withdrawMyOffer(String requestId) async {
    try {
      final res = await _sb.rpc(
        'withdraw_my_market_request_offer',
        params: {'p_request_id': requestId},
      );
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
}
