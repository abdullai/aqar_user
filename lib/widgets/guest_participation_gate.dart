import 'package:flutter/material.dart';

import 'guest_one_time_pay_sheet.dart';

/// Suggested one-time unlock (SAR), proportional to entry monthly tiers.
const double kGuestOneTimeDealSar = 59;

// --- Home: submit offer / participate (three actions) ---

enum GuestHomeOfferGateResult {
  login,
  register,
  payOnce,
}

Future<GuestHomeOfferGateResult?> showGuestHomeOfferGateSheet({
  required BuildContext context,
  required bool isAr,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<GuestHomeOfferGateResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isAr ? 'إتمام الصفقة' : 'Complete deal',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                isAr
                    ? 'الرجاء تسجيل الدخول أو إنشاء حساب ثم العودة لإتمام الصفقة، أو اختر الدفع لمرة واحدة لفتح تبويب الصفقات وإكمال الإجراء من هذا الجهاز.'
                    : 'Please sign in or create an account, then return to submit your offer — or pay once to unlock the Deals tab and submit from this device.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      height: 1.38,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestHomeOfferGateResult.login),
                icon: const Icon(Icons.login_rounded),
                label: Text(isAr ? 'تسجيل الدخول' : 'Log in'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestHomeOfferGateResult.payOnce),
                icon: const Icon(Icons.payments_outlined),
                label: Text(
                  isAr
                      ? 'دفع لإتمام الصفقة لمرة واحدة ($kGuestOneTimeDealSar ر.س)'
                      : 'One-time pay to offer (SAR $kGuestOneTimeDealSar)',
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestHomeOfferGateResult.register),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(isAr ? 'إنشاء حساب' : 'Create account'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// طلب فوري مدفوع — إتمام الصفقة بدون اشتراك (يتطلب حساباً للدردشة والحفظ).
Future<GuestAuthRequiredResult?> showGuestInstantDealAuthSheet({
  required BuildContext context,
  required bool isAr,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<GuestAuthRequiredResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: cs.error, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAr ? 'طلب فوري — بدون اشتراك' : 'Instant request — no subscription',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isAr
                    ? 'هذا الطلب مدفوع (30 ر.س) — يمكنك إتمام الصفقة والدردشة مع مقدّم الطلب بدون أي اشتراك. سجّل الدخول أو أنشئ حساباً مجانياً للمتابعة.'
                    : 'This is a paid instant request (SAR 30) — you can complete the deal and chat with the requester with no subscription. Sign in or create a free account to continue.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      height: 1.38,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestAuthRequiredResult.login),
                icon: const Icon(Icons.login_rounded),
                label: Text(isAr ? 'تسجيل الدخول' : 'Log in'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestAuthRequiredResult.register),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(isAr ? 'إنشاء حساب' : 'Create account'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// --- Any other tab / feature: full account required (two actions) ---

enum GuestAuthRequiredResult {
  login,
  register,
}

Future<GuestAuthRequiredResult?> showGuestAuthRequiredSheet({
  required BuildContext context,
  required bool isAr,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<GuestAuthRequiredResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isAr ? 'تسجيل الدخول' : 'Sign in',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                isAr
                    ? 'الرجاء تسجيل الدخول أو إنشاء حساب للاستفادة من كل الخدمات (إعلاناتي، صفقاتي، الدردشة، السلة، وغيرها).'
                    : 'Please sign in or create an account to use My ads, Deals, chat, cart, and the rest of the app.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      height: 1.38,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestAuthRequiredResult.login),
                icon: const Icon(Icons.login_rounded),
                label: Text(isAr ? 'تسجيل الدخول' : 'Log in'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestAuthRequiredResult.register),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(isAr ? 'إنشاء حساب' : 'Create account'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// --- FAB: add listing / request (three actions, copy per intent) ---

enum GuestCreateContentGateResult {
  login,
  register,
  payOnce,
}

Future<GuestCreateContentGateResult?> showGuestCreateContentGateSheet({
  required BuildContext context,
  required bool isAr,
  required bool forListing,
}) {
  final cs = Theme.of(context).colorScheme;
  final headline = forListing
      ? (isAr ? 'إعلان عقاري' : 'Property listing')
      : (isAr ? 'طلب عقاري' : 'Property request');
  final body = forListing
      ? (isAr
          ? 'لنشر إعلان عقاري تحتاج حساباً، أو يمكنك دفع لمرة واحدة ثم إكمال الإعلان من هذا الجهاز بعد التفعيل التجريبي للدفع.'
          : 'Publishing a listing needs an account, or pay once to unlock posting from this device after mock checkout.')
      : (isAr
          ? 'لإنشاء طلب عقاري تحتاج حساباً، أو يمكنك دفع لمرة واحدة ثم إكمال الطلب من هذا الجهاز بعد التفعيل التجريبي للدفع.'
          : 'Creating a request needs an account, or pay once to unlock it from this device after mock checkout.');

  return showModalBottomSheet<GuestCreateContentGateResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                headline,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      height: 1.38,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestCreateContentGateResult.login),
                icon: const Icon(Icons.login_rounded),
                label: Text(isAr ? 'تسجيل الدخول' : 'Log in'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestCreateContentGateResult.payOnce),
                icon: const Icon(Icons.payments_outlined),
                label: Text(
                  isAr
                      ? 'دفع لمرة واحدة ($kGuestOneTimeDealSar ر.س)'
                      : 'One-time pay (SAR $kGuestOneTimeDealSar)',
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(ctx).pop(GuestCreateContentGateResult.register),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(isAr ? 'إنشاء حساب' : 'Create account'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Runs mock checkout for `offer` | `listing` | `request` unlock kind.
Future<bool> runGuestOneTimePaymentFlow({
  required BuildContext context,
  required bool isAr,
  required String unlockKind,
}) {
  return showGuestOneTimePaySheet(
    context: context,
    isAr: isAr,
    unlockKind: unlockKind,
    amountSar: kGuestOneTimeDealSar,
  );
}
