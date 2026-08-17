import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';
import '../navigation/chat_navigation.dart';
import 'chat_page.dart' show ConversationKind;

/// قائمة أعضاء الفريق لبدء محادثة 1:1 (نفس أسلوب الدردشة الحالي).
class OrgTeamChatHubPage extends StatefulWidget {
  const OrgTeamChatHubPage({super.key, required this.lang});

  final String lang;

  @override
  State<OrgTeamChatHubPage> createState() => _OrgTeamChatHubPageState();
}

class _OrgTeamChatHubPageState extends State<OrgTeamChatHubPage> {
  final _svc = OrgTeamService(Supabase.instance.client);
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _errorKey;
  String? _orgId;
  List<Map<String, dynamic>> _members = [];

  bool get _isAr => widget.lang.toLowerCase() != 'en';
  String get _uid => _sb.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    final ctx = await _svc.myOrgContext();
    if (ctx == null || ctx['org_id'] == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorKey = 'no_org';
          _members = [];
        });
      }
      return;
    }
    final orgId = '${ctx['org_id']}';
    final members = await _svc.listMembers(orgId);
    if (!mounted) return;
    setState(() {
      _orgId = orgId;
      _members = members;
      _loading = false;
    });
  }

  String _memberName(Map<String, dynamic> m) {
    final prof = (m['profile'] as Map?)?.cast<String, dynamic>() ?? {};
    if (_isAr) {
      return '${prof['full_name_ar'] ?? prof['username'] ?? m['user_id']}';
    }
    return '${prof['full_name_en'] ?? prof['username'] ?? m['user_id']}';
  }

  Future<void> _openChat(String otherId, String title) async {
    if (!mounted) return;
    await ChatNavigation.push(
      context,
      isAr: _isAr,
      kind: ConversationKind.direct,
      counterpartyId: otherId,
      title: title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: AppLogoLoading());
    }
    if (_errorKey == 'no_org') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            t?.orgNoOrg ?? (_isAr ? 'لا توجد مؤسسة مرتبطة' : 'No organization'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    final others = _members
        .where((m) => '${m['user_id']}' != _uid)
        .where((m) => '${m['status']}' == 'active')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Material(
            color: cs.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              leading: Icon(Icons.campaign_outlined, color: cs.primary),
              title: Text(
                _isAr ? 'قناة الفريق (جماعية)' : 'Team channel (group)',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                _isAr
                    ? 'منشورات لكل الأعضاء النشطين — منفصلة عن المحادثة الخاصة.'
                    : 'Posts visible to all active members — not private DMs.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final oid = (_orgId ?? '').trim();
                if (oid.isEmpty) {
                  await _load();
                  if (!mounted) return;
                }
                final org = (_orgId ?? '').trim();
                if (org.isEmpty) return;
                final cid = await _svc.ensureOrgTeamChannelConversation(org);
                if (!mounted) return;
                if (cid == null || cid.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _isAr
                            ? 'تعذّر فتح القناة. طبّق SQL دمج قناة الفريق على الخادم.'
                            : 'Could not open channel. Apply org channel merge SQL.',
                      ),
                    ),
                  );
                  return;
                }
                await ChatNavigation.push(
                  context,
                  isAr: _isAr,
                  conversationId: cid,
                );
              },
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: others.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                    children: [
                      Text(
                        _isAr
                            ? 'لا يوجد أعضاء آخرون لمحادثة خاصة حالياً. يمكنك استخدام قناة الفريق أعلاه.'
                            : 'No other members for private chat yet. Use the team channel above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: others.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = others[i];
                      final uid = '${m['user_id']}';
                      final name = _memberName(m);
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            name.isNotEmpty
                                ? name.substring(0, 1).toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('${m['member_role']}'),
                        trailing: const Icon(Icons.chat_bubble_outline),
                        onTap: () => _openChat(uid, name),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
