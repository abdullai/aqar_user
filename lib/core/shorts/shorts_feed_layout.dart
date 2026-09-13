import 'package:flutter/material.dart';

/// مقاسات ذكية للفيد حسب الجوال / التابلت / سطح المكتب.
final class ShortsFeedLayout {
  ShortsFeedLayout._({
    required this.compact,
    required this.wide,
    required this.railWidth,
    required this.actionPad,
    required this.actionIcon,
    required this.titleSize,
    required this.gap,
    required this.bottomCaption,
  });

  final bool compact;
  final bool wide;
  final double railWidth;
  final double actionPad;
  final double actionIcon;
  final double titleSize;
  final double gap;
  final bool bottomCaption;

  factory ShortsFeedLayout.of(Size size) {
    final short = size.shortestSide;
    final tall = size.height;
    final compact = short < 380 || tall < 620;
    final wide = size.width >= 720;
    return ShortsFeedLayout._(
      compact: compact,
      wide: wide,
      railWidth: compact ? 56 : (wide ? 72 : 62),
      actionPad: compact ? 8 : (wide ? 11 : 9),
      actionIcon: compact ? 22 : (wide ? 26 : 24),
      titleSize: compact ? 15 : (wide ? 20 : 17),
      gap: compact ? 10 : 12,
      bottomCaption: false,
    );
  }
}
