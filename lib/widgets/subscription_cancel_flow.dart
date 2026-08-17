import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

import '../l10n/app_localizations.dart';
import '../services/subscription_service.dart';

/// إلغاء اشتراك مع: تنبيه نهاية الفترة، عرض احتفاظ لمرة واحدة، ثم استطلاع سبب الإلغاء.
class SubscriptionCancelFlow {
  static Future<bool> run({
    required BuildContext context,
    required AppLocalizations t,
    required SubscriptionService svc,
    required String subscriptionId,
    required String endDateLabel,
    String? organizationId,
  }) async {
    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(t.subscriptionsCancelEndTitle),
        content: Text(t.subscriptionsCancelEndBody(endDateLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.subscriptionsGoBack),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.subscriptionsContinue),
          ),
        ],
      ),
    );
    if (step1 != true || !context.mounted) return false;

    // مصدر الحقيقة: RPC الخادم. يحجز العرض فور إصداره ويمنع تكراره
    // لكل مستخدم ولا يظهر لأعضاء الفريق.
    final offer = await svc.offerCancellationRetention(subscriptionId);
    if (!context.mounted) return false;
    final available = offer['available'] == true;
    final reason = '${offer['reason'] ?? ''}';
    final pct = offer['discount_percent'];
    final pctNum = pct is num ? pct.toDouble() : 20.0;

    if (available) {
      await svc.logLifecycleEvent(
        eventType: 'retention_offer_shown',
        organizationId: organizationId,
        subscriptionId: subscriptionId,
        payload: {'discount_percent': pctNum},
      );
      // احتفظ بالتوافق مع منطق العميل القديم
      await svc.markRetentionOfferShown();
      if (!context.mounted) return false;
      final stay = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(t.subscriptionsRetentionTitle),
          content: Text(
            '${t.subscriptionsRetentionBody}\n\n'
            'خصم ${pctNum.toStringAsFixed(0)}% يُطبَّق على فاتورة التجديد التالية إن استمررت معنا.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.subscriptionsRetentionStay),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.subscriptionsRetentionDecline),
            ),
          ],
        ),
      );
      if (stay == true) {
        await svc.logLifecycleEvent(
          eventType: 'retention_offer_accepted',
          organizationId: organizationId,
          subscriptionId: subscriptionId,
          payload: {'discount_percent': pctNum},
        );
        return false;
      }
      await svc.logLifecycleEvent(
        eventType: 'retention_offer_declined',
        organizationId: organizationId,
        subscriptionId: subscriptionId,
        payload: {'discount_percent': pctNum},
      );
    } else if (reason == 'team_member_not_eligible') {
      // أعضاء الفريق لا يَرَون عرض الاحتفاظ — لا نُسجّل شيئاً.
    } else if (reason == 'already_used') {
      // العرض استُهلك من قبل لهذا المالك — لا نَعرضه مجدّداً.
    }

    if (!context.mounted) return false;
    final churn = await showDialog<({String? reasonKey, String detail})>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ChurnSurveyDialog(t: t),
    );

    if (!context.mounted) return false;
    final rk = churn?.reasonKey?.trim();
    final detail = churn?.detail.trim() ?? '';
    final r = await svc.cancelSubscription(
      subscriptionId,
      organizationId: organizationId,
      churnReasonKey: (rk != null && rk.isNotEmpty) ? rk : null,
      churnDetail: detail.isNotEmpty ? detail : null,
    );
    return r['ok'] == true;
  }
}

class _ChurnSurveyDialog extends StatefulWidget {
  const _ChurnSurveyDialog({required this.t});

  final AppLocalizations t;

  @override
  State<_ChurnSurveyDialog> createState() => _ChurnSurveyDialogState();
}

class _ChurnSurveyDialogState extends State<_ChurnSurveyDialog> {
  final _detailCtrl = TextEditingController();
  String? _reasonKey;

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      title: Text(t.subscriptionsChurnTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.subscriptionsChurnBody),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(t.subscriptionsChurnReasonPrice),
                  selected: _reasonKey == 'price',
                  onSelected: (_) => setState(
                    () => _reasonKey = _reasonKey == 'price' ? null : 'price',
                  ),
                ),
                FilterChip(
                  label: Text(t.subscriptionsChurnReasonFeatures),
                  selected: _reasonKey == 'features',
                  onSelected: (_) => setState(
                    () => _reasonKey =
                        _reasonKey == 'features' ? null : 'features',
                  ),
                ),
                FilterChip(
                  label: Text(t.subscriptionsChurnReasonSupport),
                  selected: _reasonKey == 'support',
                  onSelected: (_) => setState(
                    () => _reasonKey =
                        _reasonKey == 'support' ? null : 'support',
                  ),
                ),
                FilterChip(
                  label: Text(t.subscriptionsChurnReasonOther),
                  selected: _reasonKey == 'other',
                  onSelected: (_) => setState(
                    () => _reasonKey = _reasonKey == 'other' ? null : 'other',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AqarTextField(
              controller: _detailCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: t.subscriptionsChurnDetailHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            (reasonKey: null, detail: ''),
          ),
          child: Text(t.subscriptionsChurnSkip),
        ),
        FilledButton(
          onPressed: () {
            var rk = _reasonKey;
            final d = _detailCtrl.text.trim();
            if ((rk == null || rk.isEmpty) && d.isNotEmpty) {
              rk = 'other';
            }
            Navigator.pop(context, (reasonKey: rk, detail: _detailCtrl.text));
          },
          child: Text(t.subscriptionsChurnSubmit),
        ),
      ],
    );
  }
}
