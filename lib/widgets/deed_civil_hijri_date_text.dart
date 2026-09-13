import 'package:flutter/material.dart';

import '../core/utils/date_helper.dart';

/// تاريخ الصك: ميلادي yyyy/MM/dd وبجواره هجري yyyy/MM/dd — بلا وقت وبلا رموز م/هـ.
class DeedCivilHijriDateText extends StatelessWidget {
  const DeedCivilHijriDateText({
    super.key,
    required this.date,
    required this.isAr,
    this.style,
  });

  final DateTime date;
  final bool isAr;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ??
        const TextStyle(
          fontWeight: FontWeight.w700,
        );
    final dt = DateTime(date.year, date.month, date.day);
    final g = DateHelper.civilDigits(dt);
    final h = DateHelper.hijriDigits(dt);
    final ltrStyle = base.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget ltrRun(String text) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Text(text, style: ltrStyle),
      );
    }

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ltrRun(g),
          Text('  ·  ', style: base),
          ltrRun(h),
        ],
      ),
    );
  }
}
