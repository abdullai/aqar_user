import 'dart:convert';

import '../utils/date_helper.dart';

/// نصوص وتصنيف فواتير المدفوعات — مصدر واحد للحقيقة.
abstract final class InvoiceCopy {
  InvoiceCopy._();

  static String periodLabel(String raw, {required bool isAr}) {
    switch (raw.trim().toLowerCase()) {
      case 'yearly':
      case 'annual':
      case 'year':
        return isAr ? 'سنوي' : 'Yearly';
      case 'monthly':
      case 'month':
        return isAr ? 'شهري' : 'Monthly';
      case 'lifetime_one_time':
      case 'one_time':
      case 'onetime':
      case 'once':
        return isAr ? 'مرة واحدة' : 'One-time';
      case 'trial':
        return isAr ? 'تجربة' : 'Trial';
      default:
        final s = raw.trim();
        if (s.isEmpty || s == '—') {
          return isAr ? 'حسب العملية' : 'Per transaction';
        }
        return s;
    }
  }

  static String periodFromRow(Map<String, dynamic> row, {required bool isAr}) {
    final p = '${row['billing_period'] ?? row['period'] ?? ''}'.trim();
    if (p.isNotEmpty) return periodLabel(p, isAr: isAr);
    final purpose = purposeFromRow(row).toLowerCase();
    if (purpose.contains('instant') ||
        purpose.contains('one_time') ||
        purpose.contains('lifetime')) {
      return periodLabel('one_time', isAr: isAr);
    }
    final title =
        '${row['title_ar'] ?? ''} ${row['title_en'] ?? ''} ${row['title'] ?? ''}'
            .toLowerCase();
    if (title.contains('فوري') ||
        title.contains('instant') ||
        title.contains('one-time') ||
        title.contains('مرة واحدة')) {
      return periodLabel('one_time', isAr: isAr);
    }
    if (title.contains('سنوي') || title.contains('yearly')) {
      return periodLabel('yearly', isAr: isAr);
    }
    if (title.contains('شهري') || title.contains('monthly')) {
      return periodLabel('monthly', isAr: isAr);
    }
    return periodLabel('', isAr: isAr);
  }

  static String methodLabel(String raw, {required bool isAr}) {
    switch (raw.trim().toLowerCase()) {
      case 'card':
      case 'credit_card':
      case 'saved':
      case 'saved_card':
        return isAr ? 'بطاقة محفوظة' : 'Saved card';
      case 'new':
      case 'new_card':
        return isAr ? 'بطاقة جديدة' : 'New card';
      case 'visa':
        return isAr ? 'فيزا' : 'Visa';
      case 'mastercard':
      case 'master':
        return isAr ? 'ماستركارد' : 'Mastercard';
      case 'mada_pay':
      case 'mada':
        return isAr ? 'مدى' : 'mada';
      case 'google_pay':
        return 'Google Pay';
      case 'samsung_pay':
        return 'Samsung Pay';
      case 'apple_pay':
        return 'Apple Pay';
      case 'stc_pay':
        return 'STC Pay';
      case 'web_pay':
        return isAr ? 'محفظة المتصفح' : 'Browser wallet';
      default:
        final s = raw.trim();
        if (s.isEmpty) return isAr ? 'غير متوفر' : 'Unavailable';
        return s;
    }
  }

  static String statusLabel(String code, {required bool isAr}) {
    switch (code.trim().toLowerCase()) {
      case 'success':
      case 'paid':
        return isAr ? 'مدفوعة' : 'Paid';
      case 'refunded':
        return isAr ? 'مسترجعة' : 'Refunded';
      case 'partially_refunded':
        return isAr ? 'مسترجعة جزئياً' : 'Partially refunded';
      case 'pending':
        return isAr ? 'معلقة' : 'Pending';
      case 'authorized':
        return isAr ? 'بانتظار الاكتمال' : 'Authorized';
      case 'failed':
        return isAr ? 'فاشلة' : 'Failed';
      case 'voided':
        return isAr ? 'ملغاة' : 'Voided';
      case 'expired':
        return isAr ? 'منتهية' : 'Expired';
      case 'cancelled':
      case 'canceled':
        return isAr ? 'ملغاة' : 'Cancelled';
      case 'abandoned':
        return isAr ? 'غير مكتملة' : 'Abandoned';
      default:
        return isAr ? 'غير معروف' : 'Unknown';
    }
  }

  /// yyyy/MM/dd    HH:mm — بلا عوازل اتجاه (PDF).
  static String latinDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${DateHelper.civilDigits(local)}${DateHelper.dateTimeGap}${DateHelper.fmtClock(local)}';
  }

  /// عوازل الاتجاه (RLI/LRI/…) تظهر مربعات ☒ في PDF إذا غاب الحرف في الخط.
  static String stripBidi(String raw) => raw.replaceAll(
        RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'),
        '',
      );

  static String purposeLabel(String raw, {required bool isAr}) {
    switch (raw.trim().toLowerCase()) {
      case 'subscribe_new':
      case 'subscribe':
        return isAr ? 'اشتراك جديد' : 'New subscription';
      case 'renew':
      case 'renewal':
        return isAr ? 'تجديد اشتراك' : 'Subscription renewal';
      case 'upgrade':
        return isAr ? 'ترقية الباقة' : 'Plan upgrade';
      case 'period_switch':
        return isAr ? 'تحويل إلى سنوي' : 'Switch to yearly';
      case 'instant_market_request':
      case 'one_time':
        return isAr ? 'طلب عقاري فوري' : 'Instant market request';
      case 'topup':
      case 'addon':
        return isAr ? 'إضافة باقة' : 'Plan add-on';
      default:
        final s = raw.trim();
        return s.isEmpty ? (isAr ? 'عملية دفع' : 'Payment') : s;
    }
  }

  static String dualCalendar(DateTime dt, {required bool isAr}) {
    final local = dt.toLocal();
    final g = DateHelper.fmtCivilDateTime(local, isAr: isAr);
    final h = DateHelper.fmtHijriDateTime(local, isAr: isAr);
    return '$g  ·  $h';
  }

  static String purposeFromRow(Map<String, dynamic> row) {
    final direct = '${row['purpose'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    final gw = row['gateway_response'];
    if (gw is Map) {
      final p = '${gw['purpose'] ?? ''}'.trim();
      if (p.isNotEmpty) return p;
    }
    if (gw is String && gw.trim().isNotEmpty) {
      try {
        final dec = jsonDecode(gw);
        if (dec is Map) {
          final p = '${dec['purpose'] ?? ''}'.trim();
          if (p.isNotEmpty) return p;
        }
      } catch (_) {}
    }
    final meta = row['metadata'];
    if (meta is Map) {
      final p = '${meta['purpose'] ?? ''}'.trim();
      if (p.isNotEmpty) return p;
    }
    return '';
  }

  static bool isOneTimeRow(Map<String, dynamic> row) {
    final purpose = purposeFromRow(row).toLowerCase();
    if (purpose.contains('instant') ||
        purpose.contains('one_time') ||
        purpose.contains('lifetime')) {
      return true;
    }
    final period = '${row['period'] ?? ''}'.toLowerCase();
    if (period.contains('one_time') || period.contains('lifetime')) {
      return true;
    }
    final title =
        '${row['title_ar'] ?? ''} ${row['title_en'] ?? ''} ${row['title'] ?? ''}'
            .toLowerCase();
    return title.contains('فوري') ||
        title.contains('instant') ||
        title.contains('مرة واحدة') ||
        title.contains('one-time') ||
        title.contains('one_time');
  }

  static String bilingualHeader(String ar, String en) => '$ar / $en';

  /// تاريخ ميلادي ثابت yyyy/MM/dd — بلا عوازل اتجاه تظهر مربعات في PDF.
  static String slashDate(DateTime dt) => DateHelper.civilDigits(dt.toLocal());

  static String periodWithRange({
    required String periodRaw,
    DateTime? start,
    DateTime? end,
    required bool isAr,
  }) {
    final kind = periodLabel(periodRaw, isAr: isAr);
    if (start == null && end == null) return kind;
    final from = start != null ? slashDate(start) : '—';
    final to = end != null ? slashDate(end) : '—';
    return isAr ? '$kind  من $from إلى $to' : '$kind  from $from to $to';
  }

  static String statementForPlan(String planName, {required bool isAr}) {
    final name = planName.trim();
    if (name.isEmpty) {
      return isAr
          ? 'الوصول للميزات المتقدمة للباقة'
          : 'Access to the plan advanced features';
    }
    return isAr
        ? 'الوصول للميزات المتقدمة لباقة $name'
        : 'Access to advanced features of the $name plan';
  }

  static String autoRenewDiscountLabel({required bool isAr}) => isAr
      ? 'خصم تفعيل التجديد التلقائي'
      : 'Auto-renew activation discount';

  static String promoCodeDiscountLabel({required bool isAr}) =>
      isAr ? 'خصم كود الخصم' : 'Promo code discount';

  static String documentTitleForPurpose(String purpose, {required bool isAr}) {
    switch (purpose.trim().toLowerCase()) {
      case 'renew':
      case 'renewal':
        return isAr ? 'فاتورة تجديد اشتراك' : 'Subscription renewal invoice';
      case 'upgrade':
        return isAr ? 'فاتورة ترقية الباقة' : 'Plan upgrade invoice';
      case 'subscribe_new':
      case 'subscribe':
        return isAr ? 'فاتورة اشتراك جديد' : 'New subscription invoice';
      case 'instant_market_request':
      case 'one_time':
        return isAr ? 'فاتورة طلب فوري' : 'Instant request invoice';
      default:
        return isAr ? 'فاتورة' : 'Invoice';
    }
  }
}
