import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/org/org_team_capacity.dart';
import '../core/session/account_role_cache.dart';
import '../core/workflow/app_role_helper.dart';
import '../l10n/app_localizations.dart';
import '../services/org_team_service.dart';
import '../services/permission_service.dart';
import '../widgets/app_logo_loading.dart';
import 'assign_permissions_screen.dart';
import 'manage_members_screen.dart';
import 'org_join_requests_desk_page.dart';
import 'organization_analytics_screen.dart';
import 'organization_chat_screen.dart';
import 'organization_settings_screen.dart';
import 'org_member_activity_desk_page.dart';
import '../widgets/team_membership_gate.dart';
import '../widgets/team_invite_member_dialog.dart';
import 'reports_dashboard_screen.dart';
import 'subscriptions/subscription_org_desk_tab.dart';

/// يطابق ترتيب التبويبات عند فتح الشاشة من الخارج (عداد AppBar).
enum MyOrganizationTabKey {
  teamDashboard,
  manageMembers,
  joinRequests,
  rolesPermissions,
  teamChat,
  teamAnalytics,
  reportsExport,
  memberActivity,
  subscriptionDesk,
  orgSettings,
}

/// لوحة «إدارتي» للمنشأة — تبويبات ديناميكية حسب [PermissionService].
class MyOrganizationScreen extends StatefulWidget {
  const MyOrganizationScreen({
    super.key,
    required this.lang,
    this.initialTab,
    this.suppressImpliedLeading = false,
    this.embedAppBar = false,
  });

  final String lang;

  /// تبويب يُفتح عند أول إطار بعد بناء الصلاحيات.
  final MyOrganizationTabKey? initialTab;

  /// عند `true`: لا سهم رجوع ضمني — الرجوع من شريط اللوحة الخارجي (عرض عريض).
  final bool suppressImpliedLeading;

  /// داخل لوحة الرئيسية: العنوان في AppBar الخارجي فقط.
  final bool embedAppBar;

  @override
  State<MyOrganizationScreen> createState() => _MyOrganizationScreenState();
}

class _OrgDeskTab {
  const _OrgDeskTab({
    required this.key,
    required this.tab,
    required this.body,
  });

  final MyOrganizationTabKey key;
  final Tab tab;
  final Widget body;
}

class _MyOrganizationScreenState extends State<MyOrganizationScreen>
    with SingleTickerProviderStateMixin {
  final _svc = OrgTeamService(Supabase.instance.client);

  bool _loading = true;
  List<_OrgDeskTab> _tabs = const [];
  TabController? _ctrl;
  bool _deps = false;
  bool _showInviteInAppBar = false;
  String _accountType = 'office';
  String? _orgId;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_deps) return;
    _deps = true;
    _reload();
  }

  Future<void> _reload() async {
    _ctrl?.dispose();
    _ctrl = null;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _loading = true);

    // 1) ضمان وجود org_unit + عضوية المالك للأدوار التسويقية
    //    (مسوّق فردي/مكتب/مؤسسة/شركة) — يُنشئها الـ RPC إن لم تكن موجودة.
    //    بهذا تظهر التبويبات السبعة/الثمانية لإدارة الفريق فور أوّل فتح.
    final cachedAt = AccountRoleCache.snapshot?.accountType;
    final isMarketingRole = AppRoleHelper.isMarketingRole(
          AppRoleHelper.fromAccountType(cachedAt),
        ) ||
        AppRoleHelper.isOrgEntity(cachedAt);
    if (isMarketingRole) {
      await _svc.ensureMyOrgUnit();
      if (!mounted) return;
    }

    // 2) قراءة سياق المنشأة بعد التأكد من وجودها.
    final ctx = await _svc.myOrgContext();
    if (!mounted) return;
    final owner = ctx?['is_owner'] == true;
    final p = ctx?['permissions'];
    Map<String, dynamic>? pmap;
    if (p is Map) {
      pmap = Map<String, dynamic>.from(
        p.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final oid = ctx?['org_id']?.toString();
    final ps = PermissionService(pmap, isOwner: owner);
    final accountType = cachedAt ?? 'office';
    final showInvite = (owner || ps.inviteMembers) &&
        OrgTeamCapacity.canManageTeamMembers(accountType);
    _accountType = accountType;
    _orgId = oid;
    final tabs = <_OrgDeskTab>[];

    void add(MyOrganizationTabKey key, Tab tab, Widget body) {
      tabs.add(_OrgDeskTab(key: key, tab: tab, body: body));
    }

    if (ps.showDeskTabTeamDashboard) {
      add(
        MyOrganizationTabKey.teamDashboard,
        Tab(
          icon: const Icon(Icons.dashboard_customize_outlined),
          text: l10n.deskTabTeamDashboard,
        ),
        _TeamDashboardBody(
          lang: widget.lang,
          orgId: oid,
          isOwner: owner,
        ),
      );
    }
    if (ps.showDeskTabManageMembers) {
      add(
        MyOrganizationTabKey.manageMembers,
        Tab(
          icon: const Icon(Icons.groups_outlined),
          text: l10n.manageMembersTitle,
        ),
        const ManageMembersScreen(),
      );
    }
    if (ps.showDeskTabJoinRequestsDesk) {
      add(
        MyOrganizationTabKey.joinRequests,
        Tab(
          icon: const Icon(Icons.how_to_reg_outlined),
          text: l10n.deskTabJoinRequests,
        ),
        OrgJoinRequestsDeskPage(lang: widget.lang),
      );
    }
    if (ps.showDeskTabRolesPermissions) {
      add(
        MyOrganizationTabKey.rolesPermissions,
        Tab(
          icon: const Icon(Icons.admin_panel_settings_outlined),
          text: l10n.deskTabRolesPermissions,
        ),
        _OrganizationRolesTab(lang: widget.lang),
      );
    }
    if (ps.showDeskTabInternalChat) {
      add(
        MyOrganizationTabKey.teamChat,
        Tab(
          icon: const Icon(Icons.chat_bubble_outline),
          text: l10n.deskTabTeamChat,
        ),
        OrganizationChatScreen(lang: widget.lang),
      );
    }
    if (ps.viewAnalytics) {
      add(
        MyOrganizationTabKey.teamAnalytics,
        Tab(
          icon: const Icon(Icons.insights_outlined),
          text: l10n.deskTabTeamAnalytics,
        ),
        OrganizationAnalyticsScreen(lang: widget.lang),
      );
    }
    if (ps.viewReports) {
      add(
        MyOrganizationTabKey.reportsExport,
        Tab(
          icon: const Icon(Icons.table_chart_outlined),
          text: l10n.deskTabReportsDesk,
        ),
        ReportsDashboardScreen(
          embedded: true,
          lang: widget.lang,
        ),
      );
    }
    if (ps.showDeskTabMemberActivity) {
      add(
        MyOrganizationTabKey.memberActivity,
        Tab(
          icon: const Icon(Icons.timeline_outlined),
          text: l10n.deskTabMemberActivity,
        ),
        OrgMemberActivityDeskPage(lang: widget.lang),
      );
    }
    final accountTypeForSub =
        AccountRoleCache.snapshot?.accountType ?? 'office';
    if (oid != null &&
        oid.isNotEmpty &&
        (owner || ps.manageSubscription)) {
      add(
        MyOrganizationTabKey.subscriptionDesk,
        Tab(
          icon: const Icon(Icons.subscriptions_outlined),
          text: l10n.subscriptionsOrgManageTab,
        ),
        SubscriptionOrgDeskTab(
          lang: widget.lang,
          accountType: accountTypeForSub,
          organizationId: oid,
        ),
      );
    }
    if (ps.showDeskTabOrganizationSettings) {
      add(
        MyOrganizationTabKey.orgSettings,
        Tab(
          icon: const Icon(Icons.settings_outlined),
          text: l10n.orgSettingsTitle,
        ),
        const OrganizationSettingsScreen(embedAppBar: true),
      );
    }

    if (tabs.isEmpty) {
      tabs.add(
        _OrgDeskTab(
          key: MyOrganizationTabKey.teamDashboard,
          tab: Tab(text: l10n.orgTeamDeskTitle),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.orgNoOrg, textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }

    var initialIndex = 0;
    final want = widget.initialTab;
    if (want != null) {
      final i = tabs.indexWhere((e) => e.key == want);
      if (i >= 0) initialIndex = i;
    }

    if (!mounted) return;
    setState(() {
      _tabs = tabs;
      _showInviteInAppBar = showInvite;
      _ctrl = TabController(
        length: tabs.length,
        vsync: this,
        initialIndex: initialIndex.clamp(0, tabs.length - 1),
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_loading || _ctrl == null) {
      return Scaffold(
        appBar: widget.embedAppBar
            ? null
            : AppBar(
                automaticallyImplyLeading: !widget.suppressImpliedLeading,
                title: Text(l10n.orgTeamDeskTitle),
              ),
        body: const Center(child: AppLogoLoading()),
      );
    }

    final tabBar = TabBar(
      controller: _ctrl,
      isScrollable: true,
      tabs: _tabs.map((e) => e.tab).toList(),
    );

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
              child: tabBar,
            ),
            Expanded(child: _orgDeskTabBody()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.suppressImpliedLeading,
        title: Text(l10n.orgTeamDeskTitle),
        actions: [
          if (_showInviteInAppBar)
            IconButton(
              tooltip: l10n.inviteMembersTitle,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () async {
                final ok =
                    await TeamMembershipGate.ensureCanOpenTeamInviteFlow(
                  context,
                  lang: widget.lang,
                  accountType: _accountType,
                  organizationId: _orgId,
                );
                if (!ok || !context.mounted) return;
                await showTeamInviteMemberDialog(context, svc: _svc);
                if (context.mounted) await _reload();
              },
            ),
          IconButton(
            tooltip: l10n.refreshLabel,
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
        bottom: tabBar,
      ),
      body: _orgDeskTabBody(),
    );
  }

  /// ويب: تبويب علوي واحد فقط — أخف وأسرع من بناء كل أجسام TabBarView معاً.
  Widget _orgDeskTabBody() {
    final ctrl = _ctrl;
    if (ctrl == null) return const SizedBox.shrink();
    if (kIsWeb) {
      return AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) {
          if (_tabs.isEmpty) return const SizedBox.shrink();
          final i = ctrl.index.clamp(0, _tabs.length - 1);
          return KeyedSubtree(
            key: ValueKey<String>('org-desk-$i'),
            child: _tabs[i].body,
          );
        },
      );
    }
    return TabBarView(
      controller: ctrl,
      children: _tabs.map((e) => e.body).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// لوحة الفريق — بطاقات + عمود نشاط + ترتيب
// ---------------------------------------------------------------------------

class _TeamDashboardBody extends StatefulWidget {
  const _TeamDashboardBody({
    required this.lang,
    required this.orgId,
    required this.isOwner,
  });

  final String lang;
  final String? orgId;
  final bool isOwner;

  @override
  State<_TeamDashboardBody> createState() => _TeamDashboardBodyState();
}

class _TeamDashboardBodyState extends State<_TeamDashboardBody> {
  final _svc = OrgTeamService(Supabase.instance.client);
  bool _loading = true;
  int _members = 0;
  int _pendingJoin = 0;
  int _totalProps = 0;
  int _totalAds = 0;
  List<Map<String, dynamic>> _memberRows = [];
  Map<String, Map<String, int>> _contrib = {};
  Map<String, int> _weekBar = {};

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final oid = widget.orgId;
    if (oid == null || oid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (widget.isOwner) {
      await _svc.ensureMyOrgUnit();
    }
    final used = await _svc.memberCount(oid);
    final pending = widget.isOwner ? await _svc.listPendingJoinRequests() : [];
    final members = await _svc.listMembers(oid);
    final contrib = await _svc.fetchOrgMemberContribution(oid);
    final log = await _svc.activityLog(oid, limit: 200);
    var tp = 0;
    var ta = 0;
    for (final c in contrib.values) {
      tp += c['properties'] ?? 0;
      ta += c['ads'] ?? 0;
    }
    final week = _sevenDayCounts(log);
    if (!mounted) return;
    setState(() {
      _members = used;
      _pendingJoin = pending.length;
      _memberRows = members;
      _contrib = contrib;
      _totalProps = tp;
      _totalAds = ta;
      _weekBar = week;
      _loading = false;
    });
  }

  Map<String, int> _sevenDayCounts(List<Map<String, dynamic>> log) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final keys = List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });
    final map = {for (final k in keys) k: 0};
    for (final r in log) {
      final dt = DateTime.tryParse('${r['created_at']}')?.toLocal();
      if (dt == null) continue;
      final k =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      if (map.containsKey(k)) map[k] = map[k]! + 1;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: AppLogoLoading());

    final barGroups = _weekBar.entries.toList();
    final maxY = barGroups.fold<int>(1, (m, e) => m > e.value ? m : e.value);

    final board = List<Map<String, dynamic>>.from(_memberRows);
    board.sort((a, b) {
      final ua = '${a['user_id']}';
      final ub = '${b['user_id']}';
      final sa = (_contrib[ua]?['properties'] ?? 0) + (_contrib[ua]?['ads'] ?? 0);
      final sb = (_contrib[ub]?['properties'] ?? 0) + (_contrib[ub]?['ads'] ?? 0);
      return sb.compareTo(sa);
    });

    return Scrollbar(
      thumbVisibility: MediaQuery.sizeOf(context).width >= 700,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _statCard(
                  cs,
                  Icons.groups_rounded,
                  t.orgStatActiveMembers,
                  '$_members',
                ),
                _statCard(
                  cs,
                  Icons.pending_actions_outlined,
                  t.orgStatPendingJoin,
                  '$_pendingJoin',
                ),
                _statCard(
                  cs,
                  Icons.apartment_rounded,
                  t.orgStatOrgListings,
                  '$_totalProps',
                ),
                _statCard(
                  cs,
                  Icons.campaign_outlined,
                  t.orgStatOrgAds,
                  '$_totalAds',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _isAr ? 'نشاط 7 أيام' : '7-day activity',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, m) {
                          final i = v.toInt();
                          if (i < 0 || i >= barGroups.length) {
                            return const SizedBox();
                          }
                          return Text(
                            barGroups[i].key.substring(8),
                            style: TextStyle(
                              fontSize: 9,
                              color:  cs.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < barGroups.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: barGroups[i].value.toDouble(),
                            width: 14,
                            borderRadius: BorderRadius.circular(4),
                            color: cs.primary,
                          ),
                        ],
                      ),
                  ],
                  maxY: maxY > 0 ? maxY * 1.15 : 4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              t.orgLeaderboardTitle,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...List.generate(board.length.clamp(0, 12), (i) {
              final m = board[i];
              final uid = '${m['user_id'] ?? ''}';
              final role = '${m['member_role'] ?? ''}';
              final prof =
                  (m['profile'] as Map?)?.cast<String, dynamic>() ?? {};
              final name = _isAr
                  ? '${prof['full_name_ar'] ?? prof['username'] ?? uid}'
                  : '${prof['full_name_en'] ?? prof['username'] ?? uid}';
              final c = _contrib[uid] ?? {};
              final props = c['properties'] ?? 0;
              final ads = c['ads'] ?? 0;
              Widget? medal;
              if (i == 0) {
                medal = Icon(Icons.emoji_events, color: Colors.amber.shade700);
              } else if (i == 1) {
                medal = Icon(Icons.emoji_events, color: Colors.blueGrey.shade400);
              } else if (i == 2) {
                medal = Icon(Icons.emoji_events, color: Colors.brown.shade400);
              }
              return Card(
                child: ListTile(
                  leading: medal ?? CircleAvatar(child: Text('${i + 1}')),
                  title: Text(name),
                  subtitle: Text(
                    role == 'owner'
                        ? (_isAr ? 'المالك' : 'Owner')
                        : '${t.orgLeaderboardProps}: $props · ${t.orgLeaderboardAds}: $ads',
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _statCard(ColorScheme cs, IconData icon, String label, String value) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// الصلاحيات — قائمة أعضاء + فتح شاشة التعديل
// ---------------------------------------------------------------------------

class _OrganizationRolesTab extends StatefulWidget {
  const _OrganizationRolesTab({required this.lang});

  final String lang;

  @override
  State<_OrganizationRolesTab> createState() => _OrganizationRolesTabState();
}

class _OrganizationRolesTabState extends State<_OrganizationRolesTab> {
  final _svc = OrgTeamService(Supabase.instance.client);
  bool _loading = true;
  List<Map<String, dynamic>> _members = [];

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ctx = await _svc.myOrgContext();
    final oid = ctx?['org_id']?.toString();
    if (oid == null || oid.isEmpty || ctx?['is_owner'] != true) {
      if (mounted) {
        setState(() {
          _loading = false;
          _members = [];
        });
      }
      return;
    }
    final members = await _svc.listMembers(oid);
    if (!mounted) return;
    setState(() {
      _members = members;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (_loading) return const Center(child: AppLogoLoading());
    final rows = _members
        .where((m) => '${m['member_role']}' != 'owner')
        .toList();
    if (rows.isEmpty) {
      return Center(child: Text(t.orgRolesPickMember));
    }
    return Scrollbar(
      thumbVisibility: MediaQuery.sizeOf(context).width >= 700,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final m = rows[i];
            final uid = '${m['user_id'] ?? ''}';
            final prof =
                (m['profile'] as Map?)?.cast<String, dynamic>() ?? {};
            final name = _isAr
                ? '${prof['full_name_ar'] ?? prof['username'] ?? uid}'
                : '${prof['full_name_en'] ?? prof['username'] ?? uid}';
            final perms =
                (m['permissions'] as Map?)?.cast<String, dynamic>() ?? {};
            return Card(
              child: ListTile(
                title: Text(name),
                subtitle: Text(
                  t.orgRolesEditPermissions,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AssignPermissionsScreen(
                          memberUserId: uid,
                          initial: perms,
                        ),
                      ),
                    ).then((_) => _load());
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
