import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

class PaymentTransactionTile extends StatelessWidget {
  const PaymentTransactionTile({
    super.key,
    required this.createdAt,
    required this.title,
    required this.subtitle,
    required this.amountLine,
    required this.statusLine,
    this.onInvoice,
  });

  final DateTime? createdAt;
  final String title;
  final String subtitle;
  final String amountLine;
  final String statusLine;
  final VoidCallback? onInvoice;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final dateStr = createdAt != null
        ? DateFormat.yMMMMd(Localizations.localeOf(context).toString())
            .format(createdAt!)
        : '—';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateStr,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              amountLine,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(statusLine),
            if (onInvoice != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton.icon(
                  onPressed: onInvoice,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text(t.subscriptionsDownloadInvoice),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
