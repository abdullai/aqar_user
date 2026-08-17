import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/platform/web_browser_lifecycle.dart';
import '../core/navigation/app_web_soft_refresh.dart';
import '../services/user_session_coordination_service.dart';
import 'app_back_refresh_dialogs.dart';

/// يربط F5/تحديث المتصفح بحوار Flutter وتحديث ناعم (بدون تسجيل خروج).
class WebBrowserLifecycleHost extends StatefulWidget {
  const WebBrowserLifecycleHost({
    super.key,
    required this.lang,
    required this.child,
  });

  final String lang;
  final Widget child;

  @override
  State<WebBrowserLifecycleHost> createState() => _WebBrowserLifecycleHostState();
}

class _WebBrowserLifecycleHostState extends State<WebBrowserLifecycleHost> {
  bool get _isAr => widget.lang == 'ar';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    installWebBrowserLifecycle(
      shouldOfferRefresh: _shouldOfferRefresh,
      onRefreshPrompt: _promptRefresh,
    );
  }

  @override
  void dispose() {
    if (kIsWeb) {
      disposeWebBrowserLifecycle();
    }
    super.dispose();
  }

  bool _shouldOfferRefresh() {
    final name = _currentRouteName();
    if (name.isEmpty) return false;
    const blocked = {
      '/login',
      '/verify',
      '/resetPassword',
      '/passwordSetup',
      '/fastLogin',
      '/gate',
    };
    if (blocked.contains(name)) return false;
    return name == '/userDashboard' ||
        name == '/userdashboard' ||
        name == '/' ||
        name == '/entryChoice' ||
        name == '/settings' ||
        name.startsWith('/dashboard');
  }

  String _currentRouteName() {
    final nav = UserSessionCoordinationService.navigatorKey?.currentState;
    if (nav == null) return '';
    final ctx = UserSessionCoordinationService.navigatorKey?.currentContext;
    return ModalRoute.of(ctx ?? nav.context)?.settings.name ?? '';
  }

  Future<bool> _promptRefresh() async {
    // تحديث ناعم مباشرة دون حوار — المستخدم طلب نفس الصفحة محدّثة بلا خروج.
    if (AppWebSoftRefresh.hasHandler) {
      await AppWebSoftRefresh.invoke();
      return false;
    }
    final ctx = UserSessionCoordinationService.navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    return AppBackRefreshDialogs.confirmSoftRefresh(ctx, _isAr);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return wrapWebBrowserRefreshShortcuts(
      onRefreshPrompt: _promptRefresh,
      shouldOfferRefresh: _shouldOfferRefresh,
      child: widget.child,
    );
  }
}
