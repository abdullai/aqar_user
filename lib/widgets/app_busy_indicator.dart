import 'package:flutter/material.dart';

/// مؤشر تحميل بيانات خفيف موحّد — بدون شعار التطبيق.
/// استخدمه في الأزرار والقوائم وأماكن انتظار الشبكة فقط.
class AppBusyIndicator extends StatelessWidget {
  const AppBusyIndicator({
    super.key,
    this.size = 22,
    this.strokeWidth = 2.4,
    this.color,
    this.label,
  });

  final double size;
  final double strokeWidth;
  final Color? color;
  final String? label;

  /// داخل زر مزدحم (تسجيل دخول / حفظ…).
  factory AppBusyIndicator.button({
    Key? key,
    String? label,
    Color color = Colors.white,
  }) {
    return AppBusyIndicator(
      key: key,
      size: 20,
      strokeWidth: 2.2,
      color: color,
      label: label,
    );
  }

  /// صفحة كاملة أثناء جلب البيانات.
  factory AppBusyIndicator.page({Key? key, Color? color}) {
    return AppBusyIndicator(
      key: key,
      size: 36,
      strokeWidth: 3,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spinner = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color ?? cs.primary,
      ),
    );
    final text = (label ?? '').trim();
    if (text.isEmpty) return spinner;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        spinner,
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: color ?? cs.onPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
