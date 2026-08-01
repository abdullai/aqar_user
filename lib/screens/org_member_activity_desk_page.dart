import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';

/// سجل النشاط داخل المنشأة (org_activity_log).
class OrgMemberActivityDeskPage extends StatefulWidget {
  const OrgMemberActivityDeskPage({super.key, required this.lang});

  final String lang;

  @override
  State<OrgMemberActivityDeskPage> createState() =>
      _OrgMemberActivityDeskPageState();
}

class _OrgMemberActivityDeskPageState extends State<OrgMemberActivityDeskPage> {
  final _svc = OrgTeamService(Supabase.instance.client);
  bool _loading = true;
  String? _orgId;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, String> _actorNames = const {};

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _actionLabel(String action) {
    final a = action.trim().toLowerCase();
    if (a.isEmpty) return _isAr ? 'إجراء غير معروف' : 'Unknown action';
    const ar = <String, String>{
      'member_join': 'انضمام عضو',
      'member_leave': 'مغادرة عضو',
      'member_invite': 'دعوة عضو',
      'member_remove': 'إزالة عضو',
      'role_change': 'تغيير صلاحية',
      'permissions_update': 'تحديث الصلاحيات',
      'listing_create': 'إنشاء إعلان',
      'listing_update': 'تحديث إعلان',
      'listing_delete': 'حذف إعلان',
      'offer_create': 'إنشاء عرض',
      'offer_accept': 'قبول عرض',
      'offer_reject': 'رفض عرض',
      'contract_sign': 'توقيع عقد',
      'org_settings': 'إعدادات المنشأة',
      'login': 'تسجيل دخول',
    };
    const en = <String, String>{
      'member_join': 'Member joined',
      'member_leave': 'Member left',
      'member_invite': 'Member invited',
      'member_remove': 'Member removed',
      'role_change': 'Role changed',
      'permissions_update': 'Permissions updated',
      'listing_create': 'Listing created',
      'listing_update': 'Listing updated',
      'listing_delete': 'Listing deleted',
      'offer_create': 'Offer created',
      'offer_accept': 'Offer accepted',
      'offer_reject': 'Offer rejected',
      'contract_sign': 'Contract signed',
      'org_settings': 'Organization settings',
      'login': 'Sign-in',
    };
    final map = _isAr ? ar : en;
    if (map.containsKey(a)) return map[a]!;
    // لا تعرض مفاتيح خام طويلة — حسّن العرض.
    return action.replaceAll('_', ' ');
  }

  String _entityLabel(String et) {
    final e = et.trim().toLowerCase();
    if (e.isEmpty) return '';
    if (e.contains('listing') || e.contains('property')) {
      return _isAr ? 'إعلان' : 'Listing';
    }
    if (e.contains('member') || e.contains('user')) {
      return _isAr ? 'عضو' : 'Member';
    }
    if (e.contains('offer')) return _isAr ? 'عرض' : 'Offer';
    if (e.contains('contract')) return _isAr ? 'عقد' : 'Contract';
    if (e.contains('org')) return _isAr ? 'منشأة' : 'Organization';
    return et.replaceAll('_', ' ');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ctx = await _svc.myOrgContext();
    final oid = ctx?['org_id']?.toString();
    if (oid == null || oid.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final log = await _svc.activityLog(oid, limit: 300);
    final names = <String, String>{};
    final actorIds = log
        .map((r) => '${r['actor_user_id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (actorIds.isNotEmpty) {
      try {
        final rows = await Supabase.instance.client
            .from('users_profiles')
            .select(
              'user_id, full_name_ar, full_name_en, full_name, first_name_ar, first_name_en',
            )
            .inFilter('user_id', actorIds);
        for (final r in rows) {
          final m = Map<String, dynamic>.from(r as Map);
          final id = '${m['user_id'] ?? ''}'.trim();
          if (id.isEmpty) continue;
          String pick(String k) => '${m[k] ?? ''}'.trim();
          final name = _isAr
              ? (pick('full_name_ar').isNotEmpty
                  ? pick('full_name_ar')
                  : (pick('first_name_ar').isNotEmpty
                      ? pick('first_name_ar')
                      : pick('full_name')))
              : (pick('full_name_en').isNotEmpty
                  ? pick('full_name_en')
                  : (pick('first_name_en').isNotEmpty
                      ? pick('first_name_en')
                      : pick('full_name')));
          if (name.isNotEmpty) names[id] = name;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _orgId = oid;
      _rows = log;
      _actorNames = names;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: AppLogoLoading());
    if (_orgId == null) {
      return Center(
        child: Text(_isAr ? 'لا منشأة' : 'No organization'),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            t.orgMemberActivityEmpty,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final loc = _isAr ? 'ar' : 'en';
    return RefreshIndicator(
      onRefresh: _load,
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = _rows[i];
            final action = '${r['action'] ?? ''}';
            final et = '${r['entity_type'] ?? ''}';
            final actorId = '${r['actor_user_id'] ?? ''}'.trim();
            final actor = _actorNames[actorId] ??
                (actorId.isEmpty
                    ? (_isAr ? 'غير معروف' : 'Unknown')
                    : (_isAr ? 'عضو' : 'Member'));
            final atRaw = '${r['created_at'] ?? ''}';
            final atDt = DateTime.tryParse(atRaw);
            final at = atDt == null
                ? atRaw
                : DateFormat.yMMMd(loc).add_jm().format(atDt.toLocal());
            final entity = _entityLabel(et);
            return ListTile(
              leading: Icon(Icons.history, color: cs.primary),
              title: Text(
                _actionLabel(action),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                [
                  '${_isAr ? 'بواسطة' : 'By'}: $actor',
                  if (entity.isNotEmpty) '${_isAr ? 'النوع' : 'Type'}: $entity',
                  at,
                ].join('\n'),
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            );
          },
        ),
      ),
    );
  }
}
