import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/app_money.dart';
import '../../services/subscription_service.dart';

/// عناصر واجهة مشتركة لصفحات الاشتراك والدفع — تواريخ، جداول، وأسعار.
abstract final class SubscriptionUiHelpers {
  static const _denseTextStyle = TextStyle(
    fontWeight: FontWeight.w800,
    color: Colors.black,
    height: 1.25,
    fontSize: 13.5,
  );

  static const _labelStyle = TextStyle(
    fontWeight: FontWeight.w900,
    color: Colors.black,
    height: 1.2,
    fontSize: 13,
  );

  static TextStyle denseBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _denseTextStyle.copyWith(color: cs.onSurface);
  }

  static TextStyle denseLabel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _labelStyle.copyWith(color: cs.onSurface);
  }

  static String formatBillingDate(dynamic raw, {required bool isAr}) {
    if (raw == null) return '—';
    final s = raw.toString().trim();
    if (s.isEmpty) return '—';
    try {
      final d = DateTime.parse(s).toLocal();
      final locale = isAr ? 'ar_SA' : 'en_US';
      return DateFormat('yyyy-MM-dd', locale).format(d);
    } catch (_) {
      return s.length > 10 ? s.substring(0, 10) : s;
    }
  }

  /// سطر التاريخ على بطاقة الاشتراك الحالي:
  /// — نشط: «يتجدد اشتراكك في …»
  /// — ملغى / طلب إلغاء: «ينتهي اشتراكك في …»
  /// — منتهٍ: «انتهى اشتراكك في …»
  static String billingCycleStatusLine({
    required bool isAr,
    required Map<String, dynamic>? row,
  }) {
    if (row == null) return isAr ? '—' : '—';
    final status = '${row['status'] ?? ''}'.trim().toLowerCase();
    final cancelReq = row['cancellation_requested_at'];
    final cancelEff = row['cancellation_effective_at'];
    final endRaw = cancelEff ?? row['end_date'];
    final date = formatBillingDate(endRaw, isAr: isAr);

    if (status == 'expired') {
      return isAr ? 'انتهى اشتراكك في $date' : 'Your subscription ended on $date';
    }
    if (status == 'cancelled' || cancelReq != null) {
      return isAr
          ? 'ينتهي اشتراكك في $date'
          : 'Your subscription expires on $date';
    }
    return isAr ? 'يتجدد اشتراكك في $date' : 'Your subscription renews on $date';
  }

  /// اشتراك متكرر (شهري/سنوي) — ليس «مرة واحدة».
  static bool isRecurringSubscription(Map<String, dynamic>? row) {
    if (row == null) return false;
    final p = '${row['period'] ?? ''}'.trim().toLowerCase();
    return p != 'lifetime_one_time' && p != 'one_time';
  }

  /// إظهار «إلغاء الاشتراك» فقط عند تفعيل التجديد التلقائي.
  static bool showCancelSubscriptionButton({
    required Map<String, dynamic>? row,
  }) {
    if (row == null) return false;
    if (!isRecurringSubscription(row)) return false;
    if (!SubscriptionService.subscriptionAutoRenewEnabled(row)) return false;
    final status = '${row['status'] ?? ''}'.trim().toLowerCase();
    if (status == 'cancelled' || status == 'expired' || status == 'pending') {
      return false;
    }
    if (row['cancellation_requested_at'] != null) return false;
    return true;
  }

  static bool showAutoRenewToggleForPeriod(String period) {
    final p = period.trim().toLowerCase();
    return p == 'monthly';
  }

  static bool showUpgradePlanButton({
    required Map<String, dynamic>? currentRow,
    required Map<String, dynamic> targetPlan,
    required bool Function(Map<String, dynamic>? row) inPaidPeriod,
    required int Function(Map<String, dynamic> plan) planSortOrder,
  }) {
    if (currentRow == null || !inPaidPeriod(currentRow)) return false;
    final curStatus = '${currentRow['status'] ?? ''}'.trim().toLowerCase();
    if (curStatus != 'active') return false;
    final curId = '${currentRow['plan_id'] ?? ''}'.trim();
    final targetId = '${targetPlan['id'] ?? ''}'.trim();
    if (curId.isEmpty || targetId.isEmpty || curId == targetId) return false;
    final curPlan = currentRow['plan'] is Map
        ? Map<String, dynamic>.from(currentRow['plan'] as Map)
        : <String, dynamic>{};
    if (curPlan.isEmpty) return false;
    return planSortOrder(targetPlan) > planSortOrder(curPlan);
  }

  static String periodChipLabel({
    required bool isAr,
    required String period,
  }) {
    switch (period) {
      case 'yearly':
        return isAr ? 'سنوي' : 'Yearly';
      case 'one_time':
        return isAr ? 'مرة واحدة' : 'One-time';
      default:
        return isAr ? 'شهري' : 'Monthly';
    }
  }

  static BoxDecoration sectionDecoration(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.85)),
    );
  }

  static Widget section({
    required BuildContext context,
    required String title,
    required List<Widget> children,
    EdgeInsets padding = const EdgeInsets.all(12),
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: sectionDecoration(cs),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  static Widget tableRow({
    required BuildContext context,
    required String label,
    String? value,
    Widget? valueWidget,
    bool emphasize = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: denseLabel(context).copyWith(
                fontSize: emphasize ? 14 : 13,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: valueWidget ??
                  Text(
                    value ?? '',
                    textAlign: TextAlign.end,
                    style: denseBody(context).copyWith(
                      fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,
                      fontSize: emphasize ? 14 : 13.5,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget priceTableRow({
    required BuildContext context,
    required bool isAr,
    required String label,
    required double amount,
    bool emphasize = false,
    bool negative = false,
  }) {
    return tableRow(
      context: context,
      label: label,
      emphasize: emphasize,
      valueWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (negative)
            Text(
              '−',
              style: denseBody(context).copyWith(fontWeight: FontWeight.w900),
            ),
          AppMoneyLine(
            amount: amount.abs(),
            currencyCode: 'SAR',
            isAr: isAr,
            maxFractionDigits: amount == amount.roundToDouble() ? 0 : 2,
            style: denseBody(context).copyWith(
              fontWeight: FontWeight.w900,
              fontSize: emphasize ? 15 : 13.5,
            ),
          ),
        ],
      ),
    );
  }

  static Widget legalNote({
    required BuildContext context,
    required bool isAr,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Text(
        isAr
            ? 'الأسعار تشمل ضريبة القيمة المضافة حيث ينطبق ذلك. الاشتراك يمنح حصص استخدام داخل المنصة ولا يضمن إبرام أي صفقة عقارية. تطبّق شروط الاستخدام وسياسة الخصوصية.'
            : 'Prices include VAT where applicable. Subscriptions grant platform usage quotas and do not guarantee any real-estate transaction. Terms of use and privacy policy apply.',
        style: TextStyle(
          fontSize: 11.5,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
