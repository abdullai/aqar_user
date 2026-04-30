import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../navigation/chat_navigation.dart';
import 'in_app_notifications_page.dart';

/// مركز واحد من أيقونة الجرس: صندوق الإشعار + مدخل صندوق المحادثات.
class CommunicationHubPage extends StatelessWidget {
  final String lang;
  final bool isAr;

  const CommunicationHubPage({
    super.key,
    required this.lang,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final td = isAr ? TextDirection.rtl : TextDirection.ltr;

    return DefaultTabController(
      length: 2,
      child: Directionality(
        textDirection: td,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.communicationHubTitle),
            bottom: TabBar(
              tabs: [
                Tab(text: l10n.communicationHubNotificationsTab),
                Tab(text: l10n.communicationHubChatsTab),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              InAppNotificationsPage(lang: lang, embedMode: true),
              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    l10n.communicationHubChatsHint,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      ChatNavigation.push(context, isAr: isAr);
                    },
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(
                      l10n.openChatInboxButton,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
