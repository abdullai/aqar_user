// lib/services/inactivity_service.dart
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;

import '../core/auth/safe_sign_out_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show recoveryFlowNotifier, suspendAutoLock;
import '../core/session/return_after_auth.dart';
import '../core/config/app_config.dart';
import '../core/navigation/root_overlay_guard.dart';
import '../core/session/web_session_ttl.dart';
import '../services/fast_login_service.dart';
import '../routes.dart';

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
  static const String kPrefPromptDeadlineMs = 'inactivity_prompt_deadline_ms';

  Timer? _idleTimer;
  Timer? _countdownTimer;
  Timer? _deadlineFireTimer;
  ValueNotifier<int>? _promptSecVN;
  bool _promptContinueIntent = false;
  bool _dialogOpen = false;
  int? _promptDeadlineMs;

  int _lastActivityMs = 0;
  int _lastPersistWallMs = 0;
  final DateTime _serviceStartedAt = DateTime.now();

  /// لا نعرض حوار الخمول فور فتح التبويب/العودة من الخلفية.
  static const Duration _resumePromptGrace = Duration(seconds: 2);

  /// بعد دخول اللوحة على الويب: مهلة قصيرة فقط حتى يظهر عدّاد الجلسة فعلياً.
  static const Duration _webDashboardWarmupGrace = Duration(seconds: 5);
  static int? _webDashboardWarmupUntilMs;

  bool _locking = false;
  bool _signOutRunning = false;

  void start() {
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    unawaited(_persistLastActivityMs());
    _resetIdleTimer();
  }

  /// استدعِها عند إخفاء التطبيق/التبويب لتثبيت آخر نشاط + جدولة الخروج حسب الموعد.
  void onAppPaused() {
    unawaited(_persistLastActivityMs());
    // إن تجاوز الخمول دون حوار ظاهر: ابدأ عدّاد الخروج الآن ليظهر عند العودة.
    if (!_dialogOpen && !_locking) {
      final last = DateTime.fromMillisecondsSinceEpoch(_lastActivityMs);
      final elapsed = DateTime.now().difference(last);
      if (elapsed >= idleBeforePrompt) {
        final remaining = (idleBeforePrompt + promptCountdown) - elapsed;
        final sec = remaining.inSeconds.clamp(5, promptCountdown.inSeconds);
        _promptDeadlineMs =
            DateTime.now().millisecondsSinceEpoch + (sec * 1000);
      }
    }
    unawaited(_persistPromptDeadlineIfActive());
    _armDeadlineFireTimer();
  }

  /// عند العودة من الخلفية: إن تجاوز المستخدم المدة يُقفل/يُخرج فوراً حسب ساعة الجدار.
  Future<void> onAppResumedAfterBackground() async {
    if (DateTime.now().difference(_serviceStartedAt) < _resumePromptGrace) {
      return;
    }
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

      final deadline = prefs.getInt(kPrefPromptDeadlineMs);
      if (deadline != null && deadline > 0) {
        _promptDeadlineMs = deadline;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now >= deadline) {
          await prefs.remove(kPrefPromptDeadlineMs);
          _promptDeadlineMs = null;
          // لا خروج صامت بعد الخلفية — نافذة قصيرة ظاهرة أولاً.
          await _showPrompt(remainingSeconds: 12);
          return;
        }
        // أعد عرض الحوار بالمتبقي الحقيقي (لا تعيد العد من الصفر).
        if (!_dialogOpen) {
          final sec = ((deadline - now) / 1000).ceil().clamp(1, 3600);
          await _showPrompt(remainingSeconds: sec);
        } else {
          _armDeadlineFireTimer();
          _syncPromptSecondsFromDeadline();
        }
        return;
      }
    } catch (_) {}

    final last = DateTime.fromMillisecondsSinceEpoch(_lastActivityMs);
    final elapsed = DateTime.now().difference(last);
    final totalIdle = idleBeforePrompt + promptCountdown;

    // تجاوز الخمول + العدّاد بالكامل في الخلفية → أعرض حواراً قصيراً ظاهراً
    // (لا خروج صامت بدون أن يرى المستخدم العدّاد).
    if (elapsed >= totalIdle) {
      await _showPrompt(remainingSeconds: 8);
      return;
    }

    if (elapsed >= idleBeforePrompt) {
      final remaining = totalIdle - elapsed;
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
    _deadlineFireTimer?.cancel();
    _deadlineFireTimer = null;
    _promptSecVN?.dispose();
    _promptSecVN = null;
    _promptDeadlineMs = null;
    unawaited(_clearPromptDeadlinePref());
    _closeDialogIfAny();
    _dialogOpen = false;
    _locking = false;
    _signOutRunning = false;
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

  static Future<void> stampFreshActivity() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kPrefLastActivityAtMs, now);
    } catch (_) {}
  }

  static Future<void> prepareDashboardEntry() async {
    dismissBlockingPromptNow();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPrefPromptDeadlineMs);
    } catch (_) {}
    if (kIsWeb) {
      _webDashboardWarmupUntilMs = DateTime.now().millisecondsSinceEpoch +
          _webDashboardWarmupGrace.inMilliseconds;
    }
    await stampFreshActivity();
  }

  void userActivity() {
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    _maybeThrottlePersistActivity();

    if (_dialogOpen) return;
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

  Future<void> _persistPromptDeadlineIfActive() async {
    if (!_dialogOpen || _promptDeadlineMs == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(kPrefPromptDeadlineMs, _promptDeadlineMs!);
    } catch (_) {}
  }

  Future<void> _clearPromptDeadlinePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPrefPromptDeadlineMs);
    } catch (_) {}
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

      // قفل ناعم دائماً عند وجود جلسة + سياق/قفل — بدل الخروج الكامل العشوائي.
      if (await FastLoginService.canSoftLockSession()) {
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
        name == '/gate' ||
        name == '/verify' ||
        name == '/passwordSetup' ||
        name == AppRoutes.deviceManagement;
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

    if (kIsWeb) {
      final until = _webDashboardWarmupUntilMs;
      if (until != null &&
          DateTime.now().millisecondsSinceEpoch < until) {
        _resetIdleTimer();
        return;
      }
    }

    if (_isOnLoginOrFastLoginOrReset()) {
      _resetIdleTimer();
      return;
    }

    if (recoveryFlowNotifier.value == true) {
      _resetIdleTimer();
      return;
    }

    // أثناء شاشات حسّاسة (تحقق / إعدادات PIN / نشر…) لا تُظهر الحوار.
    if (suspendAutoLock.value == true) {
      _resetIdleTimer();
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      _resetIdleTimer();
      return;
    }

    final hasLock = await FastLoginService.canSoftLockSession();

    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) {
      _resetIdleTimer();
      return;
    }

    final initialSec =
        (remainingSeconds ?? promptCountdown.inSeconds).clamp(1, 3600);

    _dialogOpen = true;
    _promptContinueIntent = false;
    _promptDeadlineMs =
        DateTime.now().millisecondsSinceEpoch + (initialSec * 1000);
    unawaited(_persistPromptDeadlineIfActive());
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

    final timeLine = _formatNowLine(dialogContext);

    Future<void> present(Widget Function(BuildContext dialogCtx) page) {
      if (useIdleBlurOverlay) {
        return showGeneralDialog<void>(
          context: dialogContext,
          barrierDismissible: false,
          barrierLabel: 'inactivity',
          // حاجز واضح — الشفاف كان يخفي الحوار خلف طبقات الويب.
          barrierColor: Colors.black.withValues(alpha: 0.55),
          useRootNavigator: true,
          transitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (dialogCtx, _, __) {
            return page(dialogCtx);
          },
        );
      }
      return showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        useRootNavigator: true,
        builder: page,
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
                final progress = (sec / promptCountdown.inSeconds).clamp(0.0, 1.0);
                return Dialog(
                  insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
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
                                (isAr ? 'تم اكتشاف عدم نشاط' : 'Inactivity detected'),
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
                                : (isAr ? 'الوقت: $timeLine' : 'Time: $timeLine'),
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

          if (!useIdleBlurOverlay) {
            return dialogBody();
          }

          return SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Material(
                color: Colors.black.withValues(alpha: 0.42),
                child: Center(
                  child: dialogBody(),
                ),
              ),
            ),
          );
        },
      );
    } catch (_) {
      _closeDialogIfAny();
    } finally {
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

      if (await FastLoginService.canSoftLockSession()) {
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
      final current = _routeName();
      if (current == '/login' || current == '/') return;
      await SafeSignOutService.signOutAndNavigateToLoginFromNavigator(
        navigatorKey,
        logoutReason: 'inactivity_logout',
      );
    } catch (_) {
      // ignore
    } finally {
      _signOutRunning = false;
    }
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
