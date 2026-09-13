import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show langNotifier, themeModeNotifier;
import '../core/session/user_appearance_session.dart';
import '../core/session/return_after_auth.dart';
import '../services/auth_service.dart';
import '../services/fast_login_service.dart';
import '../services/account_completion_service.dart';
import '../core/auth/auth_local_sign_out.dart';
import '../core/auth/inactivity_auth_landing.dart';
import '../core/auth/auth_challenge_service.dart';
import '../core/auth/login_success_banner.dart';
import '../core/auth/post_login_security_guard.dart';
import '../services/session_tracking_service.dart';
import '../core/gestures/app_keyboard_stable.dart';
import '../core/theme/app_text_scale.dart';
import '../widgets/auth_top_chrome.dart';
import '../widgets/login_known_user_hero.dart';
import '../widgets/nafath_login_sheet.dart';
import '../widgets/caps_aware_password_field.dart';
import '../core/auth/login_method_policy.dart';
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
  FastUnlockMode _unlockMode = FastUnlockMode.password;
  int _pinLen = 6;
  int _pinLockSec = 0;

  String _pin = '';
  String _displayName = '';
  String? _username;
  LoginMethodSnapshot _methodSnapshot = LoginMethodSnapshot(
    host: LoginMethodPolicy.detectHost(),
    trustedThisInstall: true,
    firstPasswordDone: true,
    hasSession: true,
    hasKnownUser: true,
    pinEnabled: false,
    faceEnabled: false,
    fingerprintEnabled: false,
    preferPassword: false,
    unlockMode: FastUnlockMode.password,
  );

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (kIsWeb) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      final hasSession = Supabase.instance.client.auth.currentSession != null;
      if (!hasSession) {
        final stay = InactivityAuthLanding.isActive ||
            await FastLoginService.canSoftLockSession();
        if (!stay) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/login');
          return;
        }
      }

      FastLoginService.clearRuntimeUnlock();
      await _loadIdentity();
      await _loadPinConfig();
      await _initBiometricsAndMaybeAutoAuth();
      await _refreshMethodSnapshot();
      if (_passwordMode && mounted) {
        _passwordFocus.requestFocus();
      }
    });
  }

  Future<void> _refreshMethodSnapshot() async {
    final snap = await LoginMethodPolicy.resolve(
      hasKnownUser:
          _displayName.trim().isNotEmpty || (_username ?? '').isNotEmpty,
    );
    if (!mounted) return;
    setState(() => _methodSnapshot = snap.copyWith(
          hasKnownUser:
              _displayName.trim().isNotEmpty || (_username ?? '').isNotEmpty,
        ));
  }

  Future<void> _loadIdentity() async {
    var name = (await FastLoginService.getDisplayName() ?? '').trim();
    var uid = await FastLoginService.getUsernameNationalId();
    if (name.isEmpty || (uid ?? '').trim().isEmpty) {
      try {
        final resume = await FastLoginService.getResumeAccount();
        if (name.isEmpty) name = (resume.displayName ?? '').trim();
        if ((uid ?? '').trim().isEmpty) uid = resume.username;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _displayName = name;
      _username = uid;
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
      setState(() {
        _showBio = false;
        _unlockMode = _pinEnabled
            ? FastUnlockMode.pinOnly
            : FastUnlockMode.password;
        if (!_pinEnabled) _passwordMode = true;
      });
      return;
    }

    try {
      final mode = await FastLoginService.resolveUnlockMode();
      final enabled = mode == FastUnlockMode.faceOnly ||
          mode == FastUnlockMode.fingerprintOnly ||
          mode == FastUnlockMode.biometricOnly ||
          mode == FastUnlockMode.pinWithBiometric;
      final preferPassword = await FastLoginService.preferPasswordSurface();

      if (!mounted) return;
      setState(() {
        _unlockMode = mode;
        _showBio = enabled;
        if (preferPassword) {
          _passwordMode = true;
        } else if (mode == FastUnlockMode.faceOnly ||
            mode == FastUnlockMode.fingerprintOnly ||
            mode == FastUnlockMode.biometricOnly) {
          _passwordMode = false;
          _pinEnabled = false;
        } else if (mode == FastUnlockMode.pinOnly ||
            mode == FastUnlockMode.pinWithBiometric) {
          _passwordMode = false;
        } else {
          _passwordMode = true;
        }
      });

      if (_showBio && !_passwordMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await Future<void>.delayed(const Duration(milliseconds: 280));
          if (!mounted) return;
          await _tryBiometric(fromAuto: true);
        });
      } else if (_passwordMode && mounted) {
        _passwordFocus.requestFocus();
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
    final retry = await showAppDialog<bool>(
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
    final confirmed = await AuthChallengeService.confirmTrustedNativeUnlock();
    if (!confirmed.fullyAuthenticated) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    FastLoginService.markRuntimeUnlocked();
    await AccountCompletionService.clearEnrollmentDeferred();
    if (!mounted) return;
    final isAr = langNotifier.value != 'en';
    await LoginSuccessBanner.showOrQueue(null, isAr: isAr);
    if (!mounted) return;
    await ReturnAfterAuth.navigatePostAuthOrDefault(
      Navigator.of(context),
      '/userDashboard',
    );

    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final username = (_username ?? '').trim();
    if (uid.isNotEmpty) {
      unawaited(
        PostLoginSecurityGuard.run(
          uid: uid,
          usernameNationalId: username,
          displayName: _displayName,
          loginMethod: loginMethod,
          isAr: isAr,
          authEntryRoute: '/fastLogin',
        ),
      );
    } else {
      unawaited(
        SessionTrackingService.recordLoginStart(
          Supabase.instance.client,
          loginMethod: loginMethod,
        ),
      );
    }
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

  Future<void> _switchToPasswordSurface() async {
    if (_busy) return;
    try {
      await FastLoginService.setPreferPasswordSurface(true);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _passwordMode = true;
      _err = false;
      _pin = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  Future<void> _switchToBiometricSurface() async {
    if (_busy) return;
    try {
      await FastLoginService.setPreferPasswordSurface(false);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _passwordMode = false;
      _err = false;
    });
    if (_showBio) {
      await _tryBiometric(fromAuto: true);
    }
  }

  Future<void> _startNafathFromLock() async {
    if (_busy) return;
    await NafathLoginSheet.show(
      context,
      isAr: _isAr,
      initialNationalId: (_username ?? '').trim(),
    );
  }

  Future<void> _forgotPasscode() async {
    if (_busy) return;

    final ok = await showAppDialog<bool>(
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
      await FastLoginService.clearSecretsKeepResume();
      await FastLoginService.setPreferPasswordSurface(true);
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

  Future<void> _leaveForAnotherUser() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await FastLoginService.clearAll();
      try {
        if (Supabase.instance.client.auth.currentSession != null) {
          await AuthLocalSignOut.signOutLocal(Supabase.instance.client);
        }
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('username');
        await prefs.remove('rememberDisplayName');
        await prefs.setBool('rememberMe', false);
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
      isLight ? const Color(0xFFF5F7FA) : const Color(0xFF071210);

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
    switch (_unlockMode) {
      case FastUnlockMode.faceOnly:
        return Icons.face_retouching_natural_rounded;
      case FastUnlockMode.fingerprintOnly:
        return Icons.fingerprint_rounded;
      case FastUnlockMode.biometricOnly:
      case FastUnlockMode.pinWithBiometric:
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          return Icons.face_rounded;
        }
        return Icons.fingerprint_rounded;
      default:
        return Icons.fingerprint_rounded;
    }
  }

  String _bioPrimaryLabel() {
    switch (_unlockMode) {
      case FastUnlockMode.faceOnly:
        return _isAr ? 'فتح ببصمة الوجه' : 'Unlock with Face ID';
      case FastUnlockMode.fingerprintOnly:
        return _isAr ? 'فتح ببصمة الإصبع' : 'Unlock with fingerprint';
      default:
        return _isAr ? 'التحقق بالبصمة أو الوجه' : 'Use biometrics';
    }
  }

  String _bioHint() {
    switch (_unlockMode) {
      case FastUnlockMode.faceOnly:
        return _isAr
            ? 'انظر إلى الجهاز — يتم الدخول تلقائياً بعد التعرف'
            : 'Look at the device — you will sign in automatically';
      case FastUnlockMode.fingerprintOnly:
        return _isAr
            ? 'مرّر إصبعك على المستشعر للدخول مباشرة'
            : 'Place your finger on the sensor to sign in';
      default:
        return _isAr
            ? 'استخدم البصمة أو الوجه للدخول مباشرة'
            : 'Use fingerprint or face to sign in';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([langNotifier, themeModeNotifier]),
      builder: (context, _) {
        final isLight =
            UserAppearanceSession.resolvesLight(themeModeNotifier.value);
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
        final errColor = Theme.of(context).colorScheme.error;

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
                      child: CapsAwarePasswordField(
                        controller: _passwordCtrl,
                        focusNode: _passwordFocus,
                        obscureText: _obscure,
                        onToggleObscure: () =>
                            setState(() => _obscure = !_obscure),
                        enabled: !_busy,
                        isAr: _isAr,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitPassword(),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: _isAr ? 'كلمة المرور' : 'Password',
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: _busy
                            ? null
                            : () => _tryBiometric(fromAuto: false),
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accentBio.withValues(alpha: 0.12),
                            border: Border.all(
                              color: _accentBio.withValues(alpha: 0.55),
                              width: 2.2,
                            ),
                          ),
                          child: Icon(
                            _bioIcon(),
                            size: 56,
                            color: _accentBio,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _bioHint(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: sub,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentBio,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                      onPressed:
                          _busy ? null : () => _tryBiometric(fromAuto: false),
                      icon: Icon(_bioIcon()),
                      label: Text(
                        _bioPrimaryLabel(),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
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
                resizeToAvoidBottomInset: false,
                body: AppKeyboardStableScope(
                  child: SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 6),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxCard),
                            child: AuthTopChrome(
                              snapshot: _methodSnapshot.copyWith(
                                hasKnownUser:
                                    _displayName.trim().isNotEmpty ||
                                        (_username ?? '').isNotEmpty,
                                preferPassword: _passwordMode,
                              ),
                              busy: _busy,
                              onSelect: (kind) {
                                switch (kind) {
                                  case LoginMethodKind.password:
                                    unawaited(_switchToPasswordSurface());
                                    break;
                                  case LoginMethodKind.nafath:
                                    unawaited(_startNafathFromLock());
                                    break;
                                  case LoginMethodKind.pin:
                                  case LoginMethodKind.face:
                                  case LoginMethodKind.fingerprint:
                                    unawaited(_switchToBiometricSurface());
                                    break;
                                  case LoginMethodKind.anotherUser:
                                    unawaited(_leaveForAnotherUser());
                                    break;
                                }
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              hPad,
                              0,
                              hPad,
                              20 + bottomInset,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: maxCard),
                                child: Column(
                                  children: [
                                    const LoginBrandHero(),
                                    const SizedBox(height: 12),
                                    LoginKnownUserHero(
                                      isAr: _isAr,
                                      displayName: _displayName,
                                      accent: _brand,
                                      compact: isNarrow,
                                      showPasswordPrompt: _passwordMode,
                                    ),
                                    busyBar,
                                    const SizedBox(height: 14),
                                    if (_passwordMode) ...[
                                      passwordBlock,
                                    ] else if (_pinEnabled) ...[
                                      dotsRow,
                                      const SizedBox(height: 12),
                                      keypad,
                                    ] else ...[
                                      bioOnlyBlock,
                                    ],
                                    const SizedBox(height: 4),
                                    if (!_passwordMode &&
                                        (_pinEnabled || _showBio))
                                      TextButton(
                                        onPressed:
                                            _busy ? null : _forgotPasscode,
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
                                  ],
                                ),
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
        );
      },
    );
  }
}
