import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/org/org_team_capacity.dart';
import '../core/session/account_role_cache.dart';
import '../core/workflow/app_role_helper.dart';
import '../screens/subscriptions/subscriptions_root_screen.dart';
import '../services/org_team_service.dart';
import '../services/subscription_service.dart';

/// بوابة موحّدة: اشتراك فعّال + مقاعد متاحة قبل دعوة/قبول عضو.
class TeamMembershipGate {
  TeamMembershipGate._();

  static Future<bool> ensureCanOpenTeamInviteFlow(
    BuildContext context, {
    required String lang,
    required String accountType,
    String? organizationId,
  }) async {
    final isAr = lang.toLowerCase() != 'en';

    if (!OrgTeamCapacity.canManageTeamMembers(accountType)) {
      return false;
    }

    final sub = SubscriptionService(Supabase.instance.client);
    final hasSub = await sub.hasActiveMarketingSubscriptionAccess(
      organizationId: organizationId,
    );
    if (!context.mounted) return false;

    if (!hasSub) {
      await _showSubscriptionRequiredDialog(
        context,
        isAr: isAr,
        lang: lang,
        accountType: accountType,
        organizationId: organizationId,
        forApproveJoin: false,
      );
      return false;
    }

    final oid = organizationId?.trim() ?? '';
    if (oid.isEmpty) return true;

    final org = OrgTeamService(Supabase.instance.client);
    final used = await org.memberCount(oid);
    final limit = await org.effectiveSeatLimit(oid);
    if (!context.mounted) return false;

    if (used < limit) return true;

    if (AppRoleHelper.isStandaloneMarketer(accountType)) {
      await _showMarketerExtraSeatDialog(
        context,
        isAr: isAr,
        lang: lang,
        accountType: accountType,
        organizationId: oid,
      );
      return false;
    }

    await _showSeatLimitDialog(
      context,
      isAr: isAr,
      lang: lang,
      accountType: accountType,
      organizationId: oid,
      used: used,
      limit: limit,
    );
    return false;
  }

  /// قبل الموافقة على طلب انضمام.
  static Future<bool> ensureCanApproveJoinRequest(
    BuildContext context, {
    required String lang,
    required String accountType,
    required String organizationId,
  }) async {
    final isAr = lang.toLowerCase() != 'en';

    final sub = SubscriptionService(Supabase.instance.client);
    final hasSub = await sub.hasActiveMarketingSubscriptionAccess(
      organizationId: organizationId,
    );
    if (!context.mounted) return false;

    if (!hasSub) {
      await _showSubscriptionRequiredDialog(
        context,
        isAr: isAr,
        lang: lang,
        accountType: accountType,
        organizationId: organizationId,
        forApproveJoin: true,
      );
      return false;
    }

    final org = OrgTeamService(Supabase.instance.client);
    final used = await org.memberCount(organizationId);
    final limit = await org.effectiveSeatLimit(organizationId);
    if (!context.mounted) return false;

    if (used < limit) return true;

    if (AppRoleHelper.isStandaloneMarketer(accountType)) {
      await _showMarketerExtraSeatDialog(
        context,
        isAr: isAr,
        lang: lang,
        accountType: accountType,
        organizationId: organizationId,
      );
      return false;
    }

    await _showSeatLimitDialog(
      context,
      isAr: isAr,
      lang: lang,
      accountType: accountType,
      organizationId: organizationId,
      used: used,
      limit: limit,
    );
    return false;
  }

  static String mapJoinErrorMessage(String code, {required bool isAr}) {
    switch (code) {
      case 'seat_limit_reached':
        return isAr
            ? 'المنشأة بلغت الحد الأقصى للمقاعد. يمكن للمدير ترقية الاشتراك أو شراء مقاعد إضافية.'
            : 'This organization reached its seat limit. The owner can upgrade or buy extra seats.';
      case 'owner_subscription_required':
        return isAr
            ? 'مدير المنشأة لم يفعّل اشتراكاً بعد. سيُراجع طلبك بعد تفعيل الاشتراك والموافقة.'
            : 'The organization owner has not activated a subscription yet. Your request will be reviewed after they subscribe and approve.';
      case 'unknown_code':
        return isAr ? 'رمز الانضمام غير صحيح.' : 'Invalid join code.';
      case 'already_member':
        return isAr
            ? 'أنت عضو نشط في منشأة أخرى.'
            : 'You are already an active member of an organization.';
      case 'already_pending':
        return isAr
            ? 'لديك طلب انضمام قيد المراجعة.'
            : 'You already have a pending join request.';
      default:
        return isAr ? 'تعذر إرسال الطلب.' : 'Could not submit the request.';
    }
  }

  static Future<void> _showMarketerExtraSeatDialog(
    BuildContext context, {
    required bool isAr,
    required String lang,
    required String accountType,
    String? organizationId,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.group_add_outlined, color: Theme.of(ctx).colorScheme.primary),
        title: Text(isAr ? 'مقعد فريق إضافي' : 'Extra team seat'),
        content: Text(
          isAr
              ? 'باقة المسوّق الفردي لا تشمل أعضاء فريق مجاناً.\n\nلإضافة مساعد أو شريك، ادفع رسوم مقعد إضافي من تبويب الاشتراكات ثم أعد دعوة العضو.'
              : 'The solo marketer plan does not include free team seats.\n\nPay for an extra seat from Subscriptions, then invite your teammate.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'لاحقاً' : 'Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'الاشتراكات' : 'Subscriptions'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => SubscriptionsRootScreen(
          lang: lang,
          accountType: accountType,
          organizationId: organizationId,
        ),
      ),
    );
    SubscriptionService.invalidateSubscriptionCache();
  }

  static Future<void> _showSubscriptionRequiredDialog(
    BuildContext context, {
    required bool isAr,
    required String lang,
    required String accountType,
    String? organizationId,
    required bool forApproveJoin,
  }) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.workspace_premium_outlined, color: Theme.of(ctx).colorScheme.primary),
        title: Text(isAr ? 'اشتراك المنصّة مطلوب' : 'Platform subscription required'),
        content: Text(
          forApproveJoin
              ? (isAr
                  ? 'لقبول عضو في فريقك، يجب أن يكون لديك اشتراك فعّال في ${AppBranding.legalName(isAr: true)}.\n\nبعد إتمام الدفع يُفعَّل الاشتراك فوراً ويمكنك الموافقة على الطلب.'
                  : 'To accept a teammate, you need an active ${AppBranding.brandNameEn} subscription.\n\nAfter payment, access is enabled immediately and you can approve the request.')
              : (isAr
                  ? 'لإضافة أعضاء لفريقك أو مشاركة رمز الانضمام، فعّل اشتراكك أولاً.\n\nبعد الدفع تُفتح إدارة الفريق مباشرة.'
                  : 'To add teammates or share your join code, activate your subscription first.\n\nAfter payment, team management unlocks right away.'),
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'لاحقاً' : 'Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'الاشتراكات والدفع' : 'Plans & payment'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => SubscriptionsRootScreen(
          lang: lang,
          accountType: accountType,
          organizationId: organizationId,
        ),
      ),
    );
    SubscriptionService.invalidateSubscriptionCache();
  }

  static Future<void> _showSeatLimitDialog(
    BuildContext context, {
    required bool isAr,
    required String lang,
    required String accountType,
    required String organizationId,
    required int used,
    required int limit,
  }) async {
    final cap = OrgTeamCapacity.baseLimitLabelAr(accountType);
    final capEn = OrgTeamCapacity.baseLimitLabelEn(accountType);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.group_off_outlined, color: Theme.of(ctx).colorScheme.error),
        title: Text(isAr ? 'اكتملت مقاعد الفريق' : 'Team seats full'),
        content: Text(
          isAr
              ? 'المقاعد المستخدمة: $used من $limit.\n${cap.isNotEmpty ? '$cap.\n' : ''}يمكنك ترقية الباقة أو شراء مقاعد إضافية من تبويب الاشتراكات.'
              : 'Seats in use: $used of $limit.\n${capEn.isNotEmpty ? '$capEn.\n' : ''}Upgrade your plan or purchase extra seats from Subscriptions.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إغلاق' : 'Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'الاشتراكات' : 'Subscriptions'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => SubscriptionsRootScreen(
          lang: lang,
          accountType: accountType,
          organizationId: organizationId,
          initialIndex: 0,
        ),
      ),
    );
    SubscriptionService.invalidateSubscriptionCache();
  }

  static String accountTypeForGate() {
    return AccountRoleCache.snapshot?.accountType ?? 'office';
  }
}
