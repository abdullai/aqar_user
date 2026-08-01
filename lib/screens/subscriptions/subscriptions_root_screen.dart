import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/subscription/marketing_subscription_resume_intent.dart';
import '../../core/subscription/subscription_billing_context.dart';
import '../../core/workflow/app_role_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../services/subscription_service.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import '../organization_settings_screen.dart';
import 'manage_team_subscription_screen.dart';
import 'owner_instant_payments_hub_screen.dart';
import 'payment_history_screen.dart';
import 'payment_methods_screen.dart';
import 'subscription_details_screen.dart';
import 'subscription_plans_screen.dart';

/// جذر الاشتراكات — تبويبات حسب نوع الحساب.
class SubscriptionsRootScreen extends StatefulWidget {
  const SubscriptionsRootScreen({
    super.key,
    required this.lang,
    required this.accountType,
    this.organizationId,
    this.initialIndex = 0,
    this.embedAppBar = false,
    this.resumeAfterPurchase,
    this.marketOfferPlansOnly = false,
  });

  final String lang;
  final String accountType;
  final String? organizationId;
  final int initialIndex;

  /// عند `true`: بدون [AppBar] علوي (للدمج مع شريط لوحة التحكم الخارجية).
  final bool embedAppBar;

  /// بعد إتمام دفع باقة من مسار إجراء مدفوع يُعاد [MarketingSubscriptionResumeIntent] للوحة الأم.
  final MarketingSubscriptionResumeIntent? resumeAfterPurchase;

  /// من paywall «عروض السوق» للمعلن/المالك: إظهار باقات 11/12/13 فقط.
  final bool marketOfferPlansOnly;

  @override
  State<SubscriptionsRootScreen> createState() =>
      _SubscriptionsRootScreenState();
}

class _SubscriptionsRootScreenState extends State<SubscriptionsRootScreen>
    with SingleTickerProviderStateMixin {
  TabController? _ctrl;
  List<Tab> _tabs = const [];
  List<Widget> _bodies = const [];
  int? _upgradeTabIndex;
  SubscriptionBillingContext? _billingCtx;
  bool _billingCtxLoading = true;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prefetchBillingContext());
      _setupTabs();
    });
  }

  /// فحص صامت: فردي / عضو فريق / مدير منشأة + تجربة + فال + خصم 50%.
  Future<void> _prefetchBillingContext() async {
    final svc = SubscriptionService(Supabase.instance.client);
    final ctx = await svc.resolveBillingContext();
    if (!mounted) return;
    setState(() {
      _billingCtx = ctx;
      _billingCtxLoading = false;
    });
    // أعد بناء التبويبات لتمرير السياق لشاشة الباقات.
    _setupTabs();
  }

  void _setupTabs() {
    if (!mounted) return;
    final t = AppLocalizations.of(context)!;
    final orgEntity = AppRoleHelper.isOrgEntity(widget.accountType);
    final marketingDesk =
        AppRoleHelper.isMarketingAccountType(widget.accountType);
    final ownerDesk = AppRoleHelper.isOwnerFreeTierAccount(widget.accountType);

    final tabs = <Tab>[];
    final bodies = <Widget>[];
    int? upgradeIdx;

    void add(Tab tab, Widget body) {
      tabs.add(tab);
      bodies.add(body);
    }

    if (ownerDesk) {
      add(
        Tab(
          icon: const Icon(Icons.bolt_rounded),
          text: widget.lang.toLowerCase() != 'en' ? 'الطلب الفوري' : 'Instant',
        ),
        OwnerInstantPaymentsHubScreen(lang: widget.lang),
      );
    } else {
      add(
        Tab(
          icon: const Icon(Icons.inventory_2_outlined),
          text: t.subscriptionsTabPlans,
        ),
        SubscriptionPlansScreen(
          lang: widget.lang,
          accountType: widget.accountType,
          organizationId: widget.organizationId,
          resumeAfterPurchase: widget.resumeAfterPurchase,
          billingContext: _billingCtx,
          billingContextLoading: _billingCtxLoading,
          marketOfferPlansOnly: widget.marketOfferPlansOnly,
        ),
      );
    }
    add(
      Tab(
        icon: const Icon(Icons.credit_card),
        text: t.subscriptionsTabPaymentMethods,
      ),
      PaymentMethodsScreen(lang: widget.lang),
    );
    add(
      Tab(
        icon: const Icon(Icons.receipt_long_outlined),
        text: t.subscriptionsTabHistory,
      ),
      PaymentHistoryScreen(lang: widget.lang),
    );

    if (marketingDesk) {
      add(
        Tab(
          icon: const Icon(Icons.groups_outlined),
          text: t.subscriptionsTabTeam,
        ),
        ManageTeamSubscriptionScreen(
          lang: widget.lang,
          accountType: widget.accountType,
          organizationId: widget.organizationId,
          onRequestUpgrade: orgEntity
              ? () {
                  final u = _upgradeTabIndex;
                  if (u != null && _ctrl != null) _ctrl!.animateTo(u);
                }
              : null,
        ),
      );
      add(
        Tab(
          icon: const Icon(Icons.pie_chart_outline),
          text: t.subscriptionsTabUsage,
        ),
        SubscriptionDetailsScreen(
          lang: widget.lang,
          accountType: widget.accountType,
          organizationId: widget.organizationId,
        ),
      );
    }

    if (orgEntity) {
      upgradeIdx = tabs.length;
      add(
        Tab(
          icon: const Icon(Icons.rocket_launch_outlined),
          text: t.subscriptionsTabUpgrade,
        ),
        SubscriptionPlansScreen(
          lang: widget.lang,
          accountType: widget.accountType,
          organizationId: widget.organizationId,
          upgradeOnly: true,
          resumeAfterPurchase: widget.resumeAfterPurchase,
          billingContext: _billingCtx,
          billingContextLoading: _billingCtxLoading,
        ),
      );
      add(
        Tab(
          icon: const Icon(Icons.verified_outlined),
          text: t.subscriptionsTabRenewFal,
        ),
        _RenewFalTab(lang: widget.lang),
      );
    }

    _ctrl?.dispose();
    final idx = widget.initialIndex.clamp(0, tabs.length - 1);
    _ctrl = TabController(length: tabs.length, vsync: this, initialIndex: idx);
    setState(() {
      _tabs = tabs;
      _bodies = bodies;
      _upgradeTabIndex = upgradeIdx;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (_ctrl == null || _tabs.isEmpty) {
      return Scaffold(
        appBar: widget.embedAppBar
            ? null
            : AppBar(title: Text(t.subscriptionsTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.embedAppBar) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: cs.surface,
              elevation: 0.5,
              shadowColor: Colors.black26,
              child: TabBar(
                controller: _ctrl,
                isScrollable: _tabs.length > 4,
                tabs: _tabs,
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _ctrl,
                children: [
                  for (final body in _bodies)
                    AqarPrimaryScrollScope(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t.subscriptionsTitle),
        bottom: TabBar(
          controller: _ctrl,
          isScrollable: _tabs.length > 4,
          tabs: _tabs,
        ),
      ),
      body: TabBarView(
        controller: _ctrl,
        children: [
          for (final body in _bodies) AqarPrimaryScrollScope(child: body),
        ],
      ),
    );
  }
}

class _RenewFalTab extends StatelessWidget {
  const _RenewFalTab({required this.lang});

  final String lang;

  bool get _isAr => lang.toLowerCase() != 'en';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return AqarPrimaryScrollScope(
      child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(t.subscriptionsRenewFalBody),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const OrganizationSettingsScreen(),
                settings: const RouteSettings(name: '/desk/org-settings'),
              ),
            );
          },
          child: Text(t.subscriptionsOpenOrgSettings),
        ),
        const SizedBox(height: 16),
        Text(
          _isAr
              ? 'تأكد أن اشتراك المنشأة نشط قبل تجديد رمز العرض.'
              : 'Keep the organization subscription active before renewing the public FAL code.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
    );
  }
}
