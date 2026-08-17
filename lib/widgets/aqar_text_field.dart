import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/input/locale_text_input_guard.dart';
import '../core/platform/viewport_scroll_policy.dart';
import 'aqar_input_helpers.dart';

/// هامش تمرير فوق لوحة المفاتيح — متوازن لتجنّب رعشة التحديد على ويب الجوال.
EdgeInsets aqarFieldScrollPadding(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route is PopupRoute) {
    // الحوارات/الشيتات لديها غلاف خاص لـ viewInsets — لا نضاعف الهامش.
    return const EdgeInsets.fromLTRB(12, 12, 12, 28);
  }
  final inset = MediaQuery.viewInsetsOf(context).bottom;
  final compact = ViewportScrollPolicy.isCompactTouchLike(context);
  final base = compact ? (kIsWeb ? 160.0 : 180.0) : 100.0;
  final bottom = (inset > 0 ? inset + (compact ? 72.0 : 56.0) : base)
      .clamp(80.0, 320.0);
  return EdgeInsets.fromLTRB(16, 16, 16, bottom);
}

/// تحديد كامل للنص عند النقر المزدوج — بدون اعتراض إيماءات التحديد الجزئي.
void aqarSelectAllText(TextEditingController? controller) {
  if (controller == null) return;
  final text = controller.text;
  if (text.isEmpty) return;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: text.length,
  );
}

/// حقل إدخال موحّد: Tab/Next، تحديد كامل عند النقر المزدوج.
class AqarTextField extends StatelessWidget {
  const AqarTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
    this.onTap,
    this.onChanged,
    this.autofocus = false,
    this.enabled,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.inputFormatters,
    this.style,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.autofillHints,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.selectAllOnDoubleTap = true,
    this.cursorColor,
    this.showCursor,
    this.buildCounter,
    this.textCapitalization = TextCapitalization.none,
    this.onTapOutside,
    this.enableInteractiveSelection = true,
    this.localeScript,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool? enabled;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final Iterable<String>? autofillHints;
  final bool enableSuggestions;
  final bool autocorrect;
  final bool selectAllOnDoubleTap;
  final Color? cursorColor;
  final bool? showCursor;
  final InputCounterWidgetBuilder? buildCounter;
  final TextCapitalization textCapitalization;
  final TapRegionCallback? onTapOutside;
  final bool enableInteractiveSelection;
  final AqarLocaleScript? localeScript;

  @override
  Widget build(BuildContext context) {
    void handleTap() {
      onTap?.call();
      final node = focusNode;
      if (node != null) {
        if (!node.hasFocus) node.requestFocus();
      }
    }

    final mergedDecoration = decoration != null
        ? aqarMergeInputDecoration(context, decoration)
        : decoration;
    final formatters = aqarLocaleInputFormatters(
      context,
      localeScript: localeScript,
      existing: inputFormatters,
    );

    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    final effectiveStyle = (style ?? baseStyle)?.copyWith(
      height: style?.height ?? 1.25,
      fontSize: style?.fontSize ?? baseStyle?.fontSize ?? 16,
      fontFamily: style?.fontFamily ?? 'Cairo',
    );

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: mergedDecoration,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      onTap: handleTap,
      onChanged: onChanged,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      inputFormatters: formatters,
      style: effectiveStyle,
      textAlign: textAlign,
      textAlignVertical: TextAlignVertical.center,
      textDirection: textDirection,
      autofillHints: autofillHints,
      enableSuggestions: enableSuggestions,
      autocorrect: autocorrect,
      cursorColor: cursorColor,
      showCursor: showCursor,
      buildCounter: buildCounter,
      textCapitalization: textCapitalization,
      onTapOutside: onTapOutside,
      enableInteractiveSelection: enableInteractiveSelection,
      // السماح بتحديد النظام الأصلي (سحب/نقرتين) بلا GestureDetector يخطف الإيماءة.
      mouseCursor: SystemMouseCursors.text,
      scrollPadding: aqarFieldScrollPadding(context),
    );

    return field;
  }
}

/// TextFormField موحّد مع تحديد كامل عند النقر المزدوج.
class AqarTextFormField extends FormField<String> {
  AqarTextFormField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onFieldSubmitted,
    this.onTap,
    this.onChanged,
    this.autofocus = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.inputFormatters,
    this.style,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.autofillHints,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.selectAllOnDoubleTap = true,
    this.textCapitalization = TextCapitalization.none,
    this.localeScript,
    super.initialValue,
    super.validator,
    super.onSaved,
    super.enabled,
    super.autovalidateMode,
    super.restorationId,
  }) : super(
          builder: (FormFieldState<String> field) {
            final state = field as _AqarTextFormFieldState;
            final ctx = field.context;
            final effectiveDecoration = aqarMergeInputDecoration(
              ctx,
              decoration,
            );
            final formatters = aqarLocaleInputFormatters(
              ctx,
              localeScript: localeScript,
              existing: inputFormatters,
            );

            void handleTap() {
              onTap?.call();
              final node = focusNode;
              if (node != null) {
                if (!node.hasFocus) node.requestFocus();
              }
            }

            final baseStyle = Theme.of(ctx).textTheme.bodyLarge;
            final effectiveStyle = (style ?? baseStyle)?.copyWith(
              height: style?.height ?? 1.25,
              fontSize: style?.fontSize ?? baseStyle?.fontSize ?? 16,
              fontFamily: style?.fontFamily ?? 'Cairo',
            );

            return TextField(
              controller: state._effectiveController,
              focusNode: focusNode,
              decoration: effectiveDecoration.copyWith(
                errorText: field.errorText,
              ),
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              obscureText: obscureText,
              onSubmitted: onFieldSubmitted,
              onTap: handleTap,
              onChanged: (value) {
                field.didChange(value);
                onChanged?.call(value);
              },
              autofocus: autofocus,
              enabled: enabled,
              readOnly: readOnly,
              maxLines: maxLines,
              minLines: minLines,
              maxLength: maxLength,
              inputFormatters: formatters,
              style: effectiveStyle,
              textAlign: textAlign,
              textAlignVertical: TextAlignVertical.center,
              textDirection: textDirection,
              autofillHints: autofillHints,
              enableSuggestions: enableSuggestions,
              autocorrect: autocorrect,
              textCapitalization: textCapitalization,
              enableInteractiveSelection: true,
              mouseCursor: SystemMouseCursors.text,
              scrollPadding: aqarFieldScrollPadding(field.context),
            );
          },
        );

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final Iterable<String>? autofillHints;
  final bool enableSuggestions;
  final bool autocorrect;
  final bool selectAllOnDoubleTap;
  final TextCapitalization textCapitalization;
  final AqarLocaleScript? localeScript;

  @override
  FormFieldState<String> createState() => _AqarTextFormFieldState();
}

class _AqarTextFormFieldState extends FormFieldState<String> {
  TextEditingController? _controller;

  TextEditingController get _effectiveController =>
      widget.controller ?? _controller!;

  @override
  AqarTextFormField get widget => super.widget as AqarTextFormField;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _controller = TextEditingController(text: widget.initialValue ?? '');
    }
    widget.controller?.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AqarTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_handleControllerChanged);
      widget.controller?.addListener(_handleControllerChanged);
      if (oldWidget.controller != null && widget.controller == null) {
        _controller = TextEditingController.fromValue(oldWidget.controller!.value);
      }
      if (widget.controller != null && oldWidget.controller == null) {
        _controller?.dispose();
        _controller = null;
      }
    }
  }

  void _handleControllerChanged() {
    if (widget.controller == null) return;
    if (widget.controller!.text != value) {
      didChange(widget.controller!.text);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChange(String? value) {
    super.didChange(value);
    if (widget.controller == null) {
      _controller!.text = value ?? '';
    }
  }

  @override
  void reset() {
    super.reset();
    if (widget.controller == null) {
      _controller!.text = widget.initialValue ?? '';
    } else {
      widget.controller!.text = widget.initialValue ?? '';
    }
  }
}
