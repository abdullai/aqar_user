import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/input/caps_lock_signal.dart';
import '../core/input/caps_lock_tracker.dart';
import '../core/input/smart_keyboard_formatter.dart';
import '../l10n/app_localizations.dart';
import 'aqar_text_field.dart';

/// حقل كلمة مرور موحّد: Caps Lock لكل الشاشات دون منطق داخل Login/Register.
class CapsAwarePasswordField extends StatefulWidget {
  const CapsAwarePasswordField({
    super.key,
    required this.controller,
    this.focusNode,
    this.obscureText = true,
    this.onToggleObscure,
    this.enabled = true,
    this.decoration,
    this.onSubmitted,
    this.onChanged,
    this.textInputAction = TextInputAction.done,
    this.inputFormatters,
    this.style,
    this.cursorColor,
    this.lockIcon = Icons.lock_outline_rounded,
    this.iconColor,
    this.isAr = true,
    this.autofillHints = const [AutofillHints.password],
    @visibleForTesting this.debugReadHardware,
    @visibleForTesting this.debugReadBrowser,
    @visibleForTesting this.debugHardwareTrusted,
    @visibleForTesting this.debugPreferBrowser,
    @visibleForTesting this.debugUseTextUnderField,
    @visibleForTesting this.debugInferSoftCaps,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final bool enabled;
  final InputDecoration? decoration;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final Color? cursorColor;
  final IconData lockIcon;
  final Color? iconColor;
  final bool isAr;
  final Iterable<String>? autofillHints;

  @visibleForTesting
  final CapsLockSignal Function()? debugReadHardware;
  @visibleForTesting
  final CapsLockSignal Function()? debugReadBrowser;
  @visibleForTesting
  final bool Function()? debugHardwareTrusted;
  @visibleForTesting
  final bool Function()? debugPreferBrowser;
  @visibleForTesting
  final bool? debugUseTextUnderField;
  @visibleForTesting
  final bool? debugInferSoftCaps;

  @override
  State<CapsAwarePasswordField> createState() => _CapsAwarePasswordFieldState();
}

class _CapsAwarePasswordFieldState extends State<CapsAwarePasswordField> {
  late final CapsLockTracker _tracker;
  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus!;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocus = FocusNode();
    }
    _tracker = CapsLockTracker(
      onChanged: _onCaps,
      readHardware: widget.debugReadHardware,
      readBrowser: widget.debugReadBrowser,
      hardwareTrusted: widget.debugHardwareTrusted,
      preferBrowser: widget.debugPreferBrowser,
      inferUnshiftedUpperAsOn: _inferSoftCaps,
    );
    _tracker.attach();
    _lastText = widget.controller.text;
    _focus.addListener(_onFocus);
    if (_focus.hasFocus) {
      _tracker.onFocusChanged(true);
    }
  }

  @override
  void didUpdateWidget(covariant CapsAwarePasswordField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocus)?.removeListener(_onFocus);
      if (oldWidget.focusNode == null && widget.focusNode != null) {
        _ownedFocus?.dispose();
        _ownedFocus = null;
      }
      if (widget.focusNode == null) {
        _ownedFocus ??= FocusNode();
      }
      _focus.addListener(_onFocus);
      _tracker.onFocusChanged(_focus.hasFocus);
    }
    _tracker.bindSourceOverrides(
      readHardware: widget.debugReadHardware,
      readBrowser: widget.debugReadBrowser,
      hardwareTrusted: widget.debugHardwareTrusted,
      preferBrowser: widget.debugPreferBrowser,
      inferUnshiftedUpperAsOn: _inferSoftCaps,
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _tracker.detach();
    _ownedFocus?.dispose();
    super.dispose();
  }

  bool _inferSoftCaps() {
    if (widget.debugInferSoftCaps != null) return widget.debugInferSoftCaps!;
    final useText = widget.debugUseTextUnderField ??
        SmartKeyboardFormatter.useCapsTextUnderField(context);
    return !useText;
  }

  void _onCaps() {
    if (mounted) setState(() {});
  }

  void _onFocus() {
    _tracker.onFocusChanged(_focus.hasFocus);
  }

  String _capsLabel(BuildContext context) {
    return AppLocalizations.of(context)?.capsLockOn ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final iconColor =
        widget.iconColor ?? theme.iconTheme.color ?? theme.colorScheme.onSurface;
    final focused = _focus.hasFocus;
    final useText = widget.debugUseTextUnderField ??
        SmartKeyboardFormatter.useCapsTextUnderField(context);
    final capsOk = SmartKeyboardFormatter.allowCapsLockChrome(context);
    final on = capsOk && _tracker.isOn && focused;
    final showGlyph = on && !useText;
    final showText = on && useText;
    final label = _capsLabel(context);

    Widget eyeButton() => IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          tooltip: widget.obscureText
              ? (widget.isAr ? 'إظهار' : 'Show')
              : (widget.isAr ? 'إخفاء' : 'Hide'),
          onPressed: widget.onToggleObscure,
          icon: Icon(
            widget.obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: iconColor,
          ),
        );

    final affixes = CapsLockFieldAffixes.build(
      isRtl: rtl,
      showGlyph: showGlyph,
      capsLockLabel: label,
      isLight: isLight,
      iconColor: iconColor,
      eyeButton: eyeButton(),
      lockIcon: widget.lockIcon,
    );

    final base = widget.decoration ?? const InputDecoration();
    final merged = base.copyWith(
      prefixIcon: affixes.prefix,
      suffixIcon: affixes.suffix,
      prefixIconConstraints: affixes.prefixConstraints,
      suffixIconConstraints: affixes.suffixConstraints,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AqarTextField(
          controller: widget.controller,
          focusNode: _focus,
          obscureText: widget.obscureText,
          enabled: widget.enabled,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          onChanged: (v) {
            _tracker.inferFromInsertedLatin(_lastText, v);
            _lastText = v;
            widget.onChanged?.call(v);
          },
          keyboardType: SmartKeyboardFormatter.passwordKeyboard,
          localeScript: SmartKeyboardFormatter.englishScript,
          enableSuggestions: false,
          autocorrect: false,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          style: widget.style,
          cursorColor: widget.cursorColor,
          decoration: merged,
          onTap: () {
            if (!_focus.hasFocus) _focus.requestFocus();
            _tracker.sync(immediate: true);
          },
        ),
        if (useText)
          CapsLockHintText(
            visible: showText,
            label: label,
            isLight: isLight,
          ),
      ],
    );
  }
}
