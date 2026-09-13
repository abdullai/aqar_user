import 'package:flutter/material.dart';

import 'package:aqar_user/l10n/app_localizations.dart';
import 'package:aqar_user/main.dart';

import '../core/auth/login_method_policy.dart';
import '../core/gestures/app_keyboard_popups.dart';
import '../core/haptics/app_haptics.dart';
import '../core/session/user_appearance_session.dart';
import 'app_page_close_button.dart';

/// سطح الدخول الحالي: كلمة مرور أو قفل حيوي/رمز الجهاز.
enum AuthLoginSurface {
  password,
  biometric,
}

/// شريط علوي موحّد: لغة + مظهر + طريقة الدخول — ثلاثة أقسام متساوية دون التفاف.
class AuthTopChrome extends StatelessWidget {
  const AuthTopChrome({
    super.key,
    required this.snapshot,
    required this.onSelect,
    this.busy = false,
  });

  final LoginMethodSnapshot snapshot;
  final void Function(LoginMethodKind kind) onSelect;
  final bool busy;

  static const Color _bank = Color(0xFF0F766E);

  bool get _isAr => langNotifier.value != 'en';
  bool get _isLight =>
      UserAppearanceSession.resolvesLight(themeModeNotifier.value);

  Color get _textPrimary =>
      _isLight ? const Color(0xFF0B1220) : Colors.white;
  Color get _textSecondary =>
      _isLight ? const Color(0xFF5B6475) : const Color(0xFFB8C0D4);
  Color get _iconColor =>
      _isLight ? const Color(0xFF64748B) : const Color(0xFFCBD5E1);
  Color get _fill => _isLight ? Colors.white : const Color(0xFF0F1425);
  Color get _outline =>
      _isLight ? const Color(0xFF0A0A0A) : Colors.white;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([langNotifier, themeModeNotifier]),
      builder: (context, _) {
        final t = AppLocalizations.of(context);
        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final iconOnly = w < 340;
            final short = w < 540;
            final h = w < 360 ? 42.0 : 46.0;
            final iconSize = iconOnly ? 22.0 : (short ? 18.0 : 19.0);
            final fontSize = short ? 11.4 : 12.6;

            final langLabel = langNotifier.value == 'en' ? 'EN' : 'AR';
            final themeLabel = iconOnly
                ? ''
                : switch (themeModeNotifier.value) {
                    ThemeMode.system => t?.themeSystem ?? (_isAr ? 'النظام' : 'System'),
                    ThemeMode.light => t?.themeLight ?? (_isAr ? 'نهاري' : 'Light'),
                    ThemeMode.dark => t?.themeDark ?? (_isAr ? 'ليلي' : 'Dark'),
                  };
            final methodLabel = iconOnly
                ? ''
                : (short
                    ? (_isAr ? 'طريقة' : 'Method')
                    : (_isAr ? 'طريقة الدخول' : 'Sign-in'));

            return Semantics(
              container: true,
              label: _isAr
                  ? 'خيارات اللغة والمظهر وطريقة الدخول'
                  : 'Language, appearance, and sign-in method',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _fill,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _outline, width: 1.35),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: _isLight ? 0.06 : 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: h,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _segment(
                          tooltip: t?.language ?? (_isAr ? 'اللغة' : 'Language'),
                          icon: Icons.language_rounded,
                          label: langLabel,
                          iconSize: iconSize,
                          fontSize: fontSize,
                          iconOnly: false,
                          onTap: busy
                              ? null
                              : () => _showLanguageSheet(context, t: t),
                        ),
                      ),
                      _vDivider(),
                      Expanded(
                        child: _segment(
                          tooltip: t?.theme ?? (_isAr ? 'المظهر' : 'Appearance'),
                          icon: switch (themeModeNotifier.value) {
                            ThemeMode.system => Icons.brightness_auto_rounded,
                            ThemeMode.light => Icons.light_mode_rounded,
                            ThemeMode.dark => Icons.dark_mode_rounded,
                          },
                          label: themeLabel,
                          iconSize: iconSize,
                          fontSize: fontSize,
                          iconOnly: iconOnly,
                          onTap: busy
                              ? null
                              : () => _showThemeSheet(context, t: t),
                        ),
                      ),
                      _vDivider(),
                      Expanded(
                        child: _segment(
                          tooltip: _isAr ? 'طريقة الدخول' : 'Sign-in method',
                          icon: snapshot.tabIcon,
                          label: methodLabel,
                          iconSize: iconSize,
                          fontSize: fontSize,
                          iconOnly: iconOnly,
                          emphasize: true,
                          onTap: busy
                              ? null
                              : () => _showMethodSheet(context, t: t),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _vDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: _outline.withValues(alpha: _isLight ? 0.18 : 0.28),
    );
  }

  Widget _segment({
    required String tooltip,
    required IconData icon,
    required String label,
    required double iconSize,
    required double fontSize,
    required bool iconOnly,
    required VoidCallback? onTap,
    bool emphasize = false,
  }) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: iconSize,
            color: emphasize ? _bank : _bank.withValues(alpha: 0.95),
          ),
          if (!iconOnly && label.trim().isNotEmpty) ...[
            const SizedBox(width: 5),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: fontSize,
                    letterSpacing: 0.15,
                    height: 1.05,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 420),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  AppHaptics.selection();
                  onTap();
                },
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      ),
    );
  }

  void _showLanguageSheet(BuildContext context, {AppLocalizations? t}) {
    _openSheet(
      context,
      title: t?.language ?? (_isAr ? 'اللغة' : 'Language'),
      subtitle: _isAr ? 'اختر لغة التطبيق' : 'Choose app language',
      children: [
        _optionTile(
          icon: Icons.translate_rounded,
          title: t?.languageArabic ?? 'العربية',
          subtitle: 'العربية',
          selected: langNotifier.value != 'en',
          onTap: () async {
            Navigator.pop(context);
            await setAppLang('ar');
          },
        ),
        const SizedBox(height: 8),
        _optionTile(
          icon: Icons.abc_rounded,
          title: t?.languageEnglish ?? 'English',
          subtitle: 'English',
          selected: langNotifier.value == 'en',
          onTap: () async {
            Navigator.pop(context);
            await setAppLang('en');
          },
        ),
      ],
    );
  }

  void _showThemeSheet(BuildContext context, {AppLocalizations? t}) {
    _openSheet(
      context,
      title: t?.theme ?? (_isAr ? 'المظهر' : 'Appearance'),
      subtitle: _isAr ? 'اختر مظهر التطبيق' : 'Choose app appearance',
      children: [
        _optionTile(
          icon: Icons.brightness_auto_rounded,
          title: t?.themeSystem ?? (_isAr ? 'حسب النظام' : 'System'),
          subtitle: _isAr
              ? 'يتبع وضع الجهاز تلقائياً'
              : 'Follows the device appearance',
          selected: themeModeNotifier.value == ThemeMode.system,
          onTap: () async {
            Navigator.pop(context);
            await setAppTheme(ThemeMode.system);
          },
        ),
        const SizedBox(height: 8),
        _optionTile(
          icon: Icons.light_mode_rounded,
          title: t?.themeLight ?? (_isAr ? 'فاتح' : 'Light'),
          subtitle: _isAr ? 'نهاري' : 'Light',
          selected: themeModeNotifier.value == ThemeMode.light,
          onTap: () async {
            Navigator.pop(context);
            await setAppTheme(ThemeMode.light);
          },
        ),
        const SizedBox(height: 8),
        _optionTile(
          icon: Icons.dark_mode_rounded,
          title: t?.themeDark ?? (_isAr ? 'داكن' : 'Dark'),
          subtitle: _isAr ? 'ليلي' : 'Dark',
          selected: themeModeNotifier.value == ThemeMode.dark,
          onTap: () async {
            Navigator.pop(context);
            await setAppTheme(ThemeMode.dark);
          },
        ),
      ],
    );
  }

  void _showMethodSheet(BuildContext context, {AppLocalizations? t}) {
    final methods = snapshot.visibleMethods;
    final host = snapshot.hostLabel(isAr: _isAr);
    final trust = snapshot.trustedThisInstall && snapshot.firstPasswordDone
        ? (_isAr ? 'جهاز معتمد' : 'Trusted device')
        : (_isAr ? 'جهاز غير مسجّل بعد' : 'Device not registered yet');

    _openSheet(
      context,
      title: _isAr ? 'طريقة الدخول' : 'Sign-in method',
      subtitle: '$host · $trust',
      children: [
        for (var i = 0; i < methods.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _methodTile(context, methods[i]),
        ],
      ],
    );
  }

  Widget _methodTile(
    BuildContext context,
    LoginMethodKind kind,
  ) {
    late final IconData icon;
    late final String title;
    late final String subtitle;
    var selected = false;

    switch (kind) {
      case LoginMethodKind.password:
        icon = Icons.password_rounded;
        title = _isAr ? 'اسم المستخدم وكلمة المرور' : 'Username and password';
        subtitle = snapshot.nameOnlyPassword
            ? (_isAr
                ? 'الاسم جاهز — أدخل كلمة المرور فقط'
                : 'Name ready — enter password only')
            : (_isAr
                ? 'الدخول بالرقم المميز وكلمة المرور'
                : 'Sign in with your ID number and password');
        selected = !snapshot.quickUnlockActive;
        break;
      case LoginMethodKind.nafath:
        icon = Icons.verified_user_outlined;
        title = _isAr ? 'نفاذ' : 'Nafath';
        subtitle = _isAr
            ? 'الدخول الوطني الموحّد عبر تطبيق نفاذ'
            : 'National single sign-on via Nafath';
        break;
      case LoginMethodKind.pin:
        icon = Icons.pin_rounded;
        title = _isAr ? 'رمز الدخول السريع' : 'Quick PIN';
        subtitle = _isAr
            ? 'الرمز الذي فعّلته على هذا الجهاز'
            : 'The PIN you enabled on this device';
        selected = snapshot.quickUnlockActive && snapshot.showPin;
        break;
      case LoginMethodKind.face:
        icon = Icons.face_retouching_natural_rounded;
        title = _isAr ? 'بصمة الوجه' : 'Face ID';
        subtitle = _isAr
            ? 'التعرّف مباشرة حسب إعدادك على هذا الجهاز'
            : 'Recognize immediately from this device';
        selected = snapshot.quickUnlockActive && snapshot.showFace;
        break;
      case LoginMethodKind.fingerprint:
        icon = Icons.fingerprint_rounded;
        title = _isAr ? 'بصمة الإصبع' : 'Fingerprint';
        subtitle = _isAr
            ? 'السمات الحيوية التي فعّلتها على هذا الجهاز'
            : 'Biometrics you enabled on this device';
        selected = snapshot.quickUnlockActive && snapshot.showFingerprint;
        break;
      case LoginMethodKind.anotherUser:
        icon = Icons.switch_account_rounded;
        title = _isAr ? 'الدخول بمستخدم آخر' : 'Sign in as another user';
        subtitle = _isAr
            ? 'يلزم اسم المستخدم وكلمة المرور كاملة'
            : 'Full username and password are required';
        break;
    }

    return _optionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      selected: selected,
      onTap: () {
        Navigator.pop(context);
        onSelect(kind);
      },
    );
  }

  void _openSheet(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    showAppDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: Colors.transparent,
          child: ListenableBuilder(
            listenable: Listenable.merge([langNotifier, themeModeNotifier]),
            builder: (_, __) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _fill,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isLight
                          ? const Color(0xFFE5E7EB)
                          : const Color(0xFF2A355A),
                    ),
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
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: _textPrimary,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      subtitle,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: _textSecondary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppPageCloseButton(
                              color: _iconColor,
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...children,
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

  Widget _optionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final bg = selected
        ? _bank.withValues(alpha: _isLight ? 0.10 : 0.18)
        : Colors.transparent;
    final border = selected
        ? _bank.withValues(alpha: 0.6)
        : (_isLight ? const Color(0xFFE5E7EB) : const Color(0xFF2A355A));

    return InkWell(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _bank.withValues(alpha: _isLight ? 0.10 : 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _bank, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: _textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? _bank : _iconColor,
            ),
          ],
        ),
      ),
    );
  }
}
