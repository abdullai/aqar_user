import 'package:flutter/material.dart';

import '../core/profile/publisher_identity_prefs.dart';

/// بطاقة خيارات هوية الناشر (اسم / جوال / حضور) — للإعدادات وإضافة إعلان/طلب.
class PublisherIdentityOptionsCard extends StatelessWidget {
  const PublisherIdentityOptionsCard({
    super.key,
    required this.isAr,
    required this.nameSource,
    required this.phoneSource,
    required this.publishPresence,
    required this.officialName,
    required this.displayAlias,
    required this.primaryPhone,
    required this.secondaryPhone,
    this.onNameSourceChanged,
    this.onPhoneSourceChanged,
    this.onPublishPresenceChanged,
    this.compact = false,
    this.enabled = true,
  });

  final bool isAr;
  final PublicNameSource nameSource;
  final PublicPhoneSource phoneSource;
  final bool publishPresence;
  final String officialName;
  final String displayAlias;
  final String primaryPhone;
  final String secondaryPhone;
  final ValueChanged<PublicNameSource>? onNameSourceChanged;
  final ValueChanged<PublicPhoneSource>? onPhoneSourceChanged;
  final ValueChanged<bool>? onPublishPresenceChanged;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 420;
    final alias = displayAlias.trim().isEmpty
        ? (isAr ? '— غير مضبوط —' : '— not set —')
        : displayAlias.trim();
    final official = officialName.trim().isEmpty
        ? (isAr ? '— غير متوفر —' : '— unavailable —')
        : officialName.trim();

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 14,
          compact ? 10 : 14,
          compact ? 12 : 14,
          compact ? 10 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr
                        ? 'هوية الظهور للآخرين'
                        : 'How others see you',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isAr
                  ? 'المعاملات الرسمية تستخدم الاسم/الصفة المعتمدة. يمكنك اختيار المستعار للبطاقات.'
                  : 'Official deals use your registered name/title. You may choose an alias on cards.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _labeledBlock(
              context,
              label: isAr ? 'الاسم الظاهر' : 'Visible name',
              child: SegmentedButton<PublicNameSource>(
                segments: [
                  ButtonSegment(
                    value: PublicNameSource.official,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isAr ? 'المعتمد' : 'Official',
                        maxLines: 1,
                      ),
                    ),
                    tooltip: official,
                  ),
                  ButtonSegment(
                    value: PublicNameSource.display,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isAr ? 'المستعار' : 'Alias',
                        maxLines: 1,
                      ),
                    ),
                    tooltip: alias,
                  ),
                ],
                selected: {nameSource},
                onSelectionChanged: !enabled || onNameSourceChanged == null
                    ? null
                    : (s) {
                        if (s.isEmpty) return;
                        onNameSourceChanged!(s.first);
                      },
                style: ButtonStyle(
                  visualDensity: narrow
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              nameSource == PublicNameSource.official
                  ? (isAr ? 'سيظهر: $official' : 'Shows: $official')
                  : (isAr ? 'سيظهر: $alias' : 'Shows: $alias'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 14),
            _labeledBlock(
              context,
              label: isAr ? 'رقم الجوال الظاهر' : 'Visible phone',
              child: SegmentedButton<PublicPhoneSource>(
                segments: [
                  ButtonSegment(
                    value: PublicPhoneSource.primary,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isAr ? 'الأساسي' : 'Primary',
                        maxLines: 1,
                      ),
                    ),
                  ),
                  ButtonSegment(
                    value: PublicPhoneSource.secondary,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isAr ? 'الإضافي' : 'Extra',
                        maxLines: 1,
                      ),
                    ),
                    enabled: secondaryPhone.trim().length >= 10,
                  ),
                  ButtonSegment(
                    value: PublicPhoneSource.hidden,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isAr ? 'إخفاء' : 'Hide',
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
                selected: {phoneSource},
                onSelectionChanged: !enabled || onPhoneSourceChanged == null
                    ? null
                    : (s) {
                        if (s.isEmpty) return;
                        onPhoneSourceChanged!(s.first);
                      },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                isAr
                    ? 'إظهار «متصل الآن / آخر ظهور» على بطاقاتي'
                    : 'Show online / last seen on my cards',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  height: 1.25,
                ),
              ),
              subtitle: Text(
                isAr
                    ? 'ينطبق عند نشر إعلان أو طلب عقاري.'
                    : 'Applies when you publish a listing or request.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              value: publishPresence,
              onChanged: !enabled || onPublishPresenceChanged == null
                  ? null
                  : onPublishPresenceChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _labeledBlock(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
