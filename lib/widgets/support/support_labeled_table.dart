import 'package:flutter/material.dart';

/// صف تسمية | محتوى داخل جدول بحدود — الموضوع بجوار الحقل، التفاصيل بجوار التفصيل.
class SupportLabeledTable extends StatelessWidget {
  const SupportLabeledTable({
    super.key,
    required this.rows,
  });

  final List<SupportLabeledRow> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = BorderSide(
      color: cs.outlineVariant.withValues(alpha: 0.85),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Table(
        border: TableBorder(
          top: border,
          left: border,
          right: border,
          bottom: border,
          horizontalInside: border,
          verticalInside: border,
        ),
        columnWidths: const {
          0: IntrinsicColumnWidth(),
          1: FlexColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          for (final row in rows)
            TableRow(
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 88, maxWidth: 132),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      child: Text(
                        row.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: row.child,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class SupportLabeledRow {
  const SupportLabeledRow({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;
}

class SupportSectionCard extends StatelessWidget {
  const SupportSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.tone,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = tone ?? cs.outlineVariant.withValues(alpha: 0.7);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
