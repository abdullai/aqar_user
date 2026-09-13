import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/saudi_riyal_symbol_icon.dart';

/// تنسيق موحد للمبالغ: رمز الريال ملاصق بعد الرقم بالعربية، وSAR بعد الرقم بالإنجليزية.
class AppMoney {
  AppMoney._();

  /// رمز الريال الرسمي في يونيكود (U+20C1). Cairo/Noto لا يغطيانه فيظهر مربع □.
  static const String saudiRiyalSignUnicode = '\u{20C1}';

  /// ﷼ (U+FDFC) للنصوص/المشاركة عندما لا يُعرض SVG.
  static const String saudiRiyalSignCompat = '\u{FDFC}';

  /// رمز العملة النصي حسب اللغة.
  static String sarUiSuffix({required bool isAr}) {
    return isAr ? saudiRiyalSignCompat : 'SAR';
  }

  /// المبلغ ثم العملة: `1234﷼` بالعربية و`1234 SAR` بالإنجليزية.
  static String sarPhrase(String amountText, {required bool isAr}) {
    final t = amountText.trim();
    final suffix = sarUiSuffix(isAr: isAr);
    return isAr ? '\u202A$t$suffix\u202C' : '$t $suffix';
  }

  /// يزيل رموز/اختصارات الريال من حقل إدخال قبل التحليل.
  static String stripSarMarks(String raw) {
    return raw
        .replaceAll('ر.س', '')
        .replaceAll('ر. س', '')
        .replaceAll('ريال', '')
        .replaceAll('Riyal', '')
        .replaceAll('riyal', '')
        .replaceAll(saudiRiyalSignUnicode, '')
        .replaceAll(saudiRiyalSignCompat, '')
        .replaceAll('SAR', '')
        .replaceAll('sar', '')
        .replaceAll('\u202A', '')
        .replaceAll('\u202C', '')
        .replaceAll('\u200E', '')
        .replaceAll('\u200F', '');
  }

  /// تقريب مبلغ بالريال (منزلتان عشريتان افتراضياً).
  static double roundSar(double value, {int fractionDigits = 2}) {
    if (value.isNaN || value.isInfinite) return value;
    final f = math.pow(10, fractionDigits).toDouble();
    return (value * f).round() / f;
  }

  /// تقريب سعر المتر المربع بعد القسمة.
  static double roundPricePerSqm(double value) {
    final v = roundSar(value, fractionDigits: 6);
    if (v >= 100000) return roundSar(v, fractionDigits: 0);
    if (v >= 10000) return roundSar(v, fractionDigits: 0);
    if (v >= 1000) return roundSar(v, fractionDigits: 1);
    return roundSar(v, fractionDigits: 2);
  }

  static String formatNumber(
    double value, {
    required bool isAr,
    int maxFractionDigits = 2,
  }) {
    final rounded = roundSar(value, fractionDigits: maxFractionDigits);
    // Product rule: keep digits Latin even in Arabic UI, with clear large-number separators.
    const locale = 'en_US';
    final pattern =
        maxFractionDigits <= 0 ? '#,##0' : '#,##0.${'#' * maxFractionDigits}';
    return NumberFormat(pattern, locale).format(rounded);
  }

  /// نص فقط (مشاركة، أسطر متعددة): الرقم ثم ﷼.
  static String formatWithCurrencyCode(
    double amount, {
    required bool isAr,
    String currencyCode = 'SAR',
    int maxFractionDigits = 2,
  }) {
    final code = currencyCode.trim().toUpperCase();
    final fmt = formatNumber(
      amount,
      isAr: isAr,
      maxFractionDigits: maxFractionDigits,
    );
    return code == 'SAR' ? sarPhrase(fmt, isAr: isAr) : '$code $fmt';
  }

  /// PDF — الرقم ثم ﷼ دائماً. لا ر.س ولا SAR (تظهر مربعات إن غاب الرمز في الخط).
  static String formatForPdf(
    double amount, {
    required bool isAr,
    String currencyCode = 'SAR',
    int maxFractionDigits = 2,
  }) {
    final fmt = formatNumber(
      amount,
      isAr: isAr,
      maxFractionDigits: maxFractionDigits,
    );
    final code = currencyCode.trim().toUpperCase();
    if (code == 'SAR') {
      return isAr ? '$fmt$saudiRiyalSignCompat' : '$fmt SAR';
    }
    return '$fmt $code';
  }

  /// CSV / Excel — نص «ريال» بدلاً من رمز يونيكود (Excel لا يعرضه).
  static String formatForExport(
    double amount, {
    required bool isAr,
    String currencyCode = 'SAR',
    int maxFractionDigits = 2,
  }) {
    final fmt = formatNumber(
      amount,
      isAr: isAr,
      maxFractionDigits: maxFractionDigits,
    );
    final code = currencyCode.trim().toUpperCase();
    if (code == 'SAR') {
      return isAr ? '$fmt$saudiRiyalSignCompat' : '$fmt SAR';
    }
    return '$fmt $code';
  }
}

/// الرقم ثم رمز الريال SVG بالعربية، والرقم ثم SAR بالإنجليزية.
class AppMoneyInline extends StatelessWidget {
  final String amountText;
  final bool isAr;
  final TextStyle? style;
  final Color? symbolColor;

  const AppMoneyInline({
    super.key,
    required this.amountText,
    required this.isAr,
    this.style,
    this.symbolColor,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = amountText.trim();
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final rawFont = baseStyle.fontSize ?? 14;
    final fontSize = MediaQuery.textScalerOf(context).scale(rawFont).clamp(10.0, 48.0);
    final color = baseStyle.color ?? Theme.of(context).colorScheme.onSurface;
    final symColor = symbolColor ?? color;
    final mergedStyle = baseStyle.merge(
      TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.15,
        color: color,
        fontSize: fontSize,
        height: 1.0,
      ),
    );

    final amount = Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Text(
        fmt,
        style: mergedStyle,
        maxLines: 1,
        softWrap: false,
      ),
    );
    final gap = SizedBox(width: (fontSize * 0.18).clamp(2.0, 6.0));
    final currency = isAr
        ? SaudiRiyalSymbolIcon(size: fontSize, color: symColor)
        : Text(
            'SAR',
            style: mergedStyle.copyWith(
              fontSize: (fontSize * 0.72).clamp(10.0, 32.0),
              color: symColor,
            ),
          );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: ui.TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [amount, if (!isAr) gap, currency],
      ),
    );
  }
}

/// سطر مبلغ مع رمز الريال (SVG) بعد الرقم عند SAR.
class AppMoneyLine extends StatelessWidget {
  final double amount;
  final String currencyCode;
  final bool isAr;
  final TextStyle? style;
  final int maxFractionDigits;

  /// لون رمز الريال SVG؛ الافتراضي يتبع لون النص (فاتح/داكن).
  final Color? symbolColor;

  const AppMoneyLine({
    super.key,
    required this.amount,
    required this.currencyCode,
    required this.isAr,
    this.style,
    this.maxFractionDigits = 2,
    this.symbolColor,
  });

  @override
  Widget build(BuildContext context) {
    final code = currencyCode.trim().toUpperCase();
    final rounded =
        AppMoney.roundSar(amount, fractionDigits: maxFractionDigits);
    final fmt = AppMoney.formatNumber(
      rounded,
      isAr: isAr,
      maxFractionDigits: maxFractionDigits,
    );

    if (code != 'SAR') {
      return Text('$fmt $code', style: style);
    }

    if (!isAr) {
      return Text('$fmt SAR', style: style);
    }

    return AppMoneyInline(
      amountText: fmt,
      isAr: isAr,
      style: style,
      symbolColor: symbolColor,
    );
  }
}
