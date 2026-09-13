import 'package:flutter/material.dart';

import '../core/branding/aqar_brand_colors.dart';
import '../core/utils/app_money.dart';

/// مبلغ طلب السوق: رقم + رمز ريال إن وُجد رقم؛ بلا «غير محدد» وبلا «إلى» الوهمية.
class SpecifiedBudgetLine extends StatelessWidget {
  const SpecifiedBudgetLine({
    super.key,
    required this.min,
    required this.max,
    required this.isAr,
    this.showCaption = true,
    this.color,
    this.fontSize = 18,
    this.alignEnd = false,
  });

  final double? min;
  final double? max;
  final bool isAr;
  final bool showCaption;
  final Color? color;
  final double fontSize;
  final bool alignEnd;

  static bool _hasNum(double? v) =>
      v != null && !v.isNaN && !v.isInfinite && v > 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = color ?? cs.onSurface;
    final style = TextStyle(
      fontWeight: FontWeight.w900,
      fontFamily: 'Cairo',
      fontSize: fontSize,
      height: 1.15,
      color: ink,
      letterSpacing: -0.2,
    );
    final joinStyle = style.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: fontSize * 0.78,
    );

    final hasMin = _hasNum(min);
    final hasMax = _hasNum(max);
    final range = hasMin && hasMax && (min! - max!).abs() > 0.009;

    Widget money(double v) => AppMoneyLine(
          amount: v,
          currencyCode: 'SAR',
          isAr: isAr,
          maxFractionDigits: 0,
          symbolColor: ink,
          style: style,
        );

    final Widget? amounts;
    if (!hasMin && !hasMax) {
      amounts = null;
    } else if (range) {
      amounts = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: money(min!)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(isAr ? 'إلى' : 'to', style: joinStyle),
          ),
          Flexible(child: money(max!)),
        ],
      );
    } else {
      amounts = money(hasMin ? min! : max!);
    }

    if (amounts == null && !showCaption) {
      return const SizedBox.shrink();
    }

    final block = Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCaption)
          Text(
            isAr ? 'المبلغ المحدد' : 'Specified amount',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: 'Cairo',
              fontSize: 11,
              height: 1.1,
              color: AqarBrandColors.primary,
            ),
          ),
        if (showCaption && amounts != null) const SizedBox(height: 2),
        if (amounts != null) amounts,
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: alignEnd
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: block,
      ),
    );
  }
}
