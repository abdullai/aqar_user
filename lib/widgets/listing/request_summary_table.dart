import 'package:flutter/material.dart';



/// جدول ملخص — عنوان | قيمة بحدود، نصوص تتمدّد/تتقلّص حسب العرض دون التفاف مكسور.

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

    final visible = rows.where((r) => r.value.trim().isNotEmpty).toList();

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

            child: FittedBox(

              fit: BoxFit.scaleDown,

              alignment: AlignmentDirectional.centerStart,

              child: Text(

                title,

                maxLines: 1,

                style: TextStyle(

                  fontWeight: FontWeight.w900,

                  fontSize: titleFs,

                  color: cs.primary,

                ),

              ),

            ),

          ),

          for (var i = 0; i < visible.length; i++)

            _SummaryTableRow(

              label: visible[i].label,

              value: visible[i].value,

              emphasize: visible[i].emphasize,

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

    required this.value,

    this.emphasize = false,

  });



  final String label;

  final String value;

  final bool emphasize;

}



class _SummaryTableRow extends StatelessWidget {

  const _SummaryTableRow({

    required this.label,

    required this.value,

    required this.emphasize,

    required this.isLast,

    required this.narrow,

  });



  final String label;

  final String value;

  final bool emphasize;

  final bool isLast;

  final bool narrow;



  @override

  Widget build(BuildContext context) {

    final cs = Theme.of(context).colorScheme;

    final labelFs = narrow ? 12.0 : 13.0;

    final valueFs = emphasize ? (narrow ? 13.0 : 14.0) : (narrow ? 12.5 : 13.5);



    return Container(

      padding: EdgeInsets.symmetric(

        horizontal: narrow ? 10 : 12,

        vertical: narrow ? 7 : 9,

      ),

      decoration: BoxDecoration(

        border: Border(

          bottom: isLast

              ? BorderSide.none

              : BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),

        ),

      ),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.center,

        children: [

          Expanded(

            flex: narrow ? 4 : 5,

            child: FittedBox(

              fit: BoxFit.scaleDown,

              alignment: AlignmentDirectional.centerStart,

              child: Text(

                label,

                maxLines: 1,

                softWrap: false,

                style: TextStyle(

                  fontWeight: FontWeight.w900,

                  fontSize: labelFs,

                  color: cs.onSurfaceVariant,

                  height: 1.2,

                ),

              ),

            ),

          ),

          const SizedBox(width: 8),

          Expanded(

            flex: narrow ? 6 : 7,

            child: FittedBox(

              fit: BoxFit.scaleDown,

              alignment: AlignmentDirectional.centerEnd,

              child: Text(

                value,

                maxLines: 2,

                textAlign: TextAlign.end,

                style: TextStyle(

                  fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,

                  fontSize: valueFs,

                  color: cs.onSurface,

                  height: 1.25,

                ),

              ),

            ),

          ),

        ],

      ),

    );

  }

}


