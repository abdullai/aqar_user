import 'package:flutter/material.dart';

/// زر إغلاق موحّد (X) للرجوع/إغلاق الصفحة الحالية — مقابل قائمة ⋮ عادةً.
class AppPageCloseButton extends StatelessWidget {
  const AppPageCloseButton({
    super.key,
    this.onPressed,
    this.tooltip,
    this.color,
    this.isArabic = true,
  });

  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final bool isArabic;

  /// يضع زر الإغلاق في [AppBar.leading] (الجهة المقابلة لـ actions / ⋮).
  static Widget? leadingOf(
    BuildContext context, {
    bool enabled = true,
    VoidCallback? onPressed,
    bool isArabic = true,
    Color? color,
  }) {
    if (!enabled) return null;
    final canPop = onPressed != null || (Navigator.of(context).canPop());
    if (!canPop && onPressed == null) return null;
    return AppPageCloseButton(
      isArabic: isArabic,
      color: color,
      onPressed: onPressed ??
          () {
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.pop();
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip ?? (isArabic ? 'إغلاق' : 'Close'),
      icon: Icon(Icons.close_rounded, color: color ?? cs.onSurface),
      onPressed: onPressed,
    );
  }
}
