import 'package:flutter/material.dart';

import 'org_team_chat_hub_page.dart';

/// دردشات الفريق الداخلية (قناة + محادثات مباشرة) — طبقة توجيه حسب طلب المنتج.
class OrganizationChatScreen extends StatelessWidget {
  const OrganizationChatScreen({super.key, required this.lang});

  final String lang;

  @override
  Widget build(BuildContext context) {
    return OrgTeamChatHubPage(lang: lang);
  }
}
