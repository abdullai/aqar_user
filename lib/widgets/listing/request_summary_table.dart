import 'package:flutter/material.dart';

import '../../core/utils/app_money.dart';

/// جدول ملخص: عنوان | قيمة. النصوص الطويلة تلتف بعدة أسطر دون تصغير غير مقروء.
class RequestSummaryTable extends StatelessWidget {
  const RequestSummaryTable({
    super.key,
    required this.title,
    required this.rows,
    this.padding = const EdgeInsets.all(12),
  });

  final String title;
  final List<RequestSummaryRow> rows;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;
    final titleFs = w < 360 ? 13.5 : (w < 600 ? 14.5 : 15.5);
    final visible = rows.where((r) => r.hasContent).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.9)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
            color: cs.primary.withValues(alpha: 0.07),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: titleFs,
                color: cs.primary,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          for (var i = 0; i < visible.length; i++)
            _SummaryTableRow(
              row: visible[i],
              isLast: i == visible.length - 1,
              narrow: w < 380,
            ),
        ],
      ),
    );
  }
}

class RequestSummaryRow {
  const RequestSummaryRow({
    required this.label,
    this.value = '',
    this.valueWidget,
    this.emphasize = false,
    this.maxLines = 8,
  });

  final String label;
  final String value;
  final Widget? valueWidget;
  final bool emphasize;

  /// `null` = التفاف كامل دون قص. الرقم = حد أقصى مع نقاط إن تجاوز.
  final int? maxLines;

  bool get hasContent {
    if (valueWidget != null) return true;
    return value.trim().isNotEmpty;
  }
}

class _SummaryTableRow extends StatelessWidget {
  const _SummaryTableRow({
    required this.row,
    required this.isLast,
    required this.narrow,
  });

  final RequestSummaryRow row;
  final bool isLast;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelFs = narrow ? 12.0 : 13.0;
    final valueFs =
        row.emphasize ? (narrow ? 13.5 : 14.5) : (narrow ? 12.8 : 13.5);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 10 : 12,
        vertical: narrow ? 8 : 10,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: narrow ? 4 : 5,
            child: Text(
              row.label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: labelFs,
                color: cs.onSurface,
                height: 1.25,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: narrow ? 6 : 7,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: row.valueWidget ??
                  Text(
                    row.value.trim(),
                    maxLines: row.maxLines,
                    overflow: row.maxLines == null
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontWeight:
                          row.emphasize ? FontWeight.w900 : FontWeight.w800,
                      fontSize: valueFs,
                      color: cs.onSurface,
                      height: 1.35,
                      fontFamily: 'Cairo',
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// صف مبلغ أساسي مع رمز الريال (عربي) أو SAR (إنجليزي).
class RequestSummaryMoneyValue extends StatelessWidget {
  const RequestSummaryMoneyValue({
    super.key,
    required this.amount,
    required this.isAr,
    this.currencyCode = 'SAR',
  });

  final double amount;
  final bool isAr;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontWeight: FontWeight.w900,
      fontFamily: 'Cairo',
      fontSize: 15,
      height: 1.15,
      color: cs.onSurface,
    );
    return AppMoneyLine(
      amount: amount,
      currencyCode: currencyCode,
      isAr: isAr,
      maxFractionDigits: 0,
      symbolColor: cs.primary,
      style: style,
    );
  }
}
