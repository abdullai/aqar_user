import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/input/saudi_input_formatters.dart';

class SixDigitPinFields extends StatefulWidget {
  const SixDigitPinFields({
    super.key,
    required this.controller,
    required this.label,
    this.length = 6,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
  }) : assert(length > 0);

  final TextEditingController controller;
  final String label;
  final int length;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  State<SixDigitPinFields> createState() => _SixDigitPinFieldsState();
}

class _SixDigitPinFieldsState extends State<SixDigitPinFields> {
  late List<TextEditingController> _fields;
  late List<FocusNode> _focusNodes;
  late List<String> _digits;
  String _lastPublished = '';

  @override
  void initState() {
    super.initState();
    _createFields();
    widget.controller.addListener(_syncFromParent);
    _syncFromParent();
  }

  @override
  void didUpdateWidget(covariant SixDigitPinFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromParent);
      widget.controller.addListener(_syncFromParent);
      _syncFromParent();
    }
    if (oldWidget.length != widget.length) {
      _disposeFields();
      _createFields();
      _syncFromParent();
    }
  }

  void _createFields() {
    _digits = List<String>.filled(widget.length, '');
    _fields = List<TextEditingController>.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _focusNodes = List<FocusNode>.generate(
      widget.length,
      (_) => FocusNode(),
    );
  }

  void _disposeFields() {
    for (final field in _fields) {
      field.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
  }

  String _asciiDigits(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final result = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final arabicIndex = arabic.indexOf(char);
      final persianIndex = persian.indexOf(char);
      if (arabicIndex >= 0) {
        result.write(arabicIndex);
      } else if (persianIndex >= 0) {
        result.write(persianIndex);
      } else if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        result.write(char);
      }
    }
    return result.toString();
  }

  void _syncFromParent() {
    final incoming = _asciiDigits(widget.controller.text);
    if (incoming == _lastPublished) return;
    _lastPublished = incoming;
    for (var i = 0; i < widget.length; i++) {
      final value = i < incoming.length ? incoming[i] : '';
      _digits[i] = value;
      _setFieldValue(i, value);
    }
  }

  void _setFieldValue(int index, String value) {
    if (_fields[index].text == value) return;
    _fields[index].value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _publish() {
    final value = _digits.join();
    _lastPublished = value;
    if (widget.controller.text != value) {
      widget.controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    widget.onChanged?.call(value);
  }

  void _onFieldChanged(int index, String rawValue) {
    final value = _asciiDigits(rawValue);
    if (value.isEmpty) {
      final wasEmpty = _digits[index].isEmpty;
      _digits[index] = '';
      _publish();
      if (wasEmpty && index > 0) _focusNodes[index - 1].requestFocus();
      return;
    }

    final pasteAtStart = value.length >= widget.length;
    final start = pasteAtStart ? 0 : index;
    for (var i = 0; i < value.length && start + i < widget.length; i++) {
      _digits[start + i] = value[i];
      _setFieldValue(start + i, value[i]);
    }
    _publish();

    final next = start + value.length;
    if (next < widget.length) {
      _focusNodes[next].requestFocus();
    } else {
      _focusNodes[widget.length - 1].requestFocus();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromParent);
    _disposeFields();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: List.generate(
              widget.length,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: index == widget.length - 1 ? 0 : 6,
                  ),
                  child: TextField(
                    controller: _fields[index],
                    focusNode: _focusNodes[index],
                    enabled: widget.enabled,
                    autofocus: widget.autofocus && index == 0,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textInputAction: index == widget.length - 1
                        ? TextInputAction.done
                        : TextInputAction.next,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      const ArabicDigitsToLatinFormatter(),
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (value) => _onFieldChanged(index, value),
                    onSubmitted: (_) {
                      if (index < widget.length - 1) {
                        _focusNodes[index + 1].requestFocus();
                      } else {
                        FocusScope.of(context).unfocus();
                      }
                    },
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
