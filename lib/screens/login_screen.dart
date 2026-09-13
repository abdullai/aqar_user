// ignore_for_file: unused_element, unused_field

// lib/screens/login_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:aqar_user/l10n/app_localizations.dart';
import 'package:aqar_user/main.dart';
import 'package:aqar_user/models.dart';
import 'package:aqar_user/services/ads_service.dart';
import 'package:aqar_user/services/auth_service.dart';
import 'package:aqar_user/theme.dart';
import '../core/auth/login_success_banner.dart';
import '../core/auth/inactivity_auth_landing.dart';
import '../core/auth/in_app_otp_handoff.dart';
import 'package:aqar_user/widgets/app_busy_indicator.dart';
import 'package:aqar_user/widgets/app_logo_loading.dart';
import 'package:aqar_user/widgets/inline_property_video.dart';
import 'package:aqar_user/widgets/field_group_frame.dart';
import 'package:aqar_user/widgets/app_about_credits.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/aqar_brand_colors.dart';
import '../core/config/app_config.dart';
import '../core/input/password_arabic_script_guard.dart';
import '../core/input/password_field_input_guard.dart';
import '../core/input/smart_keyboard_formatter.dart';
import '../core/gestures/app_keyboard_stable.dart';
import '../core/session/app_session.dart';
import '../core/session/user_appearance_session.dart';
import '../core/session/web_session_ttl.dart';
import '../core/theme/app_appearance_bridge.dart';
import '../core/session/return_after_auth.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/compound_display_name.dart';
import '../services/connectivity_guard.dart';
import '../services/session_manager.dart';
import '../services/fast_login_service.dart';
import '../services/profile_compliance_service.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../core/haptics/app_haptics.dart';
import '../widgets/nafath_login_sheet.dart';
import '../widgets/auth_top_chrome.dart';
import '../widgets/login_known_user_hero.dart';
import '../widgets/caps_aware_password_field.dart';
import '../core/auth/auth_challenge_service.dart';
import '../core/auth/auth_completion_policy.dart';
import '../core/auth/login_method_policy.dart';
import '../core/platform/app_surface.dart';
import '../core/auth/auth_local_sign_out.dart';
import '../shared/core/app_flags.dart';
import 'verify_screen.dart';

/// تمرير داخل بطاقة الدخول — بدون شريط (حتى على الويب/سطح المكتب).
class _LoginScrollBehavior extends AqarAuthScrollBehavior {
  const _LoginScrollBehavior();
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin, RouteAware {
  static const Color _bankColor = Color(0xFF0F766E);

  // ✅ سياسة محاولات الدخول (محليًا)
  static const int _maxAttemptsBeforeLock = 3;
  static const Duration _lockDuration = Duration(minutes: 5);

  // ✅ مفتاح OTP verified
  String _otpVerifiedKey(String uid) => 'otp_verified_$uid';

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final ScrollController _loginScrollCtrl = ScrollController();
  final GlobalKey _usernameFieldKey = GlobalKey();
  final GlobalKey _passwordFieldKey = GlobalKey();

  bool rememberMe = false;
  bool fastLogin = false;

  /// يظهر زر «الدخول السريع / البصمة» فقط عند وجود قفل فعلي (PIN أو بصمة مفعّلة).
  bool _showQuickLoginEntry = false;
  LoginMethodSnapshot _methodSnapshot = LoginMethodSnapshot(
    host: LoginMethodPolicy.detectHost(),
    trustedThisInstall: false,
    firstPasswordDone: false,
    hasSession: false,
    hasKnownUser: false,
    pinEnabled: false,
    faceEnabled: false,
    fingerprintEnabled: false,
    preferPassword: true,
    unlockMode: FastUnlockMode.password,
  );

  bool _routeAwareSubscribed = false;

  bool obscurePassword = true;
  bool isBusy = false;
  bool _nafathBusy = false;

  /// مشغول موحّد: عند الضغط على تسجيل الدخول أو نفاذ تُعطَّل كل
  /// الخيارات الأخرى (نسيت كلمة المرور، الدخول السريع، إنشاء حساب،
  /// الدخول كضيف) لتفادي التضارب.
  bool get _busy => isBusy || _nafathBusy;

  // CAPTCHA
  bool showCaptcha = false;
  String captchaText = '';
  String userCaptchaInput = '';

  // Ads
  List<AdItem> _ads = [];

  // Remember-me masking
  String? _storedUsername;

  /// اسم الظهور الرباعي/المركّب عند تفعيل «تذكرني» — يظهر بدل حقل الرقم.
  String? _rememberDisplayName;
  bool _showRememberedIdentityChip = false;
  bool _maskedPrefillActive = false;
  bool _usernameEdited = false;

  /// حقل مخفي ثابت لمدير كلمات المرور عند عرض بطاقة الاسم (لا يُنشأ في كل بناء).
  late final TextEditingController _autofillUsernameMirror =
      TextEditingController();

  // brute-force محلي
  Map<String, int> _failedAttempts = {};
  Map<String, DateTime> _lockoutUntil = {};

  // DB checks
  Timer? _userCheckDebounce;
  bool _checkingUsername = false;
  bool _usernameExists = false;
  bool _usernameCheckDone = false;
  String? _lastUsernameRpcChecked;
  bool? _lastUsernameRpcExists;

  // اهتزاز خفيف عند خطأ حقول الدخول
  late final AnimationController _shakeCtrl;
  late final Animation<Offset> _shakeAnim;
  late final AnimationController _enterCtrl;
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;

  String? _usernameError;
  String? _passwordError;
  bool _didAutoAdvanceToPassword = false;
  Timer? _passwordBleedGuardTimer;

  /// يمنع تسرّب الرقم الحادي عشر إلى كلمة المرور بعد الانتقال التلقائي.
  bool _passwordBleedGuardActive = false;

  DateTime? _lastPasswordArabicDialogAt;

  String _packageVersionLine = '';

  bool get _isAr => langNotifier.value != 'en';

  ThemeMode get _currentTheme => themeModeNotifier.value;
  bool get _isLight => UserAppearanceSession.resolvesLight(_currentTheme);

  Color get _pageBg =>
      _isLight ? const Color(0xFFF5F7FA) : AqarBrandColors.nightSurface;
  Color get _textPrimary => _isLight ? const Color(0xFF0B1220) : Colors.white;
  Color get _textSecondary =>
      _isLight ? const Color(0xFF5B6475) : const Color(0xFFB8C0D4);

  Color get _fieldFill => _isLight ? Colors.white : const Color(0xFF0F1425);

  /// مكحّل: أسود في النهاري، أبيض في الليلي (حدود الحقول الموحّدة).
  Color get _fieldOutline => _isLight ? const Color(0xFF0A0A0A) : Colors.white;

  Color get _hintColor =>
      _isLight ? const Color(0xFF64748B) : const Color(0xFFCBD5E1);
  Color get _iconColor =>
      _isLight ? const Color(0xFF64748B) : const Color(0xFFCBD5E1);

  Color get _errorColor => const Color(0xFFDC2626);
  Color get _successColor => const Color(0xFF059669);

  bool _isSmallUi(BuildContext context) =>
      MediaQuery.of(context).size.width < 380;

  double _font(BuildContext context, double desktop, double mobile) =>
      _isSmallUi(context) ? mobile : desktop;

  void _armPasswordBleedGuard() {
    _passwordBleedGuardActive = true;
    _passwordBleedGuardTimer?.cancel();
    _passwordBleedGuardTimer = Timer(const Duration(milliseconds: 480), () {
      if (!mounted) return;
      _passwordBleedGuardActive = false;
    });
  }

  /// انتقال صارم بعد اكتمال 10 أرقام — بدون تسرّب الرقم التالي لكلمة المرور.
  void _advanceToPasswordAfterUsernameComplete() {
    if (_didAutoAdvanceToPassword) return;
    if (_sanitizeUsernameInput(_usernameController.text).length != 10) return;

    // تعبئة محفوظة/أولية بدون كتابة نشطة: لا تسرق التركيز.
    if (!_usernameFocus.hasFocus) {
      _didAutoAdvanceToPassword = true;
      return;
    }

    _didAutoAdvanceToPassword = true;
    _armPasswordBleedGuard();

    // أغلق محرر اسم المستخدم أولاً لتصفية أحداث IME المعلقة.
    _usernameFocus.unfocus();
    Future<void>.delayed(const Duration(milliseconds: 70), () {
      if (!mounted) return;
      if (_sanitizeUsernameInput(_usernameController.text).length != 10) {
        _didAutoAdvanceToPassword = false;
        _passwordBleedGuardActive = false;
        return;
      }
      // إن وصلت أرقام يتيمة لكلمة المرور أثناء الانتقال — امسحها.
      final leaked = _passwordController.text;
      if (leaked.isNotEmpty && RegExp(r'^\d{1,4}$').hasMatch(leaked)) {
        _passwordController.clear();
      }
      _passwordFocus.requestFocus();
    });
  }

  Future<void> _shakeCredentialsGroup() async {
    if (!mounted) return;
    AppHaptics.light();
    try {
      await _shakeCtrl.forward(from: 0);
    } catch (_) {}
    if (mounted) _shakeCtrl.reset();
  }

  void _showLoginError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFFB91C1C),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _applyInitialFocus() {
    if (_knownUserReady) {
      _passwordFocus.requestFocus();
    } else {
      _usernameFocus.requestFocus();
    }
  }

  void _schedulePasswordArabicDialog() {
    final n = DateTime.now();
    if (_lastPasswordArabicDialogAt != null &&
        n.difference(_lastPasswordArabicDialogAt!) <
            const Duration(milliseconds: 900)) {
      return;
    }
    _lastPasswordArabicDialogAt = n;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showPasswordArabicNotAllowedDialog(context, isAr: _isAr);
    });
  }

  InputDecoration _loginFieldDecoration({
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    int hintMaxLines = 1,
    double? hintFontSize,
    BoxConstraints? prefixIconConstraints,
    BoxConstraints? suffixIconConstraints,
  }) {
    final radius = BorderRadius.circular(12);
    final side = BorderSide(color: _fieldOutline, width: 1.6);
    final sideFocus = BorderSide(color: _fieldOutline, width: 2.2);
    final hasHint = (hintText ?? '').trim().isNotEmpty;
    final hasLabel = (labelText ?? '').trim().isNotEmpty;
    return InputDecoration(
      labelText: hasLabel ? labelText : null,
      floatingLabelBehavior:
          hasLabel ? FloatingLabelBehavior.auto : FloatingLabelBehavior.never,
      floatingLabelAlignment: FloatingLabelAlignment.start,
      alignLabelWithHint: false,
      labelStyle: TextStyle(
        color: _textSecondary,
        fontWeight: FontWeight.w800,
        fontSize: _font(context, 13.5, 12.5),
      ),
      floatingLabelStyle: TextStyle(
        color: _bankColor,
        fontWeight: FontWeight.w900,
        fontSize: _font(context, 12.5, 11.5),
      ),
      hintText: hasHint ? hintText : null,
      hintMaxLines: hasHint ? hintMaxLines : null,
      hintStyle: hasHint
          ? TextStyle(
              color: _hintColor,
              fontWeight: FontWeight.w800,
              fontSize: hintFontSize ?? _font(context, 14, 11.5),
              height: 1.25,
            )
          : null,
      counterText: '',
      contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 16, 14, 16),
      prefixIcon: prefixIcon,
      prefixIconConstraints: prefixIconConstraints ??
          const BoxConstraints(minWidth: 46, minHeight: 46),
      suffixIcon: suffixIcon,
      suffixIconConstraints: suffixIconConstraints ??
          const BoxConstraints(minWidth: 46, minHeight: 46),
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: side,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: sideFocus,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: side.copyWith(color: _errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: _errorColor, width: 2.2),
      ),
      fillColor: _fieldFill,
      filled: true,
    );
  }

  // =======================
  // ✅ Internet guard helper
  // =======================
  Future<bool> _ensureInternetOrAlert() async {
    final ok = await ConnectivityGuard.hasInternet();
    return ok;
  }

  Future<void> _loadPackageVersionLineForLogin() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _packageVersionLine = '${p.version} (${p.buildNumber})';
      });
    } catch (_) {}
  }

  // =======================
  // ✅ انتظار الجلسة بعد login
  // =======================
  Future<Session?> _waitForSession({int tries = 20}) async {
    final sb = Supabase.instance.client;
    for (int i = 0; i < tries; i++) {
      final s = sb.auth.currentSession;
      if (s != null) return s;
      if (i == 2 || i == 8) {
        try {
          final res = await sb.auth
              .refreshSession()
              .timeout(const Duration(seconds: 6));
          if (res.session != null) return res.session;
        } catch (_) {}
      }
      await Future.delayed(const Duration(milliseconds: 55));
    }
    return sb.auth.currentSession;
  }

  @override
  void initState() {
    super.initState();

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeAnim = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: Offset.zero, end: const Offset(-9, 0)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(-9, 0), end: const Offset(9, 0)),
        weight: 1.2,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(9, 0), end: const Offset(-6, 0)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(-6, 0), end: Offset.zero),
        weight: 1,
      ),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOutCubic));

    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _enterFade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _enterSlide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    if (InactivityAuthLanding.suppressEnterMotion) {
      _enterCtrl.value = 1;
    } else {
      _enterCtrl.forward();
    }

    _generateCaptcha();
    if (!InactivityAuthLanding.suppressEnterMotion) {
      unawaited(_loadAds());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(SessionManager.scrubStaleOtpFlagsWithoutSession());
      unawaited(_loadPackageVersionLineForLogin());
      if (!mounted) return;
      await _ensureInternetOrAlert();
      if (!mounted) return;
      await _loadPreferences();
      if (!mounted) return;
      _applyInitialFocus();
    });

    _usernameController.addListener(() {
      if (_maskedPrefillActive && !_usernameEdited) return;

      final original = _usernameController.text;
      final sanitized = _sanitizeUsernameInput(original);

      if (original != sanitized) {
        _usernameController.value = TextEditingValue(
          text: sanitized,
          selection: TextSelection.collapsed(offset: sanitized.length),
        );
        return;
      }

      // بعد 10 أرقام: انتقال صارم مع حارس ضد تسرّب الرقم إلى كلمة المرور.
      if (sanitized.length == 10) {
        _advanceToPasswordAfterUsernameComplete();
      } else {
        _didAutoAdvanceToPassword = false;
      }

      _checkUsernameExistsDebounced();
      // لا setState هنا على كل حرف: على Flutter Web يعيد بناء الحقول ويقطع التركيز/الكيبورد.
      // تحديث أيقونة التحقق يأتي من مسار _checkUsernameExistsDebounced و RPC.
      if ((_usernameError ?? '').isNotEmpty) {
        setState(() => _usernameError = null);
      }
    });

    _passwordController.addListener(() {
      if ((_passwordError ?? '').isNotEmpty) {
        setState(() => _passwordError = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeAwareSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeAwareSubscribed = true;
    }
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    unawaited(_loadPreferences());
  }

  @override
  void dispose() {
    if (_routeAwareSubscribed) {
      appRouteObserver.unsubscribe(this);
      _routeAwareSubscribed = false;
    }
    _userCheckDebounce?.cancel();
    _passwordBleedGuardTimer?.cancel();
    _shakeCtrl.dispose();
    _enterCtrl.dispose();
    _loginScrollCtrl.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _autofillUsernameMirror.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // =======================
  // ✅ Username normalize helpers
  // =======================
  String _normalizeDigitsToEnglish(String input) {
    if (input.isEmpty) return input;

    const map = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
    };

    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      buffer.write(map[ch] ?? ch);
    }
    return buffer.toString();
  }

  String _sanitizeUsernameInput(String input) {
    final english = _normalizeDigitsToEnglish(input);
    final digitsOnly = english.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length <= 10) return digitsOnly;
    return digitsOnly.substring(0, 10);
  }

  String _normalizeNumbers(String input) {
    final authNormalized = AuthService.normalizeNumbers(input);
    return _sanitizeUsernameInput(authNormalized);
  }

  // =======================
  // Session hygiene helpers
  // =======================
  Future<void> _ensureNotGuestMode() async {
    try {
      if (mounted) {
        await context.read<AppSession>().prepareForUserLogin();
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(AppConfig.prefGuestModeKey, false);
        await prefs.setString(AppConfig.prefEntryModeKey, 'user');
        await prefs.remove(AppConfig.prefGuestLegacyIsGuestKey);
        await prefs.remove(AppConfig.prefGuestLegacyGuestKey);
      }
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(AppConfig.prefGuestModeKey, false);
        await prefs.setString(AppConfig.prefEntryModeKey, 'user');
      } catch (_) {}
    }
  }

  Future<void> _setGuestModePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConfig.prefGuestModeKey, true);
      await prefs.setString(AppConfig.prefEntryModeKey, 'guest');
      await prefs.setBool(AppConfig.prefGuestLegacyIsGuestKey, true);
      await prefs.setBool(AppConfig.prefGuestLegacyGuestKey, true);
    } catch (_) {}
  }

  Future<void> _clearOtpVerifiedForCurrentSession() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_otpVerifiedKey(uid));
    } catch (_) {}
  }

  // =======================
  // Existing helpers
  // =======================
  void _resetDbFlags() {
    _checkingUsername = false;
    _usernameExists = false;
    _usernameCheckDone = false;
    _lastUsernameRpcChecked = null;
    _lastUsernameRpcExists = null;
  }

  bool _looksLikeUsername10Digits(String s) => RegExp(r'^\d{10}$').hasMatch(s);

  Future<bool> _usernameExistsRpc(String username) async {
    final email = await AuthService.getEmailByUsername(username);
    return email != null && email.trim().isNotEmpty;
  }

  Future<void> _checkUsernameExistsDebounced() async {
    _userCheckDebounce?.cancel();

    final u = (_getRealUsername() ?? '').trim();
    if (!_looksLikeUsername10Digits(u)) {
      if (!mounted) return;
      setState(() {
        _checkingUsername = false;
        _usernameExists = false;
        _usernameCheckDone = false;
      });
      return;
    }

    _userCheckDebounce = Timer(const Duration(milliseconds: 550), () async {
      if (!mounted) return;
      if (_lastUsernameRpcChecked == u && _lastUsernameRpcExists != null) {
        setState(() {
          _usernameExists = _lastUsernameRpcExists!;
          _checkingUsername = false;
          _usernameCheckDone = true;
        });
        return;
      }

      setState(() => _checkingUsername = true);

      final exists = await _usernameExistsRpc(u);
      _lastUsernameRpcChecked = u;
      _lastUsernameRpcExists = exists;

      if (!mounted) return;
      setState(() {
        _usernameExists = exists;
        _checkingUsername = false;
        _usernameCheckDone = true;
      });
    });
  }

  Future<void> _loadAds() async {
    final loaded = await AdsService.loadAds();
    if (!mounted) return;
    setState(() {
      _ads = loaded.where((a) => a.enabled).toList();
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    rememberMe = prefs.getBool('rememberMe') ?? false;
    fastLogin = prefs.getBool('fastLogin') ?? false;
    if (kIsWeb) fastLogin = false;

    String? resumeName;
    String? resumeUser;
    try {
      final resume = await FastLoginService.getResumeAccount();
      resumeName = (resume.displayName ?? '').trim();
      resumeUser = FastLoginService.normalizeDigits(
        (resume.username ?? '').trim(),
      );
      if (resumeUser.length < 10) resumeUser = null;
      if (resumeName.isEmpty) resumeName = null;
    } catch (_) {}

    await UserAppearanceSession.applyNotifiersToMatchStoredSession(
      langNotifier: langNotifier,
      themeModeNotifier: themeModeNotifier,
    );

    final attemptsJson = prefs.getString('failedAttempts') ?? '{}';
    final lockoutJson = prefs.getString('lockoutUntil') ?? '{}';
    try {
      _failedAttempts = Map<String, int>.from(json.decode(attemptsJson));
      final lockoutMap = Map<String, dynamic>.from(json.decode(lockoutJson));
      _lockoutUntil = lockoutMap.map((k, v) => MapEntry(k, DateTime.parse(v)));
    } catch (_) {
      _failedAttempts = {};
      _lockoutUntil = {};
    }

    if (rememberMe) {
      final u =
          _sanitizeUsernameInput((prefs.getString('username') ?? '').trim());
      _storedUsername = u.isEmpty ? resumeUser : u;
      if ((_storedUsername ?? '').isEmpty) _storedUsername = resumeUser;
      final dn = (prefs.getString('rememberDisplayName') ?? '').trim();
      _rememberDisplayName = dn.isEmpty
          ? resumeName
          : CompoundDisplayName.normalize(dn);
      if ((_rememberDisplayName ?? '').isEmpty && resumeName != null) {
        _rememberDisplayName = CompoundDisplayName.normalize(resumeName);
      }
    } else {
      await prefs.remove('username');
      await prefs.remove('rememberDisplayName');
      _storedUsername = resumeUser;
      _rememberDisplayName = resumeName == null
          ? null
          : CompoundDisplayName.normalize(resumeName);
    }

    final hasIdentity = (_storedUsername ?? '').isNotEmpty &&
        (_rememberDisplayName ?? '').trim().isNotEmpty;

    try {
      _methodSnapshot =
          await LoginMethodPolicy.resolve(hasKnownUser: hasIdentity);
    } catch (_) {}

    var forcePasswordLogin = false;
    try {
      forcePasswordLogin = await FastLoginService.consumeForcePasswordLoginOnce();
    } catch (_) {}

    if (!forcePasswordLogin &&
        _methodSnapshot.autoOpenFastLogin &&
        !FastLoginService.hasUnlockedThisRuntimeSession) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/fastLogin');
      });
      return;
    }

    // جهاز غير معتمد أو أول دخول: حقول تقليدية كاملة (اسم مستخدم + كلمة مرور).
    if (!_methodSnapshot.nameOnlyPassword) {
      _showRememberedIdentityChip = false;
      _maskedPrefillActive = false;
      _storedUsername = null;
      _rememberDisplayName = null;
      _syncAutofillUsernameMirror();
      if (_usernameController.text.trim().isNotEmpty && !_usernameEdited) {
        _usernameController.clear();
      }
    } else {
      _showRememberedIdentityChip = true;
      _syncAutofillUsernameMirror();
      _maskedPrefillActive = true;
      _usernameEdited = false;
      _usernameController.clear();
    }

    if (prefs.containsKey('password')) {
      await prefs.remove('password');
    }

    if (!mounted) return;
    final known = _showRememberedIdentityChip &&
        (_rememberDisplayName ?? '').trim().isNotEmpty &&
        (_storedUsername ?? '').isNotEmpty;
    setState(() {
      _showQuickLoginEntry = _methodSnapshot.showAnyQuickUnlock;
      _methodSnapshot = _methodSnapshot.copyWith(hasKnownUser: known);
    });
    _checkUsernameExistsDebounced();
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('rememberMe', rememberMe);
    await prefs.setBool('fastLogin', fastLogin);

    await prefs.setString('failedAttempts', json.encode(_failedAttempts));
    final lockoutJson =
        _lockoutUntil.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString('lockoutUntil', json.encode(lockoutJson));

    if (!rememberMe) {
      await prefs.remove('username');
      await prefs.remove('rememberDisplayName');
      if (prefs.containsKey('password')) {
        await prefs.remove('password');
      }
      return;
    }

    final real = (_getRealUsername() ?? '').trim();
    if (_looksLikeUsername10Digits(real)) {
      await prefs.setString('username', real);
      _storedUsername = real;
    }
    final dn = (_rememberDisplayName ?? '').trim();
    if (dn.isNotEmpty) {
      await prefs.setString('rememberDisplayName', dn);
    }

    if (prefs.containsKey('password')) {
      await prefs.remove('password');
    }
  }

  // ===== Mask helpers =====
  String _maskNationalIdLast4(String s) {
    final v = s.trim();
    if (v.isEmpty) return '';
    if (v.length <= 4) return '*' * v.length;
    final last4 = v.substring(v.length - 4);
    final stars = '*' * (v.length - 4);
    return '$stars$last4';
  }

  void _applyMaskedUsernamePrefill() {
    final u = _storedUsername ?? '';
    _maskedPrefillActive = true;
    _usernameEdited = false;
    _syncAutofillUsernameMirror();

    if (u.isNotEmpty) {
      _usernameController.text = _maskNationalIdLast4(u);
      _usernameController.selection =
          TextSelection.collapsed(offset: _usernameController.text.length);
    }
  }

  void _syncAutofillUsernameMirror() {
    final u = (_storedUsername ?? '').trim();
    if (_autofillUsernameMirror.text != u) {
      _autofillUsernameMirror.value = TextEditingValue(
        text: u,
        selection: TextSelection.collapsed(offset: u.length),
      );
    }
  }

  String? _getRealUsername() {
    if (_maskedPrefillActive && !_usernameEdited) {
      return _storedUsername?.trim();
    }
    return _sanitizeUsernameInput(_usernameController.text.trim());
  }

  void _generateCaptcha() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = math.Random();
    captchaText = String.fromCharCodes(
      List.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
    userCaptchaInput = '';
  }

  int _remainingAttempts(String username) {
    final used = (_failedAttempts[username] ?? 0);
    final rem = _maxAttemptsBeforeLock - used;
    return rem < 0 ? 0 : rem;
  }

  Future<bool> _isAccountLockedLocal(String username) async {
    final now = DateTime.now();
    final lockoutTime = _lockoutUntil[username];

    if (lockoutTime != null && now.isBefore(lockoutTime)) {
      final minutesLeft = lockoutTime.difference(now).inMinutes;
      final secondsLeft = lockoutTime.difference(now).inSeconds % 60;

      _showLoginError(
        _isAr
            ? 'الحساب مقفل مؤقتاً. حاول بعد $minutesLeft دقيقة و $secondsLeft ثانية.'
            : 'Account temporarily locked. Try again in $minutesLeft minutes $secondsLeft seconds.',
      );
      return true;
    }
    return false;
  }

  Future<void> _updateFailedAttemptsLocal(String username) async {
    final key = username.isEmpty ? 'unknown' : username;
    final attempts = (_failedAttempts[key] ?? 0) + 1;
    _failedAttempts[key] = attempts;

    final rem = _remainingAttempts(key);

    if (attempts >= _maxAttemptsBeforeLock) {
      _lockoutUntil[key] = DateTime.now().add(_lockDuration);
      setState(() {
        showCaptcha = true;
        _generateCaptcha();
      });
    }

    await _savePreferences();

    _showLoginError(
      _isAr
          ? 'بيانات الدخول غير صحيحة. المحاولات المتبقية: $rem'
          : 'Invalid credentials. Attempts left: $rem',
    );
  }

  Future<void> _resetFailedAttemptsLocal(String username) async {
    _failedAttempts.remove(username);
    _lockoutUntil.remove(username);
    await _savePreferences();
  }

  // ✅ فتح شاشة الدخول السريع
  Future<void> _openQuickLogin() async {
    if (!_methodSnapshot.showAnyQuickUnlock) return;
    final okNet = await _ensureInternetOrAlert();
    if (!mounted) return;
    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
    if (!okNet) return;

    if (Supabase.instance.client.auth.currentSession == null) {
      final loc = AppLocalizations.of(context);
      if (loc == null) return;
      _showLoginError(
        _isAr
            ? 'الجلسة غير متاحة. سجّل الدخول بكلمة المرور.'
            : 'Session unavailable. Sign in with your password.',
      );
      return;
    }

    final u = (_getRealUsername() ?? '').trim();
    final normalized = _normalizeNumbers(u).trim();

    if (!_looksLikeUsername10Digits(normalized)) {
      final loc = AppLocalizations.of(context);
      if (loc == null) return;
      _showLoginError(loc.loginEnterIdentifierFirst);
      return;
    }

    final exists = await _usernameExistsRpc(normalized);
    if (!mounted) return;
    if (!exists) {
      final loc = AppLocalizations.of(context);
      if (loc == null) return;
      _showLoginError(loc.loginNoAccountLinkedIdentifier);
      return;
    }

    await _ensureNotGuestMode();
    if (mounted) {
      await context.read<AppSession>().reloadFromPrefs();
    }

    try {
      await FastLoginService.setPreferPasswordSurface(false);
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/fastLogin');
  }

  // =======================
  // ✅ LOGIN (User)
  // =======================
  Future<void> _login() async {
    if (isBusy || _nafathBusy) return;

    final okNet = await _ensureInternetOrAlert();
    if (!mounted) return;
    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
    if (!okNet) return;

    final t = AppLocalizations.of(context);
    if (t == null) return;

    final username = (_getRealUsername() ?? '').trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() {
        _usernameError = _isAr ? 'هذا الحقل إجباري' : 'This field is required';
        _passwordError = password.isEmpty
            ? (_isAr ? 'هذا الحقل إجباري' : 'This field is required')
            : null;
      });
      await _shakeCredentialsGroup();
      if (!mounted) return;
      _usernameFocus.requestFocus();
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _usernameError = null;
        _passwordError = _isAr
            ? 'أدخل كلمة المرور للمتابعة'
            : 'Enter your password to continue';
      });
      await _shakeCredentialsGroup();
      if (!mounted) return;
      _passwordFocus.requestFocus();
      return;
    }

    setState(() {
      _usernameError = null;
      _passwordError = null;
    });

    await _ensureNotGuestMode();
    if (mounted) {
      await context.read<AppSession>().reloadFromPrefs();
    }

    final u = _normalizeNumbers(username).trim();

    if (!_looksLikeUsername10Digits(u)) {
      setState(() {
        _usernameError = t.loginIdentifierMustBe10;
        _passwordError = null;
      });
      await _shakeCredentialsGroup();
      if (!mounted) return;
      _usernameFocus.requestFocus();
      await _updateFailedAttemptsLocal(u);
      return;
    }

    if (await _isAccountLockedLocal(u)) return;
    if (!mounted) return;

    if (showCaptcha) {
      if (userCaptchaInput.trim().toUpperCase() != captchaText) {
        _showLoginError(
            _isAr ? 'رمز التحقق غير صحيح' : 'Incorrect CAPTCHA code');
        setState(() => _generateCaptcha());
        await _updateFailedAttemptsLocal(u);
        if (!mounted) return;
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => isBusy = true);
    // نافذة منبثقة فوق شاشة الدخول — بلا صفحة بيضاء وسيطة.
    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: Center(
            child: Material(
              elevation: 10,
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(ctx).colorScheme.surface,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                        _isAr ? 'جاري تسجيل الدخول…' : 'Signing in…',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    final lang = langNotifier.value == 'en' ? 'en' : 'ar';

    final result = await AuthService.login(
      username: u,
      password: password,
      lang: lang,
    );

    if (!mounted) return;

    var loginOverlayOpen = true;
    void dismissLoginOverlay() {
      if (!loginOverlayOpen) return;
      loginOverlayOpen = false;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }

    if (!result.ok) {
      dismissLoginOverlay();
      if (result.locked) {
        setState(() => isBusy = false);
        _showLoginError(
          result.message.isEmpty
              ? (_isAr
                  ? 'الحساب مقفل، استخدم استعادة كلمة المرور.'
                  : 'Account is locked. Use password recovery.')
              : result.message,
        );
        return;
      }

      setState(() => isBusy = false);
      await _updateFailedAttemptsLocal(u);
      return;
    }

    final session = await _waitForSession();
    final uid = session?.user.id;

    if (uid == null || uid.isEmpty) {
      dismissLoginOverlay();
      setState(() => isBusy = false);
      _showLoginError(
        _isAr
            ? 'تم التحقق لكن لم يتم إنشاء جلسة دخول.'
            : 'Verified but no session created.',
      );
      return;
    }

    await _resetFailedAttemptsLocal(u);

    if (!rememberMe) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('username');
        await prefs.remove('rememberDisplayName');
      } catch (_) {}
      _storedUsername = null;
      _rememberDisplayName = null;
    }

    TextInput.finishAutofillContext(shouldSave: rememberMe);

    final challenge = await AuthChallengeService.start(
      username: u,
      loginMethod: 'password',
    );
    if (!mounted) return;

    final skipOtp = challenge.fullyAuthenticated &&
        AuthCompletionPolicy.allowFastLogin(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        ) &&
        !AuthCompletionPolicy.localFlagCanBypassOtp();

    if (skipOtp) {
      dismissLoginOverlay();
      try {
        await FastLoginService.saveUserContext(
          uid: uid,
          usernameNationalId: u,
          displayName: _rememberDisplayName,
        );
        await FastLoginService.markTrustedInstall(uid: uid);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_otpVerifiedKey(uid), true);
        await prefs.setBool(AppConfig.prefGuestModeKey, false);
        await prefs.setString(AppConfig.prefEntryModeKey, 'user');
      } catch (_) {}

      if (!mounted) return;
      await context.read<AppSession>().setUser(uid);

      if (!mounted) return;
      setState(() => isBusy = false);

      if (!mounted) return;
      await LoginSuccessBanner.showOrQueue(
        null,
        isAr: langNotifier.value != 'en',
      );
      await ReturnAfterAuth.navigatePostAuthOrDefault(
        Navigator.of(context),
        '/userDashboard',
      );
      return;
    }

    final deviceId = '${DateTime.now().millisecondsSinceEpoch}_$u';

    // لا ننتظر users_profiles هنا: الاستعلام قد يتأخر أو يُرجع 500 (RLS) ويعيق الانتقال لشاشة الرمز.
    // شاشة التحقق تجلب الملف وتطبّق بديل metadata من الجلسة.
    unawaited(
      ProfileComplianceService.tryUploadPendingSignupSignature(
        Supabase.instance.client,
      ),
    );

    String? prefetchFullName;
    final au = Supabase.instance.client.auth.currentUser;
    if (au != null) {
      final mn =
          ProfileGreetingFromRow.displayNameFromAuthMetadata(au.userMetadata);
      if (mn != null && mn.isNotEmpty) {
        prefetchFullName = mn;
      }
    }

    if (rememberMe) {
      _storedUsername = u;
      final dn = (prefetchFullName ?? '').trim();
      if (dn.isNotEmpty) {
        _rememberDisplayName = CompoundDisplayName.normalize(dn);
      }
      await _savePreferences();
    }

    try {
      await FastLoginService.saveUserContext(
        uid: uid,
        usernameNationalId: u,
        displayName: prefetchFullName ?? _rememberDisplayName,
      );
    } catch (_) {}

    final args = <String, dynamic>{
      'next': kIsWeb ? '/' : '/userDashboard',
      'nextArgs': <String, dynamic>{},
      'username': u,
      'deviceId': deviceId,
      'registerDeviceOnSuccess': !challenge.trusted,
      'backToLogin': true,
      if ((challenge.challengeId ?? '').isNotEmpty)
        'challengeId': challenge.challengeId,
    };
    if (prefetchFullName != null && prefetchFullName.trim().isNotEmpty) {
      args['fullName'] = prefetchFullName.trim();
    }

    // إرسال الرمز وجلبه + آخر دخول أثناء نافذة التحميل حتى تكون الشاشة فورية.
    final requestedAt = DateTime.now().toUtc();
    var otpRes = challenge.needsOtp && challenge.ok
        ? InAppOtpRequestResult(
            expiresAt: challenge.expiresAt,
            username: u,
            challengeId: challenge.challengeId,
            devCode: challenge.devCode,
          )
        : await AuthService.requestOtpDetailed(u);
    if (otpRes.error == 'not_authenticated') {
      await _waitForSession();
      if (!mounted) return;
      otpRes = await AuthService.requestOtpDetailed(u);
    }
    if ((challenge.error ?? otpRes.error) != null && kDebugMode) {
      debugPrint('[login] OTP request hint: ${challenge.error ?? otpRes.error}');
    }

    final greetFuture = InAppOtpHandoff.fetchGreeting(isAr: _isAr);
    final codeFuture = otpRes.ok
        ? InAppOtpHandoff.pollLatestCode(requestedAtUtc: requestedAt)
        : Future<String?>.value(null);
    final greet = await greetFuture;
    final prefetchedCode = await codeFuture;

    if (!mounted) return;

    // أغلق نافذة التحميل فقط — لا تُسقط شاشة الدخول/الجلسة بـ canPop إضافي.
    dismissLoginOverlay();

    final handoffName = (greet.displayName ?? prefetchFullName ?? '').trim();
    if (handoffName.isNotEmpty) {
      args['fullName'] = handoffName;
    }
    if (greet.lastLogin != null) {
      args['lastLogin'] = greet.lastLogin!.toUtc().toIso8601String();
    }
    if ((greet.avatarUrl ?? '').isNotEmpty) {
      args['avatarUrl'] = greet.avatarUrl;
    }
    final code = (prefetchedCode ?? otpRes.devCode ?? challenge.devCode ?? '')
        .trim();
    if (code.length >= InAppOtpHandoff.otpLen) {
      args['code'] = code.substring(0, InAppOtpHandoff.otpLen);
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        settings: RouteSettings(
          name: '/verify',
          arguments: {
            ...args,
            'otpAlreadyRequested': otpRes.ok,
            if (otpRes.error != null) 'otpPrefetchError': otpRes.error,
            if (otpRes.expiresAt != null)
              'otpExpiresAt': otpRes.expiresAt!.toUtc().toIso8601String(),
          },
        ),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const VerifyScreen(),
        transitionDuration: const Duration(milliseconds: 120),
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    // لا تُفرّغ isBusy قبل الانتقال — كانت تُظهر وميض تحميل أبيض.
  }

  Future<void> _startNafathLogin() async {
    if (isBusy || _nafathBusy) return;

    final okNet = await _ensureInternetOrAlert();
    if (!mounted) return;
    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
    if (!okNet) return;

    final username = (_getRealUsername() ?? '').trim();
    final nationalId =
        _normalizeNumbers(username).replaceAll(RegExp(r'\D'), '');

    setState(() => _nafathBusy = true);
    try {
      await NafathLoginSheet.show(
        context,
        isAr: _isAr,
        initialNationalId: nationalId,
        rememberMe: rememberMe,
      );
    } finally {
      if (mounted) setState(() => _nafathBusy = false);
    }
  }

  Future<void> _switchToAnotherUser() async {
    if (_busy) return;
    try {
      await FastLoginService.clearAll();
      try {
        if (Supabase.instance.client.auth.currentSession != null) {
          await AuthLocalSignOut.signOutLocal(Supabase.instance.client);
        }
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('username');
      await prefs.remove('rememberDisplayName');
      await prefs.setBool('rememberMe', false);
    } catch (_) {}
    LoginMethodSnapshot snap;
    try {
      snap = await LoginMethodPolicy.resolve(hasKnownUser: false);
    } catch (_) {
      snap = _methodSnapshot.copyWith(
        hasKnownUser: false,
        hasSession: false,
        trustedThisInstall: false,
        firstPasswordDone: false,
        pinEnabled: false,
        faceEnabled: false,
        fingerprintEnabled: false,
      );
    }
    if (!mounted) return;
    setState(() {
      rememberMe = false;
      _storedUsername = null;
      _rememberDisplayName = null;
      _showRememberedIdentityChip = false;
      _maskedPrefillActive = false;
      _usernameEdited = false;
      _showQuickLoginEntry = false;
      _methodSnapshot = snap;
      _usernameController.clear();
      _passwordController.clear();
      _syncAutofillUsernameMirror();
      _resetDbFlags();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _usernameFocus.requestFocus();
    });
  }

  Future<void> _onLoginMethodSelected(LoginMethodKind kind) async {
    switch (kind) {
      case LoginMethodKind.password:
        await FastLoginService.setPreferPasswordSurface(true);
        break;
      case LoginMethodKind.nafath:
        await _startNafathLogin();
        break;
      case LoginMethodKind.pin:
      case LoginMethodKind.face:
      case LoginMethodKind.fingerprint:
        await FastLoginService.setPreferPasswordSurface(false);
        await _openQuickLogin();
        break;
      case LoginMethodKind.anotherUser:
        await _switchToAnotherUser();
        break;
    }
  }

  bool get _knownUserReady =>
      _showRememberedIdentityChip &&
      (_rememberDisplayName ?? '').trim().isNotEmpty &&
      (_storedUsername ?? '').isNotEmpty;

  // =======================
  // UI
  // =======================
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: ListenableBuilder(
        listenable: Listenable.merge([langNotifier, themeModeNotifier]),
        builder: (context, _) {
          return Scaffold(
            backgroundColor: _pageBg,
            resizeToAvoidBottomInset: false,
            body: AppKeyboardStableScope(
              child: SafeArea(
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;

                  // تمرير عمودي دائماً يحسّن الجوال + الويب مع لوحة المفاتيح.
                  const allowVerticalScroll = true;
                  final showAdsSide = w >= 980;

                  if (showAdsSide) {
                    final adsW = (w * 0.52).clamp(520.0, 860.0);

                    return Row(
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF0B4D47),
                                  _bankColor,
                                  Color(0xFF0A3D38),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 22,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 600,
                                  ),
                                  child: _loginCard(
                                    maxWidth: 600,
                                    borderRadius: 20,
                                    t: t,
                                    allowVerticalScroll: allowVerticalScroll,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: adsW, child: _adsPanelRight(t: t)),
                      ],
                    );
                  }

                  final surface = AppSurfaceScope.maybeOf(context);
                  final host = LoginMethodPolicy.detectHost();
                  final fillScreen = surface?.isPhone ??
                      (host == LoginHostKind.nativeMobile ||
                          host == LoginHostKind.webMobile);
                  final padH = fillScreen ? 8.0 : (w < 560 ? 8.0 : 18.0);
                  final padV = fillScreen ? 8.0 : 18.0;
                  final cardMax = fillScreen
                      ? (w - padH * 2).clamp(260.0, w)
                      : (surface?.formMaxWidth ??
                              (w < 560
                                  ? (w - padH * 2).clamp(260.0, 900.0)
                                  : 600.0))
                          .clamp(260.0, 720.0);

                  return Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(padH, padV, padH, 6),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: cardMax),
                          child: _topBarUnified(),
                        ),
                      ),
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: const _LoginScrollBehavior(),
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const ClampingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(padH, 0, padH, padV + 16),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: cardMax),
                                child: _loginCard(
                                  maxWidth: cardMax,
                                  borderRadius: fillScreen ? 14 : 18,
                                  t: t,
                                  allowVerticalScroll: false,
                                  includeTopBar: false,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  // ===================== UI helpers =====================
  Widget _loginCard({
    required double maxWidth,
    required double borderRadius,
    required AppLocalizations t,
    required bool allowVerticalScroll,
    bool includeTopBar = true,
  }) {
    final cardColor = _isLight
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFF171A22).withValues(alpha: 0.95);

    final content = Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          // تظليل فاتح واضح — لا يطمس النص (كان الأخضر الثقيل يخفي الحروف).
          selectionColor: _isLight
              ? const Color(0xFF93C5FD).withValues(alpha: 0.55)
              : const Color(0xFF38BDF8).withValues(alpha: 0.40),
          selectionHandleColor:
              _isLight ? const Color(0xFF2563EB) : const Color(0xFF38BDF8),
          cursorColor: _bankColor,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (includeTopBar) ...[
            _topBarUnified(),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user, size: 16, color: _successColor),
              const SizedBox(width: 6),
              Text(
                _isAr ? 'تسجيل دخول آمن' : 'Secure Login',
                style: TextStyle(
                  fontSize: _font(context, 12, 11),
                  color: _successColor,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 2),
          const LoginBrandHero(),
          if (_knownUserReady) ...[
            const SizedBox(height: 2),
            LoginKnownUserHero(
              isAr: _isAr,
              displayName: _rememberDisplayName!,
              accent: _bankColor,
              compact: _isSmallUi(context),
            ),
            const SizedBox(height: 14),
          ] else ...[
            if (AppBranding.prefersAppVisuals(context)) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    AppBranding.welcomeHeadline(context, isAr: _isAr),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                      height: 1.15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  t.signInToContinue,
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
            if (kIsOpsDesktopSurface) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  t.opsDeskLoginHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (context, child) => Transform.translate(
              offset: _shakeAnim.value,
              child: child,
            ),
            child: FieldGroupFrame(
              title: _knownUserReady
                  ? (_isAr ? 'كلمة المرور' : 'Password')
                  : t.fieldGroupCredentialsTitle,
              titleTextAlign: TextAlign.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: AutofillGroup(
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_knownUserReady) ...[
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: _buildUsernameField(t: t),
                        ),
                        const SizedBox(height: 10),
                      ] else
                        Offstage(
                          offstage: true,
                          child: AqarTextField(
                            controller: _autofillUsernameMirror,
                            autofillHints: const [AutofillHints.username],
                          ),
                        ),
                      FocusTraversalOrder(
                        order: NumericFocusOrder(_knownUserReady ? 1 : 2),
                        child: _buildPasswordField(t: t),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showCaptcha) ...[
            const SizedBox(height: 16),
            _buildCaptchaSection(t: t),
          ],
          const SizedBox(height: 8),
          _buildForgotRememberRow(t: t),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _busy ? null : _login,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                child: isBusy
                    ? AppBusyIndicator.button(
                        key: const ValueKey('loading'),
                        label: _isAr ? 'جاري تسجيل الدخول' : 'Signing in…',
                      )
                    : Text(
                        t.userSignIn,
                        key: const ValueKey('text'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
          ),
          if (!kIsOpsDesktopSurface) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _bankColor,
                foregroundColor: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (isBusy || _nafathBusy)
                  ? null
                  : () {
                      try {
                        Navigator.pushNamed(context, '/register');
                      } catch (_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isAr
                                  ? 'صفحة إنشاء حساب غير مفعّلة حالياً'
                                  : 'Register screen is not enabled yet',
                            ),
                          ),
                        );
                      }
                    },
              child: Text(
                _isAr ? 'إنشاء حساب جديد' : 'Create new account',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _bankColor,
                backgroundColor: _fieldFill,
                side: BorderSide(color: _fieldOutline, width: 1.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (isBusy || _nafathBusy)
                  ? null
                  : () async {
                      final okNet = await _ensureInternetOrAlert();
                      if (!mounted) return;
                      ConnectivityGuard.showOfflineSnackIfNeeded(
                          context, okNet);
                      if (!okNet) return;

                      await context.read<AppSession>().setGuest();
                      if (!mounted) return;
                      await _setGuestModePrefs();
                      if (!mounted) return;
                      unawaited(
                        syncSessionAppearanceNotifiers?.call() ??
                            Future.value(),
                      );
                      unawaited(touchWebGuestActivity());

                      if (!mounted) return;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!context.mounted) return;
                        unawaited(PostAuthNavigation.openDashboard(context));
                      });
                    },
              child: Text(
                _isAr ? 'الدخول كضيف' : 'Continue as guest',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _packageVersionLine.isEmpty
                    ? const SizedBox.shrink()
                    : SelectableText(
                        _isAr
                            ? '${kIsWeb ? 'منصّة ويب' : kIsOpsDesktopSurface ? 'تطبيق سطح المكتب' : 'تطبيق جوّال'} — الإصدار: $_packageVersionLine'
                            : '${kIsWeb ? 'Web' : kIsOpsDesktopSurface ? 'Desktop app' : 'Mobile app'} — Version: $_packageVersionLine',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _textSecondary,
                          height: 1.25,
                        ),
                      ),
              ),
              Material(
                color: _bankColor.withValues(alpha: _isLight ? 0.12 : 0.22),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => AppAboutCredits.show(
                    context,
                    isAr: _isAr,
                    versionLine: _packageVersionLine,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.priority_high_rounded,
                      size: 18,
                      color: _bankColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final child = Padding(
      padding: const EdgeInsets.all(18),
      child: allowVerticalScroll
          ? ScrollConfiguration(
              behavior: const _LoginScrollBehavior(),
              child: SingleChildScrollView(
                controller: _loginScrollCtrl,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const ClampingScrollPhysics(),
                clipBehavior: Clip.hardEdge,
                padding: const EdgeInsets.only(bottom: 20),
                child: content,
              ),
            )
          : content,
    );

    return FadeTransition(
      opacity: _enterFade,
      child: SlideTransition(
        position: _enterSlide,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Card(
            elevation: 10,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            color: cardColor,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _topBarUnified() {
    return AuthTopChrome(
      snapshot: _methodSnapshot.copyWith(hasKnownUser: _knownUserReady),
      busy: _busy,
      onSelect: (kind) => unawaited(_onLoginMethodSelected(kind)),
    );
  }

  Widget _buildForgotRememberRow({required AppLocalizations t}) {
    Future<void> onRememberChanged(bool? v) async {
      final newVal = v ?? false;
      setState(() => rememberMe = newVal);

      if (!newVal) {
        await _savePreferences();
        return;
      }

      final curU = (_getRealUsername() ?? '').trim();
      _storedUsername = curU.isEmpty ? null : curU;
      _syncAutofillUsernameMirror();

      if ((_storedUsername ?? '').isNotEmpty) {
        if ((_rememberDisplayName ?? '').isNotEmpty) {
          _showRememberedIdentityChip = true;
          _maskedPrefillActive = true;
          _usernameController.clear();
        } else {
          _applyMaskedUsernamePrefill();
        }
      }
      await _savePreferences();
      _checkUsernameExistsDebounced();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocus.requestFocus();
      });
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        final okNet = await _ensureInternetOrAlert();
                        if (!mounted) return;
                        ConnectivityGuard.showOfflineSnackIfNeeded(
                            context, okNet);
                        if (!okNet) return;
                        Navigator.pushNamed(context, '/resetPassword');
                      },
                child: Text(
                  t.forgotUsernameOrPassword,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: _font(context, 13.5, 12),
                    color: _bankColor,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerEnd,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: rememberMe,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: _busy ? null : onRememberChanged,
              ),
              Text(
                t.rememberMe,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: _font(context, 13, 12),
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ✅ حقل الهوية / الإقامة — أو بطاقة الاسم الرباعي عند الجهاز المعتمد.
  Widget _buildUsernameField({required AppLocalizations t}) {
    if (_showRememberedIdentityChip &&
        (_rememberDisplayName ?? '').trim().isNotEmpty &&
        (_storedUsername ?? '').isNotEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Column(
        key: _usernameFieldKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: cs.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _busy
                  ? null
                  : () {
                      setState(() {
                        _showRememberedIdentityChip = false;
                        _applyMaskedUsernamePrefill();
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _usernameFocus.requestFocus();
                      });
                    },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isAr ? 'مرحباً بعودتك' : 'Welcome back',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _rememberDisplayName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _showRememberedIdentityChip = false;
                                _applyMaskedUsernamePrefill();
                              });
                            },
                      child: Text(
                        _isAr ? 'تغيير' : 'Change',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // حقل مخفي لمدير كلمات مرور المتصفح/الجهاز (username).
          Offstage(
            offstage: true,
            child: AqarTextField(
              controller: _autofillUsernameMirror,
              autofillHints: const [AutofillHints.username],
            ),
          ),
        ],
      );
    }

    final raw = _getRealUsername()?.trim() ?? '';
    final normalized = _normalizeNumbers(raw).trim();
    final is10 = _looksLikeUsername10Digits(normalized);

    Widget? suffix;
    if (_checkingUsername) {
      suffix = const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: AppLogoLoading(compact: true, size: 20),
          ),
        ),
      );
    } else if (_usernameCheckDone && is10 && _usernameExists) {
      suffix = SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(Icons.verified_rounded, color: _successColor),
        ),
      );
    } else if (_usernameCheckDone &&
        is10 &&
        !_usernameExists &&
        raw.isNotEmpty) {
      suffix = SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(Icons.error_outline, color: _errorColor),
        ),
      );
    }

    return Column(
      key: _usernameFieldKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AqarTextField(
          controller: _usernameController,
          focusNode: _usernameFocus,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          textAlign: _isAr ? TextAlign.right : TextAlign.left,
          inputFormatters: [
            const _EnglishDigitsOnlyFormatter(),
            const StrictMaxLengthFormatter(10),
            LengthLimitingTextInputFormatter(10),
          ],
          maxLength: 10,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) {
            if (_sanitizeUsernameInput(_usernameController.text).length == 10) {
              _advanceToPasswordAfterUsernameComplete();
            }
          },
          autofillHints: const [AutofillHints.username],
          cursorColor: _bankColor,
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
          decoration: _loginFieldDecoration(
            labelText: _isAr ? 'اسم المستخدم' : 'Username',
            hintText: t.loginUsernameFieldHelper,
            prefixIcon: Icon(Icons.badge_outlined, color: _iconColor),
            suffixIcon: suffix,
          ),
          onTap: () {
            if (_maskedPrefillActive && !_usernameEdited) {
              _usernameEdited = true;
              _usernameController.clear();
              _resetDbFlags();
            }
            if (!_usernameFocus.hasFocus) {
              _usernameFocus.requestFocus();
            }
          },
        ),
        if ((_usernameError ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
            child: Text(
              _usernameError!,
              style: TextStyle(
                color: _errorColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // كلمة المرور — Caps Lock من CapsAwarePasswordField فقط.
  Widget _buildPasswordField({required AppLocalizations t}) {
    return Column(
      key: _passwordFieldKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CapsAwarePasswordField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          obscureText: obscurePassword,
          onToggleObscure: () =>
              setState(() => obscurePassword = !obscurePassword),
          isAr: _isAr,
          iconColor: _iconColor,
          cursorColor: _bankColor,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          autofillHints: const [AutofillHints.password],
          inputFormatters: [
            PasswordLeadingDigitBleedGuard(
              isActive: () => _passwordBleedGuardActive,
            ),
            ...passwordArabicGuardFormatters(
              onArabicScriptBlocked: _schedulePasswordArabicDialog,
            ),
          ],
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
          decoration: _loginFieldDecoration(
            labelText: t.loginPasswordFieldShortLabel,
            hintText: null,
            hintFontSize: 16,
          ),
        ),
        if ((_passwordError ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
            child: Text(
              _passwordError!,
              style: TextStyle(
                color: _errorColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ],
    );
  }


  Widget _buildCaptchaSection({required AppLocalizations t}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isLight ? const Color(0xFFFEF3C7) : const Color(0xFF78350F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isLight ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.security_rounded,
                color: _isLight ? const Color(0xFF92400E) : Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                _isAr ? 'التحقق من الأمان' : 'Security Verification',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _isLight ? const Color(0xFF92400E) : Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isAr
                ? 'لإثبات أنك لست روبوتاً، الرجاء إدخال الأحرف التالية:'
                : 'To prove you\'re not a robot, please enter the characters below:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color:
                  _isLight ? const Color(0xFF92400E) : const Color(0xFFFDE68A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: _isLight ? Colors.white : const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _fieldOutline),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < captchaText.length; i++)
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isLight
                          ? const Color(0xFFF3F4F6)
                          : const Color(0xFF374151),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      captchaText[i],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AqarTextField(
            onChanged: (value) => setState(() => userCaptchaInput = value),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _textPrimary,
              fontFamily: 'Courier',
            ),
            decoration: InputDecoration(
              hintText: _isAr ? 'أدخل الأحرف أعلاه' : 'Enter characters above',
              hintStyle: TextStyle(
                color: _hintColor,
                fontWeight: FontWeight.w800,
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () => setState(_generateCaptcha),
                icon: Icon(Icons.refresh, size: 16, color: _iconColor),
                label: Text(
                  _isAr ? 'تحديث الرمز' : 'Refresh',
                  style: TextStyle(
                    color: _iconColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => showCaptcha = false),
                icon: Icon(Icons.close, size: 16, color: _errorColor),
                label: Text(
                  _isAr ? 'تخطي' : 'Skip',
                  style: TextStyle(
                    color: _errorColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========= Right Ads Panel =========
  Widget _adsPanelRight({required AppLocalizations t}) {
    final bg1 = _isLight ? const Color(0xFFF2F6FF) : const Color(0xFF0B1020);
    final bg2 = _isLight ? const Color(0xFFEAF0FF) : const Color(0xFF111936);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg1, bg2],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -120,
            top: -120,
            child: _blurCircle(_isLight ? Colors.blue : Colors.blueAccent),
          ),
          Positioned(
            left: -140,
            bottom: -140,
            child: _blurCircle(_isLight ? Colors.indigo : Colors.indigoAccent),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            t.rightPanelTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: _isLight
                                  ? const Color(0xFF0B1220)
                                  : Colors.white,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t.rightPanelSubtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              height: 1.6,
                              color: _isLight
                                  ? const Color(0xFF4A5568)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    SizedBox(width: 320, child: _phoneCarousel(t: t)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneCarousel({required AppLocalizations t}) {
    if (_ads.isEmpty) {
      return Center(
        child: Text(
          t.noEnabledAds,
          style: TextStyle(
            color: _isLight ? Colors.black54 : Colors.white70,
            fontWeight: FontWeight.w900,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final item = _ads.first;
    final title = _isAr ? item.titleAr : item.titleEn;
    final subtitle = _isAr ? item.subtitleAr : item.subtitleEn;

    return SizedBox(
      height: 560,
      child: _PhoneMockup(
        theme: _currentTheme,
        title: title,
        subtitle: subtitle,
        imageAsset: item.assetImage,
        imageNetworkUrl: item.imageUrl,
        videoUrl: item.bestVideoUrl(),
        isAr: _isAr,
        adId: item.id,
      ),
    );
  }

  Widget _blurCircle(Color color) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }
}

int? _loginSideBrandVariant(String? adId) {
  switch (adId) {
    case 'mawthuq-demo-license':
      return 0;
    case 'mawthuq-demo-inbox':
      return 1;
    case 'mawthuq-demo-explore':
      return 2;
    default:
      return null;
  }
}

/// رسوم لوحة الدخول (ويب/شاشة عريضة) عندما تكون إعلانات الـ fallback لموثوق.
class _MawthuqLoginSideIllustration extends StatelessWidget {
  final int variant;
  final bool isLight;
  final bool isAr;

  const _MawthuqLoginSideIllustration({
    required this.variant,
    required this.isLight,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case 0:
        return _license();
      case 1:
        return _inbox();
      case 2:
        return _explore();
      default:
        return const SizedBox.expand();
    }
  }

  Widget _license() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A4D68),
            Color(0xFF0F766E),
            Color(0xFF134E4A),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -24,
            bottom: -24,
            child: Icon(
              Icons.shield_rounded,
              size: 100,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment:
                      isAr ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          isAr
                              ? AppBranding.shortNameAr
                              : AppBranding.shortNameEn,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 12,
                        color: Colors.black.withValues(alpha: 0.12),
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined,
                              size: 18, color: Color(0xFF0F766E)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isAr
                                  ? 'رخصة إعلان عقاري'
                                  : 'Licensed property ad',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                color: Color(0xFF0B1220),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _skeletonLine(0.95, const Color(0xFFE2E8F0)),
                      const SizedBox(height: 5),
                      _skeletonLine(0.75, const Color(0xFFEDF2F7)),
                      const SizedBox(height: 5),
                      _skeletonLine(0.55, const Color(0xFFF1F5F9)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            isAr ? 'حالة الرخصة' : 'Licence status',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F766E)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isAr ? 'سارية' : 'Active',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonLine(double widthFactor, Color color) {
    return LayoutBuilder(
      builder: (context, c) {
        return Container(
          height: 5,
          width: c.maxWidth * widthFactor,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      },
    );
  }

  Widget _inbox() {
    final bgTop = isLight ? const Color(0xFFE8F0FF) : const Color(0xFF152038);
    final bgBot = isLight ? const Color(0xFFDCE8FF) : const Color(0xFF1A2744);
    final textMain =
        isLight ? const Color(0xFF0B1220) : const Color(0xFFE2E8F0);
    final textDim = isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgTop, bgBot],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xFF243B5C),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 8,
                      color: Colors.black.withValues(alpha: 0.06),
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  isAr
                      ? 'السلام عليكم، نجهّز لكم جولة داخل المنصة.'
                      : 'Hi—we can tour the listing here.',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                    color: textMain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 13, color: Colors.white.withValues(alpha: 0.95)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isAr
                            ? 'ممتاز—بقينا داخل قنوات موثّقة.'
                            : 'Perfect—staying on trusted channels.',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.forum_rounded,
                    size: 14, color: _PhoneMockup._bankColor),
                const SizedBox(width: 6),
                Text(
                  isAr ? 'محادثات دون مغادرة التطبيق' : 'In-app messaging',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: textDim,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _explore() {
    final cardBg = isLight ? Colors.white : const Color(0xFF1B2640);
    final border = isLight ? const Color(0xFFE2E8F0) : const Color(0xFF2D3F66);

    Widget miniCard() {
      return Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0F766E).withValues(alpha: 0.35),
                          const Color(0xFF0A4D68).withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: isAr ? Alignment.topRight : Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 12,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 4,
                      width: 36,
                      decoration: BoxDecoration(
                        color: isLight
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF3D5277),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 4,
                      width: 22,
                      decoration: BoxDecoration(
                        color: isLight
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF344563),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F766E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.apartment_rounded,
                    size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isAr ? 'عروض بمعايير أوضح' : 'Clearer listing signals',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        miniCard(),
                        const SizedBox(width: 6),
                        miniCard(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Row(
                      children: [
                        miniCard(),
                        const SizedBox(width: 6),
                        miniCard(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneMockup extends StatelessWidget {
  static const Color _bankColor = Color(0xFF0F766E);

  final ThemeMode theme;
  final String title;
  final String subtitle;
  final String imageAsset;
  final String? imageNetworkUrl;
  final String? videoUrl;
  final bool isAr;
  final String? adId;

  const _PhoneMockup({
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    this.imageNetworkUrl,
    this.videoUrl,
    this.isAr = true,
    this.adId,
  });

  Widget _mediaArea(Color titleColor, bool isLight) {
    final brandV = _loginSideBrandVariant(adId);
    if (brandV != null) {
      return _MawthuqLoginSideIllustration(
        variant: brandV,
        isLight: isLight,
        isAr: isAr,
      );
    }

    final v = (videoUrl ?? '').trim();
    if (v.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: 800,
            height: 450,
            child: InlinePropertyVideoPlayer(
              videoUrl: v,
              isAr: isAr,
            ),
          ),
        ),
      );
    }
    final net = (imageNetworkUrl ?? '').trim();
    if (net.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: net,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorWidget: (_, __, ___) => Container(
            color: isLight ? const Color(0xFFEFF3FF) : const Color(0xFF101A33),
            child: Center(
              child: Icon(
                Icons.image_outlined,
                size: 36,
                color: titleColor,
              ),
            ),
          ),
        ),
      );
    }
    if (imageAsset.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          imageAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Container(
            color: isLight ? const Color(0xFFEFF3FF) : const Color(0xFF101A33),
            child: Center(
              child: Icon(
                Icons.image_outlined,
                size: 36,
                color: titleColor,
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isLight ? const Color(0xFFEFF3FF) : const Color(0xFF101A33),
      ),
      child: Center(
        child: Icon(
          Icons.perm_media_outlined,
          size: 36,
          color: titleColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = UserAppearanceSession.resolvesLight(theme);

    final frame = isLight ? const Color(0xFF111827) : const Color(0xFF0B1220);
    final screen = isLight ? Colors.white : const Color(0xFF0F1425);

    final titleColor = isLight ? const Color(0xFF0B1220) : Colors.white;
    final subColor =
        isLight ? const Color(0xFF4A5568) : const Color(0xFFCBD5E1);

    return Center(
      child: AspectRatio(
        aspectRatio: 9 / 19.5,
        child: Container(
          decoration: BoxDecoration(
            color: frame,
            borderRadius: BorderRadius.circular(38),
            boxShadow: [
              BoxShadow(
                blurRadius: 30,
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(0, 18),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Container(
              color: screen,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 110,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isLight
                          ? const Color(0xFFE5E7EB)
                          : const Color(0xFF1F2A44),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                              color: subColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _mediaArea(titleColor, isLight),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _bankColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 44,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isLight
                                      ? const Color(0xFFE5E7EB)
                                      : const Color(0xFF223055),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnglishDigitsOnlyFormatter extends TextInputFormatter {
  const _EnglishDigitsOnlyFormatter();

  static const Map<String, String> _digitMap = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  String _normalize(String input) {
    if (input.isEmpty) return input;

    final buffer = StringBuffer();
    for (final ch in input.split('')) {
      final mapped = _digitMap[ch] ?? ch;
      if (RegExp(r'[0-9]').hasMatch(mapped)) {
        buffer.write(mapped);
      }
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = _normalize(newValue.text);
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
      composing: TextRange.empty,
    );
  }
}
