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

import 'package:aqar_user/l10n/app_localizations.dart';
import 'package:aqar_user/main.dart';
import 'package:aqar_user/models.dart';
import 'package:aqar_user/services/ads_service.dart';
import 'package:aqar_user/services/auth_service.dart';
import 'package:aqar_user/theme.dart';
import 'package:aqar_user/widgets/app_logo_loading.dart';
import 'package:aqar_user/widgets/inline_property_video.dart';
import 'package:aqar_user/widgets/field_group_frame.dart';

import '../core/config/app_config.dart';
import '../core/input/password_arabic_script_guard.dart';
import '../core/session/app_session.dart';
import '../core/theme/app_appearance_bridge.dart';
import '../core/session/return_after_auth.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../services/connectivity_guard.dart';
import '../services/fast_login_service.dart';
import '../services/profile_compliance_service.dart';
import '../services/user_install_session_service.dart';
import '../core/government/nafath_models.dart';
import '../services/nafath_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// تمرير داخل بطاقة الدخول بنفس السلوك الذكي العام.
class _LoginScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (AqarScrollBehavior.isCompactTouchLike(context)) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final alwaysVisible =
        AqarScrollBehavior.isLargeScreenScrollbarVisible(context);
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: alwaysVisible,
      trackVisibility: alwaysVisible,
      thickness: alwaysVisible ? 8 : 5,
      radius: const Radius.circular(8),
      scrollbarOrientation:
          rtl ? ScrollbarOrientation.right : ScrollbarOrientation.left,
      child: child,
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin, RouteAware {
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

  bool rememberMe = false;
  bool fastLogin = false;

  /// يظهر زر «الدخول السريع / البصمة» فقط عند وجود قفل فعلي (PIN أو بصمة مفعّلة).
  bool _showQuickLoginEntry = false;

  bool _routeAwareSubscribed = false;

  bool obscurePassword = true;
  bool isBusy = false;
  bool _nafathBusy = false;

  // CAPTCHA
  bool showCaptcha = false;
  String captchaText = '';
  String userCaptchaInput = '';

  // Ads
  final PageController _adsController = PageController();
  int _adsIndex = 0;
  List<AdItem> _ads = [];

  // Remember-me masking
  String? _storedUsername;
  bool _maskedPrefillActive = false;
  bool _usernameEdited = false;

  // brute-force محلي
  Map<String, int> _failedAttempts = {};
  Map<String, DateTime> _lockoutUntil = {};

  // DB checks
  Timer? _userCheckDebounce;
  bool _checkingUsername = false;
  bool _usernameExists = false;
  bool _usernameCheckDone = false;

  // Animation
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  DateTime? _lastPasswordArabicDialogAt;

  bool get _isAr => langNotifier.value != 'en';

  ThemeMode get _currentTheme => themeModeNotifier.value;
  bool get _isLight => _currentTheme == ThemeMode.light;

  Color get _pageBg =>
      _isLight ? const Color(0xFFF5F7FA) : const Color(0xFF0E0F13);
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
    if (rememberMe && (_storedUsername ?? '').isNotEmpty) {
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
      prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 46),
      suffixIcon: suffixIcon,
      suffixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 46),
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

  // =======================
  // ✅ انتظار الجلسة بعد login
  // =======================
  Future<Session?> _waitForSession({int tries = 28}) async {
    final sb = Supabase.instance.client;
    for (int i = 0; i < tries; i++) {
      final s = sb.auth.currentSession;
      if (s != null) return s;
      if (i == 2 || i == 10) {
        try {
          final res = await sb.auth.refreshSession();
          if (res.session != null) return res.session;
        } catch (_) {}
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return sb.auth.currentSession;
  }

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _pulse = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl.repeat(reverse: true);

    _generateCaptcha();
    _loadAds();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _ensureInternetOrAlert();
      if (!mounted) return;
      await _loadPreferences();
      if (!mounted) return;
      // على الويب (خصوصاً متصفحات الجوال) طلب التركيز فوراً يتسبب بفتح/إغلاق لوحة المفاتيح.
      if (!kIsWeb) {
        _applyInitialFocus();
      }
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

      _checkUsernameExistsDebounced();
      // لا setState هنا على كل حرف: على Flutter Web يعيد بناء الحقول ويقطع التركيز/الكيبورد.
      // تحديث أيقونة التحقق يأتي من مسار _checkUsernameExistsDebounced و RPC.
    });

    _usernameFocus.addListener(() {
      if (_usernameFocus.hasFocus && _maskedPrefillActive && !_usernameEdited) {
        _usernameEdited = true;
        _usernameController.clear();
        _resetDbFlags();
        setState(() {});
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
    _pulseCtrl.dispose();
    _adsController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConfig.prefGuestModeKey, false);
      await prefs.setString(AppConfig.prefEntryModeKey, 'user');
      await prefs.remove('is_guest');
      await prefs.remove('guest');
    } catch (_) {}
  }

  Future<void> _setGuestModePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConfig.prefGuestModeKey, true);
      await prefs.setString(AppConfig.prefEntryModeKey, 'guest');
      await prefs.setBool('is_guest', true);
      await prefs.setBool('guest', true);
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

    _userCheckDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() => _checkingUsername = true);

      final exists = await _usernameExistsRpc(u);

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
      if (_adsIndex >= _ads.length) _adsIndex = 0;
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    rememberMe = prefs.getBool('rememberMe') ?? false;
    fastLogin = prefs.getBool('fastLogin') ?? false;
    if (kIsWeb) fastLogin = false;

    var quick = false;
    if (!kIsWeb) {
      try {
        quick = await FastLoginService.hasAnyLockEnabled();
      } catch (_) {}
    }

    final savedLang =
        prefs.getString(AppConfig.prefLangKey) ?? langNotifier.value;
    langNotifier.value = (savedLang == 'en') ? 'en' : 'ar';

    final savedTheme = prefs.getString(AppConfig.prefThemeKey) ?? 'light';
    themeModeNotifier.value =
        (savedTheme == 'dark') ? ThemeMode.dark : ThemeMode.light;

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
      _storedUsername = u.isEmpty ? null : u;
      if ((_storedUsername ?? '').isNotEmpty) {
        _applyMaskedUsernamePrefill();
      }
    }

    if (prefs.containsKey('password')) {
      await prefs.remove('password');
    }

    if (!mounted) return;
    setState(() {
      _showQuickLoginEntry = quick;
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

    if (prefs.containsKey('password')) {
      await prefs.remove('password');
    }
  }

  Future<void> _setLanguage(String code) async {
    await setAppLang(code);

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setTheme(ThemeMode mode) async {
    await setAppTheme(mode);
    if (!mounted) return;
    setState(() {});
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

    if (u.isNotEmpty) {
      _usernameController.text = _maskNationalIdLast4(u);
      _usernameController.selection =
          TextSelection.collapsed(offset: _usernameController.text.length);
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
    if (kIsWeb) return;
    final okNet = await _ensureInternetOrAlert();
    if (!mounted) return;
    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
    if (!okNet) return;

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

    if (username.isEmpty || password.isEmpty) {
      _showLoginError(t.allFieldsRequired);
      return;
    }

    await _ensureNotGuestMode();
    if (mounted) {
      await context.read<AppSession>().reloadFromPrefs();
    }

    final u = _normalizeNumbers(username).trim();

    if (!_looksLikeUsername10Digits(u)) {
      _showLoginError(t.loginIdentifierMustBe10);
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

    final lang = langNotifier.value == 'en' ? 'en' : 'ar';

    final result = await AuthService.login(
      username: u,
      password: password,
      lang: lang,
    );

    if (!mounted) return;

    if (!result.ok) {
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
      setState(() => isBusy = false);
      _showLoginError(
        _isAr
            ? 'تم التحقق لكن لم يتم إنشاء جلسة دخول.'
            : 'Verified but no session created.',
      );
      return;
    }

    await _resetFailedAttemptsLocal(u);

    if (rememberMe) {
      _storedUsername = u;
      await _savePreferences();
    }

    TextInput.finishAutofillContext(shouldSave: true);
    await _clearOtpVerifiedForCurrentSession();

    final known = await UserInstallSessionService.isCurrentInstallRegistered();
    if (!mounted) return;

    if (!kIsWeb && fastLogin && known) {
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

    bool otpOk = false;
    try {
      otpOk = await AuthService.requestOtp(u);
    } catch (_) {
      otpOk = false;
    }

    if (!otpOk) {
      setState(() => isBusy = false);
      _showLoginError(
        _isAr
            ? 'تعذر إرسال رمز التحقق. حاول مرة أخرى.'
            : 'Failed to send OTP. Please try again.',
      );
      return;
    }

    String? prefetchFullName;
    DateTime? prefetchLastLogin;
    final au = Supabase.instance.client.auth.currentUser;
    if (au != null) {
      final mn =
          ProfileGreetingFromRow.displayNameFromAuthMetadata(au.userMetadata);
      if (mn != null && mn.isNotEmpty) {
        prefetchFullName = mn;
      }
      if (au.lastSignInAt != null) {
        prefetchLastLogin =
            ProfileGreetingFromRow.lastSignInFromAuthString(au.lastSignInAt);
      }
    }

    final args = <String, dynamic>{
      'next': '/userDashboard',
      'nextArgs': <String, dynamic>{},
      'username': u,
      'deviceId': deviceId,
      'registerDeviceOnSuccess': !known,
      'backToLogin': true,
    };
    if (prefetchFullName != null && prefetchFullName.trim().isNotEmpty) {
      args['fullName'] = prefetchFullName.trim();
    }
    if (prefetchLastLogin != null) {
      args['lastLogin'] = prefetchLastLogin;
    }

    if (!mounted) return;

    setState(() => isBusy = false);

    Navigator.pushReplacementNamed(
      context,
      '/verify',
      arguments: args,
    );
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
    if (!_looksLikeUsername10Digits(nationalId)) {
      _showLoginError(
        _isAr
            ? 'أدخل رقم الهوية أو الإقامة من 10 أرقام قبل الدخول عبر نفاذ.'
            : 'Enter your 10-digit ID before using Nafath.',
      );
      return;
    }

    setState(() => _nafathBusy = true);
    try {
      final r = await NafathAuthService(Supabase.instance.client)
          .startLogin(locale: _isAr ? 'ar' : 'en', nationalId: nationalId);
      if (!mounted) return;

      switch (r.mode) {
        case NafathSessionMode.redirect:
          final u = r.authorizationUrl?.trim() ?? '';
          if (u.isEmpty) {
            _showNafathResult(r);
            return;
          }
          final uri = Uri.tryParse(u);
          if (uri == null ||
              !(uri.hasScheme &&
                  (uri.scheme == 'https' || uri.scheme == 'http'))) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isAr ? 'رابط نفاذ غير صالح' : 'Invalid Nafath URL',
                ),
              ),
            );
            return;
          }
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!launched && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isAr
                      ? 'تعذر فتح المتصفح. جرّب لاحقاً.'
                      : 'Could not open browser.',
                ),
              ),
            );
          }
          return;
        case NafathSessionMode.notConfigured:
        case NafathSessionMode.error:
          _showNafathResult(r);
          return;
        case NafathSessionMode.polling:
          await _showAndPollNafath(r);
          return;
      }
    } finally {
      if (mounted) setState(() => _nafathBusy = false);
    }
  }

  Future<void> _showAndPollNafath(NafathSessionResult initial) async {
    final requestId = (initial.requestId ?? '').trim();
    final random = (initial.random ?? '').trim();
    if (requestId.isEmpty) {
      _showNafathResult(initial);
      return;
    }

    _showNafathResult(initial);
    if (random.isNotEmpty) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(_isAr ? 'تحقق نفاذ' : 'Nafath verification'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isAr
                    ? 'افتح تطبيق نفاذ واختر الرقم التالي:'
                    : 'Open Nafath app and choose this number:',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              SelectableText(
                random,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isAr
                    ? 'سيتم إكمال الدخول تلقائياً بعد الموافقة.'
                    : 'Sign-in will continue automatically after approval.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_isAr ? 'إلغاء' : 'Cancel'),
            ),
          ],
        ),
      );
    }

    final svc = NafathAuthService(Supabase.instance.client);
    for (var i = 0; i < 30 && mounted; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final r = await svc.pollStatus(requestId);
      if (!mounted) return;
      if (r.mode == NafathSessionMode.polling) continue;
      if (r.mode == NafathSessionMode.redirect) {
        final u = (r.authorizationUrl ?? '').trim();
        final uri = Uri.tryParse(u);
        if (uri != null && uri.hasScheme) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      _showNafathResult(r);
      return;
    }

    if (!mounted) return;
    _showLoginError(
      _isAr
          ? 'لم يصل تأكيد نفاذ بعد. حاول مرة أخرى.'
          : 'Nafath confirmation was not received yet. Try again.',
    );
  }

  void _showNafathResult(NafathSessionResult r) {
    final msg = _isAr
        ? (r.messageAr ?? r.messageEn ?? r.rawError ?? '')
        : (r.messageEn ?? r.messageAr ?? r.rawError ?? '');
    final hasTechnicalSetupMessage =
        msg.contains('NAFATH_INTEGRATION_ENABLED') ||
            msg.contains('handler is not implemented') ||
            msg.contains('منطق الربط لم يُكمَل');
    final text = hasTechnicalSetupMessage
        ? (_isAr
            ? 'خدمة الدخول عبر نفاذ قيد التفعيل حالياً. الرجاء استخدام تسجيل الدخول برقم الهوية وكلمة المرور.'
            : 'Nafath sign-in is being activated. Please use ID/password sign-in for now.')
        : msg.isEmpty
            ? (_isAr
                ? 'تعذر إكمال طلب نفاذ.'
                : 'Could not complete Nafath request.')
            : msg;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  // =======================
  // UI
  // =======================
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, _, __) {
          return Scaffold(
            backgroundColor: _pageBg,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;

                  // تمرير عمودي دائماً يحسّن الجوال + الويب مع لوحة المفاتيح.
                  final allowVerticalScroll = true;
                  final showAdsSide = w >= 980;

                  if (showAdsSide) {
                    final adsW = (w * 0.52).clamp(520.0, 860.0);
                    final loginW = (w - adsW).clamp(440.0, 640.0);

                    return Row(
                      children: [
                        SizedBox(
                          width: loginW,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: _loginCard(
                                maxWidth: 600,
                                borderRadius: 20,
                                t: t,
                                allowVerticalScroll: allowVerticalScroll,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: adsW, child: _adsPanelRight(t: t)),
                      ],
                    );
                  }

                  final tightWeb = kIsWeb && w < 560;
                  final padH = tightWeb ? 8.0 : 18.0;
                  final padV = tightWeb ? 6.0 : 18.0;
                  final cardMax =
                      tightWeb ? (w - padH * 2).clamp(260.0, 900.0) : 600.0;

                  return Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(padH, padV, padH, padV),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: cardMax),
                        child: _loginCard(
                          maxWidth: cardMax,
                          borderRadius: 18,
                          t: t,
                          allowVerticalScroll: allowVerticalScroll,
                        ),
                      ),
                    ),
                  );
                },
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
  }) {
    final cardColor = _isLight
        ? Colors.white.withOpacity(0.95)
        : const Color(0xFF171A22).withOpacity(0.95);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _topBarUnified(t: t),
        const SizedBox(height: 10),
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
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, lc) {
            final narrow = lc.maxWidth < 420;
            final logoDim =
                kIsWeb ? (narrow ? 132.0 : 120.0) : (narrow ? 120.0 : 112.0);
            return ScaleTransition(
              scale: _pulse,
              child: Image.asset(
                'assets/logo.png',
                height: logoDim,
                width: logoDim,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.apartment_rounded,
                  size: logoDim * 0.65,
                  color: _textPrimary,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              t.welcomeTrustedAqar,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: _textPrimary,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              t.signInToContinue,
              style: TextStyle(
                fontSize: 14,
                color: _textSecondary,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FieldGroupFrame(
          title: t.fieldGroupCredentialsTitle,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUsernameField(t: t),
                const SizedBox(height: 10),
                _buildPasswordField(t: t),
              ],
            ),
          ),
        ),
        if (showCaptcha) ...[
          const SizedBox(height: 16),
          _buildCaptchaSection(t: t),
        ],
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        final okNet = await _ensureInternetOrAlert();
                        if (!mounted) return;
                        ConnectivityGuard.showOfflineSnackIfNeeded(
                            context, okNet);
                        if (!okNet) return;
                        Navigator.pushNamed(context, '/resetPassword');
                      },
                      child: Text(
                        t.forgotUsernameOrPassword,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: _font(context, 13.5, 12),
                          color: _bankColor,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: rememberMe,
                      onChanged: (v) async {
                        final newVal = v ?? false;
                        setState(() => rememberMe = newVal);

                        if (!newVal) {
                          _maskedPrefillActive = false;
                          _storedUsername = null;
                          _usernameEdited = false;
                          _usernameController.clear();
                          _resetDbFlags();
                          await _savePreferences();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _usernameFocus.requestFocus();
                          });
                          return;
                        }

                        final curU = (_getRealUsername() ?? '').trim();
                        _storedUsername = curU.isEmpty ? null : curU;

                        if ((_storedUsername ?? '').isNotEmpty) {
                          _applyMaskedUsernamePrefill();
                        }
                        await _savePreferences();
                        _checkUsernameExistsDebounced();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _passwordFocus.requestFocus();
                        });
                      },
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _isSmallUi(context) ? 140 : 160,
                      ),
                      child: Text(
                        t.rememberMe,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: _font(context, 13, 12),
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (!kIsWeb && _showQuickLoginEntry) ...[
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isBusy ? null : _openQuickLogin,
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                        colors: [
                          _bankColor.withValues(alpha: 0.14),
                          _bankColor.withValues(alpha: 0.04),
                        ],
                      ),
                      border: Border.all(
                        color: _bankColor.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _bankColor.withValues(alpha: 0.16),
                            ),
                            child: Icon(
                              Icons.fingerprint_rounded,
                              color: _bankColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.quickLogin,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: _font(context, 15, 14),
                                    color: _textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.quickLoginSubtitle,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: _font(context, 12, 11),
                                    color: _textSecondary,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: _textSecondary.withValues(alpha: 0.85),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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
            onPressed: (isBusy || _nafathBusy) ? null : _login,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isBusy
                  ? Row(
                      key: const ValueKey('loading'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: AppLogoLoading(compact: true, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isAr ? 'جارٍ الدخول...' : 'Signing in...',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
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
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _bankColor,
              side: BorderSide(color: _fieldOutline, width: 1.8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: (isBusy || _nafathBusy)
                ? null
                : () {
                    try {
                      Navigator.pushNamed(context, '/passwordSetup');
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
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: _font(context, 15, 13.5),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _bankColor,
              side: BorderSide(color: _bankColor.withValues(alpha: 0.55)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: (isBusy || _nafathBusy) ? null : _startNafathLogin,
            icon: _nafathBusy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: AppLogoLoading(compact: true, size: 18),
                  )
                : Icon(Icons.verified_user_outlined, color: _bankColor),
            label: Text(
              _nafathBusy
                  ? (_isAr ? 'جاري الاتصال…' : 'Connecting…')
                  : (_isAr ? 'الدخول عبر نفاذ' : 'Sign in with Nafath'),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: _font(context, 15, 13.5),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _bankColor.withOpacity(0.55)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: (isBusy || _nafathBusy)
                ? null
                : () async {
                    final okNet = await _ensureInternetOrAlert();
                    if (!mounted) return;
                    ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
                    if (!okNet) return;

                    await context.read<AppSession>().setGuest();
                    if (!mounted) return;
                    await _setGuestModePrefs();
                    if (!mounted) return;
                    unawaited(
                      syncSessionAppearanceNotifiers?.call() ?? Future.value(),
                    );

                    if (!mounted) return;
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/userDashboard',
                      (r) => false,
                    );
                  },
            icon: const Icon(Icons.person_outline),
            label: Text(
              _isAr ? 'الدخول كضيف' : 'Continue as guest',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );

    final child = Padding(
      padding: const EdgeInsets.all(18),
      child: allowVerticalScroll
          ? ScrollConfiguration(
              behavior: _LoginScrollBehavior(),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const ClampingScrollPhysics(),
                clipBehavior: Clip.hardEdge,
                child: content,
              ),
            )
          : content,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Card(
        elevation: 10,
        shadowColor: Colors.black.withOpacity(0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        color: cardColor,
        child: child,
      ),
    );
  }

  Widget _topBarUnified({required AppLocalizations t}) {
    return LayoutBuilder(
      builder: (context, c) {
        final langShort = (langNotifier.value == 'en') ? 'EN' : 'AR';
        final themeShort = _currentTheme == ThemeMode.light ? '☀' : '🌙';

        return Row(
          children: [
            Expanded(
              child: _topChipCompact(
                icon: Icons.language_rounded,
                value: langShort,
                onTap: () => _showLanguageSheet(t: t),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _topChipCompact(
                icon: Icons.color_lens_outlined,
                value: themeShort,
                onTap: () => _showThemeSheet(t: t),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _topChipCompact({
    required IconData icon,
    required String value,
    required VoidCallback onTap,
  }) {
    final bg = _isLight ? Colors.white : const Color(0xFF0F1425);
    final border = _fieldOutline;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _bankColor.withOpacity(_isLight ? 0.10 : 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _bankColor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: _font(context, 13, 12.2),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, color: _iconColor),
          ],
        ),
      ),
    );
  }

  void _showLanguageSheet({required AppLocalizations t}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ValueListenableBuilder<String>(
            valueListenable: langNotifier,
            builder: (_, __, ___) {
              final isLight = themeModeNotifier.value == ThemeMode.light;
              final bg = isLight ? Colors.white : const Color(0xFF0F1425);
              final border =
                  isLight ? const Color(0xFFE5E7EB) : const Color(0xFF2A355A);

              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 24,
                        color: Colors.black.withOpacity(0.22),
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sheetHeader(
                          title: t.language,
                          subtitle: _isAr
                              ? 'اختر لغة التطبيق'
                              : 'Choose app language',
                        ),
                        const SizedBox(height: 12),
                        _radioTile(
                          title: t.languageArabic,
                          subtitle: 'العربية',
                          selected: langNotifier.value != 'en',
                          onTap: () async {
                            await _setLanguage('ar');
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                        const SizedBox(height: 8),
                        _radioTile(
                          title: t.languageEnglish,
                          subtitle: 'English',
                          selected: langNotifier.value == 'en',
                          onTap: () async {
                            await _setLanguage('en');
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showThemeSheet({required AppLocalizations t}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (_, __, ___) {
              final isLight = themeModeNotifier.value == ThemeMode.light;
              final bg = isLight ? Colors.white : const Color(0xFF0F1425);
              final border =
                  isLight ? const Color(0xFFE5E7EB) : const Color(0xFF2A355A);

              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 24,
                        color: Colors.black.withOpacity(0.22),
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sheetHeader(
                          title: t.theme,
                          subtitle: _isAr
                              ? 'اختر مظهر التطبيق'
                              : 'Choose app appearance',
                        ),
                        const SizedBox(height: 12),
                        _radioTile(
                          title: t.themeLight,
                          subtitle: _isAr ? 'نهاري' : 'Light',
                          selected: themeModeNotifier.value == ThemeMode.light,
                          onTap: () async {
                            await _setTheme(ThemeMode.light);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                        const SizedBox(height: 8),
                        _radioTile(
                          title: t.themeDark,
                          subtitle: _isAr ? 'ليلي' : 'Dark',
                          selected: themeModeNotifier.value == ThemeMode.dark,
                          onTap: () async {
                            await _setTheme(ThemeMode.dark);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _sheetHeader({required String title, required String subtitle}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close_rounded, color: _iconColor),
          tooltip: _isAr ? 'إغلاق' : 'Close',
        ),
      ],
    );
  }

  Widget _radioTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final bg = selected
        ? _bankColor.withOpacity(_isLight ? 0.10 : 0.18)
        : Colors.transparent;

    final border = selected
        ? _bankColor.withOpacity(0.6)
        : (_isLight ? const Color(0xFFE5E7EB) : const Color(0xFF2A355A));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? _bankColor : _iconColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
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

  // ✅ حقل الهوية / الإقامة
  Widget _buildUsernameField({required AppLocalizations t}) {
    final raw = _getRealUsername()?.trim() ?? '';
    final normalized = _normalizeNumbers(raw).trim();
    final is10 = _looksLikeUsername10Digits(normalized);

    Widget? suffix;
    if (_checkingUsername) {
      suffix = SizedBox(
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _usernameController,
          focusNode: _usernameFocus,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          textAlign: _isAr ? TextAlign.right : TextAlign.left,
          inputFormatters: [
            const _EnglishDigitsOnlyFormatter(),
            LengthLimitingTextInputFormatter(10),
          ],
          maxLength: 10,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          autofillHints: const [AutofillHints.username],
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
          decoration: _loginFieldDecoration(
            labelText: t.loginIdentifierFieldLabel,
            hintText: null,
            prefixIcon: Icon(Icons.badge_outlined, color: _iconColor),
            suffixIcon: suffix,
          ),
          onTap: () {
            if (_maskedPrefillActive && !_usernameEdited) {
              _usernameEdited = true;
              _usernameController.clear();
              _resetDbFlags();
              setState(() {});
            }
          },
        ),
      ],
    );
  }

  // ✅ كلمة المرور
  Widget _buildPasswordField({required AppLocalizations t}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          obscureText: obscurePassword,
          keyboardType:
              kIsWeb ? TextInputType.text : TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          autofillHints: const [AutofillHints.password],
          enableSuggestions: false,
          autocorrect: false,
          inputFormatters: passwordArabicGuardFormatters(
            onArabicScriptBlocked: _schedulePasswordArabicDialog,
          ),
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
          decoration: _loginFieldDecoration(
            labelText: t.loginPasswordFieldShortLabel,
            hintText: null,
            hintFontSize: 16,
            prefixIcon: Icon(Icons.lock_outline, color: _iconColor),
            suffixIcon: ExcludeFocus(
              child: IconButton(
                icon: Icon(
                  obscurePassword ? Icons.visibility : Icons.visibility_off,
                  color: _iconColor,
                ),
                onPressed: () =>
                    setState(() => obscurePassword = !obscurePassword),
                tooltip: obscurePassword
                    ? (_isAr ? 'إظهار' : 'Show')
                    : (_isAr ? 'إخفاء' : 'Hide'),
              ),
            ),
          ),
        ),
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
          TextField(
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
                          const SizedBox(height: 16),
                          _dots(),
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

    return SizedBox(
      height: 560,
      child: PageView.builder(
        controller: _adsController,
        itemCount: _ads.length,
        onPageChanged: (i) => setState(() => _adsIndex = i),
        itemBuilder: (context, index) {
          final item = _ads[index];
          final title = _isAr ? item.titleAr : item.titleEn;
          final subtitle = _isAr ? item.subtitleAr : item.subtitleEn;

          return _PhoneMockup(
            theme: _currentTheme,
            title: title,
            subtitle: subtitle,
            imageAsset: item.assetImage,
            imageNetworkUrl: item.imageUrl,
            videoUrl: item.bestVideoUrl(),
            isAr: _isAr,
            adId: item.id,
          );
        },
      ),
    );
  }

  Widget _dots() {
    if (_ads.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_ads.length, (i) {
        final active = i == _adsIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 8,
          width: active ? 20 : 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: active
                ? _bankColor
                : (_isLight
                    ? const Color(0xFFBFD0FF)
                    : const Color(0xFF2B3A6B)),
          ),
        );
      }),
    );
  }

  Widget _blurCircle(Color color) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.12),
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
              color: Colors.white.withOpacity(0.06),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          isAr ? 'موثوق' : 'Verified',
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
                        color: Colors.black.withOpacity(0.12),
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
                              color: const Color(0xFF0F766E).withOpacity(0.12),
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
    final textDim =
        isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8);

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
                      color: Colors.black.withOpacity(0.06),
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
                    Icon(Icons.lock_rounded, size: 13, color: Colors.white.withOpacity(0.95)),
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
                Icon(Icons.forum_rounded, size: 14, color: _PhoneMockup._bankColor),
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
    final border =
        isLight ? const Color(0xFFE2E8F0) : const Color(0xFF2D3F66);

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
                          const Color(0xFF0F766E).withOpacity(0.35),
                          const Color(0xFF0A4D68).withOpacity(0.5),
                        ],
                      ),
                    ),
                    child: Align(
                      alignment:
                          isAr ? Alignment.topRight : Alignment.topLeft,
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
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
    final isLight = theme == ThemeMode.light;

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
                color: Colors.black.withOpacity(0.18),
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
