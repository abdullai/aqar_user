// lib/screens/marketer_dashboard_page.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session/web_session_ttl.dart';
import '../theme.dart';
import '../core/share/listing_deep_link.dart';
import '../core/utils/dashboard_greeting.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';
import 'org_join_requests_desk_page.dart';
import 'org_monitor_dashboard_page.dart';
import 'org_team_chat_hub_page.dart';
import 'org_team_management_page.dart';

/// لوحة «إدارتي» للمسوّق: **فريق العمل ومركز العمل** فقط.
/// السوق العقاري والدعوات والعروض والتعاقد — من تبويب **صفحتي** في الشريط السفلي.
class MarketerDashboardPage extends StatefulWidget {
  final String lang;

  /// عند `true`: لا يُعرض سهم الرجوع هنا لأن شريط اللوحة الخارجي يوفّر الرجوع (عرض عريض).
  final bool suppressImpliedLeading;

  const MarketerDashboardPage({
    super.key,
    required this.lang,
    this.suppressImpliedLeading = false,
  });

  @override
  State<MarketerDashboardPage> createState() => _MarketerDashboardPageState();
}

class _MarketerDashboardPageState extends State<MarketerDashboardPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  late final TabController _tabCtrl;

  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _orgCtx;
  Map<String, dynamic> _profileRow = const {};

  bool get _isAr => langNotifier.value != 'en';

  bool get _hasOrgDesk {
    final id = (_orgCtx?['org_id'] ?? '').toString().trim();
    return id.isNotEmpty;
  }

  bool get _orgOwner => _orgCtx != null && _orgCtx!['is_owner'] == true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
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

  Widget _buildDeskHubTab() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      physics: kIsWeb && AqarScrollBehavior.isCompactTouchLike(context)
          ? const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            )
          : const AlwaysScrollableScrollPhysics(),
      children: [
        Card(
          elevation: 0,
          color: cs.primaryContainer.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.list_alt_rounded, color: cs.primary, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isAr
                            ? 'السوق العقاري وطلبات التسويق'
                            : 'Real estate market & requests',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isAr
                            ? 'دعوات المالك، إتمام الصفقات، التعاقد، التصاريح، والمنشور — كلها من تبويب «صفحتي» في الشريط السفلي، وليس من إدارتي.'
                            : 'Owner invites, deals, contracting, permits, and publishing are under «My page» in the bottom bar — not in My desk.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isAr
              ? 'هنا تركز «إدارتي» على عمل المؤسسة والفريق فقط.'
              : 'My desk here focuses on organization and team work only.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
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
          Icon(
            Icons.groups_outlined,
            size: 56,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
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
      physics: kIsWeb && AqarScrollBehavior.isCompactTouchLike(context)
          ? const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            )
          : const AlwaysScrollableScrollPhysics(),
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
    final mqW = MediaQuery.sizeOf(context).width;
    final rawName = _quadName();
    final name = rawName.isEmpty
        ? ''
        : DashboardGreeting.displayNameForAppBar(
            rawName,
            compact: mqW < 480,
          );

    if (_loading) {
      return Directionality(
        textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.suppressImpliedLeading,
            title: Text(_isAr ? 'إدارتي' : 'My desk'),
          ),
          body: const Center(child: AppLogoLoading()),
        ),
      );
    }
    if (_err != null) {
      return Directionality(
        textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.suppressImpliedLeading,
            title: Text(_isAr ? 'إدارتي' : 'My desk'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_err!, textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.suppressImpliedLeading,
          toolbarHeight: 72,
          title: LayoutBuilder(
            builder: (ctx, c) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    salute,
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
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          bottom: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                height: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.dashboard_customize_outlined,
                        size: 20, color: cs.primary),
                    const SizedBox(height: 2),
                    Text(
                      _isAr ? 'مركز العمل' : 'Desk',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Tab(
                height: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.groups_outlined, size: 20),
                    const SizedBox(height: 2),
                    Text(
                      _isAr ? 'فريق العمل' : 'Team',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildDeskHubTab(),
            _buildOrgTeamTab(t),
          ],
        ),
      ),
    );
  }
}
