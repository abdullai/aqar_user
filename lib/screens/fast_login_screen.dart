// lib/screens/fast_login_screen.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show langNotifier, setAppLang, themeModeNotifier;
import '../core/session/return_after_auth.dart';
import '../core/theme/app_text_scale.dart';
import '../services/auth_service.dart';
import '../services/fast_login_service.dart';
import '../services/account_completion_service.dart';
import '../core/auth/auth_local_sign_out.dart';
import '../services/session_tracking_service.dart';
import '../core/branding/branding_logo_image.dart';
import '../widgets/session_identity_panel.dart';
import '../core/haptics/app_haptics.dart';
import '../theme.dart' show AqarAuthScrollBehavior;

/// شاشة قفل الجلسة بعد الخمول: PIN / بصمة / كلمة المرور — ببطاقة هوية مرتبة.
class FastLoginScreen extends StatefulWidget {
  const FastLoginScreen({super.key});

  @override
  State<FastLoginScreen> createState() => _FastLoginScreenState();
}

class _FastLoginScreenState extends State<FastLoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _brand = Color(0xFF0F766E);
  static const Color _accentBio = Color(0xFF8B1538);

  bool _busy = false;
  bool _err = false;
  bool _showBio = false;
  bool _pinEnabled = true;
  bool _passwordMode = false;
  int _pinLen = 6;
  int _pinLockSec = 0;

  String _pin = '';
  String _displayName = '';
  String _maskedId = '';
  String? _username;

  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  late final AnimationController _shakeCtrl;

  bool get _isAr => langNotifier.value != 'en';
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    final hasSession = Supabase.instance.client.auth.currentSession != null;
    if (!hasSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }

    FastLoginService.clearRuntimeUnlock();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadIdentity();
      await _loadPinConfig();
      await _initBiometricsAndMaybeAutoAuth();
      if (_passwordMode && mounted) {
        _passwordFocus.requestFocus();
      }
    });
  }

  Future<void> _loadIdentity() async {
    final name = (await FastLoginService.getDisplayName() ?? '').trim();
    final uid = await FastLoginService.getUsernameNationalId();
    if (!mounted) return;
    setState(() {
      _displayName = name;
      _username = uid;
      _maskedId = FastLoginService.maskNationalId(uid);
    });
  }

  Future<void> _loadPinConfig() async {
    final pinOn = await FastLoginService.isPinEnabled();
    final len = pinOn ? await FastLoginService.storedPinLength() : 0;
    final locked = await FastLoginService.isPinTemporarilyLocked();
    final rem = locked ? await FastLoginService.pinLockRemainingSeconds() : 0;
    if (!mounted) return;
    setState(() {
      _pinEnabled = pinOn;
      _pinLen = len.clamp(4, 8);
      _pinLockSec = rem;
      // بدون PIN/بصمة: فتح بكلمة المرور لنفس الحساب (اسم المستخدم ثابت).
      _passwordMode = !pinOn;
    });
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _initBiometricsAndMaybeAutoAuth() async {
    if (!_isMobile) {
      if (!mounted) return;
      setState(() => _showBio = false);
      return;
    }

    try {
      final enabled = await FastLoginService.hasAnyBiometricUnlockConfigured();

      if (!mounted) return;
      setState(() {
        _showBio = enabled;
        if (enabled && !_pinEnabled) {
          _passwordMode = false;
        }
      });

      if (_showBio) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await _tryBiometric(fromAuto: true);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _showBio = false);
    }
  }

  void _triggerErrorFeedback() {
    AppHaptics.medium();
    _shakeCtrl.forward(from: 0);
  }

  Future<void> _showBioRetryDialog() async {
    if (!mounted) return;
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'لم يتم التحقق' : 'Not verified'),
        content: Text(
          _isAr
              ? 'لم نتمكن من التحقق بالبصمة أو الوجه. يمكنك المحاولة مرة أخرى أو إدخال رمز الدخول السريع.'
              : 'Biometric verification failed. Try again or enter your PIN.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'محاولة أخرى' : 'Try again'),
          ),
        ],
      ),
    );
    if (retry == true && mounted) {
      await _tryBiometric(fromAuto: false);
    }
  }

  Future<void> _tryBiometric({required bool fromAuto}) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _err = false;
    });

    final ok = await FastLoginService.authenticateBiometric(isAr: _isAr);

    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      await _goUnlockedHome(loginMethod: 'biometric');
    } else {
      setState(() => _err = true);
      _triggerErrorFeedback();
      if (!fromAuto) await _showBioRetryDialog();
    }
  }

  Future<void> _goUnlockedHome({required String loginMethod}) async {
    FastLoginService.markRuntimeUnlocked();
    // دخول سريع = تسجيل دخول جديد من منظور بوابة الاستكمال.
    await AccountCompletionService.clearEnrollmentDeferred();
    if (!mounted) return;
    await SessionTrackingService.recordLoginStart(
      Supabase.instance.client,
      loginMethod: loginMethod,
    );
    if (!mounted) return;
    await ReturnAfterAuth.navigatePostAuthOrDefault(
      Navigator.of(context),
      '/userDashboard',
    );
  }

  void _pressDigit(String d) async {
    if (_busy || !_pinEnabled || _pinLockSec > 0) return;
    if (_pin.length >= _pinLen) return;

    setState(() {
      _pin += d;
      _err = false;
    });

    AppHaptics.selection();

    if (_pin.length == _pinLen) {
      _submitPin();
    }
  }

  void _backspace() {
    if (_busy || !_pinEnabled) return;
    if (_pin.isEmpty) return;

    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _err = false;
    });

    AppHaptics.selection();
  }

  Future<void> _submitPin() async {
    if (_busy || !_pinEnabled) return;

    if (await FastLoginService.isPinTemporarilyLocked()) {
      final rem = await FastLoginService.pinLockRemainingSeconds();
      if (!mounted) return;
      setState(() {
        _err = true;
        _pin = '';
        _pinLockSec = rem;
      });
      _triggerErrorFeedback();
      return;
    }

    final pin = FastLoginService.normalizeDigits(_pin);
    if (pin.length != _pinLen) {
      setState(() => _err = true);
      _triggerErrorFeedback();
      return;
    }

    setState(() {
      _busy = true;
      _err = false;
    });

    final ok = await FastLoginService.verifyPin(pin);

    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      await _goUnlockedHome(loginMethod: 'pin_fast');
    } else {
      final rem = await FastLoginService.pinLockRemainingSeconds();
      if (!mounted) return;
      setState(() {
        _err = true;
        _pin = '';
        _pinLockSec = rem;
      });
      _triggerErrorFeedback();
    }
  }

  Future<void> _submitPassword() async {
    if (_busy) return;
    final username = (_username ?? '').trim();
    final password = _passwordCtrl.text;
    if (username.length < 10 || password.isEmpty) {
      setState(() => _err = true);
      _triggerErrorFeedback();
      return;
    }

    setState(() {
      _busy = true;
      _err = false;
    });

    final result = await AuthService.login(
      username: username,
      password: password,
      lang: _isAr ? 'ar' : 'en',
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (result.ok) {
      await _goUnlockedHome(loginMethod: 'password_unlock');
    } else {
      setState(() => _err = true);
      _triggerErrorFeedback();
    }
  }

  Future<void> _forgotPasscode() async {
    if (_busy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'تسجيل الدخول بالحساب' : 'Sign in with password'),
        content: Text(
          _isAr
              ? 'سيتم إيقاف الدخول السريع على هذا الجهاز وستنتقل لشاشة إدخال اسم المستخدم وكلمة المرور (أو استعادة كلمة المرور).'
              : 'Quick unlock will be turned off on this device. You will use your username and password (or password recovery).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'رجوع' : 'Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'متابعة' : 'Continue'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await FastLoginService.clearAll();
      try {
        final auth = Supabase.instance.client.auth;
        if (auth.currentSession != null) {
          await AuthLocalSignOut.signOutLocal(Supabase.instance.client);
        }
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  Future<void> _signOutCompletely() async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'تسجيل الخروج' : 'Sign out'),
        content: Text(
          _isAr
              ? 'هل تريد الخروج من الحساب بالكامل؟'
              : 'Sign out completely?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'خروج' : 'Sign out'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await FastLoginService.clearAll();
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  Color _onBg(bool isLight) => isLight ? const Color(0xFF0B1220) : Colors.white;
  Color _sub(bool isLight) =>
      isLight ? const Color(0xFF5B6475) : const Color(0xFFB8C0D4);
  Color _bg(bool isLight) =>
      isLight ? const Color(0xFFF5F7FA) : const Color(0xFF0E0F13);

  Widget _dot({
    required bool filled,
    required bool isLight,
    required double size,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      margin: EdgeInsets.symmetric(horizontal: size * 0.35),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? _brand
            : (isLight ? const Color(0xFFE5E7EB) : const Color(0xFF2A355A)),
      ),
    );
  }

  Widget _keyButton({
    required Widget child,
    required VoidCallback? onTap,
    required bool isLight,
    Color? highlight,
    String? semanticsLabel,
  }) {
    final border = isLight ? const Color(0xFFE5E7EB) : const Color(0xFF22283A);
    final surface = isLight ? Colors.white : const Color(0xFF141722);

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: highlight ?? border,
                width: highlight != null ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }

  IconData _bioIcon() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return Icons.face_rounded;
    }
    return Icons.fingerprint_rounded;
  }

  String _dateLine(String localeName) {
    final now = DateTime.now();
    try {
      final day = DateFormat.EEEE(localeName).format(now);
      final md = DateFormat.MMMd(localeName).format(now);
      return '$day، $md';
    } catch (_) {
      return DateFormat.yMMMEd().format(now);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([langNotifier, themeModeNotifier]),
      builder: (context, _) {
        final isLight = themeModeNotifier.value == ThemeMode.light;
        final size = MediaQuery.sizeOf(context);
        final shortest = size.shortestSide;
        final width = size.width;
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final isNarrow = width < 520;
        final isWideWeb = kIsWeb && width >= 720;

        final maxCard = isWideWeb ? 460.0 : (isNarrow ? double.infinity : 420.0);
        final hPad = isNarrow ? 14.0 : 22.0;
        final dotSize = shortest < 360 ? 11.0 : 13.0;
        final keyTextSize = shortest < 360 ? 20.0 : 22.0;
        final gridHPad = shortest < 360 ? 8.0 : 16.0;

        final bg = _bg(isLight);
        final onBg = _onBg(isLight);
        final sub = _sub(isLight);
        final localeName = _isAr ? 'ar' : 'en';
        final errColor = Theme.of(context).colorScheme.error;

        final statusLine = _pinEnabled
            ? (_pinLockSec > 0
                ? (_isAr
                    ? 'محظور مؤقتاً ($_pinLockSec ث)'
                    : 'Temporarily locked (${_pinLockSec}s)')
                : (_isAr ? 'أدخل رمز PIN' : 'Enter PIN'))
            : (_showBio
                ? (_isAr ? 'بصمة / وجه' : 'Biometrics')
                : (_isAr ? 'أدخل كلمة المرور' : 'Enter password'));

        final keypad = Directionality(
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(
            builder: (context, c) {
              final font = TextStyle(
                fontSize: keyTextSize,
                fontWeight: FontWeight.w900,
                color: onBg,
              );

              Widget digit(String v) => _keyButton(
                    isLight: isLight,
                    semanticsLabel: 'Digit $v',
                    onTap: _busy || _pinLockSec > 0
                        ? null
                        : () => _pressDigit(v),
                    child: Text(v, style: font),
                  );

              Widget bioKey() {
                if (!_showBio) return const SizedBox.shrink();
                return _keyButton(
                  isLight: isLight,
                  highlight: _accentBio.withValues(alpha: 0.85),
                  semanticsLabel: 'Biometric',
                  onTap: _busy ? null : () => _tryBiometric(fromAuto: false),
                  child: Icon(_bioIcon(), size: 28, color: _accentBio),
                );
              }

              Widget backKey() => _keyButton(
                    isLight: isLight,
                    semanticsLabel: 'Backspace',
                    onTap: _busy ? null : _backspace,
                    child:
                        Icon(Icons.backspace_outlined, color: onBg, size: 24),
                  );

              return GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                padding: EdgeInsets.symmetric(horizontal: gridHPad),
                childAspectRatio: isNarrow ? 1.35 : 1.2,
                children: [
                  for (var i = 1; i <= 9; i++) digit('$i'),
                  bioKey(),
                  digit('0'),
                  backKey(),
                ],
              );
            },
          ),
        );

        final identity = SessionIdentityPanel(
          isAr: _isAr,
          displayName: _displayName,
          maskedId: _maskedId,
          statusLabel: statusLine,
          accent: _brand,
          compact: isNarrow,
          tableOnly: true,
        );

        final dotsRow = _pinEnabled
            ? AnimatedBuilder(
                animation: _shakeCtrl,
                builder: (context, child) {
                  final t = _shakeCtrl.value;
                  final dx =
                      _err ? (8.0 * (1 - t) * math.sin(t * 18.0)) : 0.0;
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: Column(
                  children: [
                    Directionality(
                      textDirection:
                          _isAr ? TextDirection.rtl : TextDirection.ltr,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _pinLen,
                          (i) => _dot(
                            filled: i < _pin.length,
                            isLight: isLight,
                            size: dotSize,
                          ),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _err
                          ? Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _pinLockSec > 0
                                      ? (_isAr
                                          ? 'محظور $_pinLockSec ثانية'
                                          : 'Locked for $_pinLockSec s')
                                      : (_isAr
                                          ? 'رمز غير صحيح'
                                          : 'Wrong passcode'),
                                  key: const ValueKey('err'),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: errColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox(height: 22, key: ValueKey('noerr')),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink();

        final passwordBlock = _passwordMode
            ? AnimatedBuilder(
                animation: _shakeCtrl,
                builder: (context, child) {
                  final t = _shakeCtrl.value;
                  final dx =
                      _err ? (8.0 * (1 - t) * math.sin(t * 18.0)) : 0.0;
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _err
                              ? errColor
                              : (isLight
                                  ? const Color(0xFFD1D5DB)
                                  : const Color(0xFF2A355A)),
                        ),
                        color: isLight ? Colors.white : const Color(0xFF141722),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextField(
                        controller: _passwordCtrl,
                        focusNode: _passwordFocus,
                        obscureText: _obscure,
                        enabled: !_busy,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitPassword(),
                        inputFormatters: const [
                          // keep password as typed
                        ],
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText:
                              _isAr ? 'كلمة المرور' : 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_err) ...[
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isAr
                              ? 'كلمة المرور غير صحيحة'
                              : 'Wrong password',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            color: errColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _busy ? null : _submitPassword,
                      style: FilledButton.styleFrom(
                        backgroundColor: _brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _isAr ? 'فتح الجلسة' : 'Unlock session',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink();

        final bioOnlyBlock = (!_pinEnabled && _showBio && !_passwordMode)
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accentBio,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                  onPressed:
                      _busy ? null : () => _tryBiometric(fromAuto: false),
                  icon: Icon(_bioIcon()),
                  label: Text(
                    _isAr
                        ? 'التحقق بالبصمة أو الوجه'
                        : 'Use biometrics',
                  ),
                ),
              )
            : const SizedBox.shrink();

        final busyBar = _busy
            ? Padding(
                padding: const EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(
                  minHeight: 2.5,
                  borderRadius: BorderRadius.circular(99),
                  color: _brand,
                  backgroundColor: _brand.withValues(alpha: 0.15),
                ),
              )
            : const SizedBox(height: 6);

        return UnscaledTextScope(
          child: Directionality(
            textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
            child: ScrollConfiguration(
              behavior: const AqarAuthScrollBehavior(),
              child: Scaffold(
                backgroundColor: bg,
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      hPad,
                      8,
                      hPad,
                      20 + bottomInset,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxCard),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setAppLang(
                                            _isAr ? 'en' : 'ar',
                                          ),
                                  child: Text(
                                    _isAr ? 'English' : 'العربية',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _brand,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: _isAr ? 'خروج' : 'Sign out',
                                  onPressed:
                                      _busy ? null : _signOutCompletely,
                                  icon: const Icon(Icons.logout_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            BrandingLogoImage(
                              size: shortest < 360 ? 88 : 112,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _dateLine(localeName),
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: sub,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            identity,
                            busyBar,
                            const SizedBox(height: 14),
                            if (_pinEnabled) ...[
                              dotsRow,
                              const SizedBox(height: 12),
                              keypad,
                            ] else if (_passwordMode) ...[
                              passwordBlock,
                            ] else ...[
                              bioOnlyBlock,
                            ],
                            const SizedBox(height: 4),
                            if (_pinEnabled || _showBio)
                              TextButton(
                                onPressed: _busy ? null : _forgotPasscode,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _isAr
                                        ? 'نسيت رمز الدخول؟'
                                        : 'Forgot passcode?',
                                    maxLines: 1,
                                    softWrap: false,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _brand,
                                    ),
                                  ),
                                ),
                              ),
                            if (_passwordMode && (_username ?? '').isNotEmpty)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () {
                                        setState(() {
                                          _passwordMode = false;
                                          // إذا لا يوجد قفل، العودة لكلمة المرور فقط
                                          if (!_pinEnabled && !_showBio) {
                                            _passwordMode = true;
                                          }
                                        });
                                        _forgotPasscode();
                                      },
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _isAr
                                        ? 'حساب آخر / استعادة'
                                        : 'Another account / recover',
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: sub,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
