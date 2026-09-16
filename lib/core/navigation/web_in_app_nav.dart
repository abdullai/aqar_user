import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/inactivity_auth_landing.dart';
import '../auth/safe_sign_out_service.dart';
import '../session/web_visibility.dart';
import '../../services/fast_login_service.dart';
import 'safe_overlay_pop.dart';
import 'sensitive_nav_policy.dart';
import 'web_in_app_history.dart';
import 'web_in_app_replay.dart';

/// يربط أزرار المتصفح (رجوع/تقدّم/سحب الحافة) بمكدّس Flutter ولا يغادر الموقع.
abstract final class WebInAppNav {
  WebInAppNav._();

  static GlobalKey<NavigatorState>? nestedNavigatorKey;
  static bool Function()? popNested;

  static final List<WebInAppReplay> _forward = [];
  static bool _fromHistory = false;
  static bool _armed = false;
  static int _holdBack = 0;
  static int _sealDepth = 0;
  static int _programmaticPopDepth = 0;
  static DateTime? _flutterPopAt;

  static bool get _sealing => _sealDepth > 0;

  static void install() {
    if (!kIsWeb || _armed) return;
    _armed = true;
    installWebInAppHistory(onTraverse: _onTraverse);
    listenDocumentPageShow(({required bool persisted}) {
      if (!persisted) return;
      unawaited(_onBfCacheRestore());
    });
  }

  static void dispose() {
    if (!_armed) return;
    _armed = false;
    disposeWebInAppHistory();
    nestedNavigatorKey = null;
    popNested = null;
    _forward.clear();
  }

  /// يمنع تذكّر المسارات أثناء الخروج حتى لا يعيد السهم الأيمن الشاشة السابقة.
  static void beginAuthSeal() {
    _sealDepth++;
    _forward.clear();
  }

  static void endAuthSeal() {
    if (_sealDepth > 0) _sealDepth--;
  }

  static void clearReplayStack() {
    _forward.clear();
  }

  /// Marks a Flutter close action so its NavigatorObserver pop is not replayed
  /// as a second browser-history back action.
  static void runProgrammaticPop(VoidCallback action) {
    _programmaticPopDepth++;
    try {
      action();
    } finally {
      if (_programmaticPopDepth > 0) _programmaticPopDepth--;
    }
  }

  static void sealBrowserToLogin() {
    if (!kIsWeb) return;
    _forward.clear();
    webInAppHistorySealAuth();
  }

  static void notePush(Route<dynamic> route, {required bool nested}) {
    if (!kIsWeb || _fromHistory || _sealing) return;
    if (route is! PageRoute) return;
    if (SensitiveNavPolicy.isSensitiveReplayName(route.settings.name)) return;
    webInAppHistoryPushEntry();
  }

  /// يمنع رجوع المتصفح من إسقاط النموذج/الخريطة أثناء إذن الموقع أو تأكيد الدبوس.
  static void holdBack() {
    if (!kIsWeb) return;
    _holdBack++;
    webInAppHistoryHold();
  }

  static void releaseBack() {
    if (!kIsWeb) return;
    if (_holdBack > 0) _holdBack--;
    webInAppHistoryRelease();
  }

  static void notePop(Route<dynamic> route, {required bool nested}) {
    if (!kIsWeb) return;
    if (_sealing) return;
    if (SensitiveNavPolicy.isSensitiveReplayName(route.settings.name)) {
      return;
    }
    // حوارات/شيتات/قوائم ليست صفحات — مزامنتها مع التاريخ تُغلق نموذج + أو الخريطة.
    if (route is PopupRoute) {
      return;
    }
    if (_programmaticPopDepth > 0) {
      return;
    }
    _remember(route, nested: nested);
    if (_fromHistory) return;
    if (route is! PageRoute) return;
    _flutterPopAt = DateTime.now();
    webInAppHistoryGoBack();
  }

  static void _remember(Route<dynamic> route, {required bool nested}) {
    if (SensitiveNavPolicy.isSensitiveReplayName(route.settings.name)) return;
    WebInAppReplay? snap;
    if (route is MaterialPageRoute) {
      snap = WebInAppReplay(
        nested: nested,
        materialBuilder: route.builder,
        settings: route.settings,
        fullscreenDialog: route.fullscreenDialog,
      );
    } else if (route is PageRouteBuilder) {
      snap = WebInAppReplay(
        nested: nested,
        pageBuilder: route.pageBuilder,
        settings: route.settings,
      );
    }
    if (snap == null) return;
    _forward.add(snap);
    if (_forward.length > 20) _forward.removeAt(0);
  }

  static Future<void> _onTraverse({
    required bool isForward,
    required bool leavingOrigin,
  }) async {
    if (isForward) {
      await _replayForward();
      return;
    }
    if (leavingOrigin) return;
    await handleBack();
  }

  static bool _hasAuthSession() {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _onBfCacheRestore() async {
    if (SensitiveNavPolicy.isVerifyOpen ||
        SensitiveNavPolicy.isDeleteListingOpen) {
      await WebInAppNavHost.signOutSensitive();
      return;
    }
    if (!_hasAuthSession()) {
      _forward.clear();
      await WebInAppNavHost.openAuthLanding();
    }
  }

  static Future<void> handleBack() async {
    if (_holdBack > 0) {
      webInAppHistoryTrapLeaving();
      return;
    }
    final recent = _flutterPopAt;
    if (recent != null &&
        DateTime.now().difference(recent) < const Duration(milliseconds: 480)) {
      webInAppHistoryTrapLeaving();
      return;
    }
    _fromHistory = true;
    try {
      if (SensitiveNavPolicy.isDeleteListingOpen ||
          SensitiveNavPolicy.isVerifyOpen) {
        await WebInAppNavHost.signOutSensitive();
        return;
      }
      final root = WebInAppNavHost.rootState();
      final name = SafeOverlayPop.peekTopName(root);
      if (SensitiveNavPolicy.isVerifyRouteName(name)) {
        await WebInAppNavHost.signOutSensitive();
        return;
      }
      if (SensitiveNavPolicy.isAuthGateRouteName(name)) {
        // شاشات الدخول: اترك سهم المتصفح عند المصيدة دون وميض أو مغادرة.
        webInAppHistoryTrapLeaving();
        return;
      }
      // طبقة واحدة: الشاشة السابقة حصراً (تفاصيل/خريطة/دردشة) ثم جسم اللوحة.
      final popped = SafeOverlayPop.popLayer(
        root: root,
        nested: nestedNavigatorKey?.currentState,
        popNestedOverride: popNested,
      );
      if (!popped) {
        webInAppHistoryTrapLeaving();
      }
    } finally {
      _fromHistory = false;
    }
  }

  static Future<void> _replayForward() async {
    if (_sealing) {
      _forward.clear();
      return;
    }
    final root = WebInAppNavHost.rootState();
    final top = SafeOverlayPop.peekTopName(root);
    if (!_hasAuthSession()) {
      _forward.clear();
      if (!SensitiveNavPolicy.isAuthGateRouteName(top)) {
        await WebInAppNavHost.openAuthLanding();
      }
      return;
    }
    if (SensitiveNavPolicy.isVerifyOpen ||
        SensitiveNavPolicy.isVerifyRouteName(top)) {
      _forward.clear();
      await WebInAppNavHost.signOutSensitive();
      return;
    }
    if (SensitiveNavPolicy.isAuthGateRouteName(top)) {
      _forward.clear();
      return;
    }
    if (_forward.isEmpty) return;
    _fromHistory = true;
    try {
      while (_forward.isNotEmpty) {
        final snap = _forward.removeLast();
        if (SensitiveNavPolicy.isSensitiveReplayName(snap.settings.name)) {
          continue;
        }
        final route = snap.toRoute();
        if (route == null) continue;
        if (snap.nested) {
          final n = nestedNavigatorKey?.currentState;
          if (n != null) {
            await n.push(route);
            return;
          }
        }
        if (root != null) {
          await root.push(route);
          return;
        }
      }
    } finally {
      _fromHistory = false;
    }
  }
}

class WebInAppNavObserver extends NavigatorObserver {
  WebInAppNavObserver({this.nested = false});

  final bool nested;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    WebInAppNav.notePush(route, nested: nested);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    WebInAppNav.notePop(route, nested: nested);
  }
}

/// يُحقَن من [WebBrowserLifecycleHost] بمفتاح الملاح الجذر.
abstract final class WebInAppNavHost {
  static GlobalKey<NavigatorState>? navigatorKey;

  static NavigatorState? rootState() => navigatorKey?.currentState;

  static Future<void> openAuthLanding() async {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    WebInAppNav.beginAuthSeal();
    try {
      String dest = '/login';
      try {
        dest = await FastLoginService.resolveInactivityLockRoute();
      } catch (_) {}
      if (dest != '/fastLogin' && dest != '/login') dest = '/login';
      InactivityAuthLanding.begin(route: dest);
      nav.pushNamedAndRemoveUntil(dest, (r) => false);
      WebInAppNav.sealBrowserToLogin();
    } finally {
      WebInAppNav.endAuthSeal();
    }
  }

  static Future<void> signOutSensitive() async {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    InactivityAuthLanding.begin(route: '/login');
    await SafeSignOutService.signOutAndNavigateToLogin(
      ctx,
      logoutReason: 'sensitive_nav_exit',
    );
  }
}
