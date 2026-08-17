import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/subscription/app_subscription_gate.dart';

/// زر/شريحة تنبيه عند غياب اشتراك — بديل مرئي فوري لزر الإجراء المحجوب.
class SubscriptionGateAlertChip extends StatelessWidget {
  const SubscriptionGateAlertChip({
    super.key,
    required this.isAr,
    required this.action,
    required this.onSubscribe,
    this.compact = false,
  });

  final bool isAr;
  final SubscriptionGateAction action;
  final VoidCallback onSubscribe;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<AppSubscriptionGate>();
    final cs = Theme.of(context).colorScheme;
    final title = isAr ? gate.alertTitleAr(action) : gate.alertTitleEn(action);
    final body = isAr ? gate.alertBodyAr(action) : gate.alertBodyEn(action);

    if (compact) {
      return Material(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onSubscribe,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: cs.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Icon(Icons.subscriptions_outlined, color: cs.primary, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: cs.error, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onSubscribe,
            icon: const Icon(Icons.subscriptions_outlined, size: 18),
            label: Text(
              isAr ? 'الذهاب للاشتراك' : 'Go to subscription',
            ),
          ),
        ],
      ),
    );
  }
}
