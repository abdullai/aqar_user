import 'package:flutter/material.dart';



import '../l10n/app_localizations.dart';



class PaymentMethodCard extends StatelessWidget {

  const PaymentMethodCard({

    super.key,

    required this.scheme,

    required this.lastFour,

    required this.bankHint,

    required this.expiryLabel,

    required this.isDefault,

    required this.onSetDefault,

    required this.onDelete,

    this.label,

    this.isExpired = false,

    this.needsReverify = false,

    this.onEdit,

    this.onReverify,

    this.onUpdateExpired,

    this.enabled = true,

  });



  final String scheme;

  final String lastFour;

  final String bankHint;

  final String expiryLabel;

  final String? label;

  final bool isDefault;

  final bool isExpired;

  final bool needsReverify;

  final VoidCallback onSetDefault;

  final VoidCallback onDelete;

  final VoidCallback? onEdit;

  final VoidCallback? onReverify;

  final VoidCallback? onUpdateExpired;

  final bool enabled;



  @override

  Widget build(BuildContext context) {

    final t = AppLocalizations.of(context)!;

    final cs = Theme.of(context).colorScheme;

    final canUse = enabled && !isExpired;

    return Opacity(

      opacity: canUse ? 1 : 0.55,

      child: Card(

        margin: const EdgeInsets.only(bottom: 12),

        child: Padding(

          padding: const EdgeInsets.all(16),

          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Row(

                children: [

                  Icon(Icons.credit_card, color: cs.primary),

                  const SizedBox(width: 8),

                  Expanded(

                    child: Text(

                      label?.trim().isNotEmpty == true

                          ? label!.trim()

                          : '•••• •••• •••• $lastFour',

                      style: Theme.of(context).textTheme.titleMedium?.copyWith(

                            fontWeight: FontWeight.w800,

                            letterSpacing: 0.5,

                          ),

                    ),

                  ),

                  if (isDefault)

                    Chip(

                      label: Text(t.subscriptionsDefaultCard),

                      visualDensity: VisualDensity.compact,

                    ),

                  if (isExpired)

                    Chip(

                      label: Text(

                        Localizations.localeOf(context).languageCode == 'ar'

                            ? 'منتهية'

                            : 'Expired',

                      ),

                      visualDensity: VisualDensity.compact,

                      backgroundColor: cs.errorContainer,

                    ),

                ],

              ),

              const SizedBox(height: 6),

              Text(

                '$scheme · $bankHint',

                style: Theme.of(context).textTheme.bodySmall,

              ),

              Text(

                expiryLabel,

                style: Theme.of(context).textTheme.bodySmall,

              ),

              if (needsReverify)

                Padding(

                  padding: const EdgeInsets.only(top: 4),

                  child: Text(

                    Localizations.localeOf(context).languageCode == 'ar'

                        ? 'يلزم إعادة التحقق عبر الدفع'

                        : 'Re-verify via checkout',

                    style: Theme.of(context).textTheme.bodySmall?.copyWith(

                          color: cs.tertiary,

                        ),

                  ),

                ),

              const SizedBox(height: 12),

              Row(

                mainAxisAlignment: MainAxisAlignment.end,

                children: [

                  if (onEdit != null)

                    TextButton(

                      onPressed: onEdit,

                      child: Text(

                        Localizations.localeOf(context).languageCode == 'ar'

                            ? 'تعديل الاسم'

                            : 'Edit label',

                      ),

                    ),

                  if (isExpired && onUpdateExpired != null)

                    TextButton(

                      onPressed: onUpdateExpired,

                      child: Text(

                        Localizations.localeOf(context).languageCode == 'ar'

                            ? 'تحديث البطاقة'

                            : 'Update card',

                      ),

                    ),

                  if (needsReverify && onReverify != null)

                    TextButton(

                      onPressed: onReverify,

                      child: Text(

                        Localizations.localeOf(context).languageCode == 'ar'

                            ? 'إعادة التحقق'

                            : 'Re-verify',

                      ),

                    ),

                  TextButton(

                    onPressed: canUse && !isDefault ? onSetDefault : null,

                    child: Text(t.subscriptionsSetDefault),

                  ),

                  TextButton(

                    onPressed: enabled ? onDelete : null,

                    style: TextButton.styleFrom(foregroundColor: cs.error),

                    child: Text(t.subscriptionsDelete),

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


