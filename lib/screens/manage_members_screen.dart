import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../core/session/account_role_cache.dart';
import '../services/chat_inbox_service.dart';
import '../services/org_team_service.dart';
import '../widgets/team_membership_gate.dart';
import '../widgets/app_logo_loading.dart';
import 'assign_permissions_screen.dart';
import '../widgets/team_invite_member_dialog.dart';

/// إدارة الأعضاء (نشطون، محظورون، مغادرون، طلبات خروج) — للمالك.
class ManageMembersScreen extends StatefulWidget {
  const ManageMembersScreen({super.key});

  @override
  State<ManageMembersScreen> createState() => _ManageMembersScreenState();
}

class _ManageMembersScreenState extends State<ManageMembersScreen>
    with SingleTickerProviderStateMixin {
  final _svc = OrgTeamService(Supabase.instance.client);
  late TabController _tabs;

  String? _orgId;
  bool _loading = true;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _banned = [];
  List<Map<String, dynamic>> _alumni = [];
  List<Map<String, dynamic>> _leaves = [];
  List<Map<String, dynamic>> _chatSuspensions = [];
  Map<String, String> _lastActivity = {};
  bool _platformStaff = false;

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ctx = await _svc.myOrgContext();
    final oid = ctx?['org_id']?.toString();
    final owner = ctx?['is_owner'] == true;
    if (!owner || oid == null || oid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _orgId = oid;
    final staff = await _svc.isPlatformStaffUser();
    final members = await _svc.listMembers(oid);
    final uids = members
        .map((m) => '${m['user_id'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toList();
    _lastActivity = await _svc.fetchLatestActivitySummaryByUserIds(oid, uids);
    final sb = Supabase.instance.client;
    List<Map<String, dynamic>> banned = [];
    List<Map<String, dynamic>> alumni = [];
    List<Map<String, dynamic>> leaves = [];
    try {
      final b = await sb.from('org_banned_users').select().eq('org_id', oid);
      banned = (b as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    try {
      final a = await sb.from('org_member_alumni').select().eq('org_id', oid);
      alumni = (a as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    try {
      final l = await sb
          .from('org_leave_requests')
          .select()
          .eq('org_id', oid)
          .eq('status', 'pending');
      leaves = (l as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    List<Map<String, dynamic>> chatSuspensions = [];
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final s = await sb
          .from('org_chat_member_suspensions')
          .select(
            'id, user_id, suspended_until, suspended_by, reason, created_at',
          )
          .eq('org_id', oid)
          .gt('suspended_until', nowIso)
          .order('suspended_until', ascending: true);
      chatSuspensions = (s as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _members = members;
      _banned = banned;
      _alumni = alumni;
      _leaves = leaves;
      _chatSuspensions = chatSuspensions;
      _platformStaff = staff;
      _loading = false;
    });
  }

  Future<void> _platformBanMember(
    BuildContext context,
    String uid,
    String displayName,
  ) async {
    final reason = TextEditingController();
    var canJoin = true;
    var blocksApp = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: Text(_isAr ? 'تعطيل حساب (منصّة)' : 'Platform account ban'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  AqarTextField(
                    controller: reason,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: _isAr ? 'السبب' : 'Reason',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _isAr
                          ? 'السماح بطلب انضمام لمؤسسات أخرى'
                          : 'Allow join requests to other orgs',
                    ),
                    value: canJoin,
                    onChanged: (v) => setS(() => canJoin = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _isAr
                          ? 'حظر استخدام التطبيق بالكامل'
                          : 'Block full app usage',
                    ),
                    value: blocksApp,
                    onChanged: (v) => setS(() => blocksApp = v),
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
                child: Text(_isAr ? 'تأكيد' : 'Confirm'),
              ),
            ],
          );
        },
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAr ? 'أدخل سبباً' : 'Enter a reason')),
      );
      return;
    }
    final res = await _svc.platformStaffBanUser(
      userId: uid,
      reason: text,
      canJoinOtherOrgs: canJoin,
      blocksApp: blocksApp,
    );
    if (res['ok'] == true) {
      await _svc.platformStaffTerminateSessions(uid);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true
              ? (_isAr ? 'تم تسجيل الحظر' : 'Ban recorded')
              : '${res['error']}',
        ),
      ),
    );
  }

  Map<String, dynamic>? _activeChatSuspensionFor(String userId) {
    final uid = userId.trim();
    for (final row in _chatSuspensions) {
      if ('${row['user_id']}' == uid) return row;
    }
    return null;
  }

  String _memberDisplayName(Map<String, dynamic> m, String uid) {
    final prof = (m['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    if (_isAr) {
      return '${prof['full_name_ar'] ?? prof['username'] ?? uid}';
    }
    return '${prof['full_name_en'] ?? prof['username'] ?? uid}';
  }

  String _formatSuspendedUntil(dynamic raw) {
    final dt = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final d = dt.day;
    final mo = dt.month;
    if (_isAr) {
      return 'حتى $d/$mo $h:$min';
    }
    return 'Until $d/$mo $h:$min';
  }

  Future<void> _suspendMemberFromTeamChat(
    BuildContext context,
    String uid,
    String displayName,
  ) async {
    final reason = TextEditingController();
    var hours = 24;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: Text(
              _isAr ? 'إيقاف مؤقت عن دردشة الفريق' : 'Temporary team chat suspension',
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAr
                        ? 'لن يرى العضو قناة الفريق حتى انتهاء المدة. يبقى عضواً في المنشأة.'
                        : 'Member will not see the team channel until expiry. Org membership stays active.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _isAr ? 'المدة' : 'Duration',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final opt in <(int, String)>[
                        (24, _isAr ? '24 ساعة' : '24 hours'),
                        (48, _isAr ? '48 ساعة' : '48 hours'),
                        (168, _isAr ? '7 أيام' : '7 days'),
                      ])
                        ChoiceChip(
                          label: Text(opt.$2),
                          selected: hours == opt.$1,
                          onSelected: (_) => setS(() => hours = opt.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AqarTextField(
                    controller: reason,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _isAr ? 'سبب (اختياري)' : 'Reason (optional)',
                      border: const OutlineInputBorder(),
                      isDense: true,
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
                child: Text(_isAr ? 'إيقاف' : 'Suspend'),
              ),
            ],
          );
        },
      ),
    );
    final reasonText = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted || _orgId == null) return;
    try {
      await ChatInboxService(Supabase.instance.client).adminSuspendOrgChatMember(
        orgId: _orgId!,
        userId: uid,
        hours: hours,
        reason: reasonText.isEmpty ? null : reasonText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'تم إيقاف العضو عن دردشة الفريق'
                : 'Member suspended from team chat',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _unsuspendMemberFromTeamChat(String uid) async {
    if (_orgId == null) return;
    try {
      await ChatInboxService(Supabase.instance.client)
          .adminUnsuspendOrgChatMember(orgId: _orgId!, userId: uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr ? 'تم فك إيقاف الدردشة' : 'Chat suspension lifted',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget _chatSuspensionBadge(Map<String, dynamic> suspension) {
    final until = _formatSuspendedUntil(suspension['suspended_until']);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            Icons.speaker_notes_off_outlined,
            size: 14,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _isAr ? 'موقوف عن دردشة الفريق $until' : 'Team chat suspended $until',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final ctx = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: AppLogoLoading());
    if (_orgId == null) {
      return Center(
        child: Text(_isAr ? 'غير مصرّح' : 'Not authorized'),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                final accountType =
                    AccountRoleCache.snapshot?.accountType ?? 'office';
                final ok = await TeamMembershipGate.ensureCanOpenTeamInviteFlow(
                  context,
                  lang: langNotifier.value,
                  accountType: accountType,
                  organizationId: _orgId,
                );
                if (!ok || !mounted) return;
                await showTeamInviteMemberDialog(context, svc: _svc);
                if (mounted) await _load();
              },
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(_isAr ? 'إضافة عضو' : 'Add member'),
            ),
          ),
        ),
        Material(
          color: ctx.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: [
              Tab(text: t.tabActiveMembers),
              Tab(text: t.tabBanned),
              Tab(text: t.tabAlumni),
              Tab(text: t.tabLeaveRequests),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_isAr ? 'إيقاف الدردشة' : 'Chat suspended'),
                    if (_chatSuspensions.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: ctx.error,
                        child: Text(
                          '${_chatSuspensions.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _members.length,
                  itemBuilder: (_, i) {
                    final m = _members[i];
                    final uid = '${m['user_id']}';
                    final role = '${m['member_role']}';
                    if (role == 'owner') {
                      return ListTile(
                        title: Text(_isAr ? 'المالك' : 'Owner'),
                        subtitle: const Text('—'),
                      );
                    }
                    final prof =
                        (m['profile'] as Map?)?.cast<String, dynamic>() ?? {};
                    final name = _isAr
                        ? '${prof['full_name_ar'] ?? prof['username'] ?? uid}'
                        : '${prof['full_name_en'] ?? prof['username'] ?? uid}';
                    final perms =
                        (m['permissions'] as Map?)?.cast<String, dynamic>() ??
                            {};
                    final hint = _lastActivity[uid];
                    final chatSusp = _activeChatSuspensionFor(uid);
                    final chatSuspended = chatSusp != null;
                    return Card(
                      child: ListTile(
                        title: Text(name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              perms.entries
                                  .where((e) => e.value == true)
                                  .map((e) => e.key)
                                  .take(4)
                                  .join(', '),
                            ),
                            if (hint != null && hint.isNotEmpty)
                              Text(
                                '${t.orgMemberLastActivity}: $hint',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ctx.onSurfaceVariant,
                                ),
                              ),
                            if (chatSuspended) _chatSuspensionBadge(chatSusp),
                          ],
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: Icon(
                                chatSuspended
                                    ? Icons.forum_outlined
                                    : Icons.speaker_notes_off_outlined,
                              ),
                              tooltip: chatSuspended
                                  ? (_isAr
                                      ? 'فك إيقاف الدردشة'
                                      : 'Lift chat suspension')
                                  : (_isAr
                                      ? 'إيقاف عن دردشة الفريق'
                                      : 'Suspend from team chat'),
                              onPressed: () async {
                                if (chatSuspended) {
                                  await _unsuspendMemberFromTeamChat(uid);
                                } else {
                                  await _suspendMemberFromTeamChat(
                                    context,
                                    uid,
                                    name,
                                  );
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () {
                                Navigator.push(
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
                            if (_platformStaff)
                              IconButton(
                                icon: const Icon(Icons.gavel_outlined),
                                tooltip: _isAr
                                    ? 'تعطيل حساب المنصّة'
                                    : 'Platform suspend',
                                onPressed: () =>
                                    _platformBanMember(context, uid, name),
                              ),
                            IconButton(
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: () async {
                                await _svc.ownerRemoveMember(uid);
                                if (mounted) await _load();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _banned.length,
                itemBuilder: (_, i) {
                  final r = _banned[i];
                  final uid = '${r['user_id']}';
                  return Card(
                    child: ListTile(
                      title: Text(uid),
                      subtitle: Text('${r['reason'] ?? ''}'),
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          await _svc.ownerUnbanUser(uid);
                          if (mounted) await _load();
                        },
                        child: Text(_isAr ? 'فك' : 'Unban'),
                      ),
                    ),
                  );
                },
              ),
              ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _alumni.length,
                itemBuilder: (_, i) {
                  final r = _alumni[i];
                  final id = '${r['id']}';
                  return Card(
                    child: ListTile(
                      title: Text('${r['user_id']}'),
                      subtitle: Text('${r['left_at']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _svc.ownerRemoveAlumniRow(id);
                          if (mounted) await _load();
                        },
                      ),
                    ),
                  );
                },
              ),
              ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _leaves.length,
                itemBuilder: (_, i) {
                  final r = _leaves[i];
                  final id = '${r['id']}';
                  return Card(
                    child: ListTile(
                      title: Text('${r['user_id']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: () async {
                              await _svc.decideLeaveRequest(
                                requestId: id,
                                approve: true,
                              );
                              if (mounted) await _load();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            onPressed: () async {
                              await _svc.decideLeaveRequest(
                                requestId: id,
                                approve: false,
                              );
                              if (mounted) await _load();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              RefreshIndicator(
                onRefresh: _load,
                child: _chatSuspensions.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 48,
                            color: ctx.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isAr
                                ? 'لا يوجد أعضاء موقوفون عن دردشة الفريق.'
                                : 'No active team chat suspensions.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ctx.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _chatSuspensions.length,
                        itemBuilder: (_, i) {
                          final row = _chatSuspensions[i];
                          final uid = '${row['user_id']}';
                          final member = _members.cast<Map<String, dynamic>?>().firstWhere(
                                (m) => m != null && '${m['user_id']}' == uid,
                                orElse: () => null,
                              );
                          final name = member != null
                              ? _memberDisplayName(member, uid)
                              : uid;
                          final reason =
                              (row['reason'] ?? '').toString().trim();
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    ctx.errorContainer.withValues(alpha: 0.5),
                                child: Icon(
                                  Icons.speaker_notes_off_outlined,
                                  color: ctx.error,
                                ),
                              ),
                              title: Text(name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatSuspendedUntil(
                                      row['suspended_until'],
                                    ),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: ctx.error,
                                    ),
                                  ),
                                  if (reason.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(reason),
                                    ),
                                ],
                              ),
                              trailing: FilledButton.tonal(
                                onPressed: () =>
                                    _unsuspendMemberFromTeamChat(uid),
                                child: Text(_isAr ? 'فك الإيقاف' : 'Lift'),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
