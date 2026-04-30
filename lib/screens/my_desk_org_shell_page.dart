import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'org_desk_stats_page.dart';
import 'org_join_requests_desk_page.dart';
import 'org_monitor_dashboard_page.dart';
import 'org_team_chat_hub_page.dart';
import 'org_team_management_page.dart';

/// «إدارتي» لمكاتب/شركات/مؤسسات: مراقبة، دردشة الفريق، إدارة الفريق، طلبات الانضمام، ملخص.
class MyDeskOrgShellPage extends StatefulWidget {
  const MyDeskOrgShellPage({super.key, required this.lang});

  final String lang;

  @override
  State<MyDeskOrgShellPage> createState() => _MyDeskOrgShellPageState();
}

class _MyDeskOrgShellPageState extends State<MyDeskOrgShellPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navMyDesk),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabs: [
            Tab(
              icon: const Icon(Icons.analytics_outlined),
              text: l10n.deskTabMonitoring,
            ),
            Tab(
              icon: const Icon(Icons.chat_bubble_outline),
              text: l10n.deskTabTeamChat,
            ),
            Tab(
              icon: const Icon(Icons.groups_outlined),
              text: l10n.deskTabTeam,
            ),
            Tab(
              icon: const Icon(Icons.how_to_reg_outlined),
              text: l10n.deskTabJoinRequests,
            ),
            Tab(
              icon: const Icon(Icons.insights_outlined),
              text: l10n.deskTabInsights,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          const OrgMonitorDashboardPage(embedded: true),
          OrgTeamChatHubPage(lang: widget.lang),
          const OrgTeamManagementPage(embedded: true),
          OrgJoinRequestsDeskPage(lang: widget.lang),
          OrgDeskStatsPage(lang: widget.lang),
        ],
      ),
    );
  }
}
