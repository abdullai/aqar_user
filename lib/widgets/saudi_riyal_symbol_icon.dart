import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// الرسم الرسمي لرمز الريال السعودي (مسار SAMA) كأيقونة متجهة بجانب المبالغ.
class SaudiRiyalSymbolIcon extends StatelessWidget {
  /// ارتفاع الرمز؛ العرض يُحسب تلقائياً حسب نسبة الشكل.
  final double size;
  final Color color;
  final EdgeInsetsGeometry? padding;

  const SaudiRiyalSymbolIcon({
    super.key,
    required this.size,
    required this.color,
    this.padding,
  });

  static const String assetPath = 'assets/currency/saudi_riyal_symbol.svg';

  @override
  Widget build(BuildContext context) {
    final h = size;
    final w = size * 1.08;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: SizedBox(
        width: w,
        height: h,
        child: SvgPicture.asset(
          assetPath,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          semanticsLabel: 'SAR',
        ),
      ),
    );
  }
}
