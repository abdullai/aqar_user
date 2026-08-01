import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/branding/aqar_brand_colors.dart';
import '../core/compliance/platform_policy_copy.dart';
import '../core/config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show themeModeNotifier;
import 'platform_policies_screen.dart';

/// موافقة مختصرة على الشروط والخصوصية والكوكيز — بأسلوب شاشة القبول
/// (خانات إلزامية + روابط للمستندات + زر استمرار معطّل حتى التأشير).
class LegalTermsAcceptanceScreen extends StatefulWidget {
  final String lang;
  final Map<String, dynamic> legal;
  final Future<void> Function(String version) onAccept;
  final VoidCallback onDecline;

  const LegalTermsAcceptanceScreen({
    super.key,
    required this.lang,
    required this.legal,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<LegalTermsAcceptanceScreen> createState() =>
      _LegalTermsAcceptanceScreenState();
}

class _LegalTermsAcceptanceScreenState extends State<LegalTermsAcceptanceScreen> {
  bool _privacyOk = false;
  bool _termsOk = false;
  bool _cookiesOk = false;
  bool _busy = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';
  bool get _allOk => _privacyOk && _termsOk && _cookiesOk;

  static const Color _teal = Color(0xFF0F766E);

  Future<void> _openPolicy(PlatformPolicyDoc doc) async {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 520;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: narrow ? 12 : 28,
            vertical: narrow ? 18 : 36,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: (size.width * 0.92).clamp(320.0, 560.0),
            height: (size.height * 0.78).clamp(420.0, 720.0),
            child: PlatformPoliciesScreen(
              isAr: _isAr,
              initialDoc: doc,
            ),
          ),
        );
      },
    );
  }

  Future<void> _accept() async {
    if (_busy || !_allOk) return;
    final version = (widget.legal['version'] ?? '').toString().trim();
    if (version.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2200),
          content: Text(
            _isAr
                ? 'تعذر تحديد إصدار الشروط من الخادم. أعد المحاولة لاحقاً.'
                : 'Could not read terms version from server. Try again later.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(AppConfig.prefRegulatoryCookieAckKey, true);
      await widget.onAccept(version);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _linkedAgree({
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color fg,
    required Color muted,
    required String before,
    required String linkLabel,
    required String after,
    required PlatformPolicyDoc doc,
  }) {
    final linkStyle = TextStyle(
      color: _teal,
      fontWeight: FontWeight.w900,
      decoration: TextDecoration.underline,
      decorationColor: _teal.withValues(alpha: 0.45),
      height: 1.45,
      fontSize: 14.5,
    );
    final plain = TextStyle(
      color: muted,
      fontWeight: FontWeight.w600,
      height: 1.45,
      fontSize: 14.5,
    );
    return InkWell(
      onTap: _busy ? null : () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: plain,
                  children: [
                    TextSpan(text: before),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: _busy ? null : () => _openPolicy(doc),
                        child: Text(linkLabel, style: linkStyle),
                      ),
                    ),
                    TextSpan(text: after),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: value,
                onChanged: _busy ? null : (v) => onChanged(v ?? false),
                shape: const CircleBorder(),
                activeColor: _teal,
                checkColor: Colors.white,
                side: BorderSide(
                  color: value ? _teal : muted,
                  width: 1.8,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final version = (widget.legal['version'] ?? '').toString();
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final canContinue = _allOk && version.isNotEmpty && !_busy;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, mode, _) {
          final isLight = mode == ThemeMode.light;
          final bg = isLight ? Colors.white : const Color(0xFF0E0F13);
          final fg = isLight ? const Color(0xFF1A1A1A) : Colors.white;
          final muted = fg.withValues(alpha: 0.62);

          return PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: bg,
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        narrow ? 22 : 28,
                        narrow ? 18 : 28,
                        narrow ? 22 : 28,
                        narrow ? 16 : 22,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: _isAr
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: AqarBrandColors.accent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.description_outlined,
                                        size: 28,
                                        color: _teal,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Text(
                                    _isAr
                                        ? 'راجع شروطنا المحدثة واقبلها'
                                        : 'Review and accept our updated terms',
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      fontSize: narrow ? 22 : 24,
                                      fontWeight: FontWeight.w900,
                                      color: fg,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _isAr
                                        ? 'نريد التأكد من أنك على اطلاع دائم. يُرجى مراجعة كل مستند أدناه والموافقة عليه قبل الاستمرار.'
                                        : 'We want to make sure you stay up to date. Please review each document below and agree before continuing.',
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: muted,
                                      height: 1.45,
                                    ),
                                  ),
                                  if (version.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      '${_isAr ? 'الإصدار' : 'Version'}: $version',
                                      textAlign: TextAlign.start,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 28),
                                  _linkedAgree(
                                    value: _privacyOk,
                                    onChanged: (v) =>
                                        setState(() => _privacyOk = v),
                                    fg: fg,
                                    muted: muted,
                                    before: _isAr
                                        ? 'لقد قرأت '
                                        : 'I have read the updated ',
                                    linkLabel: _isAr
                                        ? 'سياسة الخصوصية'
                                        : 'Privacy Policy',
                                    after: _isAr
                                        ? ' المحدثة وأوافق عليها'
                                        : ' and agree to it',
                                    doc: PlatformPolicyDoc.privacy,
                                  ),
                                  const SizedBox(height: 14),
                                  _linkedAgree(
                                    value: _termsOk,
                                    onChanged: (v) =>
                                        setState(() => _termsOk = v),
                                    fg: fg,
                                    muted: muted,
                                    before: _isAr
                                        ? 'لقد قرأت '
                                        : 'I have read the updated ',
                                    linkLabel: _isAr
                                        ? 'الشروط والأحكام'
                                        : 'Terms of Use',
                                    after: _isAr
                                        ? ' المحدثة وأوافق عليها'
                                        : ' and agree to them',
                                    doc: PlatformPolicyDoc.termsOfUse,
                                  ),
                                  const SizedBox(height: 14),
                                  _linkedAgree(
                                    value: _cookiesOk,
                                    onChanged: (v) =>
                                        setState(() => _cookiesOk = v),
                                    fg: fg,
                                    muted: muted,
                                    before:
                                        _isAr ? 'أوافق على ' : 'I accept the ',
                                    linkLabel: _isAr
                                        ? 'سياسة الكوكيز'
                                        : 'Cookies Policy',
                                    after: _isAr
                                        ? ' والتخزين الضروري للجلسة والأمان'
                                        : ' and essential storage for session & security',
                                    doc: PlatformPolicyDoc.cookies,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (canContinue)
                            FilledButton(
                              onPressed: _accept,
                              style: FilledButton.styleFrom(
                                backgroundColor: _teal,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isAr ? 'استمرار' : 'Continue',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                _isAr
                                    ? 'أشّر على جميع المربعات أعلاه للمتابعة.'
                                    : 'Check all boxes above to continue.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy ? null : widget.onDecline,
                            child: Text(
                              t.legalDecline,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: muted,
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
      ),
    );
  }
}
