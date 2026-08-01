import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// الرسم الرسمي لرمز الريال السعودي (مسار SAMA) كأيقونة متجهة بجانب المبالغ.
///
/// مهم: لا تضع هذا الودجت داخل [Text.rich]/[WidgetSpan] على الويب مع
/// [ColorFilter] — استخدمه داخل [Row] بجانب الرقم.
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
    final h = size.clamp(8.0, 64.0);
    final w = h * 1.08;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: SizedBox(
        width: w,
        height: h,
        child: SvgPicture.asset(
          assetPath,
          fit: BoxFit.contain,
          // خارج Text.rich آمن على الويب؛ داخل WidgetSpan كان يسبب crash.
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          semanticsLabel: 'SAR',
          placeholderBuilder: (_) => FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              kIsWeb && Directionality.of(context) == TextDirection.rtl
                  ? '﷼'
                  : 'SAR',
              style: TextStyle(
                fontSize: h * 0.72,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
