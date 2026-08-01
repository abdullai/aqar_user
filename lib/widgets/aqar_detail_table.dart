import 'package:flutter/material.dart';

/// صف عنوان/قيمة — جداول موحّدة في «صفحتي» والتفاصيل.
class AqarLabelValueRow extends StatelessWidget {
  const AqarLabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.labelFlex = 2,
    this.valueFlex = 3,
    this.dense = false,
    this.icon,
  });

  final String label;
  final String value;
  final int labelFlex;
  final int valueFlex;
  final bool dense;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w900,
          height: 1.35,
        );
    final lStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          height: 1.35,
        );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            flex: labelFlex,
            child: Text(
              label,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: lStyle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: valueFlex,
            child: Text(
              value,
              maxLines: 4,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: vStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// جدول تفاصيل داخل بطاقة — عنوان + صفوف.
class AqarDetailTable extends StatelessWidget {
  const AqarDetailTable({
    super.key,
    this.title,
    this.subtitle,
    required this.rows,
    this.dense = false,
  });

  final String? title;
  final String? subtitle;
  final List<AqarLabelValueRow> rows;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 6),
            ],
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// نص «شريكنا» الموحّد.
class AqarPartnerBadge extends StatelessWidget {
  const AqarPartnerBadge({
    super.key,
    required this.isAr,
    this.compact = false,
  });

  final bool isAr;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isAr ? 'شريكنا' : 'Our partner',
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w900,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}
