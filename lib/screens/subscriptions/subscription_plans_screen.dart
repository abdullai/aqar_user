import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/branding/app_branding.dart';
import '../../core/navigation/dashboard_embedded_route.dart';
import '../../core/subscription/marketing_subscription_resume_intent.dart';
import '../../core/subscription/plan_display_copy.dart';
import '../../core/subscription/subscription_billing_context.dart';
import '../../core/utils/app_money.dart';
import '../../core/workflow/app_role_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../services/subscription_service.dart';
import '../../widgets/app_logo_loading.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import '../../widgets/fal_support_whatsapp_row.dart';
import '../../widgets/subscription/subscription_ui_helpers.dart';
import '../../widgets/subscription_cancel_flow.dart';
import 'payment_checkout_screen.dart';
import 'plan_details_screen.dart';

class SubscriptionPlansScreen extends StatefulWidget {
  const SubscriptionPlansScreen({
    super.key,
    required this.lang,
    required this.accountType,
    this.organizationId,
    this.upgradeOnly = false,
    this.resumeAfterPurchase,
    this.billingContext,
    this.billingContextLoading = false,
    this.marketOfferPlansOnly = false,
  });

  final String lang;
  final String accountType;
  final String? organizationId;
  final bool upgradeOnly;
  final MarketingSubscriptionResumeIntent? resumeAfterPurchase;
  final SubscriptionBillingContext? billingContext;
  final bool billingContextLoading;

  /// عند true: عرض باقات عروض السوق فقط (شهري/سنوي/مرة واحدة).
  final bool marketOfferPlansOnly;

  @override
  State<SubscriptionPlansScreen> createState() =>
      _SubscriptionPlansScreenState();
}

class _SubscriptionPlansScreenState extends State<SubscriptionPlansScreen> {
  final _svc = SubscriptionService(Supabase.instance.client);
  bool _loading = true;
  bool _activatingTrial = false;
  List<Map<String, dynamic>> _plans = [];
  String _period = 'monthly';
  Map<String, dynamic>? _current;
  bool _trialAlreadyUsed = true;
  SubscriptionBillingContext? _billingCtx;
  bool _teamNoteDismissed = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  SubscriptionBillingContext? get _ctx =>
      _billingCtx ?? widget.billingContext;

  bool get _isMarketingRole =>
      AppRoleHelper.isMarketingAccountType(widget.accountType);

  bool get _isTrialEligibleAccount {
    if (AppRoleHelper.isOwnerFreeTierAccount(widget.accountType)) return false;
    if (_isMarketingRole) return true;
    final k = AppRoleHelper.fromAccountType(widget.accountType);
    return k == AppRoleKind.ownerIndividual || k == AppRoleKind.publicUser;
  }

  /// التجربة فعّالة الآن لهذا المستخدم.
  bool get _hasActiveTrial =>
      SubscriptionService.isActiveTrial(_current);

  /// التجربة انتهت ولديه اشتراك تجريبي قديم.
  bool get _trialEnded =>
      SubscriptionService.isExpiredTrial(_current);

  /// بانر «جرّب 3 أيام» — متاح للأدوار التسويقية وللفرد بعد ترحيل v6.
  /// يُخفى عن: من له اشتراك مدفوع فعّال، من سبق له استهلاك التجربة.
  bool get _showTrialBanner {
    if (_loading) return false;
    if (widget.marketOfferPlansOnly) return false;
    if (!_isTrialEligibleAccount) return false;
    final c = _ctx;
    if (c != null && c.ok) {
      return c.canShowTrialTab &&
          (_current == null ||
              !SubscriptionService.subscriptionRowInPaidAccess(_current));
    }
    return !_trialAlreadyUsed &&
        (_current == null ||
            !SubscriptionService.subscriptionRowInPaidAccess(_current));
  }

  bool get _showTeamMemberNote {
    final c = _ctx;
    if (_teamNoteDismissed) return false;
    if (c != null && c.ok) return c.showTeamMemberNote;
    return false;
  }

  bool get _paymentBlockedByFal {
    final c = _ctx;
    if (c != null && c.ok) return c.falBlocksPayment;
    return false;
  }

  /// شارة «تم استنفاذ الخدمة» — تظهر فقط لمن استخدم التجربة فعلاً ولديه
  /// سجل تجربة قديم منتهٍ (is_trial=true && ends_at <= now).
  /// لا تُظهر للأشخاص الذين لم يستخدموها بعد، ولا أثناء التجربة الفعّالة.
  bool get _showTrialExhaustedBadge {
    if (!_isMarketingRole || _loading) return false;
    if (_hasActiveTrial) return false;
    if (SubscriptionService.subscriptionRowGrantsMarketingAccess(_current)) {
      return false;
    }
    if (_ctx?.ok == true && _ctx!.hasActiveTrial) return false;
    final ctxUsed = (_ctx?.ok == true) && _ctx!.trialUsedBySelf;
    final hasExpiredTrialRow = SubscriptionService.isExpiredTrial(_current);
    // سجّل في user_trial_subscriptions_used لكن التجربة ما زالت فعّالة → لا شارة.
    if (ctxUsed && _hasActiveTrial) return false;
    return (ctxUsed || hasExpiredTrialRow) && !_hasActiveTrial;
  }

  @override
  void initState() {
    super.initState();
    SubscriptionService.invalidateSubscriptionCache();
    if (widget.marketOfferPlansOnly) {
      _period = 'monthly';
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // عرض الباقات يجب ألا يتعطّل بسبب فشل جلب الاشتراك الحالي أو سياق الفوترة
    // (resolveBillingContext قد يفشل/يتأخّر بعد تخصيص الدفع حسب المستخدم).
    // لذلك نعزل كل نداء على حدة ولا نسمح لأي فشل بإسقاط تحميل الباقات.
    List<Map<String, dynamic>> plans = const [];
    try {
      plans = await _svc.fetchPlansByUserType(widget.accountType);
    } catch (_) {
      plans = const [];
    }

    Map<String, dynamic>? cur;
    try {
      cur = await _svc.getCurrentSubscription(
        organizationId: widget.organizationId,
      );
    } catch (_) {
      cur = null;
    }

    SubscriptionBillingContext? ctx;
    try {
      ctx = widget.billingContext != null && widget.billingContext!.ok
          ? widget.billingContext
          : await _svc.resolveBillingContext();
    } catch (_) {
      ctx = null;
    }

    if (!mounted) return;

    // «التجربة مستهلكة» — لا تُظهر أثناء تجربة فعّالة أو إذا لم يُثبت الاستخدام بعد.
    var used = false;
    if (ctx != null && ctx.ok) {
      used = ctx.trialUsedBySelf;
      _billingCtx = ctx;
    } else if (_isTrialEligibleAccount) {
      try {
        used = await _svc.hasUserUsedTrial();
      } catch (_) {
        used = false;
      }
    }

    var visible = plans;
    if (widget.marketOfferPlansOnly) {
      visible = plans.where((p) {
        final n = int.tryParse('${p['sort_order'] ?? 0}') ?? 0;
        return n >= 11;
      }).toList();
    }

    var initialPeriod = _period;
    if (cur != null && _inPaidPeriod(cur)) {
      final cp = '${cur['period'] ?? ''}'.trim().toLowerCase();
      if (cp == 'yearly') {
        initialPeriod = 'yearly';
      } else if (cp == 'monthly') {
        initialPeriod = 'monthly';
      } else if (cp == 'lifetime_one_time') {
        initialPeriod = 'one_time';
      }
    } else if (widget.marketOfferPlansOnly) {
      initialPeriod = 'monthly';
    }

    setState(() {
      _plans = visible;
      _current = cur;
      _period = initialPeriod;
      _trialAlreadyUsed = used;
      _loading = false;
    });
  }

  /// نافذة تأكيد تشرح حدود التجربة قبل التفعيل (لا رجعة بعد التأكيد).
  Future<bool> _confirmTrialActivation() async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.card_giftcard_outlined, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_isAr
                  ? 'تفعيل التجربة ٣ أيام'
                  : 'Activate 3-day trial'),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isAr
                    ? 'لديك صلاحية استخدام الميزة المدفوعة لمدة ٣ أيام فقط. عند انتهائها لا بد من الاشتراك للمتابعة.'
                    : 'You will have access to the paid feature for 3 days only. After it ends, a subscription is required to continue.',
              ),
              const SizedBox(height: 12),
              Text(
                _isAr ? 'حدود التجربة:' : 'Trial limits:',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(_isAr
                  ? '• لا يمكن إضافة عضو إلى الفريق.'
                  : '• Cannot add team members.'),
              Text(_isAr
                  ? '• إعلان عقاري واحد فقط داخل تبويب «صفحتي» (تستفيد منه في كل التبويبات: تعاقد، عروض، رسائل…).'
                  : '• Only 1 real-estate listing under "My desk" (full access on it: contract, offers, chat…).'),
              Text(_isAr
                  ? '• طلبات عقارية غير محدودة.'
                  : '• Unlimited real-estate requests.'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isAr
                      ? 'تنبيه: التجربة لمرّة واحدة فقط لهذا المستخدم — لا يمكن تكرارها.'
                      : 'Note: This trial is one-time per user — cannot be repeated.',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'موافق وتفعيل' : 'Agree & activate'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _activateTrial() async {
    if (_activatingTrial) return;
    final agreed = await _confirmTrialActivation();
    if (!mounted || !agreed) return;

    setState(() => _activatingTrial = true);
    final res = await _svc.activateMarketingTrialSubscription();
    if (!mounted) return;
    final ok = res['ok'] == true;
    final err = res['error']?.toString();
    SubscriptionService.invalidateSubscriptionCache();
    setState(() => _activatingTrial = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr
              ? 'تم تفعيل تجربة ٣ أيام — تستطيع الآن استخدام الميزات.'
              : '3-day trial activated. You can use paid features now.'),
        ),
      );
      await _load();
    } else {
      String msg;
      if (err == 'trial_already_used') {
        msg = _isAr
            ? 'لقد استخدمت التجربة المجانية من قبل.'
            : 'You already used the free trial.';
      } else if (err == 'paid_subscription_active') {
        msg = _isAr
            ? 'لديك اشتراك مدفوع — لا حاجة للتجربة.'
            : 'You already have an active paid subscription.';
      } else {
        msg = _isAr
            ? 'تعذّر التفعيل: ${err ?? 'unknown'}'
            : 'Failed: ${err ?? 'unknown'}';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _activeTrialBanner(ColorScheme cs) {
    final end = SubscriptionService.subscriptionExclusiveEndUtc(_current);
    final endLocal = end?.toLocal();
    final formatted = endLocal == null
        ? ''
        : DateFormat('EEEE d MMM yyyy — HH:mm', _isAr ? 'ar' : 'en')
            .format(endLocal);
    final diff = end == null
        ? Duration.zero
        : end.difference(DateTime.now().toUtc());
    final days = diff.inDays;
    final hours = diff.inHours - days * 24;
    final remaining = days > 0
        ? (_isAr ? '$days يوم و $hours ساعة' : '$days days · $hours hours')
        : (_isAr ? '$hours ساعة' : '$hours hours');

    return Card(
      color: cs.tertiaryContainer.withValues(alpha: 0.5),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isAr
                        ? 'الفترة التجريبية مفعّلة الآن'
                        : 'Trial period is active',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_isAr
                ? 'المتبقي: $remaining'
                : 'Remaining: $remaining'),
            if (formatted.isNotEmpty)
              Text(
                _isAr ? 'تنتهي: $formatted' : 'Ends: $formatted',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            Text(
              _isAr
                  ? 'الحدود: إعلان عقاري واحد · بدون أعضاء فريق · طلبات غير محدودة.'
                  : 'Limits: 1 listing · no team members · unlimited requests.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// الباقات الرئيسية فقط — توب-أب العروض/الطلبات بدون سطر فال.
  bool _planShowsFalSupport(Map<String, dynamic> p) {
    final sort = int.tryParse('${p['sort_order'] ?? 0}') ?? 0;
    return SubscriptionService.isMainPlanSortOrder(sort);
  }

  /// عند عدم تضمين فال في الباقة: دعم فني عبر واتساب.
  Widget _falContactRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: FalSupportWhatsappRow(isAr: _isAr, compact: true),
    );
  }

  Widget _teamMemberNoteBanner(ColorScheme cs) {
    final ownerUsed = _ctx?.trialUsedByOrgOwner == true;
    return Dismissible(
      key: const ValueKey('team_member_sub_note'),
      direction: DismissDirection.up,
      onDismissed: (_) => setState(() => _teamNoteDismissed = true),
      child: Material(
        color: cs.errorContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.groups_2_outlined, size: 20, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ownerUsed
                      ? (_isAr
                          ? 'أنت عضو ضمن فريق — الاشتراك والتجربة تُدار من قِبل مدير المنشأة (استُنفِذت تجربته).'
                          : 'You are on a team — subscription/trial is managed by the org owner (their trial was used).')
                      : (_isAr
                          ? 'أنت عضو ضمن فريق ولست حساباً مستقلاً — الباقات والتجربة عبر مدير المنشأة.'
                          : 'You are a team member, not an independent account — plans/trial via the org owner.'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                        height: 1.35,
                      ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.close, size: 18, color: cs.onErrorContainer),
                onPressed: () => setState(() => _teamNoteDismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _falComplianceBanner(ColorScheme cs) {
    final c = _ctx;
    final exp = c?.falLicenseExpiresAt?.toLocal();
    final expStr = exp == null
        ? ''
        : DateFormat('d MMM yyyy', _isAr ? 'ar' : 'en').format(exp);
    final blocked = _paymentBlockedByFal;
    return Card(
      color: blocked
          ? cs.errorContainer.withValues(alpha: 0.45)
          : cs.tertiaryContainer.withValues(alpha: 0.4),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  blocked ? Icons.gpp_bad_outlined : Icons.warning_amber_outlined,
                  color: blocked ? cs.error : cs.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    blocked
                        ? (_isAr
                            ? 'رخصة فال منتهية — يُوقف الدفع حتى التجديد'
                            : 'FAL license expired — payment blocked until renewal')
                        : (_isAr
                            ? 'رخصة فال تنتهي قريباً'
                            : 'FAL license expiring soon'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            if (expStr.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _isAr ? 'تاريخ الانتهاء: $expStr' : 'Expires: $expStr',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            FalSupportWhatsappRow(isAr: _isAr, compact: true, inline: false),
          ],
        ),
      ),
    );
  }

  Widget _trialExhaustedBadge(ColorScheme cs) {
    // ملاحظة حمراء واضحة بأن الفترة التجريبية انتهت — وفق طلب المستخدم.
    return Card(
      color: cs.errorContainer,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.do_not_disturb_alt_outlined, color: cs.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isAr
                    ? 'تم استنفاذ الفترة التجريبية المجانية — لا يمكن تكرارها. اشترك من الباقات أدناه للمتابعة.'
                    : 'Free trial already used — cannot be repeated. Please subscribe from the plans below.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _planName(Map<String, dynamic> p) =>
      _isAr ? AppBranding.planNameFromRow(p, isAr: true) : AppBranding.planNameFromRow(p, isAr: false);

  double _planPriceAmount(Map<String, dynamic> p) {
    final program = (p['plan_program'] ?? 'monthly').toString().trim();
    final v = program == 'lifetime_one_time'
        ? p['price_monthly']
        : (_period == 'yearly' ? p['price_yearly'] : p['price_monthly']);
    return v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  }

  String _money(Map<String, dynamic> p) {
    return AppMoney.formatWithCurrencyCode(
      _planPriceAmount(p),
      isAr: _isAr,
      currencyCode: 'SAR',
      maxFractionDigits: 0,
    );
  }

  /// تصفية الخطط حسب البلَّيت _period — نُبقي «مرة واحدة» منفصلة عن شهري/سنوي.
  bool _planMatchesCurrentPeriod(Map<String, dynamic> p) {
    final program = (p['plan_program'] ?? 'monthly').toString().trim();
    final sort = int.tryParse('${p['sort_order'] ?? 0}') ?? 0;
    final isMainPlan = SubscriptionService.isMainPlanSortOrder(sort);

    if (_period == 'one_time') {
      return program == 'lifetime_one_time' || sort == 23 || sort == 13;
    }
    if (program == 'lifetime_one_time' || sort == 23 || sort == 13) {
      return false;
    }
    // الباقة الرئيسية تظهر في شهري وسنوي (السعر يتغيّر حسب الشريحة).
    if (isMainPlan) return true;
    if (_period == 'monthly') {
      return sort == 21 || sort == 11 || program == 'monthly';
    }
    if (_period == 'yearly') {
      return sort == 22 || sort == 12 || program == 'yearly';
    }
    return true;
  }

  bool get _hasAnyOneTimePlan =>
      _plans.any((p) => (p['plan_program'] ?? '').toString() == 'lifetime_one_time');

  String _lim(dynamic v, AppLocalizations t) {
    if (v == null) return t.subscriptionsUnlimited;
    final n = int.tryParse('$v');
    if (n == null || n <= 0) return t.subscriptionsUnlimited;
    return '$n';
  }

  /// سياسة الاشتراك — من [PlanDisplayCopy] حسب بيانات الباقة.
  String _subscriptionPolicyLine(Map<String, dynamic> p) =>
      PlanDisplayCopy.policyLine(p, lang: widget.lang);

  String _adsPerMonthLine(Map<String, dynamic> p, AppLocalizations t) {
    final v = p['max_ads_per_month'];
    if (p['is_trial_plan'] == true) {
      return _isAr
          ? '• الإعلانات العقارية / شهرياً: غير محدود (تجربة)'
          : '• Listings / month: unlimited (trial)';
    }
    final n = int.tryParse('$v');
    final val = (n == null || n <= 0)
        ? t.subscriptionsUnlimited
        : '$n ${_isAr ? 'إعلان' : 'listings'}';
    return '• ${t.subscriptionsAdsPerMonth}: $val';
  }

  String _listingRequestsLine(Map<String, dynamic> p) =>
      PlanDisplayCopy.listingRequestsLine(p, lang: widget.lang);

  String? _comprehensivePlanNote(Map<String, dynamic> p) =>
      PlanDisplayCopy.comprehensiveNote(p, lang: widget.lang);

  String _propertyListingsLine(Map<String, dynamic> p, AppLocalizations t) =>
      PlanDisplayCopy.listingsLine(p, lang: widget.lang);

  String _marketOffersLine(Map<String, dynamic> p) =>
      PlanDisplayCopy.marketOffersLine(p, lang: widget.lang);

  String _membersFeatureLine(Map<String, dynamic> p, AppLocalizations t) {
    final raw = p['max_members'];
    final n = int.tryParse('$raw');
    if (AppRoleHelper.isStandaloneMarketer(widget.accountType) &&
        n != null &&
        n == 0) {
      return _isAr
          ? '• عمل فردي — إضافة عضو بمقعد مدفوع'
          : '• Solo work — add teammates via paid seats';
    }
    return '• ${t.subscriptionsMembers}: ${_lim(raw, t)}';
  }

  bool _inPaidPeriod(Map<String, dynamic>? row) {
    if (row == null) return false;
    final st = '${row['status']}'.trim().toLowerCase();
    if (st == 'pending' || st == 'expired') return false;
    final end = DateTime.tryParse('${row['end_date']}');
    if (end == null) return false;
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final ed = DateTime(end.year, end.month, end.day);
    if (ed.isBefore(today)) return false;
    return st == 'active' || st == 'cancelled';
  }

  /// زر التجديد يظهر فقط عند انتهاء الاشتراك أو اقترابه (≤7 أيام) أو فشل التجديد التلقائي.
  bool _canRenewSubscription(Map<String, dynamic>? row) {
    if (row == null) return false;
    if (!SubscriptionUiHelpers.isRecurringSubscription(row)) return false;
    final status = '${row['status'] ?? ''}'.trim().toLowerCase();
    if (status == 'pending') return false;

    final endDate = DateTime.tryParse('${row['end_date'] ?? ''}');
    final now = DateTime.now();
    final expired =
        status == 'expired' || (endDate != null && endDate.isBefore(now));
    if (expired) return true;

    if (SubscriptionService.subscriptionRenewalFailureFlag(row)) {
      if (endDate == null) return true;
      final daysLeft = endDate.difference(now).inDays;
      return daysLeft <= 14;
    }

    if (status == 'active' && endDate != null) {
      final daysLeft = endDate.difference(now).inDays;
      if (daysLeft <= 7 &&
          !SubscriptionService.subscriptionAutoRenewEnabled(row)) {
        return true;
      }
    }

    if (status == 'cancelled' && endDate != null && endDate.isBefore(now)) {
      return true;
    }

    return false;
  }

  String _billingPeriodForCheckout() =>
      _period == 'one_time' ? 'lifetime_one_time' : _period;

  Future<void> _afterCheckoutPop(bool? ok) async {
    if (ok != true || !mounted) return;
    SubscriptionService.invalidateSubscriptionCache();
    final resume = widget.resumeAfterPurchase;
    if (resume != null && resume.isValid) {
      Navigator.of(context).pop(resume);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    return AqarPrimaryScrollScope(
      child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            SubscriptionService.planAudienceLabel(
              isAr: _isAr,
              accountType: widget.accountType,
            ),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.primary,
                ),
          ),
          const SizedBox(height: 8),
          if (widget.upgradeOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                t.subscriptionsUpgradeCta,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(t.subscriptionsMonthly),
                selected: _period == 'monthly',
                onSelected: (_) => setState(() => _period = 'monthly'),
              ),
              ChoiceChip(
                label: Text(t.subscriptionsYearly),
                selected: _period == 'yearly',
                onSelected: (_) => setState(() => _period = 'yearly'),
              ),
              if (_hasAnyOneTimePlan)
                ChoiceChip(
                  label: Text(_isAr ? 'مرة واحدة' : 'One-time'),
                  selected: _period == 'one_time',
                  onSelected: (_) => setState(() => _period = 'one_time'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _period == 'one_time'
                ? (_isAr
                    ? 'دفع لمرة واحدة برصيد محدود لإتمام الصفقات على طلبات السوق — لا يُجدَّد ولا ينتهي بالوقت.'
                    : 'One-time payment with a limited deal balance for market requests — no renewal, no time expiry.')
                : t.subscriptionsYearlyDiscountNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          if (widget.marketOfferPlansOnly) ...[
            Card(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _isAr
                      ? 'عند نفاد حصة «إتمام الصفقة»: اشترِ «إضافة صفقات» — شهري ${AppMoney.formatWithCurrencyCode(29, isAr: true, maxFractionDigits: 0)} (+10 صفقات) أو مرة واحدة ${AppMoney.formatWithCurrencyCode(25, isAr: true, maxFractionDigits: 0)} (+5 صفقات). تُفعَّل فوراً.'
                      : 'When deal quota runs out: buy «Deal top-up» — ${AppMoney.formatWithCurrencyCode(29, isAr: false, maxFractionDigits: 0)}/month (+10 deals) or ${AppMoney.formatWithCurrencyCode(25, isAr: false, maxFractionDigits: 0)} one-time (+5 deals). Applies immediately.',
                  style: SubscriptionUiHelpers.denseBody(context),
                ),
              ),
            ),
          ],
          if (!_isMarketingRole) ...[
            const SizedBox(height: 6),
            Text(
              _isAr
                  ? 'تنبيه عدالة: الاشتراك يفتح حصة لإتمام الصفقات ولا يضمن إغلاق أي صفقة. الاختيار يبقى لصاحب الطلب.'
                  : 'Fairness notice: a subscription grants deal quota only and does not guarantee a closed deal. The requester always picks the party.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
          const SizedBox(height: 16),
          if (_showTeamMemberNote) ...[
            _teamMemberNoteBanner(cs),
            const SizedBox(height: 8),
          ],
          if (_ctx?.falWarnsSoon == true || _paymentBlockedByFal)
            _falComplianceBanner(cs),
          if (_hasActiveTrial) _activeTrialBanner(cs),
          if (_showTrialBanner) ...[
            Card(
              color: cs.primaryContainer.withValues(alpha: 0.45),
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.card_giftcard_outlined, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isAr
                                ? 'جرّب ${AppBranding.shortNameAr} ٣ أيام مجاناً'
                                : 'Try ${AppBranding.shortNameEn} free for 3 days',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isAr
                          ? 'فعّل التجربة لمرة واحدة وجرّب أهم الميزات: إعلان عقاري واحد + طلبات غير محدودة. تنتهي تلقائياً بعد ٣ أيام بدون أي خصم.'
                          : 'Activate the one-time trial: 1 listing + unlimited requests. Ends automatically after 3 days, no charge.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _activatingTrial ? null : _activateTrial,
                      icon: _activatingTrial
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_outlined),
                      label: Text(
                        _isAr ? 'تفعيل تجربة ٣ أيام' : 'Activate 3-day trial',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_showTrialExhaustedBadge) _trialExhaustedBadge(cs),
          if (_plans.where(_planMatchesCurrentPeriod).isEmpty) ...[
            Card(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isAr
                          ? 'لا توجد باقات مدفوعة ظاهرة حالياً'
                          : 'No paid plans are visible right now',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isAr
                          ? 'اسحب للأسفل للتحديث. إن استمرت المشكلة تأكد من تفعيل الباقات في قاعدة البيانات أو تواصل مع الدعم.'
                          : 'Pull to refresh. If this persists, ensure plans are active in the database or contact support.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(_isAr ? 'تحديث الباقات' : 'Refresh plans'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ..._plans.where(_planMatchesCurrentPeriod).map((p) {
            final id = '${p['id']}';
            final curId = '${_current?['plan_id'] ?? ''}';
            final curPlanMap = _current?['plan'] is Map
                ? Map<String, dynamic>.from(_current!['plan'] as Map)
                : <String, dynamic>{};
            final isCurrent = _inPaidPeriod(_current) &&
                (curId == id ||
                    (curPlanMap.isNotEmpty &&
                        SubscriptionService.planSortOrder(p) ==
                            SubscriptionService.planSortOrder(curPlanMap)));
            final end = '${_current?['end_date'] ?? ''}';
            final canUpgrade = SubscriptionUiHelpers.showUpgradePlanButton(
              currentRow: _current,
              targetPlan: p,
              inPaidPeriod: _inPaidPeriod,
              planSortOrder: SubscriptionService.planSortOrder,
            );
            final upgradeCharge = canUpgrade && curPlanMap.isNotEmpty
                ? SubscriptionService.computePlanChangeCharge(
                    subscriptionRow: _current!,
                    oldPlan: curPlanMap,
                    newPlan: p,
                    targetPeriod: _period,
                  )
                : null;
            final isPeriodSwitch = isCurrent &&
                _inPaidPeriod(_current) &&
                '${_current?['period'] ?? ''}'.trim() == 'monthly' &&
                _period == 'yearly' &&
                curPlanMap.isNotEmpty;
            final periodSwitchCharge = isPeriodSwitch
                ? SubscriptionService.computePlanChangeCharge(
                    subscriptionRow: _current!,
                    oldPlan: curPlanMap,
                    newPlan: curPlanMap,
                    targetPeriod: 'yearly',
                  )
                : null;
            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              _planName(p),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _isAr ? 'تفاصيل الباقة' : 'Plan details',
                          icon: Icon(Icons.info_outline, color: cs.primary),
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => PlanDetailsScreen(
                                  lang: widget.lang,
                                  plan: p,
                                  selectedPeriod: _period,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        AppMoneyLine(
                          amount: _planPriceAmount(p),
                          currencyCode: 'SAR',
                          isAr: _isAr,
                          maxFractionDigits: 0,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            (p['plan_program'] ?? 'monthly').toString() ==
                                    'lifetime_one_time'
                                ? ' · ${_isAr ? 'دفع مرة واحدة' : 'one-time payment'}'
                                : ' / ${_period == 'yearly' ? t.subscriptionsYearly.split(' ').first : t.subscriptionsMonthly}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subscriptionPolicyLine(p),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _propertyListingsLine(p, t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _listingRequestsLine(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _marketOffersLine(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_comprehensivePlanNote(p) != null)
                      Text(
                        _comprehensivePlanNote(p)!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (_planShowsFalSupport(p) &&
                        p['has_fal_license'] != true &&
                        !SubscriptionService.isComprehensivePlanSortOrder(
                          int.tryParse('${p['sort_order'] ?? 0}') ?? 0,
                        ))
                      _falContactRow(cs),
                    const SizedBox(height: 12),
                    if (!isCurrent)
                      FilledButton(
                        onPressed: _paymentBlockedByFal
                            ? null
                            : () async {
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute<bool>(
                              settings: RouteSettings(
                                name: DashboardEmbeddedRoute.isEmbedded(context)
                                    ? DashboardEmbeddedRoute.subscriptionsCheckout
                                    : '/subscriptions/checkout',
                              ),
                              builder: (_) => PaymentCheckoutScreen(
                                lang: widget.lang,
                                accountType: widget.accountType,
                                plan: p,
                                period: _billingPeriodForCheckout(),
                                organizationId: widget.organizationId,
                                upgradeSubscriptionId:
                                    canUpgrade ? '${_current?['id']}' : null,
                                chargeAmountOverride: upgradeCharge,
                                billingContext: _ctx,
                              ),
                            ),
                          );
                          await _afterCheckoutPop(ok);
                        },
                        child: Text(
                          canUpgrade
                              ? t.subscriptionsUpgradeCta
                              : t.subscriptionsSubscribeNow,
                        ),
                      )
                    else ...[
                      if (isPeriodSwitch && periodSwitchCharge != null) ...[
                        Text(
                          _isAr
                              ? 'المتبقي من الفترة الشهرية يُخصم من سعر السنة. المستحق: '
                                  '${AppMoney.formatWithCurrencyCode(periodSwitchCharge, isAr: true, maxFractionDigits: 0)}'
                              : 'Remaining monthly value is credited toward yearly. Due: '
                                  '${AppMoney.formatWithCurrencyCode(periodSwitchCharge, isAr: false, maxFractionDigits: 0)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: () async {
                            final ok = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute<bool>(
                              settings: RouteSettings(
                                name: DashboardEmbeddedRoute.isEmbedded(context)
                                    ? DashboardEmbeddedRoute.subscriptionsCheckout
                                    : '/subscriptions/checkout',
                              ),
                                builder: (_) => PaymentCheckoutScreen(
                                  lang: widget.lang,
                                  accountType: widget.accountType,
                                  plan: p,
                                  period: 'yearly',
                                  organizationId: widget.organizationId,
                                  periodSwitchSubscriptionId:
                                      '${_current?['id']}',
                                  chargeAmountOverride: periodSwitchCharge,
                                  billingContext: _ctx,
                                ),
                              ),
                            );
                            await _afterCheckoutPop(ok);
                          },
                          child: Text(
                            _isAr
                                ? 'دفع الفرق والتحويل لسنوي'
                                : 'Pay difference & switch to yearly',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        SubscriptionUiHelpers.billingCycleStatusLine(
                          isAr: _isAr,
                          row: _current,
                        ),
                        style: SubscriptionUiHelpers.denseBody(context),
                      ),
                      const SizedBox(height: 6),
                      Builder(
                        builder: (context) {
                          if (!SubscriptionUiHelpers.isRecurringSubscription(
                            _current,
                          )) {
                            return const SizedBox.shrink();
                          }
                          final autoRenewOn =
                              SubscriptionService.subscriptionAutoRenewEnabled(
                            _current,
                          );
                          final canRenew = _canRenewSubscription(_current);
                          final canCancel =
                              SubscriptionUiHelpers.showCancelSubscriptionButton(
                            row: _current,
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (autoRenewOn && !canRenew)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    _isAr
                                        ? 'التجديد التلقائي مفعّل — لا حاجة للتجديد اليدوي'
                                        : 'Auto-renewal is on — no manual renewal needed',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              if (canRenew)
                                FilledButton.tonal(
                                  onPressed: () async {
                                    final sid = '${_current?['id']}';
                                    if (sid.isEmpty) return;
                                    final ok = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute<bool>(
                                        settings: RouteSettings(
                                          name: DashboardEmbeddedRoute
                                                  .isEmbedded(context)
                                              ? DashboardEmbeddedRoute
                                                  .subscriptionsCheckout
                                              : '/subscriptions/checkout',
                                        ),
                                        builder: (_) => PaymentCheckoutScreen(
                                          lang: widget.lang,
                                          accountType: widget.accountType,
                                          plan: p,
                                          period: _billingPeriodForCheckout(),
                                          organizationId: widget.organizationId,
                                          renewSubscriptionId: sid,
                                          billingContext: _ctx,
                                        ),
                                      ),
                                    );
                                    await _afterCheckoutPop(ok);
                                  },
                                  child: Text(t.subscriptionsRenew),
                                ),
                              if (canCancel) ...[
                                if (canRenew) const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () async {
                                    final sid = '${_current?['id']}';
                                    if (sid.isEmpty) return;
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    final ok = await SubscriptionCancelFlow.run(
                                      context: context,
                                      t: t,
                                      svc: _svc,
                                      subscriptionId: sid,
                                      endDateLabel: end.isEmpty
                                          ? '—'
                                          : SubscriptionUiHelpers
                                              .formatBillingDate(
                                            end,
                                            isAr: _isAr,
                                          ),
                                      organizationId: widget.organizationId,
                                    );
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok
                                              ? (_isAr
                                                  ? 'تم طلب الإلغاء — تبقى المزايا حتى نهاية الفترة.'
                                                  : 'Cancellation scheduled — access stays until period end.')
                                              : (_isAr
                                                  ? 'لم يُكمل الإلغاء.'
                                                  : 'Cancellation not completed.'),
                                        ),
                                      ),
                                    );
                                    if (ok) await _load();
                                  },
                                  child: Text(t.subscriptionsCancel),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    ),
    );
  }
}
