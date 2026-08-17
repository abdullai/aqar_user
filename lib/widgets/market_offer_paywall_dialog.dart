import 'package:flutter/material.dart';

import '../services/individual_market_offer_service.dart';

/// نافذة منبثقة قبل تحويل المستخدم لصفحة الاشتراكات (عروض السوق).
Future<bool> showMarketOfferPaywallDialog({
  required BuildContext context,
  required bool isAr,
  required IndividualMarketOfferAllowance allowance,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.lock_outline, color: cs.primary, size: 32),
        title: Text(
          isAr ? 'اشتراك عروض السوق مطلوب' : 'Market offers subscription required',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr
                    ? allowance.shortStatusAr()
                    : allowance.shortStatusEn(),
              ),
              if (allowance.audience == 'marketing') ...[
                const SizedBox(height: 12),
                Text(
                  isAr
                      ? 'حساب تسويقي: عند نفاد حصة «إتمام الصفقة» تظهر باقات إضافة الصفقات (شهري أو مرة واحدة). اشتراك الباقة الأساسية/الاحترافية/التميز يفتح مسار التسويق حسب نوع الحساب. الحصة تُحسب من تاريخ التفعيل.'
                      : 'Marketing account: when deal quota runs out, deal top-up plans appear (monthly or one-time). Basic / Professional / Premium unlocks your marketing workflow by account type. Quota starts from activation time.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
              if (allowance.audience != 'marketing') ...[
              const SizedBox(height: 16),
              _planTile(
                ctx,
                isAr: isAr,
                title: isAr ? 'الطلب الفوري — 30 ر.س' : 'Instant request — SAR 30',
                bullets: isAr
                    ? const [
                        'أولوية أسبوع في منطقتك و72 ساعة في باقي المناطق',
                        'إعلان وطلب وإتمام صفقة — مجاني بدون اشتراك',
                        'الرصيد غير المستخدم يُسترد قبل النشر',
                      ]
                    : const [
                        '1 week priority in your region, 72h elsewhere',
                        'Listing, request, and deals — free without subscription',
                        'Unused credit refundable before publish',
                      ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isAr
                      ? 'تنبيه عدالة: الاشتراك يفتح حصة لإتمام الصفقات فقط ولا يضمن إغلاق أي صفقة. الاختيار يبقى لصاحب الطلب. التفعيل يُحسب من وقت وتاريخ أول اشتراك بدقة.'
                      : 'Fairness: subscription grants deal quota only — no deal is guaranteed. Activation starts at your exact subscription timestamp.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'لاحقاً' : 'Later'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.subscriptions_outlined),
            label: Text(isAr ? 'عرض الباقات والدفع' : 'View plans & pay'),
          ),
        ],
      );
    },
  );
  return result == true;
}

Widget _planTile(
  BuildContext context, {
  required bool isAr,
  required String title,
  required List<String> bullets,
}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: cs.outlineVariant),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.primary,
              ),
        ),
        const SizedBox(height: 6),
        for (final b in bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: cs.primary)),
                Expanded(child: Text(b)),
              ],
            ),
          ),
      ],
    ),
  );
}
