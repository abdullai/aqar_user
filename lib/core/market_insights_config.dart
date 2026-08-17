// lib/core/market_insights_config.dart
//
// مصدر واحد لسياسة التحديث (الصفحة + أي شاشة لاحقة تربط بنفس البيانات).

import 'package:flutter/material.dart';

@immutable
abstract final class MarketInsightsConfig {
  /// بعد هذه المدة من آخر جلب ناجح يُسمح بتحديث خلفي تلقائي.
  static const Duration staleAfter = Duration(hours: 2);

  /// فحص دوري خفيف (بدون شبكة إلا إذا انتهت صلاحية [staleAfter]).
  static const Duration pollInterval = Duration(hours: 2);
}
