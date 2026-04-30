import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'saudi_riyal_symbol_icon.dart';

/// حقل مبلغ مع رمز الريال يظهر فقط عند وجود أرقام، وحجمه ولونه يتبعان الثيم وحجم النص.
class BudgetTextField extends StatefulWidget {
  const BudgetTextField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType keyboardType;

  @override
  State<BudgetTextField> createState() => _BudgetTextFieldState();
}

class _BudgetTextFieldState extends State<BudgetTextField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant BudgetTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() => setState(() {});

  bool get _hasDigits =>
      RegExp(r'[0-9]').hasMatch(widget.controller.text.trim());

  double _symbolSize(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge?.fontSize ??
        theme.textTheme.titleMedium?.fontSize ??
        16.0;
    final scaled = MediaQuery.textScalerOf(context).scale(base);
    return scaled.clamp(16.0, 28.0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurfaceVariant;
    final h = _symbolSize(context);

    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: _hasDigits
            ? Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Align(
                  widthFactor: 1,
                  heightFactor: 1,
                  alignment: AlignmentDirectional.centerEnd,
                  child: SaudiRiyalSymbolIcon(
                    size: h,
                    color: color,
                  ),
                ),
              )
            : null,
        suffixIconConstraints: _hasDigits
            ? BoxConstraints(
                minWidth: h * 1.25,
                minHeight: 36,
                maxHeight: 40,
              )
            : null,
      ),
    );
  }
}
