// ignore_for_file: unused_element, unused_field

// lib/screens/verify_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aqar_user/l10n/app_localizations.dart';

import 'package:pin_code_fields/pin_code_fields.dart';

// screen protection (mobile only)
import '../core/security/screen_protection.dart';

import 'package:provider/provider.dart';
import '../core/navigation/sensitive_nav_policy.dart';
import '../core/session/app_session.dart';
import '../core/auth/auth_signed_out_navigation_guard.dart';
import '../core/auth/auth_local_sign_out.dart';
import '../core/theme/app_appearance_bridge.dart';
import '../core/session/return_after_auth.dart';
import '../core/session/web_auth_tab_guard.dart';

import '../core/config/app_config.dart';
import '../core/utils/date_helper.dart';
import '../main.dart' show suspendAutoLock;

import '../services/fast_login_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/profile_compliance_service.dart';
import '../services/connectivity_guard.dart';
import '../services/user_install_session_service.dart';
import '../services/user_session_coordination_service.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../services/compliance_audit_service.dart';
import '../services/session_tracking_service.dart';
import '../core/input/input_normalizers.dart';
import '../core/auth/login_security_db.dart';
import '../core/auth/in_app_otp_handoff.dart';
import '../core/auth/otp_autofill.dart';
import '../core/auth/otp_pin_layout.dart';
import '../core/auth/auth_challenge_service.dart';
import '../widgets/aqar_text_field.dart';
import '../core/gestures/app_keyboard_inset.dart';
import '../core/gestures/app_keyboard_stable.dart';
import '../core/platform/app_surface.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/compound_display_name.dart';
import '../core/utils/dashboard_greeting.dart';
import '../core/haptics/app_haptics.dart';

import 'package:sms_autofill/sms_autofill.dart';

import '../core/notifications/app_sound_coordinator.dart';

import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/field_group_frame.dart';
import '../theme.dart' show AqarAuthScrollBehavior;

enum OtpSource { inApp, dev }

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({
    super.key,
    this.initialUsername,
    this.initialChallengeId,
    this.initialCode,
  });

  final String? initialUsername;
  final String? initialChallengeId;
  final String? initialCode;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const int _otpLen = InAppOtpHandoff.otpLen;
  static const int _maxSeconds = 90;
  static const int _maxAttempts = 5;
  static const int _lockAfterCycles = 2;

  String _otpVerifiedKey(String uid) => 'otp_verified_$uid';

  // ✅ NoScreenshot الآمن للمنصات
  bool _privacyMask = false;

  Timer? _timer;
  int _secondsLeft = _maxSeconds;
  DateTime? _expiresAt;

  int _attemptsLeft = _maxAttempts;
  int _failCount = 0;
  bool _error = false;
  bool _submitting = false;

  String _expectedCode = '';
  String _otp = '';

  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  // ✅ Animation Controllers
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // ✅ NEXT ROUTE
  String _nextRoute = kIsWeb ? '/' : '/userDashboard';
  Map<String, dynamic> _nextArgs = <String, dynamic>{};

  String _fullName = '';
  String _displayName = '';
  DateTime? _lastLogin;
  String _username = '';

  /// يطابق users_profiles.username وقيمة in_app_notifications.username بعد RPC التوحيد.
  String _profileUsername = '';
  String _deviceId = '';
  String? _avatarUrl;
  String _challengeId = '';

  bool _argsRead = false;
  bool _expectedFromArgs = false;
  bool _otpAlreadyRequested = false;

  OverlayEntry? _bannerEntry;
  Timer? _bannerTimer;
  bool _bannerPinnedManual = false;
  bool _otpTopNoticeVisible = true;
  String? _lastBannerCode;
  int _lastBannerAtMs = 0;

  final List<RealtimeChannel> _notifChannels = [];

  late final Future<void> _bootFuture;
  bool _booted = false;

  bool _userTypedSomething = false;

  /// بعد «إعادة إرسال» لا نُخرج المستخدم تلقائياً عند انتهاء العداد (النافذة الأولى فقط).
  bool _didResendOtp = false;

  /// يمنع استدعاءات مزدوجة للعودة لتسجيل الدخول عند انتهاء الوقت.
  bool _exitingOnTimer = false;

  bool _offline = false;
  bool _retryingNet = false;

  /// عند 500 من PostgREST (غالباً RLS / infinite recursion على users_profiles أو in_app_notifications).
  String? _restApiFailureHint;

  StreamSubscription<String>? _smsCodeSub;

  String get _notifUsername => _profileUsername.trim().isNotEmpty
      ? _profileUsername.trim()
      : _username.trim();

  List<String> _otpUsernameCandidates() {
    final out = <String>[];
    void add(String? s) {
      final t = (s ?? '').trim();
      if (t.isEmpty) return;
      if (!out.contains(t)) out.add(t);
    }

    add(_notifUsername);
    add(_profileUsername);
    add(_username);
    add(digitsOnly(normalizeAsciiDigits(_username)));
    return out;
  }

  DateTime? _latestOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  String _keyExpiresAt() => 'verify_expiresAt_$_notifUsername';

  bool get _isAr {
    try {
      final t = AppLocalizations.of(context);
      if (t == null) return Directionality.of(context) == TextDirection.rtl;
      return t.localeName.toLowerCase().startsWith('ar');
    } catch (_) {
      return Directionality.of(context) == TextDirection.rtl;
    }
  }

  double _font(BuildContext context, double desktop, double mobile) {
    final w = MediaQuery.of(context).size.width;
    if (w < 320) return mobile - 1.4;
    if (w < 330) return mobile - 1.0;
    if (w < 380) return mobile;
    return desktop;
  }

  void _onOtpFocusChanged() {
    if (_otpFocus.hasFocus) {
      OtpAutofill.stampFocusedHtmlField();
    }
  }

  void _kickOtpKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _otpFocus.requestFocus();
      OtpAutofill.stampFocusedHtmlField();
    });
  }

  @override
  void initState() {
    super.initState();
    // Prevent web auto-lock/sign-out during OTP or Chrome password checkup.
    suspendAutoLock.value = true;
    SensitiveNavPolicy.enterVerify();
    WidgetsBinding.instance.addObserver(this);

    _otpFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (!isEnter) return KeyEventResult.ignored;
      unawaited(_pasteOtpFromClipboard());
      return KeyEventResult.handled;
    };
    _otpFocus.addListener(_onOtpFocusChanged);
    _kickOtpKeyboard();

    // ✅ تهيئة Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsRead) _readArgsOnce();
    if (_booted) return;
    _booted = true;
    _bootFuture = _boot();
  }

  Future<void> _boot({bool forceRefetch = false}) async {
    await Future.wait([
      _enableScreenProtection(),
      if (!kIsWeb) _safeAsync(() => NotificationService.init()),
    ]);

    await _resolveProfileUsername();
    await _loadCachedValidCode();

    if (_username.trim().isEmpty) {
      _toast(_isAr
          ? 'بيانات التحقق غير مكتملة. أعد تسجيل الدخول.'
          : 'Missing verification data. Please login again.');
      await _goToLogin(signOut: true, clearOtp: true);
      return;
    }

    final netOk = await _ensureInternetOrShow();
    if (!netOk) {
      await _applyAuthUserFallback();
      return;
    }

    await _checkLockedStatusAndExitIfNeeded();
    _listenOtpNotifications();
    unawaited(_startSmsUserConsentListen());
    final otpKickoff = () async {
      if (_expectedCode.trim().length >= _otpLen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          onIncomingOtp(
            _expectedCode,
            source: kDebugMode ? OtpSource.dev : OtpSource.inApp,
          );
        });
        return;
      }
      if (!_otpAlreadyRequested) {
        await _requestOtpFromServer(force: forceRefetch);
      }
      await _waitForFirstOtpOrFetchFallback();
    }();
    await Future.wait([
      _loadProfileFromDbIfNeeded(),
      _loadPersistedTimerStateOnly(),
      otpKickoff,
    ]);
    _startOrResumeTimer();
    _kickOtpKeyboard();
    if (_expectedFromArgs && _expectedCode.trim().isNotEmpty) {
      return;
    }
  }

  @override
  void dispose() {
    suspendAutoLock.value = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _removeBanner();
    _pulseController.dispose();

    // ✅ إعادة تفعيل التصوير
    _safeAsync(() => ScreenProtection.disable());

    for (final ch in _notifChannels) {
      try {
        ch.unsubscribe();
      } catch (_) {}
    }
    _notifChannels.clear();

    try {
      _smsCodeSub?.cancel();
      _smsCodeSub = null;
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        unawaited(SmsAutoFill().unregisterListener());
      }
    } catch (_) {}

    _otpController.dispose();
    _otpFocus.removeListener(_onOtpFocusChanged);
    _otpFocus.dispose();
    SensitiveNavPolicy.leaveVerify();

    super.dispose();
  }

  Future<void> _enableScreenProtection() async {
    await _safeAsync(() => ScreenProtection.enable());
  }

  Future<void> _safeAsync(Future<dynamic> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  Future<bool> _hasInternet() async {
    try {
      return await ConnectivityGuard.hasInternet();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureInternetOrShow() async {
    final ok = await _hasInternet();
    if (!mounted) return false;

    if (!ok) {
      setState(() => _offline = true);
      _toast(_isAr
          ? 'لا يوجد اتصال بالإنترنت. فعّل الإنترنت ثم أعد المحاولة.'
          : 'No internet connection. Enable internet then retry.');
      return false;
    }

    if (_offline) {
      setState(() => _offline = false);
    }
    return true;
  }

  Future<void> _retryInternet() async {
    if (_retryingNet) return;
    setState(() => _retryingNet = true);
    try {
      final ok = await _hasInternet();
      if (!mounted) return;

      if (!ok) {
        setState(() {
          _offline = true;
          _retryingNet = false;
        });
        _toast(_isAr ? 'ما زال لا يوجد إنترنت.' : 'Still offline.');
        return;
      }

      setState(() {
        _offline = false;
        _retryingNet = false;
      });

      await _boot(forceRefetch: true);
    } finally {
      if (mounted) setState(() => _retryingNet = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    // Web: Chrome Password Manager sets inactive briefly — keep session, skip mask.
    if (kIsWeb) {
      if (state == AppLifecycleState.resumed) {
        setState(() => _privacyMask = false);
        _startOrResumeTimer(recalcOnly: true);
        _bannerEntry?.markNeedsBuild();
      }
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      setState(() => _privacyMask = true);
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _privacyMask = false);
      _startOrResumeTimer(recalcOnly: true);
      _bannerEntry?.markNeedsBuild();
    }
  }

  @override
  void didChangeMetrics() {
    _bannerEntry?.markNeedsBuild();
  }

  void _readArgsOnce() {
    _argsRead = true;

    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    final args = (rawArgs is Map) ? rawArgs : <String, dynamic>{};

    final fromWidget = (widget.initialCode ?? '').trim();
    final fromArgs = ((args['code'] as String?)?.trim() ?? '');
    final rawCode = fromWidget.isNotEmpty ? fromWidget : fromArgs;
    final onlyCode = rawCode.replaceAll(RegExp(r'\D'), '');
    _expectedFromArgs = onlyCode.isNotEmpty;
    _expectedCode = onlyCode.length > _otpLen
        ? onlyCode.substring(0, _otpLen)
        : onlyCode;

    _nextRoute = PostAuthNavigation.resolveDashboardRoute(
      (args['next'] as String?) ?? _nextRoute,
    );

    final na = args['nextArgs'];
    _nextArgs =
        (na is Map) ? Map<String, dynamic>.from(na) : <String, dynamic>{};

    _fullName = (args['fullName'] as String?) ?? '';
    final llRaw = args['lastLogin'];
    if (llRaw is DateTime) {
      _lastLogin = llRaw;
    } else if (llRaw != null) {
      _lastLogin = DateTime.tryParse(llRaw.toString());
    }
    final fn = _fullName.trim();
    if (fn.isNotEmpty) {
      _displayName = fn;
    }
    _username = (args['username'] as String?) ??
        (widget.initialUsername ?? '');
    _deviceId = (args['deviceId'] as String?) ?? '';
    _challengeId = (args['challengeId'] as String?)?.trim() ??
        (widget.initialChallengeId ?? '').trim();
    if (_challengeId.isNotEmpty) {
      unawaited(AuthChallengeService.persistPending(
        challengeId: _challengeId,
        username: _username,
      ));
    }
    _otpAlreadyRequested = args['otpAlreadyRequested'] == true;
    final av = (args['avatarUrl'] as String?)?.trim() ?? '';
    if (av.isNotEmpty) _avatarUrl = av;
    final expRaw = (args['otpExpiresAt'] as String?)?.trim() ?? '';
    if (expRaw.isNotEmpty) {
      _expiresAt = DateTime.tryParse(expRaw)?.toUtc();
    }
  }

  Future<void> _loadCachedValidCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final keyU in _otpUsernameCandidates()) {
        if (keyU.isEmpty) continue;
        final code = prefs.getString('last_valid_otp_$keyU');
        final timeStr = prefs.getString('last_valid_otp_time_$keyU');

        if (code != null && timeStr != null) {
          final time = DateTime.tryParse(timeStr);
          if (time != null &&
              DateTime.now().difference(time) < const Duration(minutes: 2)) {
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCachedValidCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      for (final keyU in _otpUsernameCandidates()) {
        if (keyU.isEmpty) continue;
        await prefs.setString('last_valid_otp_$keyU', code);
        await prefs.setString('last_valid_otp_time_$keyU', now);
      }
    } catch (_) {}
  }

  Future<void> _loadPersistedTimerStateOnly() async {
    final u = _notifUsername;
    if (u.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final expStr = prefs.getString(_keyExpiresAt());
    final exp = (expStr == null || expStr.trim().isEmpty)
        ? null
        : DateTime.tryParse(expStr);

    final nowUtc = DateTime.now().toUtc();

    if (exp != null) {
      final expUtc = exp.isUtc ? exp : exp.toUtc();
      if (expUtc.isAfter(nowUtc)) {
        _expiresAt = expUtc;
        return;
      }
    }

    _expiresAt = nowUtc.add(const Duration(seconds: _maxSeconds));
    await prefs.setString(_keyExpiresAt(), _expiresAt!.toIso8601String());
  }

  Future<void> _persistTimerOnly() async {
    final u = _notifUsername;
    if (u.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (_expiresAt != null) {
      await prefs.setString(_keyExpiresAt(), _expiresAt!.toIso8601String());
    }
  }

  Future<void> _clearPersistedTimerOnly() async {
    final u = _notifUsername;
    if (u.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyExpiresAt());
  }

  void _startOrResumeTimer({bool recalcOnly = false}) {
    _timer?.cancel();

    final exp = _expiresAt;
    if (exp == null) {
      _secondsLeft = _maxSeconds;
      if (mounted) setState(() {});
      if (!recalcOnly) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
      return;
    }

    final expUtc = exp.isUtc ? exp : exp.toUtc();
    final diff = expUtc.difference(DateTime.now().toUtc()).inSeconds;
    _secondsLeft = diff <= 0 ? 0 : diff;

    if (mounted) setState(() {});
    if (recalcOnly) return;

    if (diff <= 0) {
      unawaited(_onFirstOtpWindowExpiredIfNoInput());
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final exp = _expiresAt;
    if (exp == null) return;

    final expUtc = exp.isUtc ? exp : exp.toUtc();
    final diff = expUtc.difference(DateTime.now().toUtc()).inSeconds;

    if (diff <= 0) {
      _timer?.cancel();
      setState(() => _secondsLeft = 0);
      unawaited(_onFirstOtpWindowExpiredIfNoInput());
      return;
    }

    setState(() => _secondsLeft = diff);
  }

  bool _otpBoxesAreEmpty() {
    final ui = _otpDigitsFromUi().replaceAll(RegExp(r'\D'), '');
    return ui.isEmpty;
  }

  Future<void> _onFirstOtpWindowExpiredIfNoInput() async {
    if (!mounted || _exitingOnTimer) return;
    if (_offline) return;
    if (_submitting) return;
    if (_didResendOtp) return;
    if (!_otpBoxesAreEmpty()) return;

    _exitingOnTimer = true;
    _toast(_isAr
        ? 'انتهى وقت إدخال الرمز. أعد تسجيل الدخول.'
        : 'Verification time expired. Please sign in again.');
    await _goToLogin(signOut: true, clearOtp: true);
  }

  Future<bool> _isLockedInDb() async {
    try {
      final sb = Supabase.instance.client;
      for (final u in _otpUsernameCandidates()) {
        if (u.isEmpty) continue;
        final row = await sb
            .from('users_profiles')
            .select('status')
            .eq('username', u)
            .maybeSingle();
        final s = (row?['status'] ?? '').toString().trim().toLowerCase();
        if (s == 'locked') return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkLockedStatusAndExitIfNeeded() async {
    final locked = await _isLockedInDb();
    if (!mounted) return;

    if (locked) {
      _toast(_isAr
          ? 'الحساب مقفل. استخدم استعادة كلمة المرور لفتحه.'
          : 'Account locked. Use password recovery to unlock.');
      await _goToLogin(signOut: true, clearOtp: true);
    }
  }

  Future<Map<String, dynamic>?> _getOtpFailState() async {
    try {
      final sb = Supabase.instance.client;
      for (final u in _otpUsernameCandidates()) {
        if (u.isEmpty) continue;
        final row = await sb
            .from('users_profiles')
            .select('otp_fail_cycles, otp_fail_count')
            .eq('username', u)
            .maybeSingle();
        if (row != null) return row;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setOtpFailState({
    required int cycles,
    required int count,
    required bool lockNow,
  }) async {
    try {
      final sb = Supabase.instance.client;
      final data = <String, dynamic>{
        'otp_fail_cycles': cycles,
        'otp_fail_count': count,
        'otp_fail_last_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (lockNow) data['status'] = 'locked';

      for (final u in _otpUsernameCandidates()) {
        if (u.isEmpty) continue;
        final existing = await sb
            .from('users_profiles')
            .select('username')
            .eq('username', u)
            .maybeSingle();
        if (existing == null) continue;
        await sb.from('users_profiles').update(data).eq('username', u);
        return;
      }
    } catch (_) {}
  }

  Future<void> _resetOtpFailStateInDb() async {
    try {
      final sb = Supabase.instance.client;
      final data = <String, dynamic>{
        'otp_fail_cycles': 0,
        'otp_fail_count': 0,
        'otp_fail_last_at': null,
      };
      for (final u in _otpUsernameCandidates()) {
        if (u.isEmpty) continue;
        final existing = await sb
            .from('users_profiles')
            .select('username')
            .eq('username', u)
            .maybeSingle();
        if (existing == null) continue;
        await sb.from('users_profiles').update(data).eq('username', u);
        return;
      }
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _greeting() => DashboardGreeting.salutationOnly(isAr: _isAr);

  DateTime get _nowSaudi => DashboardGreeting.nowSaudiArabia();

  String _formatDateYmd(DateTime d) =>
      DateHelper.fmtCivilDate(d, isAr: _isAr);

  String _formatTime24(DateTime d) => DateHelper.fmtClock(d);

  String _weekdayName(DateTime d) {
    final wd = d.weekday;
    if (_isAr) {
      const ar = [
        'الاثنين',
        'الثلاثاء',
        'الأربعاء',
        'خميس',
        'الجمعة',
        'السبت',
        'الأحد'
      ];
      return ar[wd - 1];
    } else {
      const en = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      return (wd >= 1 && wd <= 7) ? en[wd - 1] : 'Day';
    }
  }

  String _todayLine() {
    final now = _nowSaudi;
    return '${_weekdayName(now)} ${_formatDateYmd(now)} • ${_formatTime24(now)}';
  }

  String _lastLoginLine() {
    final v = _lastLogin;
    if (v == null) return _isAr ? 'غير متوفر' : 'N/A';
    // اعرض آخر دخول بتوقيت المملكة للاتساق مع التحية.
    final saudi = v.toUtc().add(const Duration(hours: 3));
    return '${_formatDateYmd(saudi)} • ${_formatTime24(saudi)}';
  }

  /// لا نعرض أرقام الهوية / المعرف العام / أي «اسم» مكوّن من أرقام فقط كتحية بشرية.
  bool _looksLikeNumericLoginIdentifier(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (!RegExp(r'^\d+$').hasMatch(t)) return false;
    return t.length >= 9 && t.length <= 12;
  }

  String _greetingDisplayName() {
    final a = _displayName.trim();
    final b = _fullName.trim();
    if (a.isNotEmpty && !_looksLikeNumericLoginIdentifier(a)) return a;
    if (b.isNotEmpty && !_looksLikeNumericLoginIdentifier(b)) return b;
    return '';
  }

  Future<void> _requestOtpFromServer({required bool force}) async {
    if (!await _ensureInternetOrShow()) return;

    final u = _username.trim();
    if (u.isEmpty) return;

    if (!force && _expectedFromArgs) return;

    var uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null && uid.isNotEmpty) break;
      }
    }
    if (uid == null || uid.isEmpty) {
      if (_otpAlreadyRequested && !force) return;
      _toast(_isAr ? 'يلزم تسجيل الدخول قبل التحقق' : 'You must be logged in');
      return;
    }

    try {
      final ok = await AuthService.requestOtp(u);
      if (!ok) {
        _toast(_isAr ? 'تعذر إرسال إشعار الرمز' : 'Failed to send in-app code');
      } else {
        final pending = await AuthChallengeService.readPending();
        if ((pending.challengeId ?? '').isNotEmpty) {
          _challengeId = pending.challengeId!;
        }
        final peeked = await InAppOtpHandoff.pollLatestCode(
          requestedAtUtc: DateTime.now().toUtc(),
          challengeId: _challengeId,
        );
        if (peeked != null && peeked.length >= _otpLen && mounted) {
          onIncomingOtp(
            peeked,
            source: kDebugMode ? OtpSource.dev : OtpSource.inApp,
          );
        }
      }
    } catch (_) {
      _toast(_isAr ? 'تعذر إرسال إشعار الرمز' : 'Failed to send in-app code');
    }
  }

  Future<void> _waitForFirstOtpOrFetchFallback() async {
    if (!await _ensureInternetOrShow()) return;
    if (_expectedCode.trim().isNotEmpty) return;

    const delays = <int>[40, 90, 160, 280];
    for (final ms in delays) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      if (!mounted) return;

      if (_expectedCode.trim().isNotEmpty) return;

      final ok = await _hasInternet();
      if (!ok) {
        if (!mounted) return;
        setState(() => _offline = true);
        return;
      }

      await _fetchLatestOtpNotificationAndApply();
      if (_expectedCode.trim().isNotEmpty) return;
      final peeked = await InAppOtpHandoff.fetchLatestCode(
        challengeId: _challengeId,
      );
      if (peeked != null && peeked.length >= _otpLen && mounted) {
        onIncomingOtp(
          peeked,
          source: kDebugMode ? OtpSource.dev : OtpSource.inApp,
        );
        return;
      }
    }
  }

  void _noteVerifySupabaseFailure(Object e, {required String where}) {
    if (e is! PostgrestException) return;
    if (kDebugMode) {
      debugPrint(
        '[VerifyScreen] PostgrestException ($where): ${e.message} code=${e.code} details=${e.details}',
      );
    }
    if (!mounted) return;
    setState(() {
      _restApiFailureHint = _isAr
          ? 'تعذّر جلب بيانات التحقق من Supabase (خطأ خادم، غالباً 500). '
              'السبب الشائع: حلقة RLS على users_profiles أو تداخل مع in_app_notifications.\n'
              'نفّذ في SQL Editor بالترتيب:\n'
              '1) supabase/sql/20260422_users_profiles_rls_consolidated_fix.sql\n'
              '2) supabase/sql/20260420_in_app_notifications_drop_duplicate_select_policy.sql\n'
              '3) إن استمر 500: supabase/sql/20260427_users_profiles_rls_helper_row_security_off.sql\n'
              'ثم راجع Logs → Postgres في لوحة Supabase.'
          : 'Supabase request failed (often HTTP 500). Common cause: RLS recursion on users_profiles '
              'or conflicting in_app_notifications policies.\n'
              'Run in SQL Editor:\n'
              '1) supabase/sql/20260422_users_profiles_rls_consolidated_fix.sql\n'
              '2) supabase/sql/20260420_in_app_notifications_drop_duplicate_select_policy.sql\n'
              '3) If still 500: supabase/sql/20260427_users_profiles_rls_helper_row_security_off.sql\n'
              'Then check Supabase → Logs → Postgres.';
    });
    _toast(_isAr
        ? 'خطأ من قاعدة البيانات — لن يظهر الرمز حتى يُصلح الخادم'
        : 'Database error — OTP cannot load until server is fixed');
  }

  Future<void> _fetchLatestOtpNotificationAndApply() async {
    try {
      // بلا جلسة: لا تطلب الجدول المحمي (كان يظهر 401 على /login بعد سقوط الجلسة).
      if (Supabase.instance.client.auth.currentSession == null) return;
      // الاعتماد على RLS: الصفوف المرئية فقط هي التي username يطابق users_profiles.
      // تجنّب .eq('username', …) لأن أي اختلاف بسيط عن القيمة المخزنة يعيد صفراً ولا يظهر الرمز.
      final rows = await Supabase.instance.client
          .from('in_app_notifications')
          .select('type, body, data, created_at')
          .order('created_at', ascending: false)
          .limit(15);

      if (!mounted) return;
      if (rows.isNotEmpty) {
        setState(() => _restApiFailureHint = null);
      }

      if (rows.isEmpty) return;
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final typeNorm = (row['type'] ?? '').toString().trim().toLowerCase();
        if (typeNorm != 'otp') continue;
        _applyOtpFromRow(row,
            source: kDebugMode ? OtpSource.dev : OtpSource.inApp);
        return;
      }
    } on PostgrestException catch (e) {
      _noteVerifySupabaseFailure(e, where: 'in_app_notifications');
    } catch (_) {}
  }

  void _listenOtpNotifications() {
    if (_username.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('[VerifyScreen] Cannot listen OTP: username is empty');
      }
      return;
    }

    for (final ch in _notifChannels) {
      try {
        ch.unsubscribe();
      } catch (_) {}
    }
    _notifChannels.clear();

    // اشتراك بعدة قيم username محتملة (ما كتبه المستخدم، ما في الملف، والرقم بعد التطبيع)
    // حتى لا يُفوت Realtime إن اختلفت قليلاً عن ما خزّنه request_inapp_otp.
    final seen = <String>{};
    final candidates = <String>[];
    for (final c in _otpUsernameCandidates()) {
      final t = c.trim();
      if (t.isEmpty || seen.contains(t)) continue;
      seen.add(t);
      candidates.add(t);
    }

    if (candidates.isEmpty) {
      if (kDebugMode) {
        debugPrint('[VerifyScreen] Cannot listen OTP: no username candidates');
      }
      return;
    }

    final listenCount = kIsWeb ? 1 : candidates.length;
    for (var i = 0; i < listenCount; i++) {
      final u = candidates[i];
      final ch = Supabase.instance.client
          .channel('verify_otp_inserts_${u}_${hashCode}_$i')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'in_app_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'username',
              value: u,
            ),
            callback: (payload) {
              final row = Map<String, dynamic>.from(payload.newRecord);
              final typeNorm =
                  (row['type'] ?? '').toString().trim().toLowerCase();
              if (typeNorm != 'otp') return;
              _applyOtpFromRow(
                row,
                source: kDebugMode ? OtpSource.dev : OtpSource.inApp,
              );
            },
          )
          .subscribe();
      _notifChannels.add(ch);
    }
  }

  void _applyOtpFromRow(Map<String, dynamic> row, {required OtpSource source}) {
    final typeNorm = (row['type'] ?? '').toString().trim().toLowerCase();
    if (typeNorm != 'otp') return;

    String code = '';
    DateTime? exp;

    final data = row['data'];
    if (data is Map) {
      code = (data['code'] ?? '').toString().trim();
      final expRaw = (data['expiresAt'] ?? '').toString().trim();
      exp = DateTime.tryParse(expRaw);
      final cid = (data['challengeId'] ?? '').toString().trim();
      if (cid.isNotEmpty) _challengeId = cid;
    } else if (data != null) {
      final s = data.toString();
      final only = s.replaceAll(RegExp(r'\D'), '');
      if (only.length >= _otpLen) code = only.substring(0, _otpLen);
      final m = RegExp(r'expiresAt"\s*:\s*"([^"]+)"').firstMatch(s);
      if (m != null) exp = DateTime.tryParse(m.group(1) ?? '');
    }

    if (code.isEmpty) {
      final body = (row['body'] ?? '').toString();
      final only = body.replaceAll(RegExp(r'\D'), '');
      if (only.length >= _otpLen) code = only.substring(0, _otpLen);
    }

    if (code.isEmpty) {
      unawaited(() async {
        final peeked = await InAppOtpHandoff.fetchLatestCode(
          challengeId: _challengeId,
        );
        if (!mounted) return;
        if (peeked != null && peeked.length >= _otpLen) {
          onIncomingOtp(
            peeked,
            source: kDebugMode ? OtpSource.dev : source,
          );
        }
      }());
      if (exp != null) {
        _expiresAt = exp.isUtc ? exp : exp.toUtc();
        _startOrResumeTimer();
      }
      return;
    }

    if (exp != null) {
      _expiresAt = (exp.isUtc ? exp : exp.toUtc());
    } else {
      _expiresAt =
          DateTime.now().toUtc().add(const Duration(seconds: _maxSeconds));
    }

    _startOrResumeTimer();
    _persistTimerOnly();

    if (!mounted) return;

    setState(() {
      _expectedCode = code;
      if (!_userTypedSomething) {
        _otp = '';
        _otpController.clear();
        _error = false;
      }
    });

    onIncomingOtp(code, source: source);
  }

  Future<void> _playAndNotifyOtp(String code, OtpSource source) async {
    final title = _isAr
        ? (source == OtpSource.dev ? 'رمز (DEV)' : 'رمز التحقق')
        : (source == OtpSource.dev ? 'DEV code' : 'Verification code');
    // لا نعرض الرمز في إشعار النظام/الشريط — يبقى داخل التطبيق فقط (أمان + ممارسة عالمية).
    final publicBody = _isAr
        ? 'وصل رمز تحقق إلى هاتفك. افتح التطبيق وأدخل الرمز في الشاشة.'
        : 'A verification code was sent. Open the app and enter it on screen.';

    // الويب: لا يوجد إشعار نظام محلي — SnackBar عام بدون كشف الرمز.
    if (kIsWeb && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Text(
            publicBody,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    if (kIsWeb) {
      // إشعار OTP المحلي غير مدعوم على الويب — الكفاية: SnackBar أعلاه + نغمة الأصول.
      await _safeAsync(() => AppSoundCoordinator.playUiEffect(
            assetPath: 'sounds/otp_chime.wav',
            volume: 1.0,
          ));
    } else {
      await _safeAsync(() => NotificationService.showOtpNotification(
            title: title,
            body: publicBody,
            playChannelSound: true,
          ));
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        await _safeAsync(() async {
          try {
            await HapticFeedback.mediumImpact();
          } catch (_) {}
        });
      }
    }

    // ✅ تشغيل Animation
    _pulseController.forward().then((_) => _pulseController.reverse());
  }

  void onIncomingOtp(String text, {required OtpSource source}) {
    final only = text.replaceAll(RegExp(r'\D'), '');
    if (only.isEmpty) return;

    final code = only.length >= _otpLen ? only.substring(0, _otpLen) : only;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastBannerCode == code && (now - _lastBannerAtMs) < 1200) return;

    _lastBannerCode = code;
    _lastBannerAtMs = now;

    _safeAsync(() => _playAndNotifyOtp(code, source));
    unawaited(Clipboard.setData(ClipboardData(text: code)));
    _showBanner(code: code, source: source);
  }

  Future<void> _notifyThirdOtpAttempt() async {
    final t = AppLocalizations.of(context);
    final title = t?.otpAttemptsThirdNotifyTitle ??
        (_isAr ? 'تنبيه محاولات رمز التحقق' : 'Verification attempt notice');
    final body = t?.otpAttemptsThirdNotifyBody ??
        (_isAr
            ? 'أدخلت الرمز ثلاث مرات. راجع المحاولات المتبقية أو أعد إرسال رمز جديد.'
            : 'You entered the code three times. Check remaining attempts or resend a new code.');
    _toast('$title — $body');
    if (kIsWeb) {
      await _safeAsync(() => AppSoundCoordinator.playUiEffect(
            assetPath: 'sounds/otp_chime.wav',
            volume: 1.0,
          ));
      return;
    }
    await _safeAsync(() => NotificationService.showOtpNotification(
          title: title,
          body: body,
          playChannelSound: true,
        ));
  }

  double _overlayKeyboardInset(BuildContext context) {
    final view = View.maybeOf(context);
    var fromView = 0.0;
    if (view != null && view.devicePixelRatio > 0) {
      fromView = view.viewInsets.bottom / view.devicePixelRatio;
    }
    final mq = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    return fromView > mq ? fromView : mq;
  }

  void _fillOtpFromSuggestion(String code) {
    AppHaptics.selection();
    unawaited(Clipboard.setData(ClipboardData(text: code)));
    _applyIncomingCode(code, fromUserAction: true);
    _toast(_isAr ? 'تم لصق الرمز' : 'Code pasted');
    _bannerEntry?.markNeedsBuild();
  }

  Widget _bankOtpKeyboardChip(String code, {required bool isDark}) {
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final fg = isDark ? Colors.white : const Color(0xFF0B1220);
    return Material(
      elevation: 18,
      color: bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _fillOtpFromSuggestion(code),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isAr ? 'من عقار — اضغط للصق' : 'From Aqar — tap to paste',
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: cs.primary,
                  fontFamily: 'Cairo',
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                code.split('').join('  '),
                maxLines: 1,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  letterSpacing: 2,
                  color: fg,
                  fontFamily: 'Cairo',
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBanner({required String code, required OtpSource source}) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showBanner(code: code, source: source);
      });
      return;
    }
    _removeBanner();

    _bannerPinnedManual = false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final titleColor = isDark ? Colors.white : const Color(0xFF0B1220);
    final bodyColor =
        isDark ? const Color(0xFFD1D5DB) : const Color(0xFF475569);

    final title = _isAr
        ? (source == OtpSource.dev ? 'رمز (DEV)' : 'تم استلام رمز التحقق')
        : (source == OtpSource.dev ? 'DEV code' : 'Verification code received');

    _otpTopNoticeVisible = true;
    _bannerEntry = OverlayEntry(
      builder: (overlayCtx) {
        final liveCode = InAppOtpHandoff.digitsFromAny(_expectedCode) ?? code;
        final filled =
            _otpDigitsFromUi().replaceAll(RegExp(r'\D'), '').length >= _otpLen;
        final kb = _overlayKeyboardInset(overlayCtx);
        return Positioned.fill(
          child: Stack(
            children: [
              if (_otpTopNoticeVisible)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final bool isTiny = w < 360;
                      final bool isXTiny = w < 320;

                      final double side = (w * 0.04).clamp(8.0, 16.0);
                      final double topExtra =
                          (w * 0.02).clamp(4.0, 10.0) + (isTiny ? 2.0 : 4.0);

                      final double radius = (w * 0.055).clamp(16.0, 22.0);
                      final double titleFs = (w * 0.040).clamp(12.0, 15.0);
                      final double bodyFs = (w * 0.036).clamp(12.0, 14.0);
                      final double btnFs = (w * 0.034).clamp(11.8, 13.5);

                      Widget actionButton({
                        required String label,
                        required VoidCallback onTap,
                        required Color textColor,
                        bool primary = false,
                      }) {
                        return TextButton(
                          onPressed: onTap,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: isXTiny ? 10 : 12,
                              vertical: isXTiny ? 6 : 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontWeight:
                                  primary ? FontWeight.w900 : FontWeight.w800,
                              fontSize: btnFs,
                            ),
                          ),
                        );
                      }

                      final actionsRow = Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          actionButton(
                            label: _isAr ? 'لصق' : 'Paste',
                            textColor: titleColor,
                            primary: true,
                            onTap: () {
                              _fillOtpFromSuggestion(liveCode);
                              _removeBanner();
                            },
                          ),
                          const SizedBox(width: 6),
                          actionButton(
                            label: _isAr ? 'إدخال يدوي' : 'Manual',
                            textColor: bodyColor,
                            onTap: () {
                              AppHaptics.selection();
                              _bannerPinnedManual = true;
                              _otpTopNoticeVisible = false;
                              _bannerTimer?.cancel();
                              _bannerTimer = null;
                              _otpFocus.requestFocus();
                              _bannerEntry?.markNeedsBuild();
                            },
                          ),
                          const SizedBox(width: 6),
                          actionButton(
                            label: _isAr ? 'إلغاء' : 'Cancel',
                            textColor: bodyColor,
                            onTap: () {
                              _otpTopNoticeVisible = false;
                              _bannerEntry?.markNeedsBuild();
                            },
                          ),
                        ],
                      );

                      return SafeArea(
                        top: true,
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: side,
                            end: side,
                            top: topExtra,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: 1,
                            child: Material(
                              color: Colors.transparent,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (w * 0.94).clamp(300.0, 560.0),
                                ),
                                child: Container(
                                  padding: EdgeInsetsDirectional.fromSTEB(
                                    isXTiny ? 10 : 12,
                                    isXTiny ? 9 : 10,
                                    isXTiny ? 10 : 12,
                                    isXTiny ? 8 : 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(radius),
                                    border: Border.all(color: border),
                                    boxShadow: [
                                      BoxShadow(
                                        blurRadius: 18,
                                        offset: const Offset(0, 10),
                                        color: Colors.black
                                            .withValues(alpha: isDark ? 0.35 : 0.12),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: liveCode.length >= _otpLen
                                            ? () {
                                                _fillOtpFromSuggestion(
                                                  liveCode,
                                                );
                                                _removeBanner();
                                              }
                                            : null,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: isXTiny ? 34 : 38,
                                              height: isXTiny ? 34 : 38,
                                              decoration: BoxDecoration(
                                                color: (isDark
                                                        ? Colors.white
                                                        : Colors.black)
                                                    .withValues(alpha: 0.06),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                Icons
                                                    .notifications_active_outlined,
                                                color: titleColor,
                                                size: isXTiny ? 18 : 20,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: titleColor,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: titleFs,
                                                      height: 1.1,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    _isAr
                                                        ? 'رمز التحقق: $liveCode'
                                                        : 'Your code: $liveCode',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: bodyColor,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: bodyFs,
                                                      height: 1.1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: isXTiny ? 8 : 10),
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          physics:
                                              const BouncingScrollPhysics(),
                                          child: actionsRow,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (!filled &&
                  liveCode.length >= _otpLen &&
                  AppSurfaceScope.of(overlayCtx).showOtpKeyboardPasteChip)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: kb > 8 ? kb + 6 : 12,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: _bankOtpKeyboardChip(liveCode, isDark: isDark),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    overlay.insert(_bannerEntry!);

    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_bannerPinnedManual) return;
      _otpTopNoticeVisible = false;
      _bannerEntry?.markNeedsBuild();
    });
  }

  void _removeBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _bannerPinnedManual = false;
    _bannerEntry?.remove();
    _bannerEntry = null;
  }

  void _clear() {
    setState(() {
      _otp = '';
      _otpController.clear();
      _error = false;
      _userTypedSomething = false;
    });
    _otpFocus.requestFocus();
  }

  void _applyIncomingCode(String text, {required bool fromUserAction}) {
    final value = OtpAutofill.sequentialValue(text);
    if (value.text.isEmpty) return;

    final take = value.text;
    _otp = take;
    if (fromUserAction) _userTypedSomething = true;
    _otpController.value = value;
    if (_error) {
      setState(() => _error = false);
    }
    _otpFocus.requestFocus();
    OtpAutofill.stampFocusedHtmlField();
    if (take.length >= _otpLen) {
      _maybeAutoSubmit();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_otpController.text != take) {
        _otpController.value = value;
      }
      if (take.length >= _otpLen) _maybeAutoSubmit();
      _bannerEntry?.markNeedsBuild();
    });
  }

  void _maybeAutoSubmit() {
    if (_submitting) return;
    final raw = _otpDigitsFromUi().replaceAll(RegExp(r'\D'), '');
    if (raw.isEmpty) return;
    final entSlice = raw.length >= _otpLen ? raw.substring(0, _otpLen) : raw;
    if (entSlice.length != _otpLen) return;

    // المصدر الحقيقي للصحة هو verify_inapp_otp على الخادم.
    // لا نمنع الإرسال التلقائي إذا اختلف اللصق عن _expectedCode (قد يكون معروضاً قديماً أو لم يُحمَّل بعد).
    unawaited(_submit());
  }

  /// يأخذ الأرقام من الحقل أو من الحالة — يصلح اختلاف PinCodeTextField عن _otp.
  String _otpDigitsFromUi() {
    final fromCtrl = _otpController.text.replaceAll(RegExp(r'\D'), '');
    final fromState = _otp.replaceAll(RegExp(r'\D'), '');
    if (fromCtrl.length >= _otpLen) {
      return fromCtrl.length > _otpLen
          ? fromCtrl.substring(0, _otpLen)
          : fromCtrl;
    }
    if (fromState.length >= _otpLen) {
      return fromState.length > _otpLen
          ? fromState.substring(0, _otpLen)
          : fromState;
    }
    return fromCtrl.length > fromState.length ? fromCtrl : fromState;
  }

  Future<void> _submit() async {
    if (!await _ensureInternetOrShow()) return;
    if (_submitting) return;

    var entered = _otpDigitsFromUi();
    if (entered.length != _otpLen) {
      entered = _otp.trim().replaceAll(RegExp(r'\D'), '');
    }
    if (entered.length > _otpLen) {
      entered = entered.substring(0, _otpLen);
    }

    if (entered.isEmpty) {
      AppHaptics.medium();
      setState(() => _error = true);
      _toast(
          _isAr ? 'الرجاء إدخال الرمز المرسل' : 'Please enter the sent code');
      _otpFocus.requestFocus();
      return;
    }

    if (entered.length != _otpLen) {
      AppHaptics.medium();
      setState(() => _error = true);
      _toast(
          _isAr ? 'الرجاء إدخال الرمز كاملاً' : 'Please enter the full code');
      _otpFocus.requestFocus();
      return;
    }

    setState(() => _submitting = true);

    try {
      final uRaw = digitsOnly(normalizeAsciiDigits(_username.trim()));
      // يجب أن يطابق p_username في request_inapp_otp — صف الملف قد يحمل username مختلفاً (معرف عام/قديم).
      final canonical = await AuthService.securityUsernameForDeviceFlow(uRaw);
      var digits = entered.replaceAll(RegExp(r'\D'), '');
      if (digits.length > _otpLen) {
        digits = digits.substring(0, _otpLen);
      }
      final c = digits.padLeft(_otpLen, '0');

      bool ok = false;
      String? verifyError;
      final verified = await AuthChallengeService.verify(
        code: c,
        challengeId: _challengeId.isEmpty ? null : _challengeId,
        username: canonical,
      );
      ok = verified.ok;
      verifyError = verified.error;
      if (verified.locked) {
        _toast(_isAr
            ? 'تم قفل رمز التحقق. أعد تسجيل الدخول.'
            : 'Verification locked. Please sign in again.');
        await _goToLogin(signOut: true, clearOtp: true);
        return;
      }
      if (!ok && (verifyError == 'expired')) {
        _toast(_isAr ? 'انتهت صلاحية الرمز.' : 'The code has expired.');
      }

      if (!ok) {
        AppHaptics.vibrate();
        final remaining = verified.remainingAttempts;
        setState(() {
          _failCount += 1;
          if (remaining != null) {
            _attemptsLeft = remaining;
          } else {
            _attemptsLeft--;
          }
          _error = true;
          _otp = '';
          _otpController.clear();
          _userTypedSomething = false;
        });

        final state = await _getOtpFailState();

        int cycles = (state?['otp_fail_cycles'] ?? 0) is int
            ? (state?['otp_fail_cycles'] as int)
            : int.tryParse('${state?['otp_fail_cycles'] ?? 0}') ?? 0;

        int count = (state?['otp_fail_count'] ?? 0) is int
            ? (state?['otp_fail_count'] as int)
            : int.tryParse('${state?['otp_fail_count'] ?? 0}') ?? 0;

        count += 1;
        if (count >= _maxAttempts) {
          count = 0;
          cycles += 1;
        }

        final lockNow = cycles >= _lockAfterCycles;
        await _setOtpFailState(cycles: cycles, count: count, lockNow: lockNow);

        if (lockNow) {
          _toast(_isAr
              ? 'تم قفل الحساب. استعد كلمة المرور لفتحه.'
              : 'Account locked. Use password recovery to unlock.');
          await _goToLogin(signOut: true, clearOtp: true);
          return;
        }

        if (_failCount == 3) {
          await _notifyThirdOtpAttempt();
        }

        if (_attemptsLeft <= 0) {
          _toast(_isAr
              ? 'تم تجاوز الحد. تم إعادتك لتسجيل الدخول.'
              : 'Limit reached. Returning to login.');
          await _goToLogin(signOut: true, clearOtp: true);
          return;
        }

        if (!mounted) return;
        final t = AppLocalizations.of(context);
        _toast(t?.otpAttemptsRemaining(_attemptsLeft) ??
            (_isAr
                ? 'الرمز غير صحيح. المتبقي: $_attemptsLeft'
                : 'Invalid code. Left: $_attemptsLeft'));
        _otpFocus.requestFocus();
        return;
      }

      await _resetOtpFailStateInDb();
      await _saveCachedValidCode(c);

      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;

      if (uid == null || uid.isEmpty) {
        _toast(_isAr
            ? 'لا توجد جلسة دخول. أعد تسجيل الدخول.'
            : 'No session. Please login again.');
        await _goToLogin(signOut: true, clearOtp: true);
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(AppConfig.prefGuestModeKey, false);
      await prefs.setString(AppConfig.prefEntryModeKey, 'user');
      await prefs.setBool(_otpVerifiedKey(uid), true);
      if (kIsWeb) {
        await WebAuthTabGuard.establishBinding(uid);
      }

      unawaited(ComplianceAuditService.instance.log('otp.verified', {
        'source': 'verify_screen',
      }));

      if (!mounted) return;
      final appSession = context.read<AppSession>();
      await appSession.setUser(uid);
      appSession.schedulePostAuthHomeWarmup();

      _timer?.cancel();
      _removeBanner();
      await _clearPersistedTimerOnly();

      final tuple = await ReturnAfterAuth.consume();
      var route = _nextRoute;
      Map<String, dynamic>? lockedArgs;
      if (tuple != null) {
        route = PostAuthNavigation.resolveDashboardRoute(tuple.route);
        lockedArgs = ReturnAfterAuth.decodeArgsJson(tuple.argsJson);
      }

      final nextArgs = <String, dynamic>{
        ..._nextArgs,
        if (lockedArgs != null) ...lockedArgs,
        'username': _username,
        'deviceId': _deviceId,
        'fullName': _fullName,
      };

      if (!mounted) return;

      // فتح اللوحة فوراً — باقي العمل (جهاز، تتبع، إشعارات) في الخلفية
      // حتى لا تتجمّد شاشة الرمز أو المتصفح بالكامل على Chrome/Edge.
      await PostAuthNavigation.openRouteReplacingStack(
        context,
        route,
        arguments: nextArgs,
      );

      unawaited(_finishPostOtpBackgroundWork(
        uid: uid,
        sb: sb,
        username: _username.trim(),
        displayName: _greetingDisplayName(),
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// بعد الانتقال للوحة — لا يُعطّل واجهة رمز التحقق أو المتصفح.
  Future<void> _finishPostOtpBackgroundWork({
    required String uid,
    required SupabaseClient sb,
    required String username,
    required String displayName,
  }) async {
    try {
      await _safeAsync(
        () => NotificationService.clearOtpNotifications(),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}

    try {
      await ProfileComplianceService.tryUploadPendingSignupSignature(sb)
          .timeout(const Duration(seconds: 12));
    } catch (_) {}

    try {
      if (!kIsWeb) {
        final deviceSlot =
            await UserInstallSessionService.registerDeviceSlotAfterSignIn()
                .timeout(const Duration(seconds: 12));
        if (!deviceSlot.ok && deviceSlot.code == 'device_limit') {
          // PostAuthShell يعرض شاشة الأجهزة الإلزامية — لا تفتح مساراً ثانياً يومض.
          return;
        }
      }
    } catch (_) {}

    try {
      await FastLoginService.markFreshCredentialLogin();
      final sessionHints = await UserInstallSessionService.sessionHintsForBump()
          .timeout(const Duration(seconds: 8));
      await UserSessionCoordinationService.afterSignIn(
        uid,
        cityHint: sessionHints.city,
        deviceLabel: sessionHints.label,
        forceBump: true,
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}

    try {
      await SessionTrackingService.recordLoginStart(
        sb,
        loginMethod: 'otp',
      ).timeout(const Duration(seconds: 8));
      await FastLoginService.rememberSuccessfulAuth(
        loginMethod: 'otp',
        entryRoute: '/login',
      );
    } catch (_) {}

    try {
      await LoginSecurityDb.recordVerifiedLoginAfterOtp(sb)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}

    try {
      await FastLoginService.saveUserContext(
        uid: uid,
        usernameNationalId: username,
        displayName: displayName.isNotEmpty ? displayName : null,
      ).timeout(const Duration(seconds: 6));
      await FastLoginService.markTrustedInstall(uid: uid)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> _resendCode() async {
    if (!await _ensureInternetOrShow()) return;

    if (_secondsLeft > 0) {
      _toast(_isAr
          ? 'لا يمكن الإرسال قبل انتهاء العداد'
          : 'Resend is available after the timer ends');
      return;
    }

    _didResendOtp = true;

    setState(() {
      _attemptsLeft = _maxAttempts;
      _failCount = 0;
      _error = false;
      _otp = '';
      _otpController.clear();
      _userTypedSomething = false;

      _expectedCode = '';
      _expiresAt =
          DateTime.now().toUtc().add(const Duration(seconds: _maxSeconds));
      _secondsLeft = _maxSeconds;
    });

    _expectedFromArgs = false;

    await _persistTimerOnly();
    _startOrResumeTimer();

    await _requestOtpFromServer(force: true);
    await _waitForFirstOtpOrFetchFallback();

    _toast(_isAr ? 'تم إرسال إشعار برمز جديد' : 'A new in-app code was sent');
  }

  Future<void> _goToLogin(
      {required bool signOut, required bool clearOtp}) async {
    _timer?.cancel();
    _removeBanner();

    if (clearOtp) {
      await _clearPersistedTimerOnly();
    }

    if (signOut) {
      if (!mounted) return;
      final appSession = context.read<AppSession>();
      AuthSignedOutNavigationGuard.enter();
      try {
        final sb = Supabase.instance.client;
        final uid = sb.auth.currentUser?.id;
        if (uid != null && uid.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_otpVerifiedKey(uid));
        }
        if (!mounted) {
          AuthSignedOutNavigationGuard.scheduleLeave();
          return;
        }
        // يُعلَم وضع الضيف في التخزين قبل انتهاء الجلسة حتى لا يتعارض مستمع signedOut مع التوجيه.
        try {
          await appSession.setGuest();
        } catch (_) {}

        try {
          await AuthLocalSignOut.signOutLocal(sb);
        } catch (_) {}
      } catch (_) {}

      unawaited(syncSessionAppearanceNotifiers?.call() ?? Future.value());
    }

    if (!mounted) {
      if (signOut) AuthSignedOutNavigationGuard.scheduleLeave();
      return;
    }

    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      '/login',
      (r) => false,
    );
    if (signOut) {
      AuthSignedOutNavigationGuard.scheduleLeave();
    }
  }

  Future<void> _resolveProfileUsername() async {
    final raw = digitsOnly(normalizeAsciiDigits(_username.trim()));
    if (raw.isEmpty) {
      _profileUsername = '';
      return;
    }
    try {
      _profileUsername = await AuthService.securityUsernameForDeviceFlow(raw);
    } catch (_) {
      _profileUsername = raw;
    }
    if (_profileUsername.trim().isEmpty) _profileUsername = raw;
  }

  Future<void> _startSmsUserConsentListen() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await SmsAutoFill().listenForCode(smsCodeRegexPattern: r'\d{4}');
      await _smsCodeSub?.cancel();
      _smsCodeSub = SmsAutoFill().code.listen((code) {
        final only = code.replaceAll(RegExp(r'\D'), '');
        if (only.length >= _otpLen && mounted) {
          _applyIncomingCode(only, fromUserAction: false);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadProfileFromDbIfNeeded() async {
    Map<String, dynamic>? row;
    const selectCols = LoginSecurityDb.usersProfilesSelectForVerifyGreeting;

    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) {
        await _applyAuthUserFallback();
        return;
      }

      final raw = await sb
          .from('users_profiles')
          .select(selectCols)
          .eq('user_id', uid)
          .maybeSingle();

      if (raw != null) {
        row = Map<String, dynamic>.from(raw);
        if (mounted) setState(() => _restApiFailureHint = null);
      } else {
        for (final key in _otpUsernameCandidates()) {
          if (key.isEmpty) continue;
          try {
            final r = await sb
                .from('users_profiles')
                .select(selectCols)
                .eq('username', key)
                .maybeSingle();
            if (r != null) {
              row = Map<String, dynamic>.from(r);
              break;
            }
          } on PostgrestException catch (e) {
            _noteVerifySupabaseFailure(e, where: 'users_profiles by username');
          } catch (_) {}
        }
      }
    } on PostgrestException catch (e) {
      row = null;
      _noteVerifySupabaseFailure(e, where: 'users_profiles by user_id');
    } catch (_) {
      row = null;
    }

    if (!mounted) return;

    if (row != null) {
      final dbUsername = (row['username'] ?? '').toString().trim();
      // دائماً مزامنة مفتاح الإشعارات/التحقق مع عمود users_profiles.username (ما يطبقه RLS).
      if (dbUsername.isNotEmpty) {
        _profileUsername = dbUsername;
      }

      final display = ProfileGreetingFromRow.displayName(row, isAr: _isAr);
      final last = ProfileGreetingFromRow.lastLoginAt(row);
      final av = (row['avatar_url'] ?? '').toString().trim();

      setState(() {
        if (display != null && display.trim().isNotEmpty) {
          _displayName = display.trim();
          _fullName = _displayName;
        }
        if (last != null) {
          _lastLogin = _latestOf(_lastLogin, last);
        }
        if (av.isNotEmpty) _avatarUrl = av;
      });
      if (display != null && display.trim().isNotEmpty) {
        unawaited(_persistRememberDisplayNameIfNeeded(display.trim()));
      }
    }

    await _applyAuthUserFallback();
  }

  Future<void> _persistRememberDisplayNameIfNeeded(String displayName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool('rememberMe') ?? false;
      if (!remember) return;
      final normalized = CompoundDisplayName.normalize(displayName);
      if (normalized.isEmpty) return;
      await prefs.setString('rememberDisplayName', normalized);
    } catch (_) {}
  }

  /// عند عدم وجود users_profiles أو فشل RLS: الاسم من جلسة Auth فقط.
  /// لا نستخدم [User.lastSignInAt] لسطر «آخر دخول» لأنه يعكس جلسة كلمة المرور الحالية قبل إكمال OTP.
  Future<void> _applyAuthUserFallback() async {
    final u = Supabase.instance.client.auth.currentUser;
    if (u == null || !mounted) return;

    final metaName =
        ProfileGreetingFromRow.displayNameFromAuthMetadata(u.userMetadata);

    setState(() {
      if (metaName != null && metaName.isNotEmpty) {
        final badDisplay = _displayName.isEmpty ||
            _looksLikeNumericLoginIdentifier(_displayName);
        final badFull =
            _fullName.isEmpty || _looksLikeNumericLoginIdentifier(_fullName);
        if (badDisplay) _displayName = metaName;
        if (badFull) _fullName = metaName;
      }
    });
  }

  Widget _infoRow({
    required IconData icon,
    required String text,
    required Color color,
    required double fontSize,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: (fontSize + 4).clamp(14.0, 18.0), color: color),
          const SizedBox(width: 8),
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: fontSize,
              height: 1.2,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pasteOtpFromClipboard({bool silent = false}) async {
    final sent = InAppOtpHandoff.digitsFromAny(_expectedCode);
    if (sent != null && sent.length >= _otpLen) {
      if (silent) {
        _applyIncomingCode(sent, fromUserAction: true);
      } else {
        _fillOtpFromSuggestion(sent);
      }
      return;
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = digitsOnly(normalizeAsciiDigits(data?.text ?? ''));
      if (raw.isEmpty) {
        if (!silent) {
          _toast(_isAr ? 'لا يوجد رمز بعد' : 'No code yet');
        }
        return;
      }
      AppHaptics.selection();
      _applyIncomingCode(raw, fromUserAction: true);
      if (!silent) {
        _toast(_isAr ? 'تم لصق الرمز' : 'Code pasted');
      }
    } catch (_) {
      if (!silent) {
        _toast(_isAr ? 'تعذر اللصق' : 'Paste failed');
      }
    }
  }

  Widget _otpBoxes({required bool isDark, required double fontSize}) {
    return LayoutBuilder(
      builder: (context, c) {
        final cs = Theme.of(context).colorScheme;
        final maxW = c.maxWidth;
        final metrics = OtpPinLayout.of(maxW);
        final fieldW = metrics.fieldWidth;
        final fieldH = metrics.fieldHeight;

        final inactiveBorder = isDark
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.10);
        final primary = cs.primary;
        final activeBorder = primary.withValues(alpha: 0.65);
        final selectedBorder = primary;
        final errorBorder = cs.error;

        final useInactive = _error ? errorBorder : inactiveBorder;
        final useActive = _error ? errorBorder : activeBorder;
        final useSelected = _error ? errorBorder : selectedBorder;

        final fill = isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04);

        return AutofillGroup(
          child: PinCodeTextField(
            appContext: context,
            length: _otpLen,
            controller: _otpController,
            focusNode: _otpFocus,
            autoDisposeControllers: false,
            autoFocus: true,
            autoUnfocus: false,
            enablePinAutofill: true,
            useExternalAutoFillGroup: true,
            keyboardType: TextInputType.number,
            enableActiveFill: true,
            animationType: AnimationType.fade,
            animationDuration: const Duration(milliseconds: 120),
            errorTextSpace: 0,
            scrollPadding: aqarFieldScrollPadding(context),
            onTap: () => OtpAutofill.stampFocusedHtmlField(),
            inputFormatters: [
              TextInputFormatter.withFunction((oldValue, newValue) {
                final normalized =
                    digitsOnly(normalizeAsciiDigits(newValue.text));
                final clipped = normalized.length > _otpLen
                    ? normalized.substring(0, _otpLen)
                    : normalized;
                return TextEditingValue(
                  text: clipped,
                  selection: TextSelection.collapsed(offset: clipped.length),
                );
              }),
              LengthLimitingTextInputFormatter(_otpLen),
            ],
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            pinTheme: PinTheme(
              shape: PinCodeFieldShape.box,
              borderRadius: BorderRadius.circular(12),
              fieldHeight: fieldH,
              fieldWidth: fieldW,
              fieldOuterPadding: EdgeInsets.zero,
              inactiveColor: useInactive,
              activeColor: useActive,
              selectedColor: useSelected,
              inactiveFillColor: fill,
              selectedFillColor: fill,
              activeFillColor: fill,
              borderWidth: 1.4,
            ),
            textStyle: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: metrics.fontSize,
            ),
            onChanged: (v) {
              final only = digitsOnly(normalizeAsciiDigits(v));
              _otp = only.length > _otpLen ? only.substring(0, _otpLen) : only;
              if (_otp.isNotEmpty) _userTypedSomething = true;
              if (_error) {
                setState(() => _error = false);
              }
              _maybeAutoSubmit();
            },
            onCompleted: (_) {
              AppHaptics.selection();
              _maybeAutoSubmit();
            },
            beforeTextPaste: (text) {
              final sent = InAppOtpHandoff.digitsFromAny(_expectedCode);
              final only = digitsOnly(normalizeAsciiDigits(text ?? ''));
              final use =
                  (sent != null && sent.length >= _otpLen) ? sent : only;
              if (use.isEmpty) return true;
              _fillOtpFromSuggestion(use);
              return false;
            },
          ),
        );
      },
    );
  }

  Widget _offlineOverlay({required bool isDark, required Color primary}) {
    final bg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF5F7FA);
    final card = isDark ? const Color(0xFF121A2A) : Colors.white;
    final title = isDark ? Colors.white : const Color(0xFF0B1220);
    final sub = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);

    return Positioned.fill(
      child: Container(
        color: bg.withValues(alpha: 0.96),
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: card,
            elevation: 14,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 52),
                  const SizedBox(height: 10),
                  Text(
                    _isAr
                        ? 'لا يوجد اتصال بالإنترنت'
                        : 'No internet connection',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: title,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAr
                        ? 'لن يتم تأكيد الرمز بدون إنترنت. فعّل الإنترنت ثم أعد المحاولة.'
                        : 'OTP confirmation requires internet. Enable internet then retry.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: sub,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _retryingNet ? null : _retryInternet,
                      icon: _retryingNet
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(_isAr ? 'إعادة المحاولة' : 'Retry'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => _goToLogin(signOut: true, clearOtp: true),
                    child:
                        Text(_isAr ? 'العودة لتسجيل الدخول' : 'Back to login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _singleLineGreeting({
    required String greeting,
    required String name,
    required Color color,
    required double fontSize,
  }) {
    final hasName = name.trim().isNotEmpty;
    final brand = DashboardGreeting.partnerBrand(isAr: _isAr);
    final top = '$greeting $brand';
    if (!hasName) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          top,
          maxLines: 1,
          textAlign: TextAlign.center,
          softWrap: false,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: color,
            height: 1.15,
            fontFamily: 'Cairo',
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            top,
            maxLines: 1,
            textAlign: TextAlign.center,
            softWrap: false,
            style: TextStyle(
              fontSize: fontSize * 0.92,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.15,
              fontFamily: 'Cairo',
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name.trim(),
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: color,
            height: 1.2,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

  Widget _otpKeyboardDock() {
    if (_bannerEntry != null) return const SizedBox.shrink();
    if (!AppSurfaceScope.of(context).showOtpKeyboardPasteChip) {
      return const SizedBox.shrink();
    }
    final kb = _overlayKeyboardInset(context);
    final code = InAppOtpHandoff.digitsFromAny(_expectedCode);
    if (code == null || code.length < _otpLen) return const SizedBox.shrink();
    if (_otpDigitsFromUi().replaceAll(RegExp(r'\D'), '').length >= _otpLen) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      left: 12,
      right: 12,
      bottom: kb > 8 ? kb + 6 : 12,
      child: Center(
        child: _bankOtpKeyboardChip(code, isDark: isDark),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF5F7FA);
    final card = isDark ? const Color(0xFF121A2A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF041018);
    final subColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF16324A);

    final nameSize = _font(context, 18.0, 15.5);
    final bodySize = _font(context, 13.5, 12.2);

    final displayName = _greetingDisplayName();

    final showResend = _secondsLeft <= 0;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: FutureBuilder<void>(
        future: _bootFuture,
        builder: (context, _) {
          // لا تحجب حقول الرمز — أظهر الواجهة فوراً؛ الإرسال يعمل في الخلفية.
          return PopScope(
            canPop: false,
            // Do not sign out on incidental pop (Chrome password overlay / focus loss).
            // Explicit back buttons still call _goToLogin.
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              unawaited(_goToLogin(signOut: true, clearOtp: true));
            },
            child: ScrollConfiguration(
              behavior: const AqarAuthScrollBehavior(),
              child: AppKeyboardStableScope(
                child: Scaffold(
                  backgroundColor: bg,
                  resizeToAvoidBottomInset: false,
                  body: SafeArea(
                    child: Stack(
                      children: [
                        // بدون شريط تحميل يحجب الواجهة — الرمز يظهر فور الجاهزية.
                        LayoutBuilder(
                          builder: (context, c) {
                            final w = c.maxWidth;
                            // جوالات / شاشات ضيقة: عرض شبه كامل بدون دائرة هوية.
                            final isSmall = w < 520;
                            final isTiny = w < 360;
                            final phoneLike = w < 720;
                            final cardMax = phoneLike
                                ? (w - (isTiny ? 8.0 : 12.0) * 2)
                                    .clamp(280.0, w)
                                : 560.0;

                            final kb = AppKeyboardInset.bottomOf(context);
                            final visH = math.max(
                              180.0,
                              c.maxHeight - (kb > 8 ? kb : 0),
                            );
                            final bottomPad = 16.0 + (kb > 8 ? 56.0 : 0);

                            return SizedBox(
                              height: visH,
                              child: Align(
                              alignment: Alignment.topCenter,
                              child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  phoneLike ? (isTiny ? 6 : 10) : 16,
                                  phoneLike ? 8 : 16,
                                  phoneLike ? (isTiny ? 6 : 10) : 16,
                                  bottomPad,
                                ),
                                child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(maxWidth: cardMax),
                                  child: Card(
                                    color: card,
                                    elevation: phoneLike ? 4 : 10,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        phoneLike ? 16 : 24,
                                      ),
                                    ),
                                    child: Padding(
                                      padding:
                                          EdgeInsets.all(isSmall ? 14 : 22),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          AppPageCloseButton.startCorner(
                                            onPressed: () => _goToLogin(
                                              signOut: true,
                                              clearOtp: true,
                                            ),
                                          ),
                                          Container(
                                            width: double.infinity,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isTiny ? 10 : 12,
                                              vertical: isTiny ? 8 : 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? Colors.white
                                                      .withValues(alpha: 0.04)
                                                  : Colors.black
                                                      .withValues(alpha: 0.03),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: isDark
                                                    ? Colors.white
                                                        .withValues(alpha: 0.14)
                                                    : Colors.black.withValues(
                                                        alpha: 0.10),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                _singleLineGreeting(
                                                  greeting: _greeting(),
                                                  name: displayName,
                                                  color: titleColor,
                                                  fontSize: nameSize,
                                                ),
                                                const SizedBox(height: 8),
                                                _infoRow(
                                                  icon: Icons
                                                      .calendar_today_rounded,
                                                  text: _todayLine(),
                                                  color: subColor,
                                                  fontSize: bodySize,
                                                ),
                                                const SizedBox(height: 6),
                                                _infoRow(
                                                  icon: Icons.login_rounded,
                                                  text: (_isAr
                                                          ? 'آخر تسجيل دخول: '
                                                          : 'Last login: ') +
                                                      _lastLoginLine(),
                                                  color: subColor,
                                                  fontSize: bodySize,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          if (_restApiFailureHint != null) ...[
                                            const SizedBox(height: 12),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .errorContainer
                                                    .withValues(alpha: 0.85),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error
                                                      .withValues(alpha: 0.4),
                                                ),
                                              ),
                                              child: SelectableText(
                                                _restApiFailureHint!,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onErrorContainer,
                                                  fontSize: bodySize,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 14),

                                          // عدّاد إعادة الإرسال فوق الحقول — يلتف على الشاشات الضيقة ولا يختنق مع الأزرار.
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.timer_outlined,
                                                      size: 18,
                                                      color: subColor),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    showResend
                                                        ? (_isAr
                                                            ? 'انتهى الوقت'
                                                            : 'Time expired')
                                                        : (_isAr
                                                            ? 'المتبقي: $_secondsLeft ث'
                                                            : 'Remaining: $_secondsLeft s'),
                                                    style: TextStyle(
                                                      color: subColor,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: bodySize,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              TextButton.icon(
                                                onPressed:
                                                    showResend && !_offline
                                                        ? _resendCode
                                                        : null,
                                                icon: const Icon(Icons.refresh),
                                                label: Text(
                                                  _isAr
                                                      ? 'إعادة إرسال'
                                                      : 'Resend',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: bodySize,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(height: 10),
                                          FieldGroupFrame(
                                            title: t.verifySubtitle,
                                            titleTextAlign: TextAlign.center,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                              horizontal: 12,
                                            ),
                                            child: Column(
                                              children: [
                                                Directionality(
                                                  textDirection:
                                                      TextDirection.ltr,
                                                  child: _otpBoxes(
                                                    isDark: isDark,
                                                    fontSize: bodySize,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Align(
                                                  alignment: Alignment.center,
                                                  child: TextButton.icon(
                                                    onPressed: _offline
                                                        ? null
                                                        : () => unawaited(
                                                              _pasteOtpFromClipboard(),
                                                            ),
                                                    icon: const Icon(
                                                      Icons
                                                          .content_paste_rounded,
                                                      size: 18,
                                                    ),
                                                    label: Text(
                                                      _isAr
                                                          ? 'لصق الرمز'
                                                          : 'Paste code',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: bodySize,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            t.otpAttemptsRemaining(
                                                _attemptsLeft),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: bodySize,
                                              color: _error
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .error
                                                  : subColor,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          if (_error) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              t.invalidCode,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                                fontWeight: FontWeight.w900,
                                                fontSize: bodySize,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                          const SizedBox(height: 16),
                                          SizedBox(
                                            width: double.infinity,
                                            height: 50,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              onPressed:
                                                  (_submitting || _offline)
                                                      ? null
                                                      : _submit,
                                              child: _submitting
                                                  ? const SizedBox(
                                                      width: 22,
                                                      height: 22,
                                                      child: AppLogoLoading(
                                                        compact: true,
                                                        size: 20,
                                                      ),
                                                    )
                                                  : Text(
                                                      t.confirm,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: _font(
                                                            context, 16, 15),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          TextButton(
                                            onPressed: _clear,
                                            child:
                                                Text(_isAr ? 'مسح' : 'Clear'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              ),
                            );
                          },
                        ),
                        if (_privacyMask)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: Text(
                                _isAr ? 'محتوى محمي' : 'Protected content',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        if (_offline)
                          _offlineOverlay(
                            isDark: isDark,
                            primary: Theme.of(context).colorScheme.primary,
                          ),
                        _otpKeyboardDock(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
