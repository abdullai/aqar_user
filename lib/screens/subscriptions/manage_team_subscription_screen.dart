import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/workflow/app_role_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../services/org_team_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/app_logo_loading.dart';

/// مقاعد الفريق مقابل حد الباقة (وهمي/من الخادم عند الربط الكامل).
class ManageTeamSubscriptionScreen extends StatefulWidget {
  const ManageTeamSubscriptionScreen({
    super.key,
    required this.lang,
    required this.accountType,
    this.organizationId,
    this.onRequestUpgrade,
  });

  final String lang;
  final String accountType;
  final String? organizationId;
  final VoidCallback? onRequestUpgrade;

  @override
  State<ManageTeamSubscriptionScreen> createState() =>
      _ManageTeamSubscriptionScreenState();
}

class _ManageTeamSubscriptionScreenState
    extends State<ManageTeamSubscriptionScreen> {
  final _org = OrgTeamService(Supabase.instance.client);
  final _sub = SubscriptionService(Supabase.instance.client);
  bool _loading = true;
  List<Map<String, dynamic>> _members = [];
  int _seatLimit = 1;
  int _memberCount = 0;
  Map<String, dynamic>? _plan;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final oid = widget.organizationId;
    if (oid == null || oid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final members = await _org.listMembers(oid);
    final used = await _org.memberCount(oid);
    final prof = await _org.publicOrganizationProfile(oid);
    final lim = int.tryParse('${prof?['seat_limit']}') ?? 1;
    final sub = await _sub.getCurrentSubscription(organizationId: oid);
    Map<String, dynamic>? plan;
    if (sub != null && sub['plan'] is Map) {
      plan = Map<String, dynamic>.from(sub['plan'] as Map);
    }
    if (!mounted) return;
    setState(() {
      _members = members;
      _memberCount = used;
      _seatLimit = lim;
      _plan = plan;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    final maxM = _plan == null
        ? null
        : int.tryParse('${_plan!['max_members']}');
    final pct = _seatLimit > 0 ? _memberCount / _seatLimit : 0.0;
    final atLimit = _memberCount >= _seatLimit;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t.subscriptionsTeamTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_plan != null)
            Text(
              _isAr
                  ? 'الباقة: ${_plan!['name_ar'] ?? ''} — حد المقاعد: ${maxM ?? t.subscriptionsUnlimited}'
                  : 'Plan: ${_plan!['name_en'] ?? ''} — seat cap: ${maxM ?? t.subscriptionsUnlimited}',
            ),
          const SizedBox(height: 12),
          Text('${t.subscriptionsSeatsUsed}: $_memberCount / $_seatLimit'),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: pct.clamp(0, 1)),
          ),
          const SizedBox(height: 16),
          ..._members.map((m) {
            final prof = m['profile'];
            String name = '${m['user_id'] ?? ''}';
            if (prof is Map) {
              final dn = prof['display_name'] ?? prof['full_name'];
              if (dn != null && '$dn'.trim().isNotEmpty) name = '$dn';
            }
            final role = '${m['member_role'] ?? ''}';
            return ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(name),
              subtitle: Text(role),
            );
          }),
          if (!atLimit)
            FilledButton.tonal(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _isAr
                          ? 'استخدم «دعوة أعضاء» من شريط إدارتي لإضافة زميل.'
                          : 'Use Invite teammates from the org desk toolbar.',
                    ),
                  ),
                );
              },
              child: Text(t.subscriptionsAddMember),
            ),
          if (atLimit &&
              AppRoleHelper.isOrgEntity(widget.accountType)) ...[
            const SizedBox(height: 12),
            Text(
              t.subscriptionsUpgradeHint,
              style: TextStyle(color: cs.error),
            ),
            FilledButton(
              onPressed: widget.onRequestUpgrade,
              child: Text(t.subscriptionsUpgradeCta),
            ),
          ],
        ],
      ),
    );
  }
}
