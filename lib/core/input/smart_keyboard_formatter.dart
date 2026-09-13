import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'locale_text_input_guard.dart';

/// لوحة مفاتيح ذكية لحقول الدخول: منصة سطح المكتب مقابل الجوال.
abstract final class SmartKeyboardFormatter {
  /// ويب سطح المكتب (ويندوز/ماك/لينكس) وليس متصفح جوال.
  static bool get isDesktopWebPlatform {
    if (!kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// ويندوز/ماك/لينكس: نص تحت الحقل. الجوال والتطبيق: سهم داخل الحقل.
  static bool useCapsTextUnderField(BuildContext context) {
    if (kIsWeb) return isDesktopWebPlatform;
    final p = defaultTargetPlatform;
    return p == TargetPlatform.windows ||
        p == TargetPlatform.macOS ||
        p == TargetPlatform.linux;
  }

  /// يظهر مؤشر Caps Lock في أي سطح عند اكتشافه — لا يُخفى على شاشات الجوال.
  static bool allowCapsLockChrome(BuildContext context) => true;

  static const TextInputType passwordKeyboard = TextInputType.visiblePassword;
  static const AqarLocaleScript englishScript = AqarLocaleScript.english;
}

/// يمنع تجاوز الطول حتى عند اللصق أو الإدخال السريع على الويب.
class StrictMaxLengthFormatter extends TextInputFormatter {
  const StrictMaxLengthFormatter(this.maxLength);

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= maxLength) return newValue;
    final cut = newValue.text.substring(0, maxLength);
    return TextEditingValue(
      text: cut,
      selection: TextSelection.collapsed(offset: cut.length),
      composing: TextRange.empty,
    );
  }
}

/// بادئة/لاحقة حقل كلمة المرور: قفل + سهم Caps + زر الإظهار.
class CapsLockFieldAffixes {
  const CapsLockFieldAffixes({
    this.prefix,
    this.suffix,
    this.prefixConstraints,
    this.suffixConstraints,
  });

  final Widget? prefix;
  final Widget? suffix;
  final BoxConstraints? prefixConstraints;
  final BoxConstraints? suffixConstraints;

  static CapsLockFieldAffixes build({
    required bool isRtl,
    required bool showGlyph,
    required String capsLockLabel,
    required bool isLight,
    required Color iconColor,
    required Widget eyeButton,
    IconData lockIcon = Icons.lock_outline_rounded,
  }) {
    final capsColor = isLight
        ? const Color(0xFFB45309)
        : const Color(0xFFFBBF24);
    final glyph = Tooltip(
      message: capsLockLabel,
      child: Semantics(
        label: showGlyph ? capsLockLabel : null,
        excludeSemantics: !showGlyph,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Opacity(
              opacity: showGlyph ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: capsColor.withValues(alpha: isLight ? 0.16 : 0.28),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.keyboard_capslock_rounded,
                    color: capsColor,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // القفل عند بداية الحقل، وسهم Caps في الجهة المقابلة بجانب العين.
    return CapsLockFieldAffixes(
      prefix: Padding(
        padding: EdgeInsetsDirectional.only(
          start: isRtl ? 8 : 10,
          end: 4,
        ),
        child: Icon(lockIcon, color: iconColor),
      ),
      suffix: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 2),
            child: glyph,
          ),
          eyeButton,
        ],
      ),
      prefixConstraints: const BoxConstraints(minWidth: 46, minHeight: 46),
      suffixConstraints: const BoxConstraints(minWidth: 92, minHeight: 46),
    );
  }
}

/// تلميح نصّي تحت الحقل على ويب سطح المكتب عند تفعيل Caps Lock.
class CapsLockHintText extends StatelessWidget {
  const CapsLockHintText({
    super.key,
    required this.visible,
    required this.label,
    required this.isLight,
  });

  final bool visible;
  final String label;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final color = isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24);
    final scaled = MediaQuery.textScalerOf(context).scale(13);
    final h = scaled.clamp(20.0, 32.0);
    return SizedBox(
      height: h,
      child: IgnorePointer(
        ignoring: !visible,
        child: Semantics(
          liveRegion: visible,
          container: true,
          excludeSemantics: !visible,
          label: visible ? label : null,
          child: Opacity(
            opacity: visible ? 1 : 0,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, top: 4, end: 4),
              child: Row(
                children: [
                  Icon(Icons.keyboard_capslock_rounded, size: 16, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      visible ? label : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
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
