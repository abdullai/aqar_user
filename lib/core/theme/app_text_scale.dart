// lib/core/theme/app_text_scale.dart
//
// تكبير نص عالمي: يدمج إعدادات النظام + شريط المستخدم + تكيّف حجم الشاشة.
// استخدم [UnscaledTextScope] للشاشات الكثيفة (مثل لوحة PIN) حيث لا يُفضّل تكبير النص.

import 'package:flutter/material.dart';

/// عامل بسيط حسب أصغر بعد منطقي (هاتف ضيق / لوحي / سطح مكتب).
double appScreenTextAdaptFactor(Size logicalSize) {
  final s = logicalSize.shortestSide;
  final w = logicalSize.width;
  if (s < 320) return 0.92;
  if (s < 360) return 0.96;
  if (s < 400) return 1.0;
  if (w >= 1100) return 1.05;
  if (s > 600) return 1.04;
  return 1.0;
}

/// دمج: نظام × شريط الإعدادات × الشاشة، مع حدود لتقليل الكسر.
TextScaler buildAppCombinedTextScaler({
  required MediaQueryData mq,
  required double userSliderFactor,
  required Size logicalSize,
}) {
  final systemMul = mq.textScaler.scale(1.0);
  final screen = appScreenTextAdaptFactor(logicalSize);
  final raw = systemMul * userSliderFactor * screen;
  final clamped = raw.clamp(0.78, 1.58);
  return TextScaler.linear(clamped);
}

/// يعيد ضبط مضاعف النص إلى 1.0 لهذا الفرع فقط (لا يتأثر بتكبير التطبيق).
class UnscaledTextScope extends StatelessWidget {
  const UnscaledTextScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(1.0)),
      child: child,
    );
  }
}
