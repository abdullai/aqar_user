// lib/services/inactivity_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart'; // langNotifier + recoveryFlowNotifier
import '../services/fast_login_service.dart';

class InactivityService {
  InactivityService({
    required this.navigatorKey,
    this.idleBeforePrompt = const Duration(minutes: 5),
    this.promptCountdown = const Duration(minutes: 1),
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Duration idleBeforePrompt;
  final Duration promptCountdown;

  Timer? _idleTimer;
  Timer? _countdownTimer;
  int _remainingSec = 0;
  bool _dialogOpen = false;

  // ✅ Guards to prevent repeated lock/signOut loops
  bool _locking = false;
  bool _signOutRunning = false;

  void start() => _resetIdleTimer();

  void stop() {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _dialogOpen = false;
    _locking = false;
    _signOutRunning = false;
  }

  /// استدعِها عند أي تفاعل من المستخدم
  void userActivity() {
    if (_dialogOpen) {
      _closeDialogIfAny();
      _dialogOpen = false;
    }
    _resetIdleTimer();
  }

  /// قفل فوري (يُستخدم عند خروج التطبيق للخلفية)
  Future<void> lockNow() async {
    if (_locking) return;
    _locking = true;

    try {
      _countdownTimer?.cancel();
      _idleTimer?.cancel();
      _closeDialogIfAny();
      _dialogOpen = false;

      // لا نقفل أثناء Recovery
      if (recoveryFlowNotifier.value == true) return;

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        _forceToLogin();
        return;
      }

      final hasLock = await FastLoginService.hasAnyLockEnabled();
      if (hasLock) {
        _forceToFastLogin();
      } else {
        _resetIdleTimer();
      }
    } finally {
      _locking = false;
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleBeforePrompt, _showPrompt);
  }

  String _routeName() {
    final ctx = navigatorKey.currentContext;
    return ModalRoute.of(ctx ?? navigatorKey.currentState!.context)
            ?.settings
            .name ??
        '';
  }

  bool _isOnLoginOrFastLoginOrReset() {
    final name = _routeName();
    return name == '/' || name == '/fastLogin' || name == '/resetPassword';
  }

  String _t({required String ar, required String en}) {
    return (langNotifier.value == 'ar') ? ar : en;
  }

  Future<void> _showPrompt() async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

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
      _forceToLogin();
      return;
    }

    _dialogOpen = true;
    _remainingSec = promptCountdown.inSeconds;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _remainingSec--;
      if (_remainingSec <= 0) {
        _countdownTimer?.cancel();
        _lockOrLogout();
      }
    });

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            Timer(const Duration(milliseconds: 300), () {
              if (ModalRoute.of(context)?.isCurrent ?? false) setState(() {});
            });

            return AlertDialog(
              title: Text(_t(
                ar: 'تم اكتشاف عدم نشاط',
                en: 'Inactivity detected',
              )),
              content: Text(_t(
                ar: 'هل تريد الاستمرار؟ سيتم قفل التطبيق خلال $_remainingSec ثانية.',
                en: 'Do you want to continue? The app will lock in $_remainingSec seconds.',
              )),
              actions: [
                TextButton(
                  onPressed: () {
                    _closeDialogIfAny();
                    _dialogOpen = false;
                    _resetIdleTimer();
                  },
                  child: Text(_t(ar: 'استمرار', en: 'Continue')),
                ),
                TextButton(
                  onPressed: () => _lockOrLogout(),
                  child: Text(_t(ar: 'قفل الآن', en: 'Lock now')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _closeDialogIfAny() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    if (Navigator.of(ctx, rootNavigator: true).canPop()) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  }

  Future<void> _lockOrLogout() async {
    if (_locking) return;
    _locking = true;

    try {
      _countdownTimer?.cancel();
      _idleTimer?.cancel();
      _closeDialogIfAny();
      _dialogOpen = false;

      if (recoveryFlowNotifier.value == true) {
        _resetIdleTimer();
        return;
      }

      final hasLock = await FastLoginService.hasAnyLockEnabled();
      if (hasLock) {
        _forceToFastLogin();
        return;
      }

      // ✅ على الويب لا تعمل signOut تلقائي بسبب الخمول
      if (kIsWeb) {
        _forceToLogin();
        return;
      }

      await _logout();
    } finally {
      _locking = false;
    }
  }

  Future<void> _logout() async {
    if (_signOutRunning) {
      _forceToLogin();
      return;
    }
    _signOutRunning = true;

    try {
      final sb = Supabase.instance.client;

      // ✅ إذا لا يوجد Session لا تعمل signOut
      if (sb.auth.currentSession != null) {
        await sb.auth.signOut();
      }
    } catch (_) {
      // ignore
    } finally {
      _signOutRunning = false;
    }

    _forceToLogin();
  }

  void _forceToLogin() {
    final nav = navigatorKey.currentState;
    nav?.pushNamedAndRemoveUntil('/', (r) => false);
  }

  void _forceToFastLogin() {
    final nav = navigatorKey.currentState;
    nav?.pushNamedAndRemoveUntil('/fastLogin', (r) => false);
  }
}
