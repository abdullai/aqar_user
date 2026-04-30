// lib/screens/marketer_dashboard_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session/web_session_ttl.dart';
import '../core/share/listing_deep_link.dart';
import '../core/utils/dashboard_greeting.dart';
import '../l10n/app_localizations.dart';
import '../routes.dart';
import '../services/marketing_flow_service.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';
import 'marketer_request_details_page.dart';
import 'org_join_requests_desk_page.dart';
import 'org_monitor_dashboard_page.dart';
import 'org_team_chat_hub_page.dart';
import 'org_team_management_page.dart';

/// لوحة المسوّق: دعوات أوضح + مركز عمل + تبويب «فريق العمل» عند الارتباط بمؤسسة.
class MarketerDashboardPage extends StatefulWidget {
  final String lang;
  const MarketerDashboardPage({super.key, required this.lang});

  @override
  State<MarketerDashboardPage> createState() => _MarketerDashboardPageState();
}

class _MarketerDashboardPageState extends State<MarketerDashboardPage>
    with SingleTickerProviderStateMixin {
  final _svc = MarketingFlowService(Supabase.instance.client);
  final _sb = Supabase.instance.client;

  late final TabController _tabCtrl;

  bool _loading = true;
  String? _err;
  List<Map<String, dynamic>> _invites = const [];
  Map<String, dynamic>? _orgCtx;
  Map<String, dynamic> _profileRow = const {};

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  bool get _hasOrgDesk {
    final id = (_orgCtx?['org_id'] ?? '').toString().trim();
    return id.isNotEmpty;
  }

  bool get _orgOwner => _orgCtx != null && _orgCtx!['is_owner'] == true;

  int get _pendingInvitesCount {
    return _invites.where((e) {
      final s = (e['status'] ?? '').toString().toLowerCase().trim();
      return s.isEmpty ||
          s == 'pending' ||
          s == 'sent' ||
          s == 'new' ||
          s == 'invited';
    }).length;
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    unawaited(touchWebSessionActivity());
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ListingDeepLink.openIfQueued(context, lang: widget.lang));
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final rows = await _svc.marketerInvites();
      final orgCtx = await OrgTeamService(_sb).myOrgContext();
      Map<String, dynamic> prof = {};
      try {
        final uid = _sb.auth.currentUser?.id;
        if (uid != null) {
          final r = await _sb
              .from('users_profiles')
              .select(
                'first_name_ar,second_name_ar,third_name_ar,fourth_name_ar,'
                'first_name_en,second_name_en,third_name_en,fourth_name_en,'
                'full_name_ar,full_name_en,full_name,username',
              )
              .eq('user_id', uid)
              .maybeSingle();
          if (r != null) prof = Map<String, dynamic>.from(r as Map);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _invites = rows;
        _orgCtx = orgCtx;
        _profileRow = prof;
      });
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _quadName() {
    String pick(dynamic v) => (v?.toString() ?? '').trim();
    if (_isAr) {
      final q = [
        pick(_profileRow['first_name_ar']),
        pick(_profileRow['second_name_ar']),
        pick(_profileRow['third_name_ar']),
        pick(_profileRow['fourth_name_ar']),
      ].where((s) => s.isNotEmpty).join(' ').trim();
      if (q.isNotEmpty) return q;
      final f = pick(_profileRow['full_name_ar']);
      if (f.isNotEmpty) return f;
    } else {
      final q = [
        pick(_profileRow['first_name_en']),
        pick(_profileRow['second_name_en']),
        pick(_profileRow['third_name_en']),
        pick(_profileRow['fourth_name_en']),
      ].where((s) => s.isNotEmpty).join(' ').trim();
      if (q.isNotEmpty) return q;
      final f = pick(_profileRow['full_name_en']);
      if (f.isNotEmpty) return f;
    }
    final full = pick(_profileRow['full_name']);
    if (full.isNotEmpty) return full;
    return pick(_profileRow['username']);
  }

  Map<String, dynamic>? _inviteRequestMap(Map<String, dynamic> inv) {
    final raw = inv['listing_requests'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  String _inviteTitleLine(Map<String, dynamic> inv) {
    final req = _inviteRequestMap(inv);
    final title = (req?['title'] ?? '').toString().trim();
    if (title.isNotEmpty) {
      return title;
    }
    final rid = (inv['request_id'] ?? '').toString();
    return _isAr ? 'طلب تسويق' : 'Marketing request';
  }

  String _inviteSubtitleLine(Map<String, dynamic> inv) {
    final req = _inviteRequestMap(inv);
    final city = (req?['city'] ?? '').toString().trim();
    final rid = (inv['request_id'] ?? '').toString();
    final shortId = rid.length > 8 ? '${rid.substring(0, 8)}…' : rid;
    final st = _statusLabel((inv['status'] ?? '').toString());
    if (city.isNotEmpty) {
      return _isAr ? '$city • $st • $shortId' : '$city • $st • $shortId';
    }
    return _isAr ? '$st • $shortId' : '$st • $shortId';
  }

  String _statusLabel(String raw) {
    final s = raw.trim().toLowerCase();
    if (_isAr) {
      return switch (s) {
        'pending' || '' => 'بانتظار الرد',
        'submitted' => 'تم الإرسال',
        'seen' => 'تمت المشاهدة',
        'accepted' => 'مقبولة',
        'approved' => 'معتمدة',
        'owner_accepted' || 'selected' => 'مقبولة من المالك',
        'owner_rejected' || 'rejected' => 'مرفوضة',
        'declined' => 'مرفوضة',
        'expired' => 'منتهية',
        'cancelled' || 'canceled' => 'ملغاة',
        'withdrawn' => 'مسحوبة',
        _ => s.isEmpty ? '—' : s,
      };
    }
    return s.isEmpty ? 'pending' : s;
  }

  Future<void> _openInviteDetail(String inviteId, String requestId) async {
    try {
      await _svc.markInviteSeen(inviteId);
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => MarketerRequestDetailsPage(
          lang: widget.lang,
          inviteId: inviteId,
          requestId: requestId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Widget _tabWithBadge(
      {required Widget icon, required String label, int count = 0}) {
    if (count <= 0) {
      return Tab(
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Tab(
      height: 52,
      child: Badge(
        backgroundColor: cs.error,
        label: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: cs.onError,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitesTab(AppLocalizations? t) {
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_err!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_invites.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Icon(
            Icons.mark_email_unread_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _isAr ? 'لا توجد دعوات حالياً' : 'No invitations yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _isAr
                ? 'عندما يدعوك مالك لطلب تسويق سيظهر الطلب هنا مع عنوانه ومدينته.'
                : 'When an owner invites you, the request appears here with title and city.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _invites.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final inv = _invites[i];
          final inviteId = (inv['id'] ?? '').toString();
          final requestId = (inv['request_id'] ?? '').toString();

          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.forward_to_inbox_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              _inviteTitleLine(inv),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(_inviteSubtitleLine(inv)),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => _openInviteDetail(inviteId, requestId),
          );
        },
      ),
    );
  }

  Widget _buildDeskHubTab(AppLocalizations? t) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Text(
          _isAr
              ? 'اختصارات العمل — عروضك والعقود والتصاريح تظهر أيضاً في «صفحتي».'
              : 'Shortcuts — your pipeline also appears under «My ads».',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.notifications_active_outlined,
                    color: cs.primary),
                title: Text(
                  t?.notificationsTitle ??
                      (_isAr ? 'التنبيهات' : 'Notifications'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _isAr
                      ? 'عروض، عقود، وتحديثات الطلبات'
                      : 'Offers, contracts, and request updates',
                ),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.inAppNotifications,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.insights_outlined, color: cs.primary),
                title: Text(
                  t?.marketInsightsTitle ??
                      (_isAr ? 'رؤى السوق' : 'Market insights'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _isAr ? 'مؤشرات من الخادم' : 'Server-driven market snapshot',
                ),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.marketInsights,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrgTeamTab(AppLocalizations? t) {
    final cs = Theme.of(context).colorScheme;
    if (!_hasOrgDesk) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.groups_outlined,
              size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            _isAr
                ? 'لا يوجد ارتباط بمؤسسة حالياً'
                : 'No organization linked yet',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            _isAr
                ? 'عند انضمامك لمكتب أو شركة عقارية ستظهر هنا: مراقبة الفريق، الدردشة الجماعية، إدارة الأعضاء، وطلبات الانضمام.'
                : 'When you join a real estate office or company, team monitoring, group chat, member management, and join requests appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
          ),
        ],
      );
    }

    String deskNote() {
      if (_orgOwner) {
        return _isAr
            ? 'أنت مالك المؤسسة — يمكنك إدارة الصلاحيات والأعضاء.'
            : 'You are the org owner — manage permissions and members.';
      }
      return _isAr
          ? 'أنت عضو في الفريق — حسب صلاحياتك تظهر لك الأقسام.'
          : 'You are a team member — sections follow your permissions.';
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Text(
          deskNote(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.analytics_outlined, color: cs.primary),
                title: Text(
                  t?.orgMonitoring ??
                      (_isAr ? 'مراقبة الفريق' : 'Team monitoring'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _isAr ? 'مؤشرات وأداء' : 'KPIs and activity',
                ),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const OrgMonitorDashboardPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.chat_bubble_outline, color: cs.primary),
                title: Text(
                  t?.deskTabTeamChat ?? (_isAr ? 'دردشة الفريق' : 'Team chat'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _isAr ? 'محادثة جماعية داخل المؤسسة' : 'Org group chat',
                ),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => OrgTeamChatHubPage(lang: widget.lang),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.groups_outlined, color: cs.primary),
                title: Text(
                  t?.orgTeamManagement ??
                      (_isAr ? 'إدارة الفريق' : 'Team management'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _isAr
                      ? 'أعضاء، صلاحيات، أجهزة'
                      : 'Members, permissions, devices',
                ),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const OrgTeamManagementPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.how_to_reg_outlined, color: cs.primary),
                title: Text(
                  t?.deskTabJoinRequests ??
                      (_isAr ? 'طلبات الانضمام' : 'Join requests'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _isAr
                      ? 'موافقة طلبات الانضمام للمؤسسة'
                      : 'Approve org join requests',
                ),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          OrgJoinRequestsDeskPage(lang: widget.lang),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final salute = DashboardGreeting.salutationOnly(isAr: _isAr);
    final partner = _isAr ? 'شريكنا العقاري' : 'our real estate partner';
    final line1 = '$salute، $partner';
    final name = _quadName();

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: LayoutBuilder(
            builder: (ctx, c) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    line1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (name.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment:
                          _isAr ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: c.maxWidth),
                        child: Text(
                          name,
                          maxLines: 1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          actions: [
            IconButton(
              tooltip: t?.notificationsTitle,
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.inAppNotifications,
              ),
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _tabWithBadge(
                icon: const Icon(Icons.mark_email_unread_outlined, size: 20),
                label: t?.marketerTabInvites ??
                    (_isAr ? '🏢 السوق العقاري' : 'Real estate market'),
                count: _pendingInvitesCount,
              ),
              _tabWithBadge(
                icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
                label: _isAr ? 'مركز العمل' : 'Desk',
              ),
              _tabWithBadge(
                icon: const Icon(Icons.groups_outlined, size: 20),
                label: _isAr ? 'فريق العمل' : 'Team',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildInvitesTab(t),
            _buildDeskHubTab(t),
            _buildOrgTeamTab(t),
          ],
        ),
      ),
    );
  }
}
