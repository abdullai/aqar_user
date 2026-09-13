import 'package:flutter/material.dart';

/// إغلاق الصفحة/الطبقة الحالية دون إسقاط هيكل اللوحة إلى تبويب الرئيسية
/// ودون الخروج إلى شاشة تسجيل الدخول.
///
/// ترتيب الإغلاق (طبقة واحدة في كل مرة):
/// 1) الملاح المحلي إن كان فوق الجذر وليس هيكل التطبيق
/// 2) ملاح جسم اللوحة (إعدادات / إدارتي / مفضلة…)
/// 3) الملاح الجذر إن كان فوق هيكل اللوحة (تفاصيل / خريطة / دردشة / دعم)
///
/// لا يُغلق المسار الأول ولا مسارات `/` و`/userDashboard` ولا مسارات الدخول.
abstract final class SafeOverlayPop {
  /// يُحقَن من [UserDashboard] — يغلق مساراً واحداً من جسم اللوحة فقط.
  static bool Function()? popNested;

  /// يحدد إن كان هناك مسار ظاهر يمكن إغلاقه دون إسقاط هيكل التطبيق.
  /// يستخدمه شريط الصفحة حتى لا يعرض زر X لا يملك عملية إغلاق حقيقية.
  static bool canPop({
    NavigatorState? root,
    NavigatorState? nested,
    bool Function()? popNestedOverride,
  }) {
    if (root != null && _hasOverlay(root)) return true;
    final nestedPop = popNestedOverride ?? popNested;
    if (nestedPop != null) return true;
    if (nested != null && _hasOverlay(nested)) return true;
    return false;
  }

  static bool _hasOverlay(NavigatorState nav) {
    if (!nav.canPop()) return false;
    final top = peekTop(nav);
    return top is PopupRoute || !isShellRoute(top);
  }

  static bool isAppShellName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    if (n.isEmpty) return false;
    if (n == '/' ||
        n == '/userdashboard' ||
        n == '/dashboard' ||
        n == '/dashboard/root' ||
        n == '/start' ||
        n == '/postloginhome' ||
        n == '/postlogin') {
      return true;
    }
    if (n == '/login' ||
        n.startsWith('/login') ||
        n.contains('fastlogin') ||
        n.contains('verify') ||
        n.contains('password') && n.contains('setup')) {
      return true;
    }
    return false;
  }

  static bool isShellRoute(Route<dynamic>? route) {
    if (route == null) return true;
    if (route.isFirst) return true;
    return isAppShellName(route.settings.name);
  }

  static Route<dynamic>? peekTop(NavigatorState nav) {
    Route<dynamic>? top;
    try {
      nav.popUntil((route) {
        top = route;
        return true;
      });
    } catch (_) {}
    return top;
  }

  static String peekTopName(NavigatorState? nav) {
    if (nav == null) return '';
    return (peekTop(nav)?.settings.name ?? '').trim();
  }

  /// يغلق طبقة واحدة فوق الهيكل — لا يُسقط المسار الأول ولا شاشة الدخول.
  static bool popIfOverlay(NavigatorState nav, [Object? result]) {
    if (!nav.canPop()) return false;
    final top = peekTop(nav);
    // حوارات/شيتات تُغلق دائماً حتى لو حُملت اسماً مشابهاً للهيكل.
    if (top is PopupRoute) {
      nav.pop(result);
      return true;
    }
    if (isShellRoute(top)) return false;
    nav.pop(result);
    return true;
  }

  /// رجوع المتصفح/النظام: الطبقة الظاهرة أولاً (جذر) ثم جسم اللوحة.
  static bool popLayer({
    NavigatorState? root,
    NavigatorState? nested,
    bool Function()? popNestedOverride,
  }) {
    if (root != null && popIfOverlay(root)) return true;
    final nestedPop = popNestedOverride ?? popNested;
    if (nestedPop?.call() == true) return true;
    if (nested != null && popIfOverlay(nested)) return true;
    return false;
  }

  /// يغلق المسار الأقرب الذي يمكن إغلاقه — حصراً الشاشة السابقة، لا الرئيسية.
  static bool pop(BuildContext context, [Object? result]) {
    try {
      final route = ModalRoute.of(context);
      final local = Navigator.of(context);
      if (local.canPop() &&
          (route is PopupRoute || (route != null && !isShellRoute(route)))) {
        local.pop(result);
        return true;
      }
    } catch (_) {}
    try {
      final local = Navigator.of(context);
      if (popIfOverlay(local, result)) return true;
    } catch (_) {}
    if (popNested?.call() == true) return true;
    try {
      final root = Navigator.of(context, rootNavigator: true);
      if (root.canPop() && popIfOverlay(root, result)) return true;
    } catch (_) {}
    return false;
  }
}
