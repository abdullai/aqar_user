import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/input/input_normalizers.dart';
import 'aqar_text_field.dart';

/// عدد ذكي: قائمة منسدلة + إدخال يدوي (أرقام فقط، عربي/هندي → لاتيني فوراً).
class SmartCountField extends StatefulWidget {
  const SmartCountField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isAr,
    this.enabled = true,
    this.min = 0,
    this.maxPreset = 12,
    this.allowClear = false,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool isAr;
  final bool enabled;
  final int min;
  final int maxPreset;
  final bool allowClear;

  @override
  State<SmartCountField> createState() => _SmartCountFieldState();
}

class _SmartCountFieldState extends State<SmartCountField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  final Set<int> _extra = <int>{};

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.value == null ? '' : '${widget.value}',
    );
    _focus = FocusNode()..addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant SmartCountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focus.hasFocus) {
      final next = widget.value == null ? '' : '${widget.value}';
      if (_ctrl.text != next) _ctrl.text = next;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commitText(_ctrl.text);
  }

  List<int> get _options {
    final out = <int>{
      for (var i = widget.min; i <= widget.maxPreset; i++) i,
      ..._extra,
      if (widget.value != null) widget.value!,
    }.toList()
      ..sort();
    return out;
  }

  void _commitText(String raw) {
    final d = digitsOnly(raw);
    if (d.isEmpty) {
      if (widget.allowClear) widget.onChanged(null);
      return;
    }
    final n = int.tryParse(d);
    if (n == null || n < widget.min) return;
    if (n > widget.maxPreset) _extra.add(n);
    widget.onChanged(n);
    final latin = '$n';
    if (_ctrl.text != latin) {
      _ctrl.value = TextEditingValue(
        text: latin,
        selection: TextSelection.collapsed(offset: latin.length),
      );
    }
    setState(() {});
  }

  void _onChanged(String raw) {
    final latin = normalizeAsciiDigits(raw).replaceAll(RegExp(r'[^0-9]'), '');
    if (latin != raw) {
      _ctrl.value = TextEditingValue(
        text: latin,
        selection: TextSelection.collapsed(offset: latin.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        enabled: widget.enabled,
      ),
      child: Row(
        children: [
          Expanded(
            child: AqarTextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
              ],
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: widget.enabled ? _onChanged : null,
              onSubmitted: widget.enabled ? _commitText : null,
            ),
          ),
          PopupMenuButton<int?>(
            enabled: widget.enabled,
            tooltip: widget.isAr ? 'اختر من القائمة' : 'Pick from list',
            icon: Icon(Icons.arrow_drop_down_rounded, color: cs.onSurfaceVariant),
            onSelected: (v) {
              if (v == null) {
                widget.onChanged(null);
                _ctrl.clear();
                return;
              }
              if (v > widget.maxPreset) _extra.add(v);
              widget.onChanged(v);
              _ctrl.text = '$v';
              setState(() {});
            },
            itemBuilder: (ctx) => [
              if (widget.allowClear)
                PopupMenuItem<int?>(
                  value: null,
                  child: Text(widget.isAr ? 'غير محدد' : 'Not set'),
                ),
              for (final n in _options)
                PopupMenuItem<int?>(
                  value: n,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      fontWeight: widget.value == n
                          ? FontWeight.w900
                          : FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
