import 'package:flutter/foundation.dart';

/// يستخرج أسعار الباقة بمرونة من خريطة plan (مع دعم الحقول البديلة).
/// Resolves plan prices from map with fallback keys.
class PlanPriceResolver {
  PlanPriceResolver(this.plan);

  final Map<String, dynamic> plan;

  /// قراءة السعر الشهري من عدة مصادر محتملة.
  static double resolveMonthly(Map<String, dynamic> plan) {
    final nested = plan['plan'];
    final src = (plan['price_monthly'] != null || plan['price_yearly'] != null)
        ? plan
        : (nested is Map ? Map<String, dynamic>.from(nested) : plan);
    final v = src['price_monthly'] ??
        src['monthly_price'] ??
        src['price'] ??
        src['amount'] ??
        plan['price_monthly'] ??
        0.0;
    return _read(v);
  }

  /// قراءة السعر السنوي من عدة مصادر محتملة.
  static double resolveYearly(Map<String, dynamic> plan) {
    final nested = plan['plan'];
    final src = (plan['price_monthly'] != null || plan['price_yearly'] != null)
        ? plan
        : (nested is Map ? Map<String, dynamic>.from(nested) : plan);
    final v = src['price_yearly'] ??
        src['yearly_price'] ??
        src['annual_price'] ??
        plan['price_yearly'] ??
        0.0;
    return _read(v);
  }

  static double _read(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = '$v'.trim().replaceAll(',', '.');
    return double.tryParse(s) ?? 0;
  }

  Map<String, dynamic> get _source {
    if (plan['price_monthly'] != null || plan['price_yearly'] != null) {
      return plan;
    }
    final nested = plan['plan'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    return plan;
  }

  double get monthly => resolveMonthly(plan);

  double get yearly => resolveYearly(plan);

  double priceForPeriod(String period) {
    final p = period.trim().toLowerCase();
    if (p == 'lifetime_one_time' || p == 'one_time') return monthly;
    if (p == 'yearly') return yearly > 0 ? yearly : monthly * 12;
    return monthly;
  }

  double autoPayDiscountPercent() {
    final v = plan['auto_pay_discount_percent'] ?? _source['auto_pay_discount_percent'];
    if (v is num) return v.toDouble();
    return 10.0;
  }

  double chargeAmount({
    required String period,
    bool withAutoPay = false,
    bool isExistingSubscription = false,
    double? override,
  }) {
    if (override != null && override > 0) {
      return double.parse(override.clamp(0, 1e12).toStringAsFixed(2));
    }
    final base = priceForPeriod(period);
    if (isExistingSubscription || !withAutoPay) {
      return double.parse(base.toStringAsFixed(2));
    }
    final p = period.trim().toLowerCase();
    if (p == 'yearly' || p == 'lifetime_one_time' || p == 'one_time') {
      return double.parse(base.toStringAsFixed(2));
    }
    final pct = autoPayDiscountPercent();
    final discount = base * (pct / 100.0);
    return double.parse((base - discount).clamp(0, 1e12).toStringAsFixed(2));
  }

  void debugLog(String period) {
    if (!kDebugMode) return;
    debugPrint(
      '[PlanPriceResolver] planId=${plan['id']} period=$period '
      'monthly=$monthly yearly=$yearly '
      'charge=${chargeAmount(period: period)}',
    );
  }
}
