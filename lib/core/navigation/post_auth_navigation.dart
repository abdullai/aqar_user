import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/inactivity_service.dart';
import '../../services/user_session_coordination_service.dart';
import 'root_overlay_guard.dart';
import 'start_router_controller.dart';
import 'web_interaction_recovery.dart';

/// انتقال آمن إلى اللوحة أو مسار post-auth — يزيل الطبقات العالقة ويحدّث ساعة الخمول.
abstract final class PostAuthNavigation {
  static GlobalKey<NavigatorState>? get _rootKey =>
      UserSessionCoordinationService.navigatorKey;

  /// ويب: اللوحة عبر [StartRouter] عند `/` — `/userDashboard` كمسار جذر يُجمّد المتصفح.
  static String resolveDashboardRoute(String route) {
    if (!kIsWeb) return route;
    final n = route.trim().toLowerCase();
    if (n == '/userdashboard' || n == 'userdashboard') return '/';
    return route;
  }

  static Future<void> prepareForDashboardEntry() async {
    RootOverlayGuard.dismissOverlayRoutes(_rootKey);
    await InactivityService.prepareDashboardEntry();
    WebInteractionRecovery.dismissStuckOverlaysOnce();
  }

  /// ويب + `/`: ارجع للجذر وحدّث [StartRouter] — لا تُعد بناء المكدس (كان يُجمّد).
  static Future<void> _replaceStackWithRoute(
    NavigatorState nav,
    String route, {
    Object? arguments,
  }) async {
    final resolved = resolveDashboardRoute(route);
    if (kIsWeb && resolved == '/') {
      if (nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      }
      if (await StartRouterController.refreshInPlaceIfRegistered()) {
        return;
      }
    }
    nav.pushNamedAndRemoveUntil(
      resolved,
      (r) => false,
      arguments: arguments,
    );
  }

  static Future<void> openDashboard(
    BuildContext context, {
    Object? arguments,
  }) async {
    await prepareForDashboardEntry();
    if (!context.mounted) return;
    await _replaceStackWithRoute(
      Navigator.of(context, rootNavigator: true),
      '/userDashboard',
      arguments: arguments,
    );
    _afterWebDashboardNav();
  }

  static Future<void> openRouteReplacingStack(
    BuildContext context,
    String route, {
    Object? arguments,
  }) async {
    await prepareForDashboardEntry();
    if (!context.mounted) return;
    await _replaceStackWithRoute(
      Navigator.of(context, rootNavigator: true),
      route,
      arguments: arguments,
    );
    _afterWebDashboardNav();
  }

  static Future<void> navigatorOpenRouteReplacingStack(
    NavigatorState nav,
    String route, {
    Object? arguments,
  }) async {
    await prepareForDashboardEntry();
    await _replaceStackWithRoute(nav, route, arguments: arguments);
    _afterWebDashboardNav();
  }

  static void _afterWebDashboardNav() {
    if (!kIsWeb) return;
    WebInteractionRecovery.dismissStuckOverlaysOnce();
    WebInteractionRecovery.scheduleDashboardRecovery(
      forDuration: const Duration(seconds: 12),
    );
  }
}
