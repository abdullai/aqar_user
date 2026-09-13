import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/fast_login_service.dart';
import '../auth/auth_local_sign_out.dart';
import '../auth/inactivity_auth_landing.dart';
import '../auth/safe_sign_out_service.dart';
import '../navigation/sensitive_nav_policy.dart';
import '../session/app_session.dart';
import '../../services/user_session_coordination_service.dart';

/// انقطاع قصير على الويب: لا تُنهى الجلسة فوراً (navigator.onLine يومض).
/// بعد انقطاع ممتد يُقفَل الحساب دون ترك بيانات جلسة معلّقة.
abstract final class SessionConnectivityLock {
  SessionConnectivityLock._();

  static bool _armed = false;
  static bool _signingOut = false;
  static Timer? _blip;
  static Timer? _lock;

  /// وميض قصير: ننتظر قبل اعتبار الانقطاع حقيقياً للقفل.
  static const Duration shortDropGrace = Duration(seconds: 45);

  /// بعدها يُنهى JWT محلياً حتى لا تبقى الجلسة معلّقة/مُسرَّبة على جهاز مشترك.
  static const Duration lockAfterOffline = Duration(minutes: 3);

  static void attach(AppSession session) {
    if (_armed) return;
    _armed = true;
    session.onWentOffline = () => _onOffline(session);
    session.onWentOnline = () => _onOnline();
  }

  static void detach(AppSession session) {
    _blip?.cancel();
    _lock?.cancel();
    session.onWentOffline = null;
    session.onWentOnline = null;
    _armed = false;
  }

  static void _onOnline() {
    _blip?.cancel();
    _lock?.cancel();
    _signingOut = false;
  }

  static void _onOffline(AppSession session) {
    _blip?.cancel();
    _lock?.cancel();
    _blip = Timer(shortDropGrace, () {
      if (session.hasInternet) return;
      _lock?.cancel();
      _lock = Timer(lockAfterOffline - shortDropGrace, () {
        if (session.hasInternet) return;
        unawaited(_lockAndExit(session));
      });
    });
  }

  static Future<void> _lockAndExit(AppSession session) async {
    if (_signingOut) return;
    if (session.hasInternet) return;
    final nav = UserSessionCoordinationService.navigatorKey;
    final ctx = nav?.currentContext;
    String name = '';
    try {
      if (ctx != null) {
        name = ModalRoute.of(ctx)?.settings.name ?? '';
      }
    } catch (_) {}
    if (SensitiveNavPolicy.isAuthGateRouteName(name) && name != '/verify') {
      return;
    }
    _signingOut = true;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final loggedIn = uid != null && uid.isNotEmpty && !session.isGuest;
      if (loggedIn) {
        final dest = kIsWeb
            ? '/login'
            : await FastLoginService.resolveInactivityLockRoute();
        InactivityAuthLanding.begin(route: dest);
        final live = nav?.currentContext;
        if (live == null || !live.mounted) return;
        await SafeSignOutService.signOutAndNavigateToLogin(
          live,
          uidForCleanup: uid,
          logoutReason: 'connectivity_lost',
        );
        return;
      }
      if (session.isGuest && ctx != null && ctx.mounted) {
        try {
          await AuthLocalSignOut.signOutLocal(Supabase.instance.client);
        } catch (_) {}
        await session.logout();
        nav?.currentState?.pushNamedAndRemoveUntil('/entryChoice', (r) => false);
        return;
      }
      if (ctx != null && ctx.mounted && name == '/verify') {
        await SafeSignOutService.signOutAndNavigateToLogin(
          ctx,
          logoutReason: 'connectivity_lost',
        );
      }
    } finally {
      _signingOut = false;
    }
  }
}
