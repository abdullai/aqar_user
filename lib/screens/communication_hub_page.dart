import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/marketing_flow_service.dart';
import '../widgets/app_page_close_button.dart';
import 'chat_page.dart';
import 'in_app_notifications_page.dart';

/// مركز واحد من أيقونة الجرس: صندوق الإشعار + مدخل صندوق المحادثات.
///
/// [hideLeadingBecauseShellHasBack] عند `true` (مثلاً داخل لوحة عريضة حيث زر الرجوع
/// في [AppBar] الخارجي): لا يُعرض سهم رجوع ثانٍ هنا.
class CommunicationHubPage extends StatefulWidget {
  final String lang;
  final bool isAr;
  final bool hideLeadingBecauseShellHasBack;

  const CommunicationHubPage({
    super.key,
    required this.lang,
    required this.isAr,
    this.hideLeadingBecauseShellHasBack = false,
  });

  @override
  State<CommunicationHubPage> createState() => _CommunicationHubPageState();
}

class _CommunicationHubPageState extends State<CommunicationHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  int _inboxUnread = 0;
  int _chatUnread = 0;
  int _campaignUnread = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!mounted) return;
        if (!_tabCtrl.indexIsChanging) setState(() {});
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshBadges());
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshBadges() async {
    await _refreshInboxUnreadBadge();
    await _refreshChatUnreadBadge();
  }

  Future<void> _refreshInboxUnreadBadge() async {
    try {
      final rows = await MarketingFlowService(Supabase.instance.client)
          .myInAppNotificationsInbox();
      if (mounted) {
        setState(() {
          _inboxUnread =
              rows.where(MarketingFlowService.countsForGeneralInboxBadge).length;
          _campaignUnread =
              rows.where(MarketingFlowService.countsForCampaignInboxBadge).length;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _inboxUnread = 0;
          _campaignUnread = 0;
        });
      }
    }
  }

  Future<void> _refreshChatUnreadBadge() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'get_chat_list2',
        params: {'p_limit': 80, 'p_archived_only': false},
      );
      final list = (res is List) ? res : <dynamic>[];
      var sum = 0;
      for (final e in list) {
        if (e is! Map) continue;
        final u = e['unread_count'];
        if (u is int) sum += u;
        if (u is num) sum += u.toInt();
      }
      if (mounted) setState(() => _chatUnread = sum);
    } catch (_) {
      if (mounted) setState(() => _chatUnread = 0);
    }
  }

  Widget _outerTabLabel(
    String title, {
    required bool showUnreadBadge,
    int? badgeCount,
  }) {
    final n = badgeCount ?? _inboxUnread;
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (showUnreadBadge && n > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                n > 99 ? '99+' : '$n',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  height: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabBarMaterial(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 0,
      child: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          _outerTabLabel(
            l10n.communicationHubNotificationsTab,
            showUnreadBadge: true,
          ),
          _outerTabLabel(
            l10n.communicationHubChatsTab,
            showUnreadBadge: true,
            badgeCount: _chatUnread,
          ),
          _outerTabLabel(
            l10n.communicationHubCampaignsTab,
            showUnreadBadge: true,
            badgeCount: _campaignUnread,
          ),
        ],
      ),
    );
  }

  Widget _hubBody(BuildContext context) {
    // ويب: ابن واحد فقط — تبديل التبويب العلوي فوري وأخف (لا بناء إشعارات+دردشة معاً).
    if (kIsWeb) {
      return AnimatedBuilder(
        animation: _tabCtrl,
        builder: (context, _) {
          final i = _tabCtrl.index.clamp(0, 2);
          if (i == 0) {
            return KeyedSubtree(
              key: const ValueKey('hub-inbox'),
              child: InAppNotificationsPage(
                lang: widget.lang,
                embedMode: true,
                onInboxSurfaceChanged: _refreshBadges,
              ),
            );
          }
          if (i == 2) {
            return KeyedSubtree(
              key: const ValueKey('hub-campaigns'),
              child: InAppNotificationsPage(
                lang: widget.lang,
                embedMode: true,
                campaignsOnly: true,
                onInboxSurfaceChanged: _refreshBadges,
              ),
            );
          }
          return KeyedSubtree(
            key: const ValueKey('hub-chats'),
            child: ChatPage(
              isAr: widget.isAr,
              embedInParentDashboardShell: true,
              onInboxSurfaceChanged: _refreshBadges,
            ),
          );
        },
      );
    }
    return TabBarView(
      controller: _tabCtrl,
      children: [
        InAppNotificationsPage(
          lang: widget.lang,
          embedMode: true,
          onInboxSurfaceChanged: _refreshBadges,
        ),
        ChatPage(
          isAr: widget.isAr,
          embedInParentDashboardShell: true,
          onInboxSurfaceChanged: _refreshBadges,
        ),
        InAppNotificationsPage(
          lang: widget.lang,
          embedMode: true,
          campaignsOnly: true,
          onInboxSurfaceChanged: _refreshBadges,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final td = widget.isAr ? TextDirection.rtl : TextDirection.ltr;
    final hideLeading = widget.hideLeadingBecauseShellHasBack;

    if (hideLeading) {
      return Directionality(
        textDirection: td,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tabBarMaterial(context),
              Expanded(child: _hubBody(context)),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: td,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: (!widget.hideLeadingBecauseShellHasBack &&
                  Navigator.canPop(context))
              ? AppPageCloseButton(
                  isArabic: widget.isAr,
                )
              : null,
          title: Text(l10n.communicationHubTitle),
          bottom: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _outerTabLabel(
                l10n.communicationHubNotificationsTab,
                showUnreadBadge: true,
              ),
              _outerTabLabel(
                l10n.communicationHubChatsTab,
                showUnreadBadge: true,
                badgeCount: _chatUnread,
              ),
              _outerTabLabel(
                l10n.communicationHubCampaignsTab,
                showUnreadBadge: true,
                badgeCount: _campaignUnread,
              ),
            ],
          ),
        ),
        body: _hubBody(context),
      ),
    );
  }
}
