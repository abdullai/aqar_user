import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../navigation/chat_navigation.dart';
import '../services/org_team_service.dart';
import '../widgets/app_logo_loading.dart';

/// يفتح [ChatPage] لمحادثة `org_team_channel` الموحّدة مع `messages`
/// (بعد `20260502_org_team_channel_unified_inbox.sql`).
class OrgTeamChannelPage extends StatefulWidget {
  const OrgTeamChannelPage({super.key, required this.lang});

  final String lang;

  @override
  State<OrgTeamChannelPage> createState() => _OrgTeamChannelPageState();
}

class _OrgTeamChannelPageState extends State<OrgTeamChannelPage> {
  final _svc = OrgTeamService(Supabase.instance.client);

  bool _loading = true;
  String? _errorKey;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
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
        });
      }
      return;
    }
    final orgId = '${ctx['org_id']}'.trim();
    final cid = await _svc.ensureOrgTeamChannelConversation(orgId);
    if (!mounted) return;
    if (cid == null || cid.isEmpty) {
      setState(() {
        _loading = false;
        _errorKey = 'no_conv';
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        ChatNavigation.materialRoute(
          isAr: _isAr,
          conversationId: cid,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _isAr ? 'قناة الفريق' : 'Team channel';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: AppLogoLoading())
          : _errorKey == 'no_org'
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _isAr ? 'لا توجد مؤسسة مرتبطة' : 'No organization',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _isAr
                          ? 'تعذّر فتح القناة. طبّق SQL الدمج 20260502 على Supabase ثم أعد المحاولة.'
                          : 'Could not open channel. Apply SQL 20260502 on Supabase and retry.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
    );
  }
}
