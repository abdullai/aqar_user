import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'subscriptions_root_screen.dart';
import 'subscription_details_screen.dart';

/// تبويب «إدارة الاشتراك» داخل لوحة المنشأة.
class SubscriptionOrgDeskTab extends StatelessWidget {
  const SubscriptionOrgDeskTab({
    super.key,
    required this.lang,
    required this.accountType,
    required this.organizationId,
  });

  final String lang;
  final String accountType;
  final String organizationId;

  bool get _isAr => lang.toLowerCase() != 'en';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          t.subscriptionsOrgManageTab,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: SubscriptionDetailsScreen(
            lang: lang,
            accountType: accountType,
            organizationId: organizationId,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SubscriptionsRootScreen(
                  lang: lang,
                  accountType: accountType,
                  organizationId: organizationId,
                  embedAppBar: true,
                ),
              ),
            );
          },
          child: Text(t.subscriptionsTitle),
        ),
        const SizedBox(height: 8),
        Text(
          _isAr
              ? 'افتح مركز الاشتراكات الكامل لإدارة البطاقات والفواتير والترقية.'
              : 'Open the full subscriptions hub to manage cards, invoices, and upgrades.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
