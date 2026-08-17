import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/org_team_service.dart';
import '../core/utils/users_profiles_safe_select.dart';

/// ملخص سريع لنوع الحساب والمنشأة والصلاحيات.
class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({super.key, required this.lang});

  final String lang;

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  bool _loading = true;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _orgCtx;
  int _props = 0;
  int _ads = 0;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final row = await sb
          .from('users_profiles')
          .select(UsersProfilesSafeSelect.enrichedProfileColumns.first)
          .eq('user_id', uid)
          .maybeSingle();
      final svc = OrgTeamService(sb);
      final ctx = await svc.myOrgContext();
      int p = 0;
      int a = 0;
      try {
        final pr = await sb.from('properties').select('id').eq('owner_id', uid);
        p = (pr as List).length;
      } catch (_) {}
      try {
        final ad = await sb.from('ads').select('id').eq('owner_id', uid);
        a = (ad as List).length;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _profile = row == null ? null : Map<String, dynamic>.from(row);
        _orgCtx = ctx;
        _props = p;
        _ads = a;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isAr ? 'حالة الحساب' : 'Account status'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final at = '${_profile?['account_type'] ?? '—'}';
    final orgName = '${_orgCtx?['display_name_ar'] ?? _orgCtx?['org_name'] ?? ''}';
    final perm = _orgCtx?['permissions'];
    final permMap = perm is Map
        ? perm.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final activePermKeys = permMap.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .take(12)
        .join(', ');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'حالة الحساب' : 'Account status'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: Text(_isAr ? 'نوع الحساب' : 'Account type'),
            subtitle: Text(at),
          ),
          ListTile(
            title: Text(_isAr ? 'المنشأة' : 'Organization'),
            subtitle: Text(orgName.isEmpty ? '—' : orgName),
          ),
          ListTile(
            title: Text(_isAr ? 'صلاحيات مختصرة' : 'Permissions (sample)'),
            subtitle: Text(activePermKeys.isEmpty ? '—' : activePermKeys),
          ),
          ListTile(
            title: Text(_isAr ? 'عقاراتي (مقدّرة)' : 'My properties (count)'),
            subtitle: Text('$_props'),
          ),
          ListTile(
            title: Text(_isAr ? 'إعلاناتي (مقدّرة)' : 'My ads (count)'),
            subtitle: Text('$_ads'),
          ),
        ],
      ),
    );
  }
}
