// lib/services/inactivity_service.dart
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show recoveryFlowNotifier;
import '../core/session/return_after_auth.dart';
import '../core/config/app_config.dart';
import '../core/session/web_session_ttl.dart';
import '../services/fast_login_service.dart';

class InactivityService {
  InactivityService({
    required this.navigatorKey,
    this.idleBeforePrompt = const Duration(minutes: 5),
    this.promptCountdown = const Duration(minutes: 1),
    this.useIdleBlurOverlay = false,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Duration idleBeforePrompt;
  final Duration promptCountdown;

  /// Web / desktop: full-screen blur instead of a floating dialog sheet.
  final bool useIdleBlurOverlay;

  static const String kPrefLastActivityAtMs = 'inactivity_last_activity_ms';

  Timer? _idleTimer;
  Timer? _countdownTimer;
  ValueNotifier<int>? _promptSecVN;
  bool _promptContinueIntent = false;
  bool _dialogOpen = false;

  int _lastActivityMs = 0;
  int _lastPersistWallMs = 0;

  // ✅ Guards to prevent repeated loops
  bool _locking = false;
  bool _signOutRunning = false;

  void start() {
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    unawaited(_persistLastActivityMs());
    _resetIdleTimer();
  }

  /// استدعِها عند إخفاء التطبيق/التبويب لتثبيت آخر نشاط (للفحص عند العودة).
  void onAppPaused() {
    unawaited(_persistLastActivityMs());
  }

  /// عند العودة من الخلفية: إن تجاوز المستخدم مدة الخمول دون تفاعل يُقفل أو يُطلب الدخول.
  Future<void> onAppResumedAfterBackground() async {
    if (_isOnLoginOrFastLoginOrReset()) return;
    if (recoveryFlowNotifier.value == true) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    _idleTimer?.cancel();
    _idleTimer = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(kPrefLastActivityAtMs);
      if (stored != null && stored > 0) {
        _lastActivityMs = stored;
      }
    } catch (_) {}

    final last = DateTime.fromMillisecondsSinceEpoch(_lastActivityMs);
    final elapsed = DateTime.now().difference(last);
    final totalIdle = idleBeforePrompt + promptCountdown;

    if (elapsed >= idleBeforePrompt) {
      final remaining =
          elapsed >= totalIdle ? promptCountdown : totalIdle - elapsed;
      final sec = remaining.inSeconds.clamp(1, promptCountdown.inSeconds);
      await _showPrompt(remainingSeconds: sec);
      return;
    }
    _resetIdleTimer();
  }

  void stop() {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _promptSecVN?.dispose();
    _promptSecVN = null;
    _closeDialogIfAny();
    _dialogOpen = false;
    _locking = false;
    _signOutRunning = false;
  }

  /// استدعِها عند أي تفاعل من المستخدم
  void userActivity() {
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    _maybeThrottlePersistActivity();

    if (_dialogOpen) return;
    if (kIsWeb) {
      unawaited(touchWebSessionActivity());
      unawaited(_touchWebGuestActivityIfGuest());
    }
    _resetIdleTimer();
  }

  void _maybeThrottlePersistActivity() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPersistWallMs < 5000) return;
    _lastPersistWallMs = now;
    unawaited(_persistLastActivityMs());
  }

  Future<void> _touchWebGuestActivityIfGuest() async {
    try {
      final p = await SharedPreferences.getInstance();
      final guest = p.getBool(AppConfig.prefGuestModeKey) ?? false;
      final entry =
          (p.getString(AppConfig.prefEntryModeKey) ?? '').trim().toLowerCase();
      if (guest || entry == 'guest') {
        await touchWebGuestActivity();
      }
    } catch (_) {}
  }

  Future<void> _persistLastActivityMs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kPrefLastActivityAtMs, _lastActivityMs);
    } catch (_) {}
  }

  /// قفل فوري (يُستخدم عند خروج التطبيق للخلفية)
  Future<void> lockNow() async {
    if (_locking) return;
    _locking = true;

    try {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _idleTimer?.cancel();
      _promptSecVN?.dispose();
      _promptSecVN = null;
      _closeDialogIfAny();
      _dialogOpen = false;

      // لا نقفل أثناء Recovery
      if (recoveryFlowNotifier.value == true) return;

      final session = Supabase.instance.client.auth.currentSession;

      // ✅ إذا لا يوجد Session: غالباً ضيف -> لا تعمل redirect
      if (session == null) {
        _resetIdleTimer();
        return;
      }

      // ✅ إذا يوجد قفل (بصمة/Pin) -> FastLogin
      final hasLock = await FastLoginService.hasAnyLockEnabled();
      if (hasLock) {
        await _forceToFastLogin();
        return;
      }

      await _logoutThenLogin();
    } finally {
      _locking = false;
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleBeforePrompt, () => _showPrompt());
  }

  String _routeName() {
    final ctx = navigatorKey.currentContext;
    final stateCtx = navigatorKey.currentState?.context;
    return ModalRoute.of(ctx ?? stateCtx!)?.settings.name ?? '';
  }

  bool _isOnLoginOrFastLoginOrReset() {
    final name = _routeName();
    return name == '/' ||
        name == '/fastLogin' ||
        name == '/resetPassword' ||
        name == '/login' ||
        name == '/entryChoice' ||
        name == '/gate';
  }

  String _formatNowLine(BuildContext context) {
    final loc = Localizations.localeOf(context);
    return DateFormat.yMMMd(loc.toLanguageTag())
        .add_Hms()
        .format(DateTime.now());
  }

  Future<void> _showPrompt({int? remainingSeconds}) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (_dialogOpen) return;

    if (_isOnLoginOrFastLoginOrReset()) {
      _resetIdleTimer();
      return;
    }

    if (recoveryFlowNotifier.value == true) {
      _resetIdleTimer();
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      _resetIdleTimer();
      return;
    }

    final hasLock = await FastLoginService.hasAnyLockEnabled();

    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) {
      _resetIdleTimer();
      return;
    }

    final initialSec =
        (remainingSeconds ?? promptCountdown.inSeconds).clamp(1, 3600);

    _dialogOpen = true;
    _promptContinueIntent = false;
    _promptSecVN?.dispose();
    _promptSecVN = ValueNotifier<int>(initialSec);
    final vn = _promptSecVN!;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (vn.value <= 1) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        unawaited(_lockOrGoLogin());
        return;
      }
      vn.value = vn.value - 1;
    });

    final timeLine = _formatNowLine(dialogContext);

    Future<void> present(Widget Function(BuildContext dialogCtx) page) {
      if (useIdleBlurOverlay) {
        return showGeneralDialog<void>(
          context: dialogContext,
          barrierDismissible: false,
          barrierLabel: '',
          barrierColor: Colors.transparent,
          useRootNavigator: true,
          transitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (dialogCtx, _, __) {
            return page(dialogCtx);
          },
        );
      }
      return showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: page,
      );
    }

    present(
      (dialogCtx) {
        final l10n = AppLocalizations.of(dialogCtx);
        final cs = Theme.of(dialogCtx).colorScheme;
        final tt = Theme.of(dialogCtx).textTheme;

        Widget dialogBody() {
          return ValueListenableBuilder<int>(
            valueListenable: vn,
            builder: (context, sec, _) {
              return AlertDialog(
                title: Text(l10n?.securityInactivityTitle ?? 'Inactivity'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n != null
                              ? l10n.securityInactivityTime(timeLine)
                              : 'Time: $timeLine',
                          style: tt.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          hasLock
                              ? (l10n?.securityInactivityBodyLock(sec) ??
                                  'Unlock in $sec s')
                              : (l10n?.securityInactivityBodySignOut(sec) ??
                                  'Sign out in $sec s'),
                          textAlign: TextAlign.start,
                          style: tt.bodyMedium?.copyWith(color: cs.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
                actionsAlignment: MainAxisAlignment.spaceBetween,
                actions: [
                  TextButton(
                    onPressed: () {
                      _promptContinueIntent = true;
                      _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
                      unawaited(_persistLastActivityMs());
                      Navigator.of(dialogCtx, rootNavigator: true).pop();
                    },
                    child: Text(l10n?.securityContinue ?? 'Continue'),
                  ),
                  TextButton(
                    onPressed: () {
                      _promptContinueIntent = false;
                      Navigator.of(dialogCtx, rootNavigator: true).pop();
                      unawaited(_lockOrGoLogin());
                    },
                    child: Text(l10n?.securitySignOutFromPrompt ?? 'Sign out'),
                  ),
                ],
              );
            },
          );
        }

        if (!useIdleBlurOverlay) {
          return dialogBody();
        }

        return SafeArea(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              color: Colors.black.withValues(alpha: 0.38),
              child: Center(
                child: dialogBody(),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _promptSecVN?.dispose();
      _promptSecVN = null;
      _dialogOpen = false;
      if (_promptContinueIntent) {
        _promptContinueIntent = false;
        _resetIdleTimer();
      }
    });
  }

  void _closeDialogIfAny() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    if (Navigator.of(ctx, rootNavigator: true).canPop()) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  }

  Future<void> _lockOrGoLogin() async {
    if (_locking) return;
    _locking = true;

    try {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _idleTimer?.cancel();
      _closeDialogIfAny();
      _dialogOpen = false;

      if (recoveryFlowNotifier.value == true) {
        _resetIdleTimer();
        return;
      }

      final session = Supabase.instance.client.auth.currentSession;

      if (session == null) {
        _resetIdleTimer();
        return;
      }

      final hasLock = await FastLoginService.hasAnyLockEnabled();
      if (hasLock) {
        await _forceToFastLogin();
        return;
      }

      await _logoutThenLogin();
    } finally {
      _locking = false;
    }
  }

  Future<void> _logoutThenLogin() async {
    await ReturnAfterAuth.saveFromNavigatorKey(navigatorKey);

    if (_signOutRunning) return;
    _signOutRunning = true;
    try {
      final sb = Supabase.instance.client;
      if (sb.auth.currentSession != null) {
        try {
          await sb.auth.signOut(
            scope: kIsWeb ? SignOutScope.local : SignOutScope.global,
          );
        } catch (_) {
          await sb.auth.signOut(scope: SignOutScope.local);
        }
      }
    } catch (_) {
      // ignore
    } finally {
      _signOutRunning = false;
    }

    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final current = _routeName();
    if (current == '/login' || current == '/') return;
    nav.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _forceToFastLogin() async {
    await ReturnAfterAuth.saveFromNavigatorKey(navigatorKey);

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final current = _routeName();
    if (current == '/fastLogin') return;

    FastLoginService.clearRuntimeUnlock();
    nav.pushNamedAndRemoveUntil('/fastLogin', (r) => false);
  }
}
