import 'package:flutter/material.dart';

import '../core/navigation/safe_overlay_pop.dart';
import '../core/navigation/web_in_app_nav.dart';

/// زر إغلاق موحّد (X) لكل صفحة / نافذة / شيت.
///
/// المكان والاتجاه من [Directionality] فقط: في العربية (RTL) على اليمين،
/// وفي الإنجليزية (LTR) على اليسار — نفس جهة [AppBar.leading].
/// بلا [onPressed]: يرجع حصراً إلى الشاشة السابقة عبر [SafeOverlayPop]
/// إذا [Navigator.canPop]، ولا يُسقط هيكل اللوحة ولا يذهب للرئيسية عشوائياً.
class AppPageCloseButton extends StatelessWidget {
  const AppPageCloseButton({
    super.key,
    this.onPressed,
    this.tooltip,
    this.color,
    this.isArabic,
    this.iconSize = 22,
    this.visualDensity,
    this.enabled = true,
  });

  final VoidCallback? onPressed;
  final String? tooltip;

  /// إن وُجد يُستخدم للأيقونة فقط؛ الموضع دائماً حسب اتجاه الواجهة.
  final Color? color;

  /// اختياري ومتقادم للوضع — لا يُقلَب الزر يدوياً. التلميح يُشتق من الاتجاه إن لزم.
  final bool? isArabic;
  final double iconSize;
  final VisualDensity? visualDensity;
  final bool enabled;

  /// [AppBar.leading] الذكي: يظهر فقط إن وُجد مسار سابق أو [onPressed].
  static Widget? leadingOf(
    BuildContext context, {
    bool enabled = true,
    VoidCallback? onPressed,
    Color? color,
    String? tooltip,
    double iconSize = 22,
  }) {
    if (!enabled) return null;
    final canPop = onPressed != null ||
        SafeOverlayPop.canPop(
          root: Navigator.of(context, rootNavigator: true),
          nested: Navigator.of(context),
        );
    if (!canPop) return null;
    return AppPageCloseButton(
      color: color,
      tooltip: tooltip,
      iconSize: iconSize,
      onPressed: onPressed ?? () => SafeOverlayPop.pop(context),
    );
  }

  /// زاوية البداية داخل [Stack]/صف: يمين في RTL ويسار في LTR.
  static Widget startCorner({
    Key? key,
    VoidCallback? onPressed,
    Color? color,
    String? tooltip,
    double iconSize = 22,
  }) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppPageCloseButton(
        key: key,
        onPressed: onPressed,
        color: color,
        tooltip: tooltip,
        iconSize: iconSize,
      ),
    );
  }

  static void _defaultPop(BuildContext context) {
    SafeOverlayPop.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loc = MaterialLocalizations.of(context);
    final _ = isArabic;
    return IconButton(
      tooltip: tooltip ?? loc.closeButtonTooltip,
      visualDensity: visualDensity,
      icon: Icon(
        Icons.close_rounded,
        size: iconSize,
        color: color ?? cs.onSurface,
      ),
      onPressed: !enabled
          ? null
          : () => WebInAppNav.runProgrammaticPop(
                onPressed ?? () => _defaultPop(context),
              ),
    );
  }
}
