// lib/services/inactivity_service.dart
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:flutter/services.dart';

import '../core/auth/safe_sign_out_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier, recoveryFlowNotifier, suspendAutoLock;
import '../core/session/return_after_auth.dart';
import '../core/auth/auth_local_sign_out.dart';
import '../core/auth/inactivity_auth_landing.dart';
import '../core/config/app_config.dart';
import '../core/utils/date_helper.dart';
import '../core/navigation/root_overlay_guard.dart';
import '../core/session/web_session_ttl.dart';
import '../core/session/web_visibility.dart';
import '../services/fast_login_service.dart';
import '../services/notification_service.dart';
import '../routes.dart';

class InactivityService {
  InactivityService({
    required this.navigatorKey,
    this.idleBeforePrompt = const Duration(minutes: 3),
    this.promptCountdown = const Duration(minutes: 1),
    this.useIdleBlurOverlay = false,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Duration idleBeforePrompt;
  final Duration promptCountdown;

  /// Web / desktop: full-screen blur instead of a floating dialog sheet.
  final bool useIdleBlurOverlay;

  static const String kPrefLastActivityAtMs = 'inactivity_last_activity_ms';
  static const String kPrefPromptDeadlineMs = 'inactivity_prompt_deadline_ms';
  static const String kPrefIdleUntilMs = 'inactivity_idle_until_ms';
  static const String kPrefLockUntilMs = 'inactivity_lock_until_ms';

  Timer? _idleTimer;
  Timer? _countdownTimer;
  Timer? _deadlineFireTimer;
  Timer? _wallClockTimer;
  ValueNotifier<int>? _promptSecVN;
  bool _promptContinueIntent = false;
  bool _dialogOpen = false;
  int? _promptDeadlineMs;

  int _lastActivityMs = 0;
  int _lastPersistWallMs = 0;
  int _activityRevision = 0;
  final DateTime _serviceStartedAt = DateTime.now();

  /// يمنع لمسة/لوحة مفاتيح من تصفير العدّاد أثناء إغلاق الشاشة أو تصغير المتصفح.
  bool _backgroundHold = false;
  bool _resumeAuditBusy = false;

  /// لا نعرض حوار الخمول في أجزاء الثانية الأولى من إقلاع الخدمة فقط.
  static const Duration _resumePromptGrace = Duration(milliseconds: 400);

  bool _locking = false;
  bool _signOutRunning = false;
  bool _hardwareKeysArmed = false;

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      userActivity();
    }
    return false;
  }

  int get _idleUntilMs => _lastActivityMs + idleBeforePrompt.inMilliseconds;

  int get _lockUntilMs {
    if (_promptDeadlineMs != null && _promptDeadlineMs! > 0) {
      return _promptDeadlineMs!;
    }
    return _lastActivityMs +
        idleBeforePrompt.inMilliseconds +
        promptCountdown.inMilliseconds;
  }

  void start() {
    _backgroundHold = false;
    _resumeAuditBusy = false;
    if (!_hardwareKeysArmed) {
      HardwareKeyboard.instance.addHandler(_onHardwareKey);
      _hardwareKeysArmed = true;
    }
    unawaited(_bootFromPersistedClock());
  }

  Future<void> _bootFromPersistedClock() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final bootRevision = _activityRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(kPrefLastActivityAtMs);
      if (_activityRevision == bootRevision) {
        if (stored != null && stored > 0 && stored <= now) {
          _lastActivityMs = stored;
        } else {
          _lastActivityMs = now;
        }
      }
      final storedPrompt = prefs.getInt(kPrefPromptDeadlineMs);
      if (storedPrompt != null && storedPrompt > 0) {
        _promptDeadlineMs = storedPrompt;
      }
    } catch (_) {
      _lastActivityMs = now;
    }
    await _persistDeadlines();
    _resetIdleTimer();
    _armWallClockWatch();
    await _applyWallClockLockState();
  }

  /// استدعِها عند إخفاء التطبيق/التبويب لتثبيت آخر نشاط + جدولة الخروج حسب الموعد.
  void onAppPaused() {
    _backgroundHold = true;
    if (!_dialogOpen && !_locking) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= _idleUntilMs && _promptDeadlineMs == null) {
        final remaining = _lockUntilMs - now;
        final sec = remaining <= 0
            ? 0
            : (remaining / 1000).ceil().clamp(1, promptCountdown.inSeconds);
        if (sec > 0) {
          _promptDeadlineMs = now + (sec * 1000);
        }
      }
    }
    unawaited(_persistDeadlines());
    unawaited(_notifyBackgroundSecurityCountdown());
    _armDeadlineFireTimer();
    _armWallClockWatch();
  }

  /// عند العودة من الخلفية: ساعة الجدار هي المرجع — العدّ لا يُصفَّر ولا يُعاد من الصفر.
  Future<void> onAppResumedAfterBackground() async {
    if (DateTime.now().difference(_serviceStartedAt) < _resumePromptGrace) {
      _backgroundHold = false;
      await _applyWallClockLockState();
      return;
    }
    _resumeAuditBusy = true;
    try {
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
        final storedLock = prefs.getInt(kPrefLockUntilMs);
        final storedPrompt = prefs.getInt(kPrefPromptDeadlineMs);
        if (storedPrompt != null && storedPrompt > 0) {
          _promptDeadlineMs = storedPrompt;
        } else if (storedLock != null && storedLock > 0) {
          _promptDeadlineMs = storedLock;
        }
      } catch (_) {}

      await _applyWallClockLockState();
    } finally {
      _resumeAuditBusy = false;
      _backgroundHold = false;
    }
  }

  void stop() {
    _idleTimer?.cancel();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _deadlineFireTimer?.cancel();
    _deadlineFireTimer = null;
    _wallClockTimer?.cancel();
    _wallClockTimer = null;
    _promptSecVN?.dispose();
    _promptSecVN = null;
    _promptDeadlineMs = null;
    _backgroundHold = false;
    _resumeAuditBusy = false;
    unawaited(_clearPromptDeadlinePref());
    _closeDialogIfAny();
    _dialogOpen = false;
    _locking = false;
    _signOutRunning = false;
    if (_hardwareKeysArmed) {
      HardwareKeyboard.instance.removeHandler(_onHardwareKey);
      _hardwareKeysArmed = false;
    }
  }

  void dismissBlockingPrompt() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _deadlineFireTimer?.cancel();
    _deadlineFireTimer = null;
    _promptSecVN?.dispose();
    _promptSecVN = null;
    _promptDeadlineMs = null;
    unawaited(_clearPromptDeadlinePref());
    _closeDialogIfAny();
    _dialogOpen = false;
    _locking = false;
    _resetIdleTimer();
  }

  static int _lastWebTouchMs = 0;

  static void Function()? dismissBlockingPromptCallback;

  static void dismissBlockingPromptNow() {
    dismissBlockingPromptCallback?.call();
  }

  /// يُحدَّث في [main.dart] إلى `_inactivity.userActivity` — بدونه يبقى المؤقّت الحي
  /// يعتمد على آخر نشاط قديم محفوظ عند إقلاع التطبيق حتى لو صُفِّر في التخزين فقط،
  /// فيعتبر المهلة منتهية فوراً بعد كل دخول (OTP / إدارة الأجهزة) ويُخرج المستخدم عشوائياً.
  static void Function()? refreshLiveActivityCallback;

  static Future<void> stampFreshActivity() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kPrefLastActivityAtMs, now);
      await prefs.remove(kPrefPromptDeadlineMs);
    } catch (_) {}
    refreshLiveActivityCallback?.call();
  }

  static Future<void> prepareDashboardEntry() async {
    dismissBlockingPromptNow();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPrefPromptDeadlineMs);
    } catch (_) {}
    await stampFreshActivity();
  }

  void userActivity() {
    if (_backgroundHold || _resumeAuditBusy || _dialogOpen) return;
    _activityRevision++;
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    if (_promptDeadlineMs != null) {
      _promptDeadlineMs = null;
      unawaited(_clearPromptDeadlinePref());
    }
    _maybeThrottlePersistActivity();

    if (kIsWeb) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastWebTouchMs >= 3000) {
        _lastWebTouchMs = now;
        unawaited(touchWebSessionActivity());
        unawaited(_touchWebGuestActivityIfGuest());
      }
    }
    _resetIdleTimer();
  }

  void _maybeThrottlePersistActivity() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPersistWallMs < 5000) return;
    _lastPersistWallMs = now;
    unawaited(_persistDeadlines());
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

  Future<void> _persistDeadlines() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kPrefLastActivityAtMs, _lastActivityMs);
      await prefs.setInt(kPrefIdleUntilMs, _idleUntilMs);
      await prefs.setInt(kPrefLockUntilMs, _lockUntilMs);
      if (_promptDeadlineMs != null && _promptDeadlineMs! > 0) {
        await prefs.setInt(kPrefPromptDeadlineMs, _promptDeadlineMs!);
      } else {
        await prefs.remove(kPrefPromptDeadlineMs);
      }
    } catch (_) {}
  }

  Future<void> _persistLastActivityMs() async {
    await _persistDeadlines();
  }

  Future<void> _clearPromptDeadlinePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPrefPromptDeadlineMs);
    } catch (_) {}
  }

  Future<void> _notifyBackgroundSecurityCountdown() async {
    if (kIsWeb) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < _idleUntilMs) return;
    final remainingMs = _lockUntilMs - now;
    final isAr = langNotifier.value != 'en';
    final title =
        isAr ? 'تنبيه أمني — عدم نشاط' : 'Security alert — inactivity';
    final body = remainingMs <= 0
        ? (isAr
            ? 'انتهت مهلة الجلسة. أعد الدخول للمتابعة.'
            : 'Session timed out. Sign in again to continue.')
        : (isAr
            ? 'العدّاد مستمر حتى مع إغلاق الشاشة. ستُقفل الجلسة خلال ${(remainingMs / 1000).ceil()} ثانية إن لم تُكمل.'
            : 'The countdown continues while the screen is off. Session locks in ${(remainingMs / 1000).ceil()}s unless you continue.');
    try {
      await NotificationService.showWorkflowLocalNotification(
        title: title,
        body: body,
        dedupeKey: 'inactivity_wall_clock',
      );
    } catch (_) {}
  }

  Future<void> _applyWallClockLockState() async {
    if (_locking) return;
    if (_isOnLoginOrFastLoginOrReset()) return;
    if (recoveryFlowNotifier.value == true) return;
    if (suspendAutoLock.value == true) {
      return;
    }
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= _lockUntilMs) {
      await _lockOrGoLogin();
      return;
    }
    if (now >= _idleUntilMs) {
      final sec = ((_lockUntilMs - now) / 1000).ceil().clamp(1, 3600);
      if (_dialogOpen) {
        _armDeadlineFireTimer();
        _syncPromptSecondsFromDeadline();
        return;
      }
      await _showPrompt(remainingSeconds: sec);
      return;
    }
    _resetIdleTimer();
  }

  void _armWallClockWatch() {
    _wallClockTimer?.cancel();
    _wallClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tickWallClock());
    });
  }

  Future<void> _tickWallClock() async {
    if (_locking || _signOutRunning) return;
    if (_isOnLoginOrFastLoginOrReset()) return;
    if (recoveryFlowNotifier.value == true) return;
    if (suspendAutoLock.value == true) return;
    if (Supabase.instance.client.auth.currentSession == null) return;

    if (_backgroundHold) {
      unawaited(_persistDeadlines());
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= _lockUntilMs) {
      await _lockOrGoLogin();
      return;
    }
    if (_dialogOpen) {
      _syncPromptSecondsFromDeadline();
      if (_promptDeadlineMs != null && now >= _promptDeadlineMs!) {
        await _lockOrGoLogin();
      }
      return;
    }
    if (now >= _idleUntilMs) {
      final sec = ((_lockUntilMs - now) / 1000).ceil().clamp(1, 3600);
      await _showPrompt(remainingSeconds: sec);
    }
  }

  int _remainingPromptSeconds() {
    final deadline = _promptDeadlineMs;
    if (deadline == null) return promptCountdown.inSeconds;
    final sec =
        ((deadline - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    return sec.clamp(0, 3600);
  }

  void _syncPromptSecondsFromDeadline() {
    final vn = _promptSecVN;
    if (vn == null) return;
    final sec = _remainingPromptSeconds();
    if (vn.value != sec) vn.value = sec;
  }

  /// مؤقّت واحد يعتمد ساعة الجدار — يعمل حتى مع تخفيف المتصفح للمؤقّتات الدورية.
  void _armDeadlineFireTimer() {
    _deadlineFireTimer?.cancel();
    final deadline = _promptDeadlineMs;
    if (deadline == null) return;
    final ms = deadline - DateTime.now().millisecondsSinceEpoch;
    if (ms <= 0) {
      unawaited(_lockOrGoLogin());
      return;
    }
    _deadlineFireTimer = Timer(Duration(milliseconds: ms + 30), () {
      if (_remainingPromptSeconds() <= 0) {
        unawaited(_lockOrGoLogin());
      }
    });
  }

  Future<void> lockNow() async {
    if (_locking) return;
    _locking = true;

    try {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _deadlineFireTimer?.cancel();
      _deadlineFireTimer = null;
      _idleTimer?.cancel();
      _promptSecVN?.dispose();
      _promptSecVN = null;
      _promptDeadlineMs = null;
      unawaited(_clearPromptDeadlinePref());
      _closeDialogIfAny();
      _dialogOpen = false;

      if (recoveryFlowNotifier.value == true) return;

      final session = Supabase.instance.client.auth.currentSession;

      if (session == null) {
        _resetIdleTimer();
        return;
      }

      await _routeToRememberedAuthSurface();
    } finally {
      _locking = false;
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_locking || _dialogOpen) return;
    if (_isOnLoginOrFastLoginOrReset()) return;
    final remaining = _idleUntilMs - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      unawaited(_applyWallClockLockState());
      return;
    }
    _idleTimer = Timer(Duration(milliseconds: remaining + 30), () {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= _lockUntilMs) {
        unawaited(_lockOrGoLogin());
      } else if (now >= _idleUntilMs) {
        final sec = ((_lockUntilMs - now) / 1000).ceil().clamp(1, 3600);
        unawaited(_showPrompt(remainingSeconds: sec));
      } else {
        _resetIdleTimer();
      }
    });
  }

  String _routeName() {
    try {
      final ctx = navigatorKey.currentContext;
      final stateCtx = navigatorKey.currentState?.context;
      final c = ctx ?? stateCtx;
      if (c == null) return '';
      return ModalRoute.of(c)?.settings.name ?? '';
    } catch (_) {
      return '';
    }
  }

  bool _isOnLoginOrFastLoginOrReset() {
    final name = _routeName();
    return name == '/' ||
        name == '/fastLogin' ||
        name == '/resetPassword' ||
        name == '/login' ||
        name == '/entryChoice' ||
        name == '/gate' ||
        name == '/verify' ||
        name == '/passwordSetup' ||
        name == AppRoutes.deviceManagement;
  }

  String _formatNowLine(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return DateHelper.fmtCivilDateTime(DateTime.now(),
        isAr: isAr, withSeconds: true);
  }

  Future<void> _showPrompt({int? remainingSeconds}) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (_dialogOpen) return;

    if (_isOnLoginOrFastLoginOrReset()) {
      return;
    }

    if (recoveryFlowNotifier.value == true) {
      return;
    }

    if (suspendAutoLock.value == true) {
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= _lockUntilMs) {
      await _lockOrGoLogin();
      return;
    }

    final hasLock = await FastLoginService.canSoftLockSession();

    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) {
      return;
    }

    var initialSec =
        (remainingSeconds ?? _remainingPromptSeconds()).clamp(0, 3600);
    if (initialSec <= 0) {
      await _lockOrGoLogin();
      return;
    }

    _dialogOpen = true;
    _promptContinueIntent = false;
    _promptDeadlineMs =
        DateTime.now().millisecondsSinceEpoch + (initialSec * 1000);
    unawaited(_persistDeadlines());
    _promptSecVN?.dispose();
    _promptSecVN = ValueNotifier<int>(initialSec);
    final vn = _promptSecVN!;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final sec = _remainingPromptSeconds();
      if (sec <= 0) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        unawaited(_clearPromptDeadlinePref());
        unawaited(_lockOrGoLogin());
        return;
      }
      if (vn.value != sec) {
        vn.value = sec;
      }
    });
    _armDeadlineFireTimer();
    if (kIsWeb) setWebDocumentScrollLocked(true);

    final timeLine = _formatNowLine(dialogContext);

    Future<void> present(Widget Function(BuildContext dialogCtx) page) {
      return showGeneralDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        barrierLabel: 'inactivity',
        barrierColor: Colors.black.withValues(alpha: 0.55),
        useRootNavigator: true,
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (dialogCtx, _, __) {
          return page(dialogCtx);
        },
      );
    }

    try {
      await present(
        (dialogCtx) {
          final l10n = AppLocalizations.of(dialogCtx);
          final cs = Theme.of(dialogCtx).colorScheme;
          final isAr = Localizations.localeOf(dialogCtx).languageCode != 'en';

          Widget dialogBody() {
            return ValueListenableBuilder<int>(
              valueListenable: vn,
              builder: (context, sec, _) {
                final progress =
                    (sec / promptCountdown.inSeconds).clamp(0.0, 1.0);
                return Dialog(
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.timer_outlined,
                              size: 32,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n?.securityInactivityTitle ??
                                (isAr
                                    ? 'تم اكتشاف عدم نشاط'
                                    : 'Inactivity detected'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              color: cs.onSurface,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n != null
                                ? l10n.securityInactivityTime(timeLine)
                                : (isAr
                                    ? 'الوقت: $timeLine'
                                    : 'Time: $timeLine'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: 88,
                            height: 88,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 88,
                                  height: 88,
                                  child: CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 7,
                                    backgroundColor:
                                        cs.primary.withValues(alpha: 0.12),
                                    color: sec <= 10 ? cs.error : cs.primary,
                                  ),
                                ),
                                Text(
                                  '$sec',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 28,
                                    color: sec <= 10 ? cs.error : cs.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            hasLock
                                ? (l10n?.securityInactivityBodyLock(sec) ??
                                    (isAr
                                        ? 'سيتم قفل الجلسة خلال $sec ثانية.'
                                        : 'Session locks in $sec s.'))
                                : (l10n?.securityInactivityBodySignOut(sec) ??
                                    (isAr
                                        ? 'هل تريد الاستمرار؟ إن لم تختر خلال $sec ثانية سيتم تسجيل خروجك.'
                                        : 'Continue? You will be signed out in $sec s.')),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              height: 1.4,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    _promptContinueIntent = false;
                                    _promptDeadlineMs = null;
                                    unawaited(_clearPromptDeadlinePref());
                                    Navigator.of(dialogCtx, rootNavigator: true)
                                        .pop();
                                    unawaited(_lockOrGoLogin());
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: cs.error,
                                    side: BorderSide(
                                      color: cs.error.withValues(alpha: 0.55),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    l10n?.securitySignOutFromPrompt ??
                                        (isAr ? 'تسجيل الخروج' : 'Sign out'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    _promptContinueIntent = true;
                                    _lastActivityMs =
                                        DateTime.now().millisecondsSinceEpoch;
                                    _promptDeadlineMs = null;
                                    unawaited(_persistLastActivityMs());
                                    unawaited(_clearPromptDeadlinePref());
                                    Navigator.of(dialogCtx, rootNavigator: true)
                                        .pop();
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: cs.primary,
                                    foregroundColor: cs.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    l10n?.securityContinue ??
                                        (isAr ? 'استمرار' : 'Continue'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }

          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Material(
                color: Colors.black.withValues(alpha: 0.42),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: dialogBody(),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } catch (_) {
      _closeDialogIfAny();
    } finally {
      if (kIsWeb) setWebDocumentScrollLocked(false);
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _deadlineFireTimer?.cancel();
      _deadlineFireTimer = null;
      _promptSecVN?.dispose();
      _promptSecVN = null;
      _dialogOpen = false;
      if (_promptContinueIntent) {
        _promptContinueIntent = false;
        _promptDeadlineMs = null;
        unawaited(_clearPromptDeadlinePref());
        _resetIdleTimer();
      }
    }
  }

  void _closeDialogIfAny() {
    RootOverlayGuard.dismissOverlayRoutes(navigatorKey);
  }

  Future<void> _lockOrGoLogin() async {
    if (_locking) return;
    _locking = true;

    try {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _deadlineFireTimer?.cancel();
      _deadlineFireTimer = null;
      _idleTimer?.cancel();
      _promptDeadlineMs = null;
      unawaited(_clearPromptDeadlinePref());
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

      await _routeToRememberedAuthSurface();
    } finally {
      _locking = false;
    }
  }

  Future<void> _routeToRememberedAuthSurface() async {
    FastLoginService.clearRuntimeUnlock();
    final dest = await FastLoginService.resolveInactivityLockRoute();
    InactivityAuthLanding.begin(route: dest);
    await ReturnAfterAuth.saveFromNavigatorKey(navigatorKey);

    if (_signOutRunning) return;
    _signOutRunning = true;
    try {
      final current = _routeName();
      if (current == dest) {
        await AuthLocalSignOut.signOutLocal(
          Supabase.instance.client,
          tryRemoteRevoke: true,
        );
        return;
      }
      await SafeSignOutService.signOutAndNavigateToLoginFromNavigator(
        navigatorKey,
        logoutReason: 'inactivity_logout',
      );
    } catch (_) {
    } finally {
      _signOutRunning = false;
    }
  }
}
