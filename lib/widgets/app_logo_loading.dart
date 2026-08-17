import 'package:flutter/material.dart';

import 'app_busy_indicator.dart';

/// مؤشر تحميل بيانات — يوجّه إلى [AppBusyIndicator] الخفيف (بدون شعار التطبيق).
/// الإبقاء على الاسم يحافظ على كل الاستدعاءات الحالية دون عبث واسع.
class AppLogoLoading extends StatelessWidget {
  const AppLogoLoading({
    super.key,
    this.size = 96,
    this.compact = false,
  });

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final indicatorSize = compact
        ? size.clamp(16.0, 28.0).toDouble()
        : (size > 48 ? 36.0 : size.clamp(22.0, 40.0).toDouble());
    return AppBusyIndicator(
      size: indicatorSize,
      strokeWidth: compact ? 2.2 : 3.0,
    );
  }
}
