import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier, themeModeNotifier;
import '../core/session/account_role_cache.dart';
import '../services/org_team_service.dart';
import '../widgets/team_membership_gate.dart';
import '../widgets/team_invite_member_dialog.dart';
import '../widgets/app_logo_loading.dart';

/// إدارة فريق المؤسسة (صاحب مكتب/مؤسسة/شركة فقط).
class OrgTeamManagementPage extends StatefulWidget {
  const OrgTeamManagementPage({super.key, this.embedded = false});

  /// عند `true` يُعرض المحتوى فقط (للتضمين داخل [TabBarView] في «إدارتي»).
  final bool embedded;

  @override
  State<OrgTeamManagementPage> createState() => _OrgTeamManagementPageState();
}

class _OrgTeamManagementPageState extends State<OrgTeamManagementPage> {
  final _svc = OrgTeamService(Supabase.instance.client);
  bool _loading = true;
  bool _busy = false;
  String? _errorKey;
  Map<String, dynamic>? _org;
  List<Map<String, dynamic>> _members = [];
  int _used = 0;
  int _limit = 0;

  final Map<String, List<Map<String, dynamic>>> _devicesCache = {};
  final Map<String, bool> _permSaving = {};

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    final ctx = await _svc.myOrgContext();
    if (ctx == null || ctx['is_owner'] != true) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorKey = 'not_owner';
        });
      }
      return;
    }
    await _svc.ensureMyOrgUnit();
    final org = await _svc.orgUnitForOwner();
    if (org == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorKey = 'no_org';
        });
      }
      return;
    }
    final id = '${org['id']}';
    final used = await _svc.memberCount(id);
    final lim = await _svc.effectiveSeatLimit(id);
    final members = await _svc.listMembers(id);
    if (!mounted) return;
    setState(() {
      _org = org;
      _used = used;
      _limit = lim;
      _members = members;
      _loading = false;
    });
  }

  Future<void> _loadDevices(String userId) async {
    if (_devicesCache.containsKey(userId)) return;
    final list = await _svc.listTrustedDevicesForUser(userId);
    if (!mounted) return;
    setState(() => _devicesCache[userId] = list);
  }

  Future<void> _savePermissions(
    String memberUserId,
    String jsonRaw,
    AppLocalizations t,
  ) async {
    final m = OrgTeamService.parsePermissionsJson(jsonRaw);
    if (m == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr ? 'JSON غير صالح' : 'Invalid JSON'),
        ),
      );
      return;
    }
    setState(() => _permSaving[memberUserId] = true);
    try {
      await _svc.updateMemberPermissions(
        memberUserId: memberUserId,
        permissions: m,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            langNotifier.value == 'ar' ? 'تم حفظ الصلاحيات' : 'Permissions saved',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.orgInviteFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _permSaving[memberUserId] = false);
      }
    }
  }

  String _permissionsToJsonString(dynamic p) {
    if (p == null) return '{}';
    if (p is Map) {
      try {
        return const JsonEncoder.withIndent('  ').convert(p);
      } catch (_) {
        return '{}';
      }
    }
    final s = p.toString();
    return s.isEmpty ? '{}' : s;
  }

  Future<void> _revokeDevice(String memberUserId, String fp, AppLocalizations t) async {
    final ok = await _svc.ownerRevokeMemberDevice(
      memberUserId: memberUserId,
      fingerprint: fp,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? t.orgDeviceRevoked : t.orgInviteFailed)),
    );
    _devicesCache.remove(memberUserId);
    await _loadDevices(memberUserId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, _, __) {
        final body = _loading
                ? const Center(child: AppLogoLoading())
                : _errorKey != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _errorKey == 'not_owner'
                                ? t.orgOwnerOnly
                                : t.orgNoOrg,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              t.orgSeatUsage(_used, _limit),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            if (_limit > 0) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: (_used / _limit).clamp(0.0, 1.0),
                                  minHeight: 10,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              '${_isAr ? 'نوع الحساب' : 'Account type'}: ${_org?['account_type'] ?? '—'}',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final ok =
                                          await TeamMembershipGate
                                              .ensureCanOpenTeamInviteFlow(
                                        context,
                                        lang: langNotifier.value,
                                        accountType: AccountRoleCache
                                                .snapshot?.accountType ??
                                            'office',
                                        organizationId: '${_org?['id']}',
                                      );
                                      if (!ok || !mounted) return;
                                      final sent = await showTeamInviteMemberDialog(
                                        context,
                                        svc: _svc,
                                      );
                                      if (sent == true) await _reload();
                                    },
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              label: Text(_isAr ? 'إضافة عضو' : 'Add member'),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              t.orgMembersTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._members.map((m) => _memberTile(m, t)),
                          ],
                        ),
                      );

        return Directionality(
          textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
          child: widget.embedded
              ? body
              : Scaffold(
                  appBar: AppBar(
                    title: Text(t.orgTeamManagement),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loading ? null : _reload,
                      ),
                    ],
                  ),
                  body: body,
                ),
        );
      },
    );
  }

  bool _profileShowsVerified(Map<String, dynamic> prof) {
    final ver = '${prof['verification_status'] ?? ''}'.toLowerCase();
    final hasLic = '${prof['license_no'] ?? ''}'.trim().isNotEmpty;
    final hasRega = prof['rega_fal_snapshot'] != null;
    return hasRega || (ver == 'approved' && hasLic);
  }

  Widget _memberTile(Map<String, dynamic> m, AppLocalizations t) {
    final uid = '${m['user_id']}';
    final role = '${m['member_role']}'.trim();
    final prof = (m['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    final uname = '${prof['username'] ?? ''}'.trim();
    final phone = '${prof['phone'] ?? ''}'.trim();
    final st = '${m['status'] ?? ''}'.trim().toLowerCase();
    var name = _isAr
        ? '${prof['full_name_ar'] ?? ''}'.trim()
        : '${prof['full_name_en'] ?? ''}'.trim();
    if (name.isEmpty) name = uname;
    if (name.isEmpty) name = phone;
    if (name.isEmpty) {
      name = uid.length > 14 ? '${uid.substring(0, 12)}…' : uid;
    }
    final isOwner = role == 'owner';

    final subParts = <String>[
      if (role.isNotEmpty && role != 'null') role,
      if (uname.isNotEmpty) '@$uname',
      if (phone.isNotEmpty) phone,
      if (st.isNotEmpty && st != 'active')
        (_isAr ? 'الحالة: $st' : 'Status: $st'),
    ];
    final subtitle = subParts.isEmpty ? uid : subParts.join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(child: Text(name)),
            if (_profileShowsVerified(prof))
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: _isAr ? 0 : 8,
                  end: _isAr ? 8 : 0,
                ),
                child: Chip(
                  avatar: const Icon(Icons.verified, size: 16),
                  label: Text(t.badgeVerifiedShort),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        subtitle: Text(
          subtitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        onExpansionChanged: (open) {
          if (open && !isOwner) _loadDevices(uid);
        },
        children: [
          if (isOwner)
            ListTile(
              title: Text(_isAr ? 'صاحب المؤسسة' : 'Organization owner'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _isAr ? 'صلاحيات (JSON)' : 'Permissions (JSON)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _MemberPermEditor(
                initialJson: _permissionsToJsonString(m['permissions']),
                saving: _permSaving[uid] ?? false,
                onSave: (raw) => _savePermissions(uid, raw, t),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                t.orgDevicesTitle,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ...(_devicesCache[uid] ?? const [])
                .where((d) => d['revoked_at'] == null)
                .map(
                  (d) => ListTile(
                    dense: true,
                    title: Text(
                      '${d['platform'] ?? ''} ${d['model_label'] ?? ''}'.trim(),
                    ),
                    subtitle: Text(
                      '${d['device_fingerprint']}'.length > 24
                          ? '${'${d['device_fingerprint']}'.substring(0, 24)}…'
                          : '${d['device_fingerprint']}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _revokeDevice(
                        uid,
                        '${d['device_fingerprint']}',
                        t,
                      ),
                      child: Text(t.orgRemoveDevice),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _MemberPermEditor extends StatefulWidget {
  final String initialJson;
  final bool saving;
  final void Function(String raw) onSave;

  const _MemberPermEditor({
    required this.initialJson,
    required this.saving,
    required this.onSave,
  });

  @override
  State<_MemberPermEditor> createState() => _MemberPermEditorState();
}

class _MemberPermEditorState extends State<_MemberPermEditor> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialJson);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AqarTextField(
          controller: _c,
          maxLines: 4,
          decoration: const InputDecoration(
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: widget.saving ? null : () => widget.onSave(_c.text.trim()),
          child: widget.saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: AppLogoLoading(compact: true, size: 20),
                )
              : Text(MaterialLocalizations.of(context).saveButtonLabel),
        ),
      ],
    );
  }
}
