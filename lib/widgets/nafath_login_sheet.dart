import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth/auth_challenge_service.dart';
import '../core/auth/in_app_otp_handoff.dart';
import '../core/auth/login_success_banner.dart';
import '../core/branding/app_branding.dart';
import '../core/gestures/app_keyboard_stable.dart';
import '../core/government/nafath_models.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/session/app_session.dart';
import '../core/session/return_after_auth.dart';
import '../services/fast_login_service.dart';
import '../services/nafath_auth_service.dart';
import '../screens/verify_screen.dart';
import '../core/branding/branding_logo_image.dart';
import 'aqar_text_field.dart';
import 'app_logo_loading.dart';

/// نافذة نفاذ فوق شاشة الدخول: الهوية → رمز التحقق / الرابط → جلسة.
class NafathLoginSheet extends StatefulWidget {
  const NafathLoginSheet({
    super.key,
    required this.isAr,
    this.rememberMe = false,
  });

  final bool isAr;
  final bool rememberMe;

  static Future<void> show(
    BuildContext context, {
    required bool isAr,
    bool rememberMe = false,
  }) {
    return showAppModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => NafathLoginSheet(
        isAr: isAr,
        rememberMe: rememberMe,
      ),
    );
  }

  @override
  State<NafathLoginSheet> createState() => _NafathLoginSheetState();
}

class _NafathLoginSheetState extends State<NafathLoginSheet> {
  static const Color _bank = Color(0xFF0F766E);

  late final TextEditingController _idCtrl;
  bool _busy = false;
  bool _polling = false;
  bool _pollInFlight = false;
  String? _error;
  String _random = '';
  String? _requestId;
  Timer? _pollTimer;
  int _pollTicks = 0;

  bool get _isAr => widget.isAr;

  @override
  void initState() {
    super.initState();
    _idCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _idCtrl.dispose();
    super.dispose();
  }

  String get _nationalId {
    return arabicAndPersianDigitsToLatin(_idCtrl.text)
        .replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _start() async {
    final id = _nationalId;
    if (id.length != 10) {
      setState(() {
        _error = _isAr
            ? 'أدخل رقم الهوية أو الإقامة (10 أرقام).'
            : 'Enter a 10-digit national / Iqama ID.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final svc = NafathAuthService(Supabase.instance.client);
    final r = await svc.startLogin(
      locale: _isAr ? 'ar' : 'en',
      nationalId: id,
    );
    if (!mounted) return;

    if (r.mode == NafathSessionMode.notConfigured) {
      setState(() {
        _busy = false;
        _error = _isAr
            ? (r.messageAr ?? 'خدمة نفاذ غير مفعّلة حالياً.')
            : (r.messageEn ?? 'Nafath is not configured yet.');
      });
      return;
    }
    if (r.mode == NafathSessionMode.error) {
      setState(() {
        _busy = false;
        _error = _isAr
            ? (r.messageAr ?? 'تعذر بدء جلسة نفاذ.')
            : (r.messageEn ?? 'Could not start Nafath.');
      });
      return;
    }
    final token = (r.accessToken ?? '').trim();
    final refresh = (r.refreshToken ?? '').trim();
    if (r.mode == NafathSessionMode.redirect &&
        token.isNotEmpty &&
        refresh.isNotEmpty) {
      _pollTimer?.cancel();
      await _applySession(refreshToken: refresh);
      return;
    }

    if (r.mode == NafathSessionMode.redirect) {
      setState(() => _busy = false);
      final url = (r.authorizationUrl ?? '').trim();
      if (url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      return;
    }

    setState(() {
      _busy = false;
      _polling = true;
      _requestId = r.requestId;
      _random = (r.random ?? '').trim();
    });
    _pollTimer?.cancel();
    _pollTicks = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollOnce());
    });
  }

  Future<void> _pollOnce() async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      await _pollOnceInternal();
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _pollOnceInternal() async {
    final rid = (_requestId ?? '').trim();
    if (rid.isEmpty || !_polling) return;
    _pollTicks += 1;
    if (_pollTicks > 150) {
      _pollTimer?.cancel();
      if (mounted) {
        setState(() {
          _polling = false;
          _error = _isAr
              ? 'انتهت مهلة تأكيد نفاذ. أعد المحاولة.'
              : 'Nafath confirmation timed out. Try again.';
        });
      }
      return;
    }
    final svc = NafathAuthService(Supabase.instance.client);
    final r = await svc.pollStatus(rid);
    if (!mounted) return;

    if (r.mode == NafathSessionMode.error ||
        r.mode == NafathSessionMode.notConfigured) {
      _pollTimer?.cancel();
      setState(() {
        _polling = false;
        _error = _isAr
            ? (r.messageAr ?? 'تعذر التحقق من طلب نفاذ.')
            : (r.messageEn ?? 'Could not verify the Nafath request.');
      });
      return;
    }

    if (r.mode == NafathSessionMode.redirect) {
      _pollTimer?.cancel();
      final uri = Uri.tryParse((r.authorizationUrl ?? '').trim());
      var opened = false;
      try {
        opened = uri != null &&
            uri.scheme == 'https' &&
            await launchUrl(uri, mode: LaunchMode.externalApplication);
      } on Exception catch (e) {
        debugPrint('Could not open Nafath sign-in link: $e');
      }
      if (!mounted) return;
      setState(() {
        _polling = false;
        if (!opened) {
          _error = _isAr
              ? 'تعذر فتح رابط إكمال الدخول.'
              : 'Could not open the sign-in link.';
        }
      });
      return;
    }

    final st = (r.status ?? '').toLowerCase();
    if (st == 'rejected' || st == 'expired' || st == 'failed') {
      _pollTimer?.cancel();
      setState(() {
        _polling = false;
        _error = _isAr
            ? (r.messageAr ?? 'لم يُعتمد الطلب في نفاذ.')
            : (r.messageEn ?? 'Nafath request was not approved.');
      });
      return;
    }

    final rnd = (r.random ?? '').trim();
    if (rnd.isNotEmpty && rnd != _random) {
      setState(() => _random = rnd);
    }
  }

  Future<void> _applySession({
    required String refreshToken,
  }) async {
    setState(() {
      _polling = false;
      _busy = true;
    });
    try {
      await Supabase.instance.client.auth.setSession(refreshToken);
    } catch (e) {
      debugPrint('Could not establish the Nafath Supabase session: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _isAr
              ? 'تم التحقق من نفاذ لكن تعذر إنشاء جلسة الدخول. أعد المحاولة.'
              : 'Nafath verified, but a sign-in session could not be created. Try again.';
        });
      }
      return;
    }
    final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _isAr
              ? 'اكتمل نفاذ لكن تعذر فتح الجلسة.'
              : 'Nafath completed but the session could not be opened.';
        });
      }
      return;
    }
    try {
      await FastLoginService.saveUserContext(
        uid: uid,
        usernameNationalId: _nationalId,
      );
    } catch (_) {}

    final challenge = await AuthChallengeService.start(
      username: _nationalId,
      loginMethod: 'nafath',
    );
    if (!mounted) return;

    if (challenge.needsOtp || !challenge.fullyAuthenticated) {
      final args = <String, dynamic>{
        'next': kIsWeb ? '/' : '/userDashboard',
        'username': _nationalId,
        'otpAlreadyRequested': challenge.ok && challenge.needsOtp,
        if ((challenge.challengeId ?? '').isNotEmpty)
          'challengeId': challenge.challengeId,
        if ((challenge.devCode ?? '').length >= InAppOtpHandoff.otpLen)
          'code': challenge.devCode!.substring(0, InAppOtpHandoff.otpLen),
        if (challenge.expiresAt != null)
          'otpExpiresAt': challenge.expiresAt!.toUtc().toIso8601String(),
      };
      final nav = Navigator.of(context, rootNavigator: true);
      nav.pop();
      await nav.pushReplacement(
        PageRouteBuilder<void>(
          settings: RouteSettings(name: '/verify', arguments: args),
          pageBuilder: (context, animation, secondaryAnimation) => VerifyScreen(
            initialUsername: _nationalId,
            initialChallengeId: challenge.challengeId,
            initialCode: challenge.devCode,
          ),
          transitionDuration: const Duration(milliseconds: 120),
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      return;
    }

    try {
      await FastLoginService.markTrustedInstall(uid: uid);
      await FastLoginService.rememberSuccessfulAuth(
        loginMethod: 'nafath',
        entryRoute: '/login',
      );
    } catch (_) {}
    if (!mounted) return;
    await context.read<AppSession>().setUser(uid);
    if (!mounted) return;
    await LoginSuccessBanner.showOrQueue(context, isAr: _isAr);
    if (!mounted) return;
    Navigator.of(context).pop();
    await ReturnAfterAuth.navigatePostAuthOrDefault(
      Navigator.of(context),
      '/userDashboard',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isAr ? 'الدخول عبر نفاذ' : 'Sign in with Nafath',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                _isAr
                    ? 'أدخل رقم الهوية ثم أكّد الطلب من تطبيق نفاذ.'
                    : 'Enter your ID then confirm in the Nafath app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _signInBrandTile(
                      label: _isAr ? 'نفاذ' : 'Nafath',
                      child: Image.asset(
                        'assets/nafath_mark.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                        semanticLabel: _isAr ? 'شعار نفاذ' : 'Nafath logo',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _signInBrandTile(
                      label: AppBranding.displayNameForContext(
                        context,
                        isAr: _isAr,
                      ),
                      child: const BrandingLogoImage(
                        size: 48,
                        semanticLabel: 'Aqar',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AqarTextField(
                controller: _idCtrl,
                keyboardType: TextInputType.number,
                enabled: !_busy && !_polling,
                inputFormatters: [
                  const ArabicDigitsToLatinFormatter(),
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText:
                      _isAr ? 'رقم الهوية / الإقامة' : 'National / Iqama ID',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_random.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: _bank.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isAr ? 'الرقم في تطبيق نفاذ' : 'Number in Nafath app',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _random,
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                          color: _bank,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: (_busy || _polling) ? null : _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: _bank,
                    alignment: Alignment.center,
                  ),
                  child: (_busy || _polling)
                      ? const AppLogoLoading(size: 28)
                      : Text(
                          _polling
                              ? (_isAr ? 'بانتظار التأكيد…' : 'Waiting…')
                              : (_isAr
                                  ? 'متابعة عبر نفاذ'
                                  : 'Continue with Nafath'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signInBrandTile({
    required String label,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 50, child: Center(child: child)),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
