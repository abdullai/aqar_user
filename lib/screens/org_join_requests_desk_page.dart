import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/saudi_input_formatters.dart';
import '../l10n/app_localizations.dart';
import '../services/org_notification_service.dart';
import '../services/org_team_service.dart';
import '../widgets/team_invite_member_dialog.dart';
import '../widgets/app_logo_loading.dart';

/// طلبات انضمام الفريق (دعوات هوية + جوال) — للمالك فقط.
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
  List<Map<String, dynamic>> _invitations = [];
  int _prevPendingLen = -1;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final ctx = await _svc.myOrgContext();
    if (ctx == null || ctx['org_id'] == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _isOwner = false;
          _invitations = [];
        });
      }
      return;
    }
    final isOwner = ctx['is_owner'] == true;
    List<Map<String, dynamic>> list = [];
    if (isOwner) {
      await _svc.ensureMyOrgUnit();
      try {
        list = await _svc.listTeamInvitations();
        list = list
            .where((e) => '${e['status'] ?? ''}' == 'pending')
            .toList();
      } catch (_) {}
    }
    if (!mounted) return;
    final n = list.length;
    if (_prevPendingLen >= 0 && n > _prevPendingLen) {
      unawaited(OrgNotificationService.signalNewPendingJoinRequest(
        dedupeKey: list.isNotEmpty ? '${list.last['invitation_id']}' : null,
      ));
    }
    _prevPendingLen = n;
    setState(() {
      _isOwner = isOwner;
      _invitations = list;
      _loading = false;
    });
  }

  Future<void> _editInvitation(Map<String, dynamic> row) async {
    final id = '${row['invitation_id'] ?? ''}';
    if (id.isEmpty) return;
    final nidCtrl = TextEditingController(text: '${row['national_id'] ?? ''}');
    final mobCtrl = TextEditingController(text: '${row['mobile_local'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'تعديل الطلب' : 'Edit invitation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AqarTextField(
              controller: nidCtrl,
              keyboardType: TextInputType.number,
              maxLength: 10,
              inputFormatters: latinDigitsOnlyFormatters(maxLength: 10),
              decoration: InputDecoration(
                counterText: '',
                labelText: _isAr ? 'رقم الهوية' : 'National ID',
              ),
            ),
            const SizedBox(height: 12),
            AqarTextField(
              controller: mobCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: latinDigitsOnlyFormatters(maxLength: 10),
              decoration: InputDecoration(
                counterText: '',
                labelText: _isAr ? 'رقم الجوال' : 'Mobile',
                hintText: '05xxxxxxxx',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true) {
      nidCtrl.dispose();
      mobCtrl.dispose();
      return;
    }
    final res = await _svc.updateTeamInvitation(
      invitationId: id,
      nationalId: nidCtrl.text,
      mobile: mobCtrl.text,
    );
    nidCtrl.dispose();
    mobCtrl.dispose();
    if (!mounted) return;
    if (res['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAr ? 'تم التحديث' : 'Updated')),
      );
      await _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${res['error'] ?? 'error'}')),
      );
    }
  }

  String _formatDt(dynamic raw) {
    final dt = DateTime.tryParse('$raw');
    if (dt == null) return '$raw';
    final loc = _isAr ? 'ar' : 'en';
    return DateFormat.yMMMd(loc).add_jm().format(dt.toLocal());
  }

  Widget _invitationCard(Map<String, dynamic> row) {
    final cs = Theme.of(context).colorScheme;
    final exp = DateTime.tryParse('${row['expires_at'] ?? ''}');
    final hoursLeft = exp == null
        ? null
        : exp.difference(DateTime.now()).inHours.clamp(0, 999);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${row['national_id'] ?? '—'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.phone_iphone_outlined,
                    size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  '${row['mobile_local'] ?? '—'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${_isAr ? 'تاريخ الطلب' : 'Requested'}: ${_formatDt(row['created_at'])}',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hoursLeft != null) ...[
              const SizedBox(height: 4),
              Text(
                _isAr
                    ? 'متبقٍ تقريباً $hoursLeft ساعة (صلاحية 72 ساعة)'
                    : '~$hoursLeft h left (72h window)',
                style: TextStyle(
                  fontSize: 12,
                  color: hoursLeft < 12 ? cs.error : cs.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => _editInvitation(row),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(_isAr ? 'تعديل البيانات' : 'Edit details'),
              ),
            ),
          ],
        ),
      ),
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
                ? 'طلبات الانضمام تُدار من قبل مدير المنشأة أو المسوّق. راجع تبويب «الفريق» للأعضاء والصلاحيات.'
                : 'Join invitations are managed by your organization owner.',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: FilledButton.icon(
                onPressed: () async {
                  final ok = await showTeamInviteMemberDialog(
                    context,
                    svc: _svc,
                  );
                  if (ok == true) await _reload();
                },
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(_isAr ? 'إضافة عضو' : 'Add member'),
              ),
            ),
          ),
          if (_invitations.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(t.orgJoinNoPending)),
            )
          else
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final w = MediaQuery.sizeOf(context).width;
                final cols = w >= 1100
                    ? 3
                    : w >= 720
                        ? 2
                        : 1;
                if (cols == 1) {
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _invitationCard(_invitations[i]),
                        ),
                        childCount: _invitations.length,
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _invitationCard(_invitations[i]),
                      childCount: _invitations.length,
                    ),
                  ),
                );
              },
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}
