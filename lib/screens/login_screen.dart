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
import 'package:aqar_user/widgets/app_busy_indicator.dart';
import 'package:aqar_user/widgets/app_logo_loading.dart';
import 'package:aqar_user/widgets/inline_property_video.dart';
import 'package:aqar_user/widgets/field_group_frame.dart';
import 'package:aqar_user/widgets/app_about_credits.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_logo_image.dart';
import '../core/input/caps_lock_probe.dart';
import '../core/config/app_config.dart';
import '../core/input/password_arabic_script_guard.dart';
import '../core/session/app_session.dart';
import '../core/session/web_session_ttl.dart';
import '../core/theme/app_appearance_bridge.dart';
import '../core/session/return_after_auth.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/compound_display_name.dart';
import '../core/utils/dashboard_greeting.dart';
import '../services/connectivity_guard.dart';
import '../services/session_manager.dart';
import '../services/fast_login_service.dart';
import '../services/profile_compliance_service.dart';
import '../services/user_install_session_service.dart';
import '../core/navigation/post_auth_navigation.dart';
import '../core/government/nafath_models.dart';
import '../core/haptics/app_haptics.dart';
import '../services/nafath_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
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
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
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
  bool _capsLockPassword = false;
  bool _pendingCapsUi = false;
  Timer? _capsUiDebounce;

  /// آخر حرف لاتيني مكتوب: true=كبير → يظهر السهم، false=صغير → يختفي.
  bool? _lastLatinWasUpper;

  /// عند فشل lockModes على ويب الجوال: حالة يدوية بعد ضغط Caps Lock.
  bool? _capsLockLatched;
  bool _didAutoAdvanceToPassword = false;
  Timer? _capsResyncTimer;

  /// ويب سطح المكتب (ويندوز/ماك/لينكس).
  bool get _desktopWebCapsTextMode {
    if (!kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// ويب سطح المكتب العريض (>=700): نص Caps تحت الحقل.
  /// الجوال / ويب الجوال / التطبيق / الشاشات الصغيرة: سهم بجانب القفل فقط.
  bool _useCapsTextUnderField(BuildContext context) {
    if (!_desktopWebCapsTextMode) return false;
    return MediaQuery.sizeOf(context).width >= 700;
  }

  DateTime? _lastPasswordArabicDialogAt;

  String _packageVersionLine = '';

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

  void _notePasswordLatinCase(String text) {
    for (var i = text.length - 1; i >= 0; i--) {
      final c = text.codeUnitAt(i);
      if (c >= 65 && c <= 90) {
        _lastLatinWasUpper = true;
        return;
      }
      if (c >= 97 && c <= 122) {
        _lastLatinWasUpper = false;
        return;
      }
    }
  }

  bool? _readHardwareCaps() {
    try {
      return HardwareKeyboard.instance.lockModesEnabled
          .contains(KeyboardLockMode.capsLock);
    } catch (_) {
      return null;
    }
  }

  /// يستنتج Caps من حرف + Shift (موثوق على الويب بعد أول ضغطة).
  bool? _capsFromKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
    final ch = event.character;
    if (ch == null || ch.length != 1) return null;
    final cu = ch.codeUnitAt(0);
    final isUpper = cu >= 65 && cu <= 90;
    final isLower = cu >= 97 && cu <= 122;
    if (!isUpper && !isLower) return null;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    // بدون Shift: حرف كبير ⇒ Caps ON، صغير ⇒ OFF.
    // مع Shift: العكس (Shift+Caps يعطي صغيراً).
    if (!shift) return isUpper;
    return isLower;
  }

  void _applyCapsLockState(bool caps, {bool clearLatch = false}) {
    if (clearLatch) _capsLockLatched = null;
    if (!mounted || caps == _capsLockPassword) return;
    // ويب ويندوز/سطح المكتب: ثبّت النص تحت الحقل (تجنّب وميض probe/resync).
    if (_desktopWebCapsTextMode) {
      _pendingCapsUi = caps;
      _capsUiDebounce?.cancel();
      _capsUiDebounce = Timer(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        if (_pendingCapsUi == _capsLockPassword) return;
        setState(() => _capsLockPassword = _pendingCapsUi);
      });
      return;
    }
    setState(() => _capsLockPassword = caps);
  }

  void _syncCapsLockFromHardware({bool preferHardware = false}) {
    if (preferHardware) {
      _capsLockLatched = null;
    }

    final browser = probeBrowserCapsLock();
    final hardware = _readHardwareCaps();

    // ويب سطح المكتب: اعتمد DOM + استدلال الأحرف فقط (lockModes يُومض النص).
    if (_desktopWebCapsTextMode) {
      if (browser != null) {
        _applyCapsLockState(browser);
        return;
      }
      if (_lastLatinWasUpper != null) {
        _applyCapsLockState(_lastLatinWasUpper!);
      }
      return;
    }

    // لا تُصفّر الحالة عند التركيز قبل أي حدث لوحة — Caps قد يكون شغال مسبقاً.
    if (browser == null &&
        hardware == null &&
        _capsLockLatched == null &&
        _lastLatinWasUpper == null) {
      return;
    }

    var caps = false;
    if (browser != null) {
      caps = browser;
    } else if (hardware != null) {
      caps = hardware;
    } else if (_capsLockLatched != null) {
      caps = _capsLockLatched!;
    } else if (_lastLatinWasUpper == true) {
      caps = true;
    }

    // مصدر حقيقي يفوز دائماً (لا يطغى عليه استدلال حرف صغير).
    if (browser == true || hardware == true) {
      caps = true;
    } else if (browser == false || hardware == false) {
      caps = false;
      if (_lastLatinWasUpper == true && browser == null && hardware == false) {
        // لوحات جوال ناعمة قد تُبلّغ lockModes=false مع حرف كبير.
        caps = true;
      }
    }

    _applyCapsLockState(caps);
  }

  void _scheduleCapsResync() {
    _capsResyncTimer?.cancel();
    // ويب سطح المكتب: أقل إعادة مزامنة لتقليل وميض النص.
    final delays = _desktopWebCapsTextMode
        ? <int>[50, 180, 450]
        : <int>[0, 16, 48, 120, 280, 500, 900];
    var i = 0;
    void tick() {
      if (!mounted) return;
      _syncCapsLockFromHardware(preferHardware: true);
      i++;
      if (i >= delays.length) return;
      _capsResyncTimer = Timer(Duration(milliseconds: delays[i]), tick);
    }

    tick();
  }

  bool _loginHardwareCapsKeyHandler(KeyEvent event) {
    if (!_passwordFocus.hasFocus &&
        event.logicalKey != LogicalKeyboardKey.capsLock) {
      // حدّث كاش DOM حتى لو الحقل غير مركّز (مهم عند دخول الحقل وCaps شغال مسبقاً).
      if (kIsWeb && (event is KeyDownEvent || event is KeyUpEvent)) {
        probeBrowserCapsLock();
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.capsLock) {
      if (event is KeyDownEvent) {
        final hardwareOn = _readHardwareCaps() ?? false;
        final browserOn = probeBrowserCapsLock();
        // بدّل التوقّع يدوياً إن تأخرت المنصة؛ يُصحَّح بعد الإطار من المصدر الحقيقي.
        if (browserOn == null && _readHardwareCaps() == null) {
          _capsLockLatched = !(_capsLockPassword || hardwareOn);
        } else {
          _capsLockLatched = null;
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncCapsLockFromHardware(preferHardware: true);
        _scheduleCapsResync();
      });
      return false;
    }

    final inferred = _capsFromKeyEvent(event);
    if (inferred != null) {
      _lastLatinWasUpper = inferred;
      _capsLockLatched = null;
      _applyCapsLockState(inferred);
      return false;
    }

    if (event is KeyDownEvent || event is KeyUpEvent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncCapsLockFromHardware();
      });
    }
    return false;
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
    _enterCtrl.forward();

    _generateCaptcha();
    unawaited(_loadAds());

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

      // بعد 10 أرقام: الانتقال فوراً لحقل كلمة المرور (جوال/ويب/ويندوز).
      if (sanitized.length == 10) {
        if (!_didAutoAdvanceToPassword) {
          _didAutoAdvanceToPassword = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_sanitizeUsernameInput(_usernameController.text).length != 10) {
              return;
            }
            _passwordFocus.requestFocus();
          });
        }
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

    _passwordFocus.addListener(() {
      if (_passwordFocus.hasFocus) {
        _scrollLoginFieldIntoView(_passwordFieldKey);
        // لا تمسح الـ latch قبل قراءة حقيقية — Caps قد يكون شغال مسبقاً.
        refreshBrowserCapsLockCache();
        probeBrowserCapsLock();
        _syncCapsLockFromHardware(preferHardware: true);
        _scheduleCapsResync();
      } else {
        // عند مغادرة الحقل أعد المزامنة دون إجبار إخفاء الإشارة.
        _syncCapsLockFromHardware();
      }
    });
    // يفعّل مستمع DOM مبكراً على الويب.
    refreshBrowserCapsLockCache();
    probeBrowserCapsLock();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCapsLockFromHardware(preferHardware: true);
    });

    _usernameFocus.addListener(() {
      if (_usernameFocus.hasFocus) {
        _scrollLoginFieldIntoView(_usernameFieldKey);
      }
    });

    HardwareKeyboard.instance.addHandler(_loginHardwareCapsKeyHandler);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!_usernameFocus.hasFocus && !_passwordFocus.hasFocus) return;
    final key = _passwordFocus.hasFocus ? _passwordFieldKey : _usernameFieldKey;
    _scrollLoginFieldIntoView(key);
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

  void _scrollLoginFieldIntoView(GlobalKey key) {
    // ويب الجوال: تمريرة واحدة كافية — التكرار مع SoftKeyboardEnsureVisible كان يهز الحقل.
    void run([int attempt = 0]) {
      if (!mounted) return;
      final ctx = key.currentContext;
      if (ctx == null) {
        if (attempt < 2) {
          Future<void>.delayed(const Duration(milliseconds: 100), () {
            run(attempt + 1);
          });
        }
        return;
      }
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      if (inset < 8 && attempt == 0) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: inset > 0 ? 0.14 : 0.28,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }

    Future<void>.delayed(const Duration(milliseconds: 90), run);
    if (kIsWeb) {
      Future<void>.delayed(const Duration(milliseconds: 280), () => run(1));
    }
  }

  @override
  void dispose() {
    if (_routeAwareSubscribed) {
      appRouteObserver.unsubscribe(this);
      _routeAwareSubscribed = false;
    }
    _userCheckDebounce?.cancel();
    _capsResyncTimer?.cancel();
    _capsUiDebounce?.cancel();
    _shakeCtrl.dispose();
    _enterCtrl.dispose();
    _loginScrollCtrl.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _autofillUsernameMirror.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    HardwareKeyboard.instance.removeHandler(_loginHardwareCapsKeyHandler);
    WidgetsBinding.instance.removeObserver(this);
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

    var quick = false;
    try {
      final hasSession = Supabase.instance.client.auth.currentSession != null;
      if (hasSession) {
        quick = await FastLoginService.hasAnyLockEnabled();
      }
    } catch (_) {}

    String? resumeName;
    String? resumeUser;
    try {
      final resume = await FastLoginService.getResumeAccount();
      resumeName = (resume.displayName ?? '').trim();
      resumeUser = FastLoginService.normalizeDigits(
        (resume.username ?? '').trim(),
      );
      if (resumeUser.length < 10) resumeUser = null;
      if ((resumeName ?? '').isEmpty) resumeName = null;
    } catch (_) {}

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
      final dn = (prefs.getString('rememberDisplayName') ?? '').trim();
      _rememberDisplayName =
          dn.isEmpty ? null : CompoundDisplayName.normalize(dn);
      if ((_storedUsername ?? '').isNotEmpty) {
        _showRememberedIdentityChip = (_rememberDisplayName ?? '').isNotEmpty;
        _syncAutofillUsernameMirror();
        if (!_showRememberedIdentityChip) {
          _applyMaskedUsernamePrefill();
        } else {
          _maskedPrefillActive = true;
          _usernameEdited = false;
          _usernameController.clear();
        }
      }
    } else {
      // بدون تذكرني: لا تملأ اسم المستخدم من التخزين أو الاستئناف.
      await prefs.remove('username');
      await prefs.remove('rememberDisplayName');
      _storedUsername = null;
      _rememberDisplayName = null;
      _showRememberedIdentityChip = false;
      _maskedPrefillActive = false;
      _syncAutofillUsernameMirror();
      if (_usernameController.text.trim().isNotEmpty && !_usernameEdited) {
        _usernameController.clear();
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
    showDialog<void>(
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

    void dismissLoginOverlay() {
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

    final args = <String, dynamic>{
      'next': kIsWeb ? '/' : '/userDashboard',
      'nextArgs': <String, dynamic>{},
      'username': u,
      'deviceId': deviceId,
      'registerDeviceOnSuccess': !known,
      'backToLogin': true,
    };
    if (prefetchFullName != null && prefetchFullName.trim().isNotEmpty) {
      args['fullName'] = prefetchFullName.trim();
    }

    // إرسال الرمز دون انتظار — الانتقال لشاشة التحقق فوري؛ الشاشة تكمل الجلب إن لزم.
    unawaited(AuthService.requestOtpWithMessage(u));

    if (!mounted) return;

    // أغلق نافذة التحميل ثم انتقل لرمز التحقق مباشرة (بلا شاشة بيضاء).
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) rootNav.pop();

    // أبقِ نافذة «جاري تسجيل الدخول» فوق شاشة الدخول — بلا شاشة بيضاء وسيطة.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        settings: RouteSettings(name: '/verify', arguments: args),
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

                  // هاتف / ويب جوال: البطاقة بعرض الشاشة تقريباً؛ سطح المكتب يبقى ممركزاً.
                  final phoneLike = w < 720;
                  final padH = phoneLike ? (w < 360 ? 4.0 : 8.0) : 18.0;
                  final padV = phoneLike ? 6.0 : 18.0;
                  final cardMax = phoneLike
                      ? (w - padH * 2).clamp(280.0, w)
                      : 600.0;
                  final kb = MediaQuery.viewInsetsOf(context).bottom;

                  return ScrollConfiguration(
                    behavior: const _LoginScrollBehavior(),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        padH,
                        padV,
                        padH,
                        padV + kb + 16,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: cardMax),
                          child: _loginCard(
                            maxWidth: cardMax,
                            borderRadius: phoneLike ? 14 : 18,
                            t: t,
                            // التمرير الخارجي يرفع الحقول فوق لوحة المفاتيح.
                            allowVerticalScroll: false,
                          ),
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
              final dim = AppBranding.loginHeroLogoSize(context);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: _bankColor.withValues(alpha: 0.14),
                          blurRadius: 28,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: BrandingLogoImage(
                      width: dim,
                      height: dim,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorIcon: Icons.apartment_rounded,
                    ),
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
                AppBranding.welcomeHeadline(context, isAr: _isAr),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                  height: 1.2,
                ),
                maxLines: 2,
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
          // هوية الجلسة المفعّلة تُعرض في شاشة «مستخدم / ضيف» فقط — ليس فوق حقول الدخول.
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (context, child) => Transform.translate(
              offset: _shakeAnim.value,
              child: child,
            ),
            child: FieldGroupFrame(
              title: t.fieldGroupCredentialsTitle,
              titleTextAlign: TextAlign.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: AutofillGroup(
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: _buildUsernameField(t: t),
                      ),
                      const SizedBox(height: 10),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showQuickLoginEntry) ...[
                const SizedBox(height: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _busy ? null : _openQuickLogin,
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
                              child: const Icon(
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
          const SizedBox(height: 8),
          _buildNafathLoginButton(),
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
                backgroundColor: Colors.white,
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
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _packageVersionLine.isEmpty
                    ? const SizedBox.shrink()
                    : SelectableText(
                        _isAr
                            ? '${kIsWeb ? 'منصّة ويب' : 'تطبيق جوّال'} — الإصدار: $_packageVersionLine'
                            : '${kIsWeb ? 'Web' : 'Mobile app'} — Version: $_packageVersionLine',
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
              behavior: _LoginScrollBehavior(),
              child: SingleChildScrollView(
                controller: _loginScrollCtrl,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const ClampingScrollPhysics(),
                clipBehavior: Clip.hardEdge,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
                ),
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
                color: _bankColor.withValues(alpha: _isLight ? 0.10 : 0.18),
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
                        color: Colors.black.withValues(alpha: 0.22),
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
                        color: Colors.black.withValues(alpha: 0.22),
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
        ? _bankColor.withValues(alpha: _isLight ? 0.10 : 0.18)
        : Colors.transparent;

    final border = selected
        ? _bankColor.withValues(alpha: 0.6)
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

  Widget _buildForgotRememberRow({required AppLocalizations t}) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 340;
        final remember = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              value: rememberMe,
              onChanged: _busy
                  ? null
                  : (v) async {
                      final newVal = v ?? false;
                      setState(() => rememberMe = newVal);

                      if (!newVal) {
                        _maskedPrefillActive = false;
                        _storedUsername = null;
                        _rememberDisplayName = null;
                        _showRememberedIdentityChip = false;
                        _usernameEdited = false;
                        _usernameController.clear();
                        _syncAutofillUsernameMirror();
                        _resetDbFlags();
                        await _savePreferences();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _usernameFocus.requestFocus();
                        });
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
                    },
            ),
            Text(
              t.rememberMe,
              style: TextStyle(
                color: _textPrimary,
                fontSize: _font(context, 13, 12),
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );

        final forgot = TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _busy
              ? null
              : () async {
                  final okNet = await _ensureInternetOrAlert();
                  if (!mounted) return;
                  ConnectivityGuard.showOfflineSnackIfNeeded(context, okNet);
                  if (!okNet) return;
                  Navigator.pushNamed(context, '/resetPassword');
                },
          child: Text(
            t.forgotUsernameOrPassword,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: _font(context, 13.5, 11.5),
              color: _bankColor,
              height: 1.15,
            ),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              remember,
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: forgot,
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            remember,
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: forgot,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// زر نفاذ — عرض كامل، خلفية بيضاء (تحت تسجيل الدخول).
  Widget _buildNafathLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: _bankColor,
          backgroundColor: Colors.white,
          side: BorderSide(color: _fieldOutline, width: 1.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: (isBusy || _nafathBusy) ? null : _startNafathLogin,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _nafathBusy
              ? Row(
                  key: const ValueKey('nafath_loading'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: AppLogoLoading(compact: true, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isAr ? 'جاري الاتصال…' : 'Connecting…',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                )
              : Row(
                  key: const ValueKey('nafath_idle'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_user_outlined, color: _bankColor),
                    const SizedBox(width: 8),
                    Text(
                      _isAr ? 'نفاذ' : 'Nafath',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ✅ حقل الهوية / الإقامة — أو بطاقة الاسم الرباعي عند «تذكرني».
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
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
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
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            DashboardGreeting.partnerSalutationLine(
                              isAr: _isAr,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _rememberDisplayName!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.2,
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
            LengthLimitingTextInputFormatter(10),
          ],
          maxLength: 10,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
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

  // ✅ كلمة المرور
  Widget _buildPasswordField({required AppLocalizations t}) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // ويب سطح المكتب العريض: نص تحت الحقل. جوال/ضيق/تطبيق: سهم فقط بجانب القفل.
    final useCapsText = _useCapsTextUnderField(context);
    final showCapsGlyph = _capsLockPassword && !useCapsText;
    final showCapsText = _capsLockPassword && useCapsText;
    final capsColor =
        _isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24);

    Widget eyeButton() => IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            obscurePassword ? Icons.visibility : Icons.visibility_off,
            color: _iconColor,
          ),
          onPressed: () => setState(() => obscurePassword = !obscurePassword),
          tooltip: obscurePassword
              ? (_isAr ? 'إظهار' : 'Show')
              : (_isAr ? 'إخفاء' : 'Hide'),
        );

    Widget capsGlyph() => Tooltip(
          message: _isAr ? 'أحرف كبيرة مفعّلة (Caps Lock)' : 'Caps Lock is on',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: capsColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {},
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: capsColor.withValues(alpha: 0.6)),
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 18,
                    color: capsColor,
                  ),
                ),
              ),
            ),
          ),
        );

    final lockIcon = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Icon(Icons.lock_outline, color: _iconColor),
    );

    // العين في جهة، والقفل + السهم في الجهة المقابلة (لا يتكرّر السهم).
    late final Widget prefixIcon;
    late final Widget suffixIcon;
    late final BoxConstraints prefixConstraints;
    late final BoxConstraints suffixConstraints;

    if (rtl) {
      // العين يمين (prefix)، القفل/السهم يسار (suffix).
      prefixIcon = eyeButton();
      prefixConstraints = const BoxConstraints(minWidth: 46, minHeight: 46);
      if (showCapsGlyph) {
        suffixIcon = Row(
          mainAxisSize: MainAxisSize.min,
          children: [capsGlyph(), lockIcon],
        );
        suffixConstraints = const BoxConstraints(minWidth: 78, minHeight: 46);
      } else {
        suffixIcon = lockIcon;
        suffixConstraints = const BoxConstraints(minWidth: 46, minHeight: 46);
      }
    } else {
      // القفل/السهم يسار، العين يمين.
      if (showCapsGlyph) {
        prefixIcon = Row(
          mainAxisSize: MainAxisSize.min,
          children: [lockIcon, capsGlyph()],
        );
        prefixConstraints = const BoxConstraints(minWidth: 78, minHeight: 46);
      } else {
        prefixIcon = lockIcon;
        prefixConstraints = const BoxConstraints(minWidth: 46, minHeight: 46);
      }
      suffixIcon = eyeButton();
      suffixConstraints = const BoxConstraints(minWidth: 46, minHeight: 46);
    }

    return Column(
      key: _passwordFieldKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onKeyEvent: (node, event) {
            final inferred = _capsFromKeyEvent(event);
            if (inferred != null) {
              _lastLatinWasUpper = inferred;
              _applyCapsLockState(inferred, clearLatch: true);
            } else {
              _syncCapsLockFromHardware();
            }
            return KeyEventResult.ignored;
          },
          child: AqarTextField(
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
            cursorColor: _bankColor,
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
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              prefixIconConstraints: prefixConstraints,
              suffixIconConstraints: suffixConstraints,
            ),
            onTap: () {
              if (!_passwordFocus.hasFocus) {
                _passwordFocus.requestFocus();
              }
              _syncCapsLockFromHardware(preferHardware: true);
              _scheduleCapsResync();
              _scrollLoginFieldIntoView(_passwordFieldKey);
            },
            onChanged: (v) {
              _notePasswordLatinCase(v);
              // ويب ويندوز/سطح المكتب: يظهر تنبيه Caps مع حرف كبير ويختفي مع صغير.
              // الجوال: السهم يتبع نفس المنطق مع تفضيل مصدر العتاد عند التعارض.
              if (_lastLatinWasUpper == true) {
                _applyCapsLockState(true, clearLatch: true);
              } else if (_lastLatinWasUpper == false) {
                final shift = HardwareKeyboard.instance.isShiftPressed;
                if (shift) {
                  // Shift + حرف صغير ⇒ Caps Lock مفعّل.
                  _applyCapsLockState(true, clearLatch: true);
                } else {
                  // حرف صغير بدون Shift ⇒ Caps OFF (نص ويندوز أو سهم الجوال).
                  _applyCapsLockState(false, clearLatch: true);
                }
              } else {
                _syncCapsLockFromHardware();
              }
            },
          ),
        ),
        if (showCapsText) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
            child: Text(
              _isAr
                  ? 'تنبيه: لوحة المفاتيح على أحرف كبيرة (Caps Lock).'
                  : 'Note: Caps Lock is on.',
              style: TextStyle(
                color: capsColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
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
