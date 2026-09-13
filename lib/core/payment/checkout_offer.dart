import 'invoice_copy.dart';

/// عرض السعر المعتمد من الخادم — Flutter يعرضه ولا يحسبه.
class CheckoutOffer {
  const CheckoutOffer({
    required this.ok,
    this.error,
    this.basePrice = 0,
    this.finalAmount = 0,
    this.autoPayPct = 0,
    this.autoPaySar = 0,
    this.showAutoPay = false,
    this.promoCode,
    this.promoDiscountSar = 0,
    this.promoPercent = 0,
    this.promoSkipped,
    this.appliedKind = 'none',
    this.discountSar = 0,
    this.discountLabelAr = '',
    this.discountLabelEn = '',
    this.eligibleCodes = const [],
    this.hasEligiblePromos = false,
    this.recommendedKind = 'none',
  });

  final bool ok;
  final String? error;
  final double basePrice;
  final double finalAmount;
  final double autoPayPct;
  final double autoPaySar;
  final bool showAutoPay;
  final String? promoCode;
  final double promoDiscountSar;
  final double promoPercent;
  final String? promoSkipped;
  final String appliedKind;
  final double discountSar;
  final String discountLabelAr;
  final String discountLabelEn;
  final List<CheckoutPromoOption> eligibleCodes;
  final bool hasEligiblePromos;
  final String recommendedKind;

  bool get showAutoPayRow =>
      (appliedKind == 'auto_pay' || appliedKind == 'stacked') &&
      autoPaySar > 0.004;

  bool get showPromoRow =>
      (appliedKind == 'promo' || appliedKind == 'stacked') &&
      promoDiscountSar > 0.004 &&
      (promoCode ?? '').trim().isNotEmpty;

  double get bestEligiblePercent {
    var best = 0.0;
    for (final c in eligibleCodes) {
      if (c.percent > best) best = c.percent;
    }
    return best;
  }

  bool isBetterThanAutoPay(double autoPayPercent) =>
      hasEligiblePromos && bestEligiblePercent > autoPayPercent + 0.0001;

  /// حقل الكود: أكواد حقيقية فقط، وأفضل من التجديد إن كان التجديد مفعّلاً.
  bool shouldShowPromoField({
    required bool autoRenewOn,
    required double autoPayPercent,
    required bool promoAlreadyApplied,
  }) {
    if (promoAlreadyApplied) return true;
    if (!hasEligiblePromos) return false;
    if (!autoRenewOn) return true;
    return isBetterThanAutoPay(autoPayPercent);
  }

  bool get showBeforeDiscount =>
      discountSar > 0.004 &&
      appliedKind != 'none' &&
      appliedKind.trim().isNotEmpty &&
      (showAutoPayRow || showPromoRow);

  String discountLabel({required bool isAr}) {
    if (appliedKind == 'promo' || showPromoRow) {
      return InvoiceCopy.promoCodeDiscountLabel(isAr: isAr);
    }
    if (appliedKind == 'auto_pay' || showAutoPayRow) {
      return InvoiceCopy.autoRenewDiscountLabel(isAr: isAr);
    }
    final stored = isAr ? discountLabelAr : discountLabelEn;
    if (stored.trim().isNotEmpty) return stored.trim();
    return isAr ? 'الخصم' : 'Discount';
  }

  factory CheckoutOffer.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const CheckoutOffer(ok: false, error: 'bad_response');
    }
    final m = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (m['ok'] != true) {
      return CheckoutOffer(
        ok: false,
        error: '${m['error'] ?? 'offer_failed'}',
        eligibleCodes: CheckoutPromoOption.listFrom(m['eligible_codes']),
      );
    }
    final codes = CheckoutPromoOption.listFrom(m['eligible_codes']);
    return CheckoutOffer(
      ok: true,
      basePrice: _n(m['base_price']),
      finalAmount: _n(m['final_amount']),
      autoPayPct: _n(m['auto_pay_discount_pct']),
      autoPaySar: _n(m['auto_pay_discount_sar']),
      showAutoPay: m['show_auto_pay'] == true,
      promoCode: _s(m['promo_code']),
      promoDiscountSar: _n(m['promo_discount_sar']),
      promoPercent: _n(m['promo_percent']),
      promoSkipped: _s(m['promo_skipped']),
      appliedKind: '${m['applied_discount_kind'] ?? 'none'}',
      discountSar: _n(m['discount_sar']),
      discountLabelAr: '${m['discount_label_ar'] ?? ''}',
      discountLabelEn: '${m['discount_label_en'] ?? ''}',
      eligibleCodes: codes,
      hasEligiblePromos: m['has_eligible_promos'] == true || codes.isNotEmpty,
      recommendedKind: '${m['recommended_kind'] ?? 'none'}',
    );
  }

  static double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  static String? _s(dynamic v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
}

class CheckoutPromoOption {
  const CheckoutPromoOption({
    required this.code,
    this.kind = 'percent_off',
    this.percent = 0,
    this.discountSar = 0,
    this.minAmountSar,
    this.maxDiscountSar,
    this.validTo,
    this.titleAr,
    this.titleEn,
    this.stackWithAutoPay = false,
  });

  final String code;
  final String kind;
  final double percent;
  final double discountSar;
  final double? minAmountSar;
  final double? maxDiscountSar;
  final String? validTo;
  final String? titleAr;
  final String? titleEn;
  final bool stackWithAutoPay;

  String percentLabel({required bool isAr}) {
    if (kind == 'percent_off' && percent > 0) {
      return '${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 1)}%';
    }
    return '';
  }

  factory CheckoutPromoOption.fromMap(Map<String, dynamic> m) {
    double? opt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    return CheckoutPromoOption(
      code: '${m['code'] ?? ''}'.trim(),
      kind: '${m['kind'] ?? 'percent_off'}',
      percent: CheckoutOffer._n(m['percent']),
      discountSar: CheckoutOffer._n(m['discount_sar']),
      minAmountSar: opt(m['min_amount_sar']),
      maxDiscountSar: opt(m['max_discount_sar']),
      validTo: CheckoutOffer._s(m['valid_to']),
      titleAr: CheckoutOffer._s(m['title_ar']),
      titleEn: CheckoutOffer._s(m['title_en']),
      stackWithAutoPay: m['stack_with_auto_pay'] == true,
    );
  }

  static List<CheckoutPromoOption> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <CheckoutPromoOption>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final o = CheckoutPromoOption.fromMap(
        Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))),
      );
      if (o.code.isEmpty) continue;
      if (RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(o.code)) {
        continue;
      }
      out.add(o);
    }
    return out;
  }
}
