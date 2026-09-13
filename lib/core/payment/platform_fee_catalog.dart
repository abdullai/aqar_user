import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_money.dart';

/// أسعار رسوم المنصة من `platform_fee_catalog` — الرقم كما في القاعدة؛ الرمز حسب اللغة.
class PlatformFeeCatalog extends ChangeNotifier {
  PlatformFeeCatalog(this._sb) {
    instance = this;
  }

  final SupabaseClient _sb;

  static const instantMarketRequest = 'instant_market_request';
  static const saveCardVerify = 'save_card_verify';
  static const guestOneTimeDeal = 'guest_one_time_deal';

  static PlatformFeeCatalog? instance;

  static PlatformFeeCatalog of(BuildContext context, {bool listen = false}) =>
      Provider.of<PlatformFeeCatalog>(context, listen: listen);

  final Map<String, double> _amounts = {};
  bool loaded = false;

  Future<void> refresh() async {
    try {
      final rows = await _sb
          .from('platform_fee_catalog')
          .select('fee_key, amount_sar');
      final next = <String, double>{};
      for (final raw in rows) {
        final key = (raw['fee_key'] ?? '').toString().trim();
        final amt = _readAmount(raw['amount_sar']);
        if (key.isEmpty || amt == null || amt <= 0) continue;
        next[key] = amt;
      }
      _amounts
        ..clear()
        ..addAll(next);
      loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[PlatformFeeCatalog] $e');
    }
  }

  List<MapEntry<String, double>> get entries {
    final keys = _amounts.keys.toList()..sort();
    return [for (final k in keys) MapEntry(k, _amounts[k]!)];
  }

  double? amountOf(String feeKey) => _amounts[feeKey];

  /// الرقم كما في القاعدة (بدون رمز عملة).
  String numberText(String feeKey, {required bool isAr}) {
    final v = _amounts[feeKey];
    if (v == null) return '';
    return AppMoney.formatNumber(
      v,
      isAr: isAr,
      maxFractionDigits: _frac(v),
    );
  }

  /// الرقم + رمز/نص العملة حسب اللغة (﷼ / SAR).
  String phrase(String feeKey, {required bool isAr}) {
    final v = _amounts[feeKey];
    if (v == null) return '';
    return AppMoney.formatWithCurrencyCode(
      v,
      isAr: isAr,
      maxFractionDigits: _frac(v),
    );
  }

  String instantPhrase({required bool isAr}) =>
      phrase(instantMarketRequest, isAr: isAr);

  String guestPhrase({required bool isAr}) =>
      phrase(guestOneTimeDeal, isAr: isAr);

  String saveCardPhrase({required bool isAr}) =>
      phrase(saveCardVerify, isAr: isAr);

  String instantTitle({required bool isAr}) {
    final p = instantPhrase(isAr: isAr);
    if (p.isEmpty) return isAr ? 'الطلب الفوري' : 'Instant request';
    return isAr ? 'الطلب الفوري — $p' : 'Instant request — $p';
  }

  String instantPayOnlyHint({required bool isAr}) {
    final p = instantPhrase(isAr: isAr);
    if (isAr) {
      return p.isEmpty
          ? 'ادفع فقط عند اختيار «فوري»'
          : 'ادفع $p فقط عند اختيار «فوري»';
    }
    return p.isEmpty
        ? 'pay only when you choose Instant'
        : 'pay $p only when you choose Instant';
  }

  String instantRequiresPay({required bool isAr}) {
    final p = instantPhrase(isAr: isAr);
    if (isAr) {
      return p.isEmpty
          ? 'الطلب الفوري يتطلب الدفع قبل النشر.'
          : 'الطلب الفوري يتطلب دفع $p قبل النشر.';
    }
    return p.isEmpty
        ? 'Instant requests require payment before publishing.'
        : 'Instant requests require $p payment before publishing.';
  }

  String instantPayIncomplete({required bool isAr}) {
    final p = instantPhrase(isAr: isAr);
    if (isAr) {
      return p.isEmpty
          ? 'لم يُكتمل دفع الطلب الفوري.'
          : 'لم يُكتمل دفع الطلب الفوري ($p).';
    }
    return p.isEmpty
        ? 'Instant request payment was not completed.'
        : 'Instant request payment ($p) was not completed.';
  }

  String instantRefundHint({required bool isAr}) {
    final p = instantPhrase(isAr: isAr);
    if (isAr) {
      return p.isEmpty
          ? 'سيتم استرداد المبلغ إلى وسيلة الدفع الأصلية.'
          : 'سيتم استرداد $p إلى وسيلة الدفع الأصلية.';
    }
    return p.isEmpty
        ? 'The amount will be refunded to your original payment method.'
        : '$p will be refunded to your original payment method.';
  }

  String cancelInstantRefund({required bool isAr}) {
    final p = instantPhrase(isAr: isAr);
    if (isAr) {
      return p.isEmpty
          ? 'إلغاء الطلب (استرجاع المبلغ)'
          : 'إلغاء الطلب (استرجاع $p)';
    }
    return p.isEmpty
        ? 'Cancel request (refund)'
        : 'Cancel request (refund $p)';
  }

  String unusedPaymentReversal({required bool isAr}) {
    final p = instantPhrase(isAr: isAr);
    if (isAr) {
      return p.isEmpty
          ? 'لم تُستخدم هذه الدفعة في طلب منشور. سيتم عكس المبلغ على نفس وسيلة الدفع حسب سياسة البوابة.'
          : 'لم تُستخدم هذه الدفعة في طلب منشور. سيتم عكس المبلغ ($p) على نفس وسيلة الدفع حسب سياسة البوابة.';
    }
    return p.isEmpty
        ? 'This payment was not used for a published request. The amount will be reversed to your payment method per gateway policy.'
        : 'This payment was not used for a published request. $p will be reversed to your payment method per gateway policy.';
  }

  String instantPaidGuestHint({required bool isAr}) {
    final p = instantPhrase(isAr: isAr);
    if (isAr) {
      return p.isEmpty
          ? 'هذا الطلب مدفوع — يمكنك إتمام الصفقة والدردشة مع مقدّم الطلب بدون أي اشتراك. سجّل الدخول أو أنشئ حساباً مجانياً للمتابعة.'
          : 'هذا الطلب مدفوع ($p) — يمكنك إتمام الصفقة والدردشة مع مقدّم الطلب بدون أي اشتراك. سجّل الدخول أو أنشئ حساباً مجانياً للمتابعة.';
    }
    return p.isEmpty
        ? 'This is a paid instant request — you can complete the deal and chat with the requester with no subscription. Sign in or create a free account to continue.'
        : 'This is a paid instant request ($p) — you can complete the deal and chat with the requester with no subscription. Sign in or create a free account to continue.';
  }

  static int _frac(double v) => v == v.roundToDouble() ? 0 : 2;

  static double? _readAmount(dynamic raw) {
    if (raw is num) {
      final d = raw.toDouble();
      return d > 0 ? d : null;
    }
    return double.tryParse('${raw ?? ''}');
  }
}
