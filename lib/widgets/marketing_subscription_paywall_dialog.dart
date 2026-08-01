import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../services/subscription_service.dart';

/// Paywall when marketing paid workflow is blocked.
///
/// Three states:
///   - Expired subscription   → show real `ends_at` date & time.
///   - Renewal failure        → show last billed date/reason hint.
///   - No subscription at all → "this feature requires a subscription".
Future<void> showMarketingSubscriptionPaywallDialog({
  required BuildContext context,
  required bool isAr,
  required Map<String, dynamic>? subscriptionRow,
  required VoidCallback onSubscribe,
}) async {
  final loc = AppLocalizations.of(context);
  final hasRow = subscriptionRow != null;
  final isExpiredTrial =
      SubscriptionService.isExpiredTrial(subscriptionRow);
  final arOn =
      SubscriptionService.subscriptionAutoRenewEnabled(subscriptionRow);
  final failed =
      SubscriptionService.subscriptionRenewalFailureFlag(subscriptionRow);
  final endUtc = SubscriptionService.subscriptionExclusiveEndUtc(
    subscriptionRow,
  );
  final endLocal = endUtc?.toLocal();
  final formattedEnd = endLocal == null
      ? ''
      : DateFormat(
          'EEEE d MMM yyyy — HH:mm',
          isAr ? 'ar' : 'en',
        ).format(endLocal);

  // افحص هل استخدم المستخدم التجربة من قبل (يخفي زر التجربة).
  bool trialAlreadyUsed = false;
  try {
    final svc = SubscriptionService(Supabase.instance.client);
    trialAlreadyUsed = await svc.hasUserUsedTrial();
  } catch (_) {
    trialAlreadyUsed = true; // عند الشك — لا تعرض الزر.
  }

  String title;
  String body;

  if (isExpiredTrial) {
    title = isAr ? 'انتهت الفترة التجريبية' : 'Trial period ended';
    final base = isAr
        ? 'انتهت فترتك التجريبية ولا تستطيع متابعة هذا الإجراء. لإكمال العروض والتعاقد والنشر، اشترك في إحدى الباقات.'
        : 'Your trial period has ended. To complete offers, contracts and listings, subscribe to a paid plan.';
    body = formattedEnd.isEmpty
        ? base
        : (isAr
            ? '$base\n\nانتهت بتاريخ: $formattedEnd'
            : '$base\n\nEnded on: $formattedEnd');
  } else if (!hasRow) {
    title = isAr ? 'يتطلب اشتراكاً فعّالاً' : 'Subscription required';
    body = isAr
        ? (trialAlreadyUsed
            ? 'هذه الميزة تتطلب اشتراكاً فعّالاً. اشترك الآن للاستفادة الكاملة.'
            : 'هذه الميزة تتطلب اشتراكاً فعّالاً. يمكنك تفعيل التجربة المجانية ٣ أيام (مرة واحدة) أو الاشتراك مباشرة.')
        : (trialAlreadyUsed
            ? 'This feature requires an active subscription. Subscribe now to unlock all features.'
            : 'This feature requires an active subscription. Activate the 3-day free trial (once per account) or subscribe directly.');
  } else if (arOn && failed) {
    title = loc?.subscriptionsPaywallExpiredTitle ??
        (isAr ? 'الاشتراك غير فعّال' : 'Subscription inactive');
    final base = isAr
        ? 'تعذّر خصم رسوم التجديد التلقائي (رفض البنك أو عدم كفاية الرصيد). لا يُسمح بهذا الإجراء حتى ينجح الدفع أو تُجدّد يدوياً.'
        : 'Automatic renewal could not be charged (bank declined or insufficient balance). This action is blocked until payment succeeds or you renew manually.';
    body = formattedEnd.isEmpty
        ? base
        : (isAr
            ? '$base\n\nالتاريخ المُسجّل لانتهاء الفترة: $formattedEnd'
            : '$base\n\nRecorded end date: $formattedEnd');
  } else {
    // Expired (not auto-renewing, or row exists but past ends_at)
    title = loc?.subscriptionsPaywallExpiredTitle ??
        (isAr ? 'الاشتراك غير فعّال' : 'Subscription inactive');
    final base = isAr
        ? 'انتهت فترة الاشتراك المدفوعة. لا يُسمح بهذا الإجراء حتى تجدّد الاشتراك. تبقى بياناتك كما هي ويمكنك المتابعة ضمن حدود الباقة المجانية بعد الإغلاق.'
        : 'Your paid subscription period has ended. This action is blocked until you renew. Your data stays within free-tier limits.';
    body = formattedEnd.isEmpty
        ? base
        : (isAr
            ? '$base\n\nانتهى بتاريخ: $formattedEnd'
            : '$base\n\nEnded on: $formattedEnd');
  }

  final showDevButton =
      AppConfig.allowDevTestSubscriptionGrant || kDebugMode;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Text(body),
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(loc?.subscriptionsPaywallCloseLabel ??
              (isAr ? 'إغلاق' : 'Close')),
        ),
        if (!hasRow && !trialAlreadyUsed)
          TextButton.icon(
            icon: const Icon(Icons.card_giftcard_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(ctx);
              try {
                final res = await Supabase.instance.client
                    .rpc('activate_marketing_trial_subscription');
                Map<String, dynamic>? data;
                if (res is Map) {
                  data = Map<String, dynamic>.from(res);
                }
                final ok = data?['ok'] == true;
                if (ctx.mounted) Navigator.pop(ctx);
                SubscriptionService.invalidateSubscriptionCache();
                final err = data?['error']?.toString();
                String msg;
                if (ok) {
                  msg = isAr
                      ? 'تم تفعيل تجربة 3 أيام — أعد المحاولة الآن.'
                      : '3-day trial activated. Please try the action again.';
                } else if (err == 'trial_already_used') {
                  msg = isAr
                      ? 'لقد استخدمت التجربة المجانية من قبل.'
                      : 'You already used your free trial.';
                } else if (err == 'paid_subscription_active') {
                  msg = isAr
                      ? 'لديك اشتراك مدفوع فعّال — لا حاجة للتجربة.'
                      : 'You already have an active paid subscription.';
                } else if (err == 'no_plan_available') {
                  msg = isAr
                      ? 'خطة التجربة غير متوفرة لنوع حسابك — تواصل مع الدعم.'
                      : 'Trial plan is not available for your account type — contact support.';
                } else if (err == 'role_not_eligible_for_trial') {
                  msg = isAr
                      ? 'نوع حسابك غير مؤهل للتجربة المجانية.'
                      : 'Your account type is not eligible for the free trial.';
                } else {
                  msg = isAr
                      ? 'تعذّر تفعيل التجربة: ${err ?? 'unknown'}'
                      : 'Failed to activate trial: ${err ?? 'unknown'}';
                }
                messenger.showSnackBar(SnackBar(content: Text(msg)));
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      isAr ? 'تعذّر الاستدعاء: $e' : 'RPC error: $e',
                    ),
                  ),
                );
              }
            },
            label: Text(
              isAr ? 'تجربة 3 أيام مجاناً' : 'Try 3 days free',
            ),
          ),
        if (showDevButton)
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(ctx);
              try {
                final res = await Supabase.instance.client
                    .rpc('dev_grant_test_subscription_for_me');
                Map<String, dynamic>? data;
                if (res is Map) {
                  data = Map<String, dynamic>.from(res);
                }
                final ok = data?['ok'] == true;
                if (ctx.mounted) Navigator.pop(ctx);
                SubscriptionService.invalidateSubscriptionCache();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? (isAr
                              ? 'تم تفعيل اشتراك تجريبي لمدة 365 يوم — أعد المحاولة.'
                              : 'Test subscription granted (365 days). Try again.')
                          : (isAr
                              ? 'تعذّر التفعيل التجريبي: ${data?['error'] ?? 'unknown'}'
                              : 'Failed to grant test subscription: ${data?['error'] ?? 'unknown'}'),
                    ),
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      isAr ? 'تعذّر استدعاء RPC: $e' : 'RPC error: $e',
                    ),
                  ),
                );
              }
            },
            child: Text(
              isAr ? 'تفعيل تطوير (365 يوم)' : 'Dev grant (365 days)',
            ),
          ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            onSubscribe();
          },
          child: Text(loc?.subscriptionsPaywallGoPlans ??
              (isAr ? 'الباقات والدفع' : 'Plans & pay')),
        ),
      ],
    ),
  );
}
