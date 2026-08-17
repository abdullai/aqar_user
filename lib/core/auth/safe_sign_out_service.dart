import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../session/app_session.dart';
import '../session/web_auth_tab_guard.dart';
import 'auth_signed_out_navigation_guard.dart';
import '../../services/in_app_notification_hub.dart';
import '../../services/marketing_buckets_cache.dart';
import '../../services/marketing_workflow_hub.dart';
import '../../services/presence_heartbeat_service.dart';
import '../../services/session_manager.dart';
import '../../services/session_tracking_service.dart';
import '../../services/subscription_service.dart';
import '../auth/auth_local_sign_out.dart';
import '../auth/web_auth_exit_history.dart';
import '../platform/web_browser_lifecycle.dart';
import '../navigation/root_overlay_guard.dart';
import '../../services/user_session_coordination_service.dart';

/// خروج موحّد من الحساب — على الويب يُنقَل إلى `/login` فوراً ثم يُكمَل signOut في الخلفية
/// لتجنّب تجمّد تبويب Chrome عند `await auth.signOut()` بدون مهلة.
abstract final class SafeSignOutService {
  static bool _inFlight = false;

  static Future<void> signOutAndNavigateToLogin(
    BuildContext context, {
    String? uidForCleanup,
    String logoutReason = 'user_logout',
    bool useRootNavigator = true,
  }) async {
    if (_inFlight) return;
    _inFlight = true;
    AuthSignedOutNavigationGuard.enter();

    final uid = (uidForCleanup?.trim().isNotEmpty ?? false)
        ? uidForCleanup!.trim()
        : Supabase.instance.client.auth.currentUser?.id;

    AppSession? session;
    if (context.mounted) {
      try {
        session = context.read<AppSession>();
      } catch (_) {}
    }

    InAppNotificationHub.setSessionUsername(null);
    InAppNotificationHub.setSessionUserId(null);
    SubscriptionService.teardownRealtimeChannel();
    SubscriptionService.invalidateSubscriptionCache();
    InAppNotificationHub.clearQueueAndToast();
    MarketingBucketsCache.instance.clearAll();
    try {
      MarketingWorkflowHub.hubHighlightRequestId.value = null;
    } catch (_) {}

    // قبل أيّ تنظيف: نبضة وداع → يظهر للمستخدمين الآخرين «آخر ظهور» فوراً
    // بدلاً من بقاء «متصل الآن» حتى تنتهي نافذة الـ 90 ثانية تلقائياً.
    try {
      await PresenceHeartbeatService.markOffline(
        Supabase.instance.client,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}

    Future<void> remoteAndLocalCleanup() async {
      try {
        await SessionManager.clearPreferencesAfterLogout(uid).timeout(
          const Duration(seconds: 4),
        );
      } catch (_) {}

      final sb = Supabase.instance.client;
      if (sb.auth.currentSession != null) {
        unawaited(
          SessionTrackingService.recordLogoutEnd(
            sb,
            reason: logoutReason,
          ).timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          ),
        );
        try {
          await AuthLocalSignOut.signOutLocal(sb, tryRemoteRevoke: true);
        } catch (_) {}
      }

      try {
        await WebAuthTabGuard.clearBinding();
      } catch (_) {}

      try {
        await session?.applyLocalLogoutAfterSupabaseSignOut().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {}
    }

    void navigate() {
      if (!context.mounted) return;
      if (kIsWeb) suppressWebBeforeUnloadBriefly();
      RootOverlayGuard.dismissAll(UserSessionCoordinationService.navigatorKey);
      final nav = useRootNavigator
          ? Navigator.of(context, rootNavigator: true)
          : Navigator.of(context);
      nav.pushNamedAndRemoveUntil('/login', (route) => false);
      if (kIsWeb) {
        try {
          WebAuthExitHistory.replaceLoginUrl();
        } catch (_) {}
      }
    }

    try {
      if (kIsWeb) {
        navigate();
        await Future<void>.delayed(const Duration(milliseconds: 16));
        unawaited(remoteAndLocalCleanup());
      } else {
        await remoteAndLocalCleanup();
        navigate();
      }
    } finally {
      _inFlight = false;
      AuthSignedOutNavigationGuard.scheduleLeave();
    }
  }

  /// للمسارات التي تملك [NavigatorState] فقط (مثل خمول الجلسة).
  static Future<void> signOutAndNavigateToLoginFromNavigator(
    GlobalKey<NavigatorState> navigatorKey, {
    String? uidForCleanup,
    String logoutReason = 'inactivity_logout',
  }) async {
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await signOutAndNavigateToLogin(
        ctx,
        uidForCleanup: uidForCleanup,
        logoutReason: logoutReason,
        useRootNavigator: true,
      );
      return;
    }

    if (_inFlight) return;
    _inFlight = true;
    AuthSignedOutNavigationGuard.enter();
    final uid = uidForCleanup ?? Supabase.instance.client.auth.currentUser?.id;

    try {
      RootOverlayGuard.dismissAll(navigatorKey);
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
      final sb = Supabase.instance.client;
      if (sb.auth.currentSession != null) {
        unawaited(
          (() async {
            try {
              await SessionManager.clearPreferencesAfterLogout(uid).timeout(
                const Duration(seconds: 4),
              );
            } catch (_) {}
            try {
              InAppNotificationHub.clearQueueAndToast();
              InAppNotificationHub.setSessionUsername(null);
              InAppNotificationHub.setSessionUserId(null);
              MarketingBucketsCache.instance.clearAll();
              MarketingWorkflowHub.hubHighlightRequestId.value = null;
            } catch (_) {}
            try {
              await AuthLocalSignOut.signOutLocal(sb, tryRemoteRevoke: true);
            } catch (_) {}
            try {
              await WebAuthTabGuard.clearBinding();
            } catch (_) {}
          })(),
        );
      }
    } finally {
      _inFlight = false;
      AuthSignedOutNavigationGuard.scheduleLeave();
    }
  }
}
