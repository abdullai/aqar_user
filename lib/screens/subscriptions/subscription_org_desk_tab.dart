import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/org_fal_and_seats_panel.dart';
import 'subscriptions_root_screen.dart';

/// تبويب «إدارة الاشتراك» داخل لوحة المنشأة — بلا تكرار مع إعدادات المنشأة.
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
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          _isAr
              ? 'تجديد فال، المقاعد، الباقات والفواتير — كلها هنا. إعدادات الاسم والعنوان في تبويب إعدادات المنشأة.'
              : 'FAL renewal, seats, plans and invoices live here. Name and address stay in organization settings.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        OrgFalAndSeatsPanel(
          accountType: accountType,
          organizationId: organizationId,
          lang: lang,
          onOpenPlans: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SubscriptionsRootScreen(
                  lang: lang,
                  accountType: accountType,
                  organizationId: organizationId,
                  initialIndex: 0,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SubscriptionsRootScreen(
                  lang: lang,
                  accountType: accountType,
                  organizationId: organizationId,
                ),
              ),
            );
          },
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(t.subscriptionsTitle),
        ),
      ],
    );
  }
}
