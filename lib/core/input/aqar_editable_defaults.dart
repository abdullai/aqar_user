import 'dart:ui' show BoxHeightStyle, BoxWidthStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'aqar_field_keyboard.dart';
import 'locale_text_input_guard.dart';

/// معايير تظليل/مؤشر موحّدة لكل حقول الإدخال — بلا صندوق زائد خارج الحرف.
abstract final class AqarEditableDefaults {
  static const BoxHeightStyle heightStyle = BoxHeightStyle.tight;
  static const BoxWidthStyle widthStyle = BoxWidthStyle.tight;

  static TextStyle styleFor(BuildContext context, TextStyle? style) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge;
    return (base ?? const TextStyle()).copyWith(
      height: style?.height ?? 1.2,
      leadingDistribution: TextLeadingDistribution.even,
      fontSize: style?.fontSize ?? base?.fontSize ?? 16,
      fontFamily: style?.fontFamily ?? 'Cairo',
    );
  }

  static StrutStyle strutFor(TextStyle style) {
    return StrutStyle(
      fontSize: style.fontSize,
      height: style.height ?? 1.2,
      leading: 0,
      forceStrutHeight: false,
      fontFamily: style.fontFamily,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  static double cursorHeightFor(TextStyle style) {
    final fs = style.fontSize ?? 16;
    return (fs * 1.08).clamp(14.0, 22.0);
  }

  static double cursorWidth(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 700;
    return compact ? 2.0 : 1.8;
  }

  /// كلمات مرور/إنجليزي/أرقام: LTR حتى لا يظهر صندوق تظليل وهمي بجانب الحرف الأول في RTL.
  static TextDirection? directionFor({
    required bool obscureText,
    TextInputType? keyboardType,
    TextDirection? requested,
    AqarLocaleScript? localeScript,
  }) {
    if (requested != null) return requested;
    if (obscureText) return TextDirection.ltr;
    if (localeScript == AqarLocaleScript.english) return TextDirection.ltr;
    final t = keyboardType;
    if (t == TextInputType.emailAddress ||
        t == TextInputType.url ||
        t == TextInputType.visiblePassword) {
      return TextDirection.ltr;
    }
    return AqarFieldKeyboard.textDirectionFor(keyboardType, null);
  }

  static Widget contextMenu(BuildContext context, EditableTextState state) {
    return AdaptiveTextSelectionToolbar.editableText(
      editableTextState: state,
    );
  }

  static TextMagnifierConfiguration magnifier() {
    if (kIsWeb) return TextMagnifierConfiguration.disabled;
    return TextMagnifier.adaptiveMagnifierConfiguration;
  }

  /// على الويب: مقابض Material أصغر وأكثر انتظاماً من مقابض Safari/Cupertino المتداخلة.
  static TextSelectionControls? selectionControls() {
    if (kIsWeb) return materialTextSelectionHandleControls;
    return null;
  }

  static SmartDashesType dashes({required bool obscureText, required bool numeric}) {
    if (obscureText || numeric) return SmartDashesType.disabled;
    return SmartDashesType.enabled;
  }

  static SmartQuotesType quotes({required bool obscureText, required bool numeric}) {
    if (obscureText || numeric) return SmartQuotesType.disabled;
    return SmartQuotesType.enabled;
  }
}
