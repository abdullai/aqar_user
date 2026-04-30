// lib/screens/change_password_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/input/password_arabic_script_guard.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier, themeModeNotifier;
import '../widgets/app_logo_loading.dart';
import '../widgets/field_group_frame.dart';

/// تغيير كلمة المرور للمستخدم المسجّل دخوله (بدون رابط استعادة).
class ChangePasswordScreen extends StatefulWidget {
  /// عضو فريق: إجبار التغيير بعد أول دخول (لا رجوع حتى النجاح).
  final bool mandatoryTeamReset;
  final VoidCallback? onMandatorySuccess;

  const ChangePasswordScreen({
    super.key,
    this.mandatoryTeamReset = false,
    this.onMandatorySuccess,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const Color _bankColor = Color(0xFF0F766E);

  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _obscure3 = true;
  bool _busy = false;
  DateTime? _lastPasswordArabicDialogAt;

  bool get _isAr => langNotifier.value != 'en';
  bool get _isLight => themeModeNotifier.value == ThemeMode.light;

  Color get _pageBg =>
      _isLight ? const Color(0xFFF5F7FA) : const Color(0xFF0E0F13);
  Color get _fieldFill => _isLight ? Colors.white : const Color(0xFF0F1425);
  Color get _fieldBorder =>
      _isLight ? const Color(0xFFE5E7EB) : const Color(0xFF2A355A);
  Color get _iconColor =>
      _isLight ? const Color(0xFF64748B) : const Color(0xFFCBD5E1);

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Supabase.instance.client.auth.currentUser == null) {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context)!;
    final email = Supabase.instance.client.auth.currentUser?.email?.trim();
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.changePasswordFailed)),
      );
      return;
    }

    final cur = _current.text.trim();
    final n1 = _next.text.trim();
    final n2 = _confirm.text.trim();

    if (cur.isEmpty || n1.isEmpty || n2.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.allFieldsRequired)),
      );
      return;
    }
    if (n1.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.passwordTooShort)),
      );
      return;
    }
    if (n1 != n2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr
              ? 'كلمتا المرور الجديدتان غير متطابقتين'
              : 'New passwords do not match'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: cur,
      );
    } on AuthException catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.wrongCurrentPassword)),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.wrongCurrentPassword)),
      );
      return;
    }

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: n1),
      );
      if (widget.mandatoryTeamReset) {
        try {
          await Supabase.instance.client.rpc('clear_must_change_password_after_auth');
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.passwordChangedSuccess)),
      );
      if (widget.mandatoryTeamReset) {
        widget.onMandatorySuccess?.call();
      } else {
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.changePasswordFailed}: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.changePasswordFailed)),
      );
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(Icons.lock_outline, color: _iconColor),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _fieldBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _bankColor, width: 2),
      ),
      fillColor: _fieldFill,
      filled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, _, __) {
          final scaffold = Scaffold(
            backgroundColor: _pageBg,
            appBar: AppBar(
              automaticallyImplyLeading: !widget.mandatoryTeamReset,
              title: Text(t.changePasswordTitle),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  FieldGroupFrame(
                    title: t.changePasswordTitle,
                    subtitle: widget.mandatoryTeamReset
                        ? t.orgMandatoryPasswordHint
                        : (_isAr
                            ? 'أدخل كلمة المرور الحالية ثم كلمة المرور الجديدة.'
                            : 'Enter your current password, then your new password.'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _current,
                          obscureText: _obscure1,
                          enabled: !_busy,
                          enableSuggestions: false,
                          autocorrect: false,
                          inputFormatters: passwordArabicGuardFormatters(
                            onArabicScriptBlocked:
                                _schedulePasswordArabicDialog,
                          ),
                          decoration: _dec(
                            t.currentPasswordLabel,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure1
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: _iconColor,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure1 = !_obscure1),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _next,
                          obscureText: _obscure2,
                          enabled: !_busy,
                          enableSuggestions: false,
                          autocorrect: false,
                          inputFormatters: passwordArabicGuardFormatters(
                            onArabicScriptBlocked:
                                _schedulePasswordArabicDialog,
                          ),
                          decoration: _dec(
                            t.newPasswordLabel,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure2
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: _iconColor,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure2 = !_obscure2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _confirm,
                          obscureText: _obscure3,
                          enabled: !_busy,
                          enableSuggestions: false,
                          autocorrect: false,
                          inputFormatters: passwordArabicGuardFormatters(
                            onArabicScriptBlocked:
                                _schedulePasswordArabicDialog,
                          ),
                          onSubmitted: (_) {
                            if (!_busy) _submit();
                          },
                          decoration: _dec(
                            t.confirmNewPasswordLabel,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure3
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: _iconColor,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure3 = !_obscure3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: _bankColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _busy
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: AppLogoLoading(
                                        compact: true, size: 20),
                                  )
                                : Text(
                                    t.savePassword,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
          if (widget.mandatoryTeamReset) {
            return PopScope(
              canPop: false,
              child: scaffold,
            );
          }
          return scaffold;
        },
      ),
    );
  }
}
