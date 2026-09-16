import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/gestures/app_keyboard_inset.dart';
import '../core/gestures/app_outside_unfocus.dart';
import '../core/haptics/app_haptics.dart';
import '../core/input/aqar_editable_defaults.dart';
import '../core/input/aqar_field_keyboard.dart';
import '../core/input/locale_text_input_guard.dart';
import '../core/platform/viewport_scroll_policy.dart';
import 'aqar_input_helpers.dart';

/// هامش سفلي يكفي لإبقاء الحقل فوق الكيبورد مع بقاء التمرير في الخلفية.
EdgeInsets aqarFieldScrollPadding(BuildContext context) {
  final extra = AppKeyboardInset.scrollContentBottomOf(context);
  final bottom = extra > 0 ? (extra * 0.35).clamp(24.0, 80.0) : 10.0;
  return EdgeInsets.fromLTRB(8, 10, 8, bottom);
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
    }

    final mergedDecoration = decoration != null
        ? aqarMergeInputDecoration(context, decoration)
        : decoration;
    final compact = ViewportScrollPolicy.isCompactTouchLike(context);
    final multiline = AqarFieldKeyboard.isMultilineField(
      maxLines: maxLines,
      minLines: minLines,
      obscureText: obscureText,
    );
    final resolvedKeyboard = AqarFieldKeyboard.keyboardForField(
      requested: keyboardType,
      compactTouch: compact,
      multiline: multiline,
    );
    final resolvedAction = AqarFieldKeyboard.actionForField(
      requested: textInputAction,
      multiline: multiline,
    );
    final formatters = AqarFieldKeyboard.mergeNumericFormatters(
      keyboardType: resolvedKeyboard,
      existing: aqarLocaleInputFormatters(
        context,
        localeScript: localeScript,
        existing: inputFormatters,
      ),
    );
    final numeric = AqarFieldKeyboard.isNumericType(resolvedKeyboard);
    final resolvedDirection = AqarEditableDefaults.directionFor(
      obscureText: obscureText,
      keyboardType: resolvedKeyboard,
      requested: textDirection,
      localeScript: localeScript,
    );

    final effectiveStyle = AqarEditableDefaults.styleFor(context, style);

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: mergedDecoration,
      keyboardType: resolvedKeyboard,
      textInputAction: resolvedAction,
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
      strutStyle: AqarEditableDefaults.strutFor(effectiveStyle),
      textAlign: textAlign,
      textAlignVertical:
          multiline ? TextAlignVertical.top : TextAlignVertical.center,
      textDirection: resolvedDirection,
      autofillHints: autofillHints,
      enableSuggestions: numeric || obscureText ? false : enableSuggestions,
      autocorrect: numeric || obscureText ? false : autocorrect,
      cursorColor: cursorColor,
      cursorHeight: AqarEditableDefaults.cursorHeightFor(effectiveStyle),
      cursorRadius: const Radius.circular(1.2),
      cursorOpacityAnimates: !kIsWeb,
      showCursor: showCursor,
      buildCounter: buildCounter,
      textCapitalization: textCapitalization,
      onTapOutside: onTapOutside ?? (_) => AppOutsideUnfocus.unfocusEditable(),
      enableInteractiveSelection: enableInteractiveSelection,
      mouseCursor: SystemMouseCursors.text,
      scrollPadding: AppKeyboardInset.inputScrollPadding(context),
      cursorWidth: AqarEditableDefaults.cursorWidth(context),
      selectionHeightStyle: AqarEditableDefaults.heightStyle,
      selectionWidthStyle: AqarEditableDefaults.widthStyle,
      magnifierConfiguration: AqarEditableDefaults.magnifier(),
      selectionControls: AqarEditableDefaults.selectionControls(),
      smartDashesType: AqarEditableDefaults.dashes(
        obscureText: obscureText,
        numeric: numeric,
      ),
      smartQuotesType: AqarEditableDefaults.quotes(
        obscureText: obscureText,
        numeric: numeric,
      ),
      contextMenuBuilder: AqarEditableDefaults.contextMenu,
      onEditingComplete: resolvedAction == TextInputAction.next
          ? () {
              AppHaptics.selection();
              FocusScope.of(context).nextFocus();
            }
          : null,
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
            final compact = ViewportScrollPolicy.isCompactTouchLike(ctx);
            final multiline = AqarFieldKeyboard.isMultilineField(
              maxLines: maxLines,
              minLines: minLines,
              obscureText: obscureText,
            );
            final resolvedKeyboard = AqarFieldKeyboard.keyboardForField(
              requested: keyboardType,
              compactTouch: compact,
              multiline: multiline,
            );
            final resolvedAction = AqarFieldKeyboard.actionForField(
              requested: textInputAction,
              multiline: multiline,
            );
            final formatters = AqarFieldKeyboard.mergeNumericFormatters(
              keyboardType: resolvedKeyboard,
              existing: aqarLocaleInputFormatters(
                ctx,
                localeScript: localeScript,
                existing: inputFormatters,
              ),
            );
            final numeric = AqarFieldKeyboard.isNumericType(resolvedKeyboard);
            final resolvedDirection = AqarEditableDefaults.directionFor(
              obscureText: obscureText,
              keyboardType: resolvedKeyboard,
              requested: textDirection,
              localeScript: localeScript,
            );

            void handleTap() {
              onTap?.call();
            }

            final effectiveStyle = AqarEditableDefaults.styleFor(ctx, style);

            return TextField(
              controller: state._effectiveController,
              focusNode: focusNode,
              decoration: effectiveDecoration.copyWith(
                errorText: field.errorText,
              ),
              keyboardType: resolvedKeyboard,
              textInputAction: resolvedAction,
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
              strutStyle: AqarEditableDefaults.strutFor(effectiveStyle),
              textAlign: textAlign,
              textAlignVertical:
                  multiline ? TextAlignVertical.top : TextAlignVertical.center,
              textDirection: resolvedDirection,
              autofillHints: autofillHints,
              enableSuggestions:
                  numeric || obscureText ? false : enableSuggestions,
              autocorrect: numeric || obscureText ? false : autocorrect,
              textCapitalization: textCapitalization,
              enableInteractiveSelection: true,
              mouseCursor: SystemMouseCursors.text,
              scrollPadding: AppKeyboardInset.inputScrollPadding(field.context),
              cursorWidth: AqarEditableDefaults.cursorWidth(ctx),
              cursorHeight:
                  AqarEditableDefaults.cursorHeightFor(effectiveStyle),
              cursorRadius: const Radius.circular(1.2),
              cursorOpacityAnimates: !kIsWeb,
              selectionHeightStyle: AqarEditableDefaults.heightStyle,
              selectionWidthStyle: AqarEditableDefaults.widthStyle,
              magnifierConfiguration: AqarEditableDefaults.magnifier(),
              selectionControls: AqarEditableDefaults.selectionControls(),
              smartDashesType: AqarEditableDefaults.dashes(
                obscureText: obscureText,
                numeric: numeric,
              ),
              smartQuotesType: AqarEditableDefaults.quotes(
                obscureText: obscureText,
                numeric: numeric,
              ),
              contextMenuBuilder: AqarEditableDefaults.contextMenu,
              onTapOutside: (_) => AppOutsideUnfocus.unfocusEditable(),
              onEditingComplete: resolvedAction == TextInputAction.next
                  ? () {
                      AppHaptics.selection();
                      FocusScope.of(ctx).nextFocus();
                    }
                  : null,
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
        _controller =
            TextEditingController.fromValue(oldWidget.controller!.value);
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
