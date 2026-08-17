import 'package:flutter/material.dart';

/// ألوان هوية «موثوق لاين» من نظام التصميم الشبكي (مثال الواجهة).
abstract final class AqarBrandColors {
  static const Color dark = Color(0xFF05221B);
  static const Color primary = Color(0xFF0B4D3E);
  static const Color light = Color(0xFF147A64);
  static const Color gold = Color(0xFFDFB230);
  static const Color goldHover = Color(0xFFCBA028);
  static const Color bg = Color(0xFFF3FAF8);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE1EDEA);
  static const Color accent = Color(0xFFEBF6F3);
  static const Color alertRed = Color(0xFFDA3E27);
  static const Color alertBg = Color(0xFFFFF2F0);

  /// إطار ذهبي للطلبات المدفوعة / ذات الأولوية النشطة.
  static Border goldPriorityBorder({double width = 1.8}) => Border.all(
        color: gold.withValues(alpha: 0.85),
        width: width,
      );

  static List<BoxShadow> premiumShadow = [
    BoxShadow(
      color: primary.withValues(alpha: 0.08),
      blurRadius: 28,
      offset: const Offset(0, 12),
      spreadRadius: -6,
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
}
