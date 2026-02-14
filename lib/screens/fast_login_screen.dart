// lib/screens/fast_login_screen.dart
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/fast_login_service.dart';
import '../services/connectivity_guard.dart'; // ✅ NEW

class FastLoginScreen extends StatefulWidget {
  const FastLoginScreen({super.key});

  @override
  State<FastLoginScreen> createState() => _FastLoginScreenState();
}

class _FastLoginScreenState extends State<FastLoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _brand = Color(0xFF0F766E);
  static const int _pinLen = 6;

  bool _busy = false;
  bool _err = false;
  bool _showBio = false;
  bool _canBio = false;

  // ✅ NEW: offline guard
  bool _offline = false;
  bool _retryingNet = false;

  // ✅ we keep internal digits typed (always in correct order),
  // and only reverse the *visual* direction in dots row.
  String _pin = '';

  late final Future<String?> _displayNameFuture;
  late final AnimationController _shakeCtrl;

  bool get _isAr => langNotifier.value != 'en';
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshInternetState();
      if (!mounted) return;
      if (!_offline) {
        await _initBiometricsAndMaybeAutoAuth();
      }
    });
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  // =========================
  // ✅ Internet guard
  // =========================

  Future<bool> _hasInternet() async {
    try {
      return await ConnectivityGuard.hasInternet();
    } catch (_) {
      return false;
    }
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

  Future<void> _refreshInternetState() async {
    final ok = await _hasInternet();
    if (!mounted) return;
    setState(() => _offline = !ok);
  }

  Future<bool> _ensureInternetOrShow() async {
    final ok = await _hasInternet();
    if (!mounted) return false;

    if (!ok) {
      if (!_offline) setState(() => _offline = true);
      _toast(_isAr
          ? 'لا يوجد اتصال بالإنترنت. فعّل الإنترنت ثم أعد المحاولة.'
          : 'No internet connection. Enable internet then retry.');
      return false;
    }

    if (_offline) setState(() => _offline = false);
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

      await _initBiometricsAndMaybeAutoAuth();
    } finally {
      if (mounted) setState(() => _retryingNet = false);
    }
  }

  Widget _offlineOverlay({required bool isLight}) {
    final onBg = _onBg(isLight);
    final sub = _sub(isLight);
    final surface = isLight ? Colors.white : const Color(0xFF10121A);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: (isLight ? Colors.white : Colors.black).withOpacity(0.55),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 18,
              color: surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 54, color: onBg),
                    const SizedBox(height: 10),
                    Text(
                      _isAr
                          ? 'لا يوجد اتصال بالإنترنت'
                          : 'No internet connection',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: onBg,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isAr
                          ? 'لن يمكنك الدخول السريع بدون إنترنت.'
                          : 'Quick login requires internet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: sub,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brand,
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
                      onPressed: _busy
                          ? null
                          : () => _switchAccount(clearFastLock: false),
                      child: Text(
                          _isAr ? 'العودة لتسجيل الدخول' : 'Back to login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================
  // ✅ Biometrics init
  // =========================

  Future<void> _initBiometricsAndMaybeAutoAuth() async {
    if (!_isMobile) {
      if (!mounted) return;
      setState(() {
        _showBio = false;
        _canBio = false;
      });
      return;
    }

    try {
      final enabled = await FastLoginService.isBiometricEnabled();
      final can = await FastLoginService.canCheckBiometrics();

      if (!mounted) return;
      setState(() {
        _canBio = can;
        _showBio = enabled && can;
      });

      if (_showBio) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;

          // ✅ لا تحاول البصمة بدون إنترنت
          if (!await _ensureInternetOrShow()) return;

          await _tryBiometric();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _showBio = false;
        _canBio = false;
      });
    }
  }

  void _triggerErrorFeedback() {
    HapticFeedback.mediumImpact();
    _shakeCtrl.forward(from: 0);
  }

  Future<void> _tryBiometric() async {
    // ✅ لا تحاول بدون إنترنت
    if (!await _ensureInternetOrShow()) return;

    if (_busy) return;

    setState(() {
      _busy = true;
      _err = false;
    });

    final ok = await FastLoginService.authenticateBiometric(isAr: _isAr);

    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Navigator.pushReplacementNamed(context, '/userDashboard');
    } else {
      setState(() => _err = true);
      _triggerErrorFeedback();
    }
  }

  void _pressDigit(String d) async {
    // ✅ لا تقبل إدخال بدون إنترنت
    if (!await _ensureInternetOrShow()) return;

    if (_busy) return;
    if (_pin.length >= _pinLen) return;

    setState(() {
      _pin += d; // ✅ keep logical order
      _err = false;
    });

    HapticFeedback.selectionClick();

    if (_pin.length == _pinLen) {
      _submitPin();
    }
  }

  void _backspace() {
    if (_busy) return;
    if (_pin.isEmpty) return;

    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _err = false;
    });

    HapticFeedback.selectionClick();
  }

  Future<void> _submitPin() async {
    // ✅ لا submit بدون إنترنت
    if (!await _ensureInternetOrShow()) return;

    if (_busy) return;

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
      Navigator.pushReplacementNamed(context, '/userDashboard');
    } else {
      setState(() {
        _err = true;
        _pin = '';
      });
      _triggerErrorFeedback();
    }
  }

  Future<void> _switchAccount({required bool clearFastLock}) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      if (clearFastLock) {
        await FastLoginService.clearAll();
      }
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // ---- UI helpers

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
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }

  IconData _bioIcon() {
    return Icons.fingerprint;
  }

  @override
  Widget build(BuildContext context) {
    final isLight = themeModeNotifier.value == ThemeMode.light;
    final size = MediaQuery.sizeOf(context);
    final shortest = size.shortestSide;

    final cardPad = shortest < 360 ? 14.0 : 18.0;
    final titleSize = shortest < 360 ? 16.0 : 18.0;
    final logoSize = shortest < 360 ? 54.0 : 64.0;
    final dotSize = shortest < 360 ? 11.0 : 13.0;
    final keyTextSize = shortest < 360 ? 20.0 : 22.0;
    final gridHPad = shortest < 360 ? 10.0 : 18.0;

    final bg = _bg(isLight);
    final onBg = _onBg(isLight);
    final sub = _sub(isLight);

    // ✅ Keypad MUST be LTR for correct 1-2-3 layout
    final keypad = Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, c) {
          final childAspect = 1.05;
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
              semanticsLabel: 'Biometric',
              onTap: _busy ? null : _tryBiometric,
              child: Icon(_bioIcon(), size: 28, color: onBg),
            );
          }

          Widget backKey() => _keyButton(
                isLight: isLight,
                semanticsLabel: 'Backspace',
                onTap: _busy ? null : _backspace,
                child: Icon(Icons.backspace, color: onBg),
              );

          return GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            padding: EdgeInsets.symmetric(horizontal: gridHPad),
            childAspectRatio: childAspect,
            children: [
              for (var i = 1; i <= 9; i++) digit('$i'),
              backKey(),
              digit('0'),
              bioKey(),
            ],
          );
        },
      ),
    );

    final header = FutureBuilder<String?>(
      future: _displayNameFuture,
      builder: (context, snap) {
        final name = (snap.data ?? '').trim();
        return Column(
          children: [
            Container(
              width: logoSize,
              height: logoSize,
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF141722),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isLight
                      ? const Color(0xFFE5E7EB)
                      : const Color(0xFF22283A),
                ),
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/logo.png',
                width: logoSize * 0.78,
                height: logoSize * 0.78,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.apartment_rounded,
                  size: logoSize * 0.62,
                  color: onBg,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isAr ? 'الدخول السريع' : 'Quick Login',
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
                color: onBg,
              ),
            ),
            const SizedBox(height: 6),
            if (name.isNotEmpty)
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: onBg,
                ),
              ),
            const SizedBox(height: 6),
            Text(
              _isAr ? 'أدخل رمز PIN' : 'Enter your PIN',
              style: TextStyle(color: sub),
            ),
          ],
        );
      },
    );

    final dotsRow = AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (context, child) {
        final t = _shakeCtrl.value;
        final dx = _err ? (8.0 * (1 - t) * math.sin(t * 18.0)) : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Column(
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
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
                      _isAr ? 'رمز غير صحيح' : 'Invalid PIN',
                      key: const ValueKey('err'),
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : const SizedBox(height: 20, key: ValueKey('noerr')),
          ),
        ],
      ),
    );

    final actionsRow = Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        TextButton.icon(
          onPressed: _busy ? null : () => _switchAccount(clearFastLock: true),
          icon: const Icon(Icons.logout),
          label: Text(_isAr ? 'تبديل الحساب' : 'Switch account'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await FastLoginService.clearAll();
                  if (!mounted) return;
                  Navigator.pushReplacementNamed(context, '/login');
                },
          child: Text(_isAr ? 'نسيت رمز الدخول السريع؟' : 'Forgot quick PIN?'),
        ),
      ],
    );

    final busyBar = _busy
        ? const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          )
        : const SizedBox(height: 12);

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      elevation: 2,
                      color: isLight ? Colors.white : const Color(0xFF10121A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(cardPad),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            header,
                            const SizedBox(height: 16),
                            dotsRow,
                            const SizedBox(height: 8),
                            keypad,
                            busyBar,
                            actionsRow,
                            const SizedBox(height: 6),
                            Text(
                              _showBio
                                  ? (_isAr
                                      ? 'يمكنك أيضًا استخدام البصمة/الوجه'
                                      : 'You can also use biometrics')
                                  : (_isAr
                                      ? (_canBio
                                          ? 'البصمة/الوجه متاحة من الإعدادات'
                                          : 'الدخول عبر PIN فقط')
                                      : (_canBio
                                          ? 'Biometrics are available in settings'
                                          : 'PIN-only unlock')),
                              style: TextStyle(color: sub, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ✅ Offline overlay
              if (_offline) _offlineOverlay(isLight: isLight),
            ],
          ),
        ),
      ),
    );
  }
}
