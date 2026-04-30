import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/users_profiles_safe_select.dart';
import '../l10n/app_localizations.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';

/// تبويب مخصّص لطلبات الانضمام (للمالك؛ يظهر للعضو رسالة توجيهية).
class OrgJoinRequestsDeskPage extends StatefulWidget {
  const OrgJoinRequestsDeskPage({super.key, required this.lang});

  final String lang;

  @override
  State<OrgJoinRequestsDeskPage> createState() => _OrgJoinRequestsDeskPageState();
}

class _OrgJoinRequestsDeskPageState extends State<OrgJoinRequestsDeskPage> {
  final _svc = OrgTeamService(Supabase.instance.client);

  bool _loading = true;
  bool _isOwner = false;
  List<Map<String, dynamic>> _pending = [];
  bool _joinBusy = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<List<Map<String, dynamic>>> _enrichJoinProfiles(
    List<Map<String, dynamic>> raw,
  ) async {
    final out = <Map<String, dynamic>>[];
    for (final row in raw) {
      final m = Map<String, dynamic>.from(row);
      final uid = m['applicant_user_id']?.toString();
      if (uid != null && uid.isNotEmpty) {
        try {
          final p = await UsersProfilesSafeSelect.fetchProfileById(
            Supabase.instance.client,
            uid,
            columnAttempts: const [
              'user_id,username,full_name_ar,full_name_en',
              'user_id,username',
              'user_id',
            ],
          );
          if (p != null) {
            m['profile'] = Map<String, dynamic>.from(p);
          }
        } catch (_) {}
      }
      out.add(m);
    }
    return out;
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final ctx = await _svc.myOrgContext();
    if (ctx == null || ctx['org_id'] == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _isOwner = false;
          _pending = [];
        });
      }
      return;
    }
    final isOwner = ctx['is_owner'] == true;
    List<Map<String, dynamic>> pending = [];
    if (isOwner) {
      await _svc.ensureMyOrgUnit();
      try {
        pending = await _enrichJoinProfiles(await _svc.listPendingJoinRequests());
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _isOwner = isOwner;
      _pending = pending;
      _loading = false;
    });
  }

  Future<void> _decide(String requestId, bool approve, AppLocalizations t) async {
    if (requestId.isEmpty) return;
    setState(() => _joinBusy = true);
    final res = await _svc.decideJoinRequest(
      requestId: requestId,
      approve: approve,
      permissions: <String, dynamic>{},
    );
    if (!mounted) return;
    setState(() => _joinBusy = false);
    final ok = res['ok'] == true;
    if (ok && res['approved'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.orgJoinApprovedToast)),
      );
      await _reload();
      return;
    }
    if (ok && res['approved'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.orgJoinRejectedToast)),
      );
      await _reload();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.orgJoinActionFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    if (_loading) {
      return const Center(child: AppLogoLoading());
    }

    if (!_isOwner) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _isAr
                ? 'طلبات الانضمام تُدار من قبل مدير المكتب أو المؤسسة أو الشركة العقارية. راجع تبويب «الفريق» للصلاحيات والأعضاء.'
                : 'Join requests are managed by your organization owner. Use the Team tab for members and permissions.',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4),
          ),
        ),
      );
    }

    if (_pending.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            Center(child: Text(t.orgJoinNoPending)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pending.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final j = _pending[i];
          final id = '${j['request_id'] ?? ''}';
          final prof = (j['profile'] as Map?)?.cast<String, dynamic>() ?? {};
          final label = _isAr
              ? '${prof['full_name_ar'] ?? prof['username'] ?? j['applicant_user_id']}'
              : '${prof['full_name_en'] ?? prof['username'] ?? j['applicant_user_id']}';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _joinBusy || id.isEmpty
                              ? null
                              : () => _decide(id, true, t),
                          child: Text(t.orgJoinApprove),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _joinBusy || id.isEmpty
                              ? null
                              : () => _decide(id, false, t),
                          child: Text(t.orgJoinReject),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
