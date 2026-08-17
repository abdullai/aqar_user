/// حصة «طلبات عقارية» من [listing_requests_unified_allowance] (الباقة + top-ups).
class ListingRequestsAllowance {
  const ListingRequestsAllowance({
    required this.ok,
    required this.hasSubscription,
    required this.used,
    required this.max,
    required this.remaining,
    required this.unlimited,
    required this.needsPaywall,
    required this.audience,
    this.isTrial = false,
    this.error,
  });

  final bool ok;
  final bool hasSubscription;
  final int used;
  final int max;
  final int remaining;
  final bool unlimited;
  final bool needsPaywall;
  final String audience;
  final bool isTrial;
  final String? error;

  bool get canCreateNow {
    if (!ok) return false;
    if (unlimited) return true;
    if (!hasSubscription) return false;
    return remaining > 0;
  }

  factory ListingRequestsAllowance.fromRpc(Map<String, dynamic> m) {
    final unlimited = m['unlimited'] == true;
    final totalMax = m['total_max'];
    final totalRem = m['total_remaining'];
    final main = m['main'] is Map
        ? Map<String, dynamic>.from(
            (m['main'] as Map).map((k, v) => MapEntry(k.toString(), v)),
          )
        : null;
    int max = 0;
    int rem = 0;
    if (unlimited) {
      max = 999999;
      rem = 999999;
    } else {
      max = totalMax == null ? 0 : (int.tryParse('$totalMax') ?? 0);
      rem = totalRem == null ? max : (int.tryParse('$totalRem') ?? 0);
    }
    return ListingRequestsAllowance(
      ok: m['ok'] == true,
      hasSubscription: m['has_subscription'] == true,
      used: int.tryParse('${m['total_used'] ?? 0}') ?? 0,
      max: max,
      remaining: rem,
      unlimited: unlimited,
      needsPaywall: m['needs_paywall'] == true,
      audience: '${m['audience'] ?? 'individual'}',
      isTrial: main?['is_trial'] == true,
      error: m['error']?.toString(),
    );
  }

  String shortStatusAr() {
    if (!ok) return 'تعذّر التحقق من حصة الطلبات العقارية.';
    if (isTrial && unlimited) {
      return 'الفترة التجريبية — نشر الطلبات العقارية متاح.';
    }
    if (!hasSubscription) {
      return 'يلزم اشتراك فعّال لنشر طلب عقاري في الرئيسية.';
    }
    if (unlimited) return 'يمكنك نشر طلبات عقارية دون حد حالي.';
    if (remaining <= 0) {
      return 'استنفدت حصة الطلبات العقارية ($used من $max).';
    }
    return 'حصة الطلبات: $used من $max — المتبقي $remaining.';
  }

  String shortStatusEn() {
    if (!ok) return 'Could not verify property-request quota.';
    if (isTrial && unlimited) {
      return 'Trial active — property requests are available.';
    }
    if (!hasSubscription) {
      return 'An active subscription is required to post a property request.';
    }
    if (unlimited) return 'Property requests are unlimited for now.';
    if (remaining <= 0) {
      return 'Property request quota used ($used of $max).';
    }
    return 'Requests: $used of $max — $remaining remaining.';
  }
}
