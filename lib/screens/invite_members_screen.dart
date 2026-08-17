import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../widgets/team_invite_member_dialog.dart';
import '../widgets/app_logo_loading.dart';

/// إضافة عضو بالهوية والجوال (بدون QR أو رمز فال).
class InviteMembersScreen extends StatefulWidget {
  const InviteMembersScreen({super.key, required this.lang});

  final String lang;

  @override
  State<InviteMembersScreen> createState() => _InviteMembersScreenState();
}

class _InviteMembersScreenState extends State<InviteMembersScreen> {
  final _svc = OrgTeamService(Supabase.instance.client);
  bool _loading = true;
  bool _owner = false;

  bool get _isAr => langNotifier.value != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ctx = await _svc.myOrgContext();
    if (!mounted) return;
    setState(() {
      _owner = ctx?['is_owner'] == true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t.inviteMembersTitle)),
      body: _loading
          ? const Center(child: AppLogoLoading())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  _isAr
                      ? 'أضف العضو برقم هويته/إقامته ورقم جواله (10 أرقام تبدأ بـ 05). يُكمل العضو التسجيل خلال 72 ساعة من شاشة إنشاء الحساب باختيار «عضو ضمن فريق».'
                      : 'Add a member with national ID and mobile (10 digits, 05…). They complete signup within 72 hours using «Team member» on the registration screen.',
                  style: TextStyle(
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (!_owner)
                  Text(
                    _isAr ? 'الإضافة للمالك فقط.' : 'Only the owner can invite.',
                    style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => showTeamInviteMemberDialog(context, svc: _svc),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(_isAr ? 'إضافة عضو' : 'Add member'),
                  ),
              ],
            ),
    );
  }
}
