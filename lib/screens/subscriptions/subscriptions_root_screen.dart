import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/subscription/marketing_subscription_resume_intent.dart';
import '../../core/subscription/subscription_billing_context.dart';
import '../../core/workflow/app_role_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../services/subscription_service.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import '../../widgets/org_fal_and_seats_panel.dart';
import '../../widgets/app_page_close_button.dart';
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
  final TabBarScrollController _tabsScrollController = TabBarScrollController();
  List<Tab> _tabs = const [];
  List<Widget> _bodies = const [];
  int? _upgradeTabIndex;
  SubscriptionBillingContext? _billingCtx;
  bool _billingCtxLoading = true;

  bool _shouldUseScrollableTabs(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    final narrow = (mq?.size.width ?? double.infinity) < 720;
    final textScale = mq?.textScaler.scale(1) ?? 1.0;
    return _tabs.length > 4 || narrow || textScale > 1.1;
  }

  Widget _tabLabel(String label) {
    return Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _tabsScrollController.dispose();
    super.dispose();
  }

  Widget _buildTabsBar(BuildContext context) {
    final scrollable = _shouldUseScrollableTabs(context);
    return TabBar(
      controller: _ctrl,
      isScrollable: scrollable,
      tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
      scrollController: scrollable ? _tabsScrollController : null,
      labelPadding: const EdgeInsets.symmetric(horizontal: 16),
      tabs: _tabs,
    );
  }

  Widget _buildScrollableTabsBar(BuildContext context) {
    if (!_shouldUseScrollableTabs(context)) return _buildTabsBar(context);
    return Scrollbar(
      controller: _tabsScrollController,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      thickness: 3,
      child: _buildTabsBar(context),
    );
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

    add(
      Tab(
        icon: const Icon(Icons.inventory_2_outlined),
        child: _tabLabel(t.subscriptionsTabPlans),
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

    if (ownerDesk) {
      add(
        Tab(
          icon: const Icon(Icons.bolt_rounded),
          child: _tabLabel(
            widget.lang.toLowerCase() != 'en'
                ? t.marketRequestPriorityImmediate
                : 'Instant',
          ),
        ),
        OwnerInstantPaymentsHubScreen(lang: widget.lang),
      );
    }
    add(
      Tab(
        icon: const Icon(Icons.credit_card),
        child: _tabLabel(t.subscriptionsTabPaymentMethods),
      ),
      PaymentMethodsScreen(lang: widget.lang),
    );
    add(
      Tab(
        icon: const Icon(Icons.receipt_long_outlined),
        child: _tabLabel(t.subscriptionsTabHistory),
      ),
      PaymentHistoryScreen(lang: widget.lang),
    );

    if (marketingDesk) {
      add(
        Tab(
          icon: const Icon(Icons.groups_outlined),
          child: _tabLabel(t.subscriptionsTabTeam),
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
          child: _tabLabel(t.subscriptionsTabUsage),
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
          child: _tabLabel(t.subscriptionsTabUpgrade),
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
          child: _tabLabel(t.subscriptionsTabRenewFal),
        ),
        _RenewFalTab(
          lang: widget.lang,
          accountType: widget.accountType,
          organizationId: widget.organizationId,
          onOpenPlans: () {
            _ctrl?.animateTo(0);
          },
        ),
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
            : AppBar(
                automaticallyImplyLeading: false,
                leading: AppPageCloseButton(
                  isArabic: widget.lang.toLowerCase() != 'en',
                ),
                title: Text(t.subscriptionsTitle),
              ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.embedAppBar) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: AppPageCloseButton(
            isArabic: widget.lang.toLowerCase() != 'en',
          ),
          title: Text(t.subscriptionsTitle),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: cs.surface,
              elevation: 0.5,
              shadowColor: Colors.black26,
              child: _buildScrollableTabsBar(context),
            ),
            Expanded(
              child: TabBarView(
                controller: _ctrl,
                children: [
                  for (final body in _bodies)
                    // سجل المدفوعات يدير Expanded/تمريره ذاتياً — لا تغليفه بـ PrimaryScroll.
                    body is PaymentHistoryScreen
                        ? body
                        : AqarPrimaryScrollScope(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: AppPageCloseButton(
          isArabic: widget.lang.toLowerCase() != 'en',
        ),
        title: Text(t.subscriptionsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: _buildScrollableTabsBar(context),
          ),
        ),
      ),
      body: TabBarView(
        controller: _ctrl,
        children: [
          for (final body in _bodies)
            body is PaymentHistoryScreen
                ? body
                : AqarPrimaryScrollScope(child: body),
        ],
      ),
    );
  }
}

class _RenewFalTab extends StatelessWidget {
  const _RenewFalTab({
    required this.lang,
    required this.accountType,
    this.organizationId,
    this.onOpenPlans,
  });

  final String lang;
  final String accountType;
  final String? organizationId;
  final VoidCallback? onOpenPlans;

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
          OrgFalAndSeatsPanel(
            accountType: accountType,
            organizationId: organizationId,
            lang: lang,
            onOpenPlans: onOpenPlans,
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
