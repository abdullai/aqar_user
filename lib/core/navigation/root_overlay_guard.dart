import 'package:flutter/material.dart';

/// يزيل حوارات/طبقات [showDialog] و[showGeneralDialog] العالقة فوق المسارات الجذرية.
///
/// بعد `pushNamedAndRemoveUntil` قد تبقى طبقة حاجزة شفافة (خمول، شبكة…) وتمنع اللمس
/// رغم ظهور اللوحة تحتها — يُستدعى قبل الانتقال للوحة أو تسجيل الدخول.
abstract final class RootOverlayGuard {
  /// يُغلق [PopupRoute] / حوارات فقط — **لا** يُزيل مسارات الصفحات (PageRoute).
  static void dismissOverlayRoutes(GlobalKey<NavigatorState>? navigatorKey) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    try {
      for (var pass = 0; pass < 4; pass++) {
        if (!nav.canPop()) break;
        nav.popUntil(
          (route) => route is PageRoute<dynamic> || route.isFirst,
        );
      }
    } catch (_) {}
  }

  /// للتوافق مع الاستدعاءات القديمة — يُغلق الطبقات العائمة فقط.
  static void dismissAll(GlobalKey<NavigatorState>? navigatorKey) {
    dismissOverlayRoutes(navigatorKey);
  }
}
