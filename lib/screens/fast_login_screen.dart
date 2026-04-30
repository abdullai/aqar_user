// lib/screens/fast_login_screen.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart' show langNotifier, setAppLang, themeModeNotifier;
import '../core/session/return_after_auth.dart';
import '../core/theme/app_text_scale.dart';
import '../services/fast_login_service.dart';
import '../widgets/app_logo_loading.dart';
import '../core/haptics/app_haptics.dart';

/// شاشة قفل تطبيقي (PIN / بصمة) بأسلوب قريب من تطبيقات البنوك.
class FastLoginScreen extends StatefulWidget {
  const FastLoginScreen({super.key});

  @override
  State<FastLoginScreen> createState() => _FastLoginScreenState();
}

class _FastLoginScreenState extends State<FastLoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _brand = Color(0xFF0F766E);
  /// لون مميز لزر البيومتري (قريب من واجهات البنوك).
  static const Color _accentBio = Color(0xFF8B1538);

  bool _busy = false;
  bool _err = false;
  bool _showBio = false;
  bool _pinEnabled = true;
  int _pinLen = 6;

  String _pin = '';

  late final Future<String?> _displayNameFuture;
  late final AnimationController _shakeCtrl;

  bool get _isAr => langNotifier.value != 'en';
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();

    _displayNameFuture = FastLoginService.getDisplayName();

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
      await _loadPinConfig();
      await _initBiometricsAndMaybeAutoAuth();
    });
  }

  Future<void> _loadPinConfig() async {
    final pinOn = await FastLoginService.isPinEnabled();
    final len = pinOn ? await FastLoginService.storedPinLength() : 0;
    if (!mounted) return;
    setState(() {
      _pinEnabled = pinOn;
      _pinLen = len.clamp(4, 8);
    });
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
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
      setState(() => _showBio = enabled);

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
      await _goUnlockedHome();
    } else {
      setState(() => _err = true);
      _triggerErrorFeedback();
      await _showBioRetryDialog();
    }
  }

  Future<void> _goUnlockedHome() async {
    FastLoginService.markRuntimeUnlocked();
    if (!mounted) return;
    await ReturnAfterAuth.navigatePostAuthOrDefault(
      Navigator.of(context),
      '/userDashboard',
    );
  }

  void _pressDigit(String d) async {
    if (_busy || !_pinEnabled) return;
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
      await _goUnlockedHome();
    } else {
      setState(() {
        _err = true;
        _pin = '';
      });
      _triggerErrorFeedback();
    }
  }

  /// نسيت رمز الدخول → تسجيل الدخول الكامل (كلمة المرور / استعادة).
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
          await auth.signOut(scope: SignOutScope.local);
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
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
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

  String _initialFromName(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first).toUpperCase();
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
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        final titleSize = shortest < 360 ? 17.0 : 19.0;
        final avatarR = shortest < 360 ? 36.0 : 42.0;
        final dotSize = shortest < 360 ? 11.0 : 13.0;
        final keyTextSize = shortest < 360 ? 21.0 : 23.0;
        final gridHPad = shortest < 360 ? 12.0 : 22.0;

        final bg = _bg(isLight);
        final onBg = _onBg(isLight);
        final sub = _sub(isLight);
        final localeName = _isAr ? 'ar' : 'en';
        final errColor = Theme.of(context).colorScheme.error;

        /// صف المفاتيح السفلي: بصمة | 0 | حذف (LTR) — يعكس بصرياً مع RTL.
        final keypad = Directionality(
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(
            builder: (context, c) {
              const childAspect = 1.05;
              final font = TextStyle(
                fontSize: keyTextSize,
                fontWeight: FontWeight.w900,
                color: onBg,
              );

              Widget digit(String v) => _keyButton(
                    isLight: isLight,
                    semanticsLabel: 'Digit $v',
                    onTap: _busy ? null : () => _pressDigit(v),
                    child: Text(v, style: font),
                  );

              Widget bioKey() {
                if (!_showBio) return const SizedBox.shrink();
                return _keyButton(
                  isLight: isLight,
                  highlight: _accentBio.withValues(alpha: 0.85),
                  semanticsLabel: 'Biometric',
                  onTap: _busy ? null : () => _tryBiometric(fromAuto: false),
                  child: Icon(_bioIcon(), size: 30, color: _accentBio),
                );
              }

              Widget backKey() => _keyButton(
                    isLight: isLight,
                    semanticsLabel: 'Backspace',
                    onTap: _busy ? null : _backspace,
                    child: Icon(Icons.backspace_outlined, color: onBg, size: 26),
                  );

              return GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                padding: EdgeInsets.symmetric(horizontal: gridHPad),
                childAspectRatio: childAspect,
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

        final header = FutureBuilder<String?>(
          future: _displayNameFuture,
          builder: (context, snap) {
            final name = (snap.data ?? '').trim();
            final initial = _initialFromName(name);
            return Column(
              children: [
                CircleAvatar(
                  radius: avatarR,
                  backgroundColor:
                      isLight ? const Color(0xFFE5E7EB) : const Color(0xFF2A355A),
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: avatarR * 0.85,
                      fontWeight: FontWeight.w800,
                      color: onBg,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _dateLine(localeName),
                  style: TextStyle(
                    color: sub,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  name.isEmpty
                      ? (_isAr ? 'أهلاً بعودتك' : 'Welcome back')
                      : (_isAr ? 'أهلاً بعودتك $name' : 'Welcome back, $name'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w900,
                    color: onBg,
                    height: 1.15,
                  ),
                ),
                if (_pinEnabled) ...[
                  const SizedBox(height: 6),
                  Text(
                    _isAr ? 'أدخل رمز الدخول السريع' : 'Enter your passcode',
                    style: TextStyle(color: sub, fontSize: 13),
                  ),
                ],
              ],
            );
          },
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
                              child: Text(
                                _isAr ? 'رمز غير صحيح' : 'Wrong passcode',
                                key: const ValueKey('err'),
                                style: TextStyle(
                                  color: errColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : const SizedBox(height: 22, key: ValueKey('noerr')),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    if (_showBio)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accentBio,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                        ),
                        onPressed: _busy
                            ? null
                            : () => _tryBiometric(fromAuto: false),
                        icon: Icon(_bioIcon()),
                        label: Text(
                          _isAr
                              ? 'التحقق بالبصمة أو الوجه'
                              : 'Use biometrics',
                        ),
                      ),
                    if (_err && !_showBio)
                      Text(
                        _isAr
                            ? 'تعذر التحقق. فعّل البصمة من الإعدادات.'
                            : 'Verification unavailable. Enable biometrics in Settings.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: errColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              );

        final busyBar = _busy
            ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: AppLogoLoading(compact: true, size: 26),
                    ),
                  ],
                ),
              )
            : const SizedBox(height: 8);

        return UnscaledTextScope(
          child: Directionality(
            textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              backgroundColor: bg,
              body: SafeArea(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      8,
                      18,
                      20 + bottomInset,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _brand,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: _isAr ? 'المزيد' : 'More',
                                  onPressed: _busy ? null : _signOutCompletely,
                                  icon: const Icon(Icons.more_horiz_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            header,
                            const SizedBox(height: 18),
                            dotsRow,
                            if (_pinEnabled) ...[
                              const SizedBox(height: 14),
                              keypad,
                            ],
                            busyBar,
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy ? null : _forgotPasscode,
                              child: Text(
                                _isAr
                                    ? 'نسيت رمز الدخول؟'
                                    : 'Forgot passcode?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _brand,
                                ),
                              ),
                            ),
                          ],
                        ),
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
  }
}
