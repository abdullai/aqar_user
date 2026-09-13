import 'invoice_copy.dart';

/// شرح بشري لعملية الدفع من الحقول الموجودة.
/// ليس نموذجاً لغوياً ولا يحسب أي مبلغ — المبلغ يُمرَّر جاهزاً من السجل.
abstract final class PaymentPlainExplain {
  PaymentPlainExplain._();

  static String receiptSubtitle({
    required bool isAr,
    required String period,
    String? purpose,
  }) {
    final p = (purpose ?? '').trim().toLowerCase();
    if (p.contains('instant') || p.contains('one_time')) {
      return isAr
          ? 'تم تأكيد دفع الطلب الفوري — الرصيد يظهر في تبويب «مرة واحدة».'
          : 'Instant-request payment confirmed — it appears under One-time.';
    }
    if (p.contains('upgrade')) {
      return isAr
          ? 'تم تأكيد فرق الترقية — باقتك المحدَّثة تنعكس فوراً.'
          : 'Upgrade difference confirmed — your new plan is live.';
    }
    if (p.contains('renew')) {
      return isAr
          ? 'تم تأكيد التجديد — الفترة التالية مفعّلة.'
          : 'Renewal confirmed — the next period is active.';
    }
    if (p.contains('period')) {
      return isAr
          ? 'تم التحويل للفترة السنوية بعد دفع الفرق.'
          : 'Switched to yearly after paying the difference.';
    }
    if (p.contains('topup') || p.contains('addon')) {
      return isAr
          ? 'تم شراء الإضافة فوق باقتك الحالية — ليست اشتراكاً جديداً.'
          : 'Add-on purchased on top of your current plan.';
    }
    final periodL = InvoiceCopy.periodLabel(period, isAr: isAr);
    return isAr
        ? 'تم تفعيل العملية ($periodL) وتنعكس في سجل الفواتير حسب حالتها.'
        : 'Payment activated ($periodL) and listed in invoices by status.';
  }

  static String checkoutTrust({required bool isAr}) => isAr
      ? 'لا نخزّن رقم البطاقة ولا رمز CVV. الاشتراك يُفعَّل بعد تأكيد بوابة الدفع، وليس بمجرد الضغط على الدفع.'
      : 'We do not store the card number or CVV. The subscription is activated only after the payment gateway confirms, not when you tap Pay.';
}
