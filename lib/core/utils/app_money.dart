import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/saudi_riyal_symbol_icon.dart';

/// تقريب المبالغ وعرضها: عملة SAR مع [SaudiRiyalSymbolIcon] بجانب الرقم؛ غير SAR كنص.
class AppMoney {
  AppMoney._();

  /// رمز الريال في يونيكود (للنصوص/المشاركة حيث لا يُعرض SVG).
  static const String saudiRiyalSignUnicode = '\u{20C1}';

  /// لعرض الواجهة كنص فقط: عربي → ر.س، إنجليزي → SAR.
  /// لا تستخدم U+20C1 هنا — Cairo/Noto لا يغطيانه فيظهر مربع □.
  /// للواجهة المرئية فضّل [AppMoneyLine] (SVG بجانب الرقم).
  static String sarUiSuffix({required bool isAr}) {
    return isAr ? 'ر.س' : 'SAR';
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

  /// نص فقط (مشاركة، أسطر متعددة): عربي + يونيكود؛ إنجليزي + `SAR`.
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
    if (code == 'SAR') {
      // عربي: الرمز على يسار الرقم (من منظور المستخدم) عبر بادئة LTR.
      return isAr
          ? '\u200E${sarUiSuffix(isAr: true)} $fmt'
          : '$fmt ${sarUiSuffix(isAr: false)}';
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
      return isAr ? '\u200Eر.س $fmt' : '$fmt SAR';
    }
    return '$fmt $code';
  }
}

/// سطر مبلغ مع رمز الريال (SVG) بجانب الرقم عند SAR.
class AppMoneyLine extends StatelessWidget {
  final double amount;
  final String currencyCode;
  final bool isAr;
  final TextStyle? style;
  final int maxFractionDigits;

  /// لون رمز الريال SVG؛ الافتراضي يتبع لون النص.
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

    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final rawFont = baseStyle.fontSize ?? 14;
    final textScaler = MediaQuery.textScalerOf(context);
    final fontSize = textScaler.scale(rawFont).clamp(10.0, 64.0);
    final color = baseStyle.color ?? Theme.of(context).colorScheme.onSurface;
    final symColor = symbolColor ?? color;
    final mergedStyle = baseStyle.merge(
      const TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.15,
      ),
    );

    // رقم + رمز الريال في Row (آمن على الويب؛ تجنّب WidgetSpan).
    // دائماً LTR داخل الصف: الرمز على يسار المستخدم ثم الرقم.
    final amountText = Text(
      fmt,
      style: mergedStyle,
      maxLines: 1,
      softWrap: false,
    );
    final symbol = SaudiRiyalSymbolIcon(
      size: fontSize * 1.02,
      color: symColor,
    );
    final gap = SizedBox(width: fontSize * 0.32);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: isAr
              ? [symbol, gap, amountText]
              : [amountText, gap, Text('SAR', style: mergedStyle)],
        ),
      ),
    );
  }
}
