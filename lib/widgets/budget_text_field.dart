import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aqar_text_field.dart';
import 'saudi_riyal_symbol_icon.dart';

/// حقل مبلغ: رمز الريال أو SAR ظاهر دائماً قبل الرقم.
///
/// يُبنى على [AqarTextField] / [AqarTextFormField] فقط — نفس التحديد الضيّق
/// ([AqarEditableDefaults]) وتفريق التركيز ([AppOutsideUnfocus]) لكل الحقول.
class BudgetTextField extends StatefulWidget {
  const BudgetTextField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.isAr = true,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
    this.validator,
    this.alignOpposite = false,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool isAr;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final bool alignOpposite;

  @override
  State<BudgetTextField> createState() => _BudgetTextFieldState();
}

class _BudgetTextFieldState extends State<BudgetTextField> {
  double _symbolSize(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge?.fontSize ??
        theme.textTheme.titleMedium?.fontSize ??
        16.0;
    return MediaQuery.textScalerOf(context).scale(base).clamp(14.0, 22.0);
  }

  Widget _currency(BuildContext context, Color color, double h) {
    if (widget.isAr) {
      return SaudiRiyalSymbolIcon(size: h, color: color);
    }
    return Text(
      'SAR',
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: h * 0.72,
        color: color,
        fontFamily: 'Cairo',
        height: 1.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurfaceVariant;
    final h = _symbolSize(context);
    final suffixW = widget.isAr ? h * 1.35 + 16 : h * 2.1 + 12;

    final decoration = InputDecoration(
      labelText: widget.label,
      border: const OutlineInputBorder(),
      isDense: true,
      prefixIcon: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          alignment: Alignment.center,
          child: _currency(context, color, h),
        ),
      ),
      prefixIconConstraints: BoxConstraints(
        minWidth: suffixW,
        minHeight: 40,
        maxHeight: 48,
      ),
    );

    final field = widget.validator == null
        ? AqarTextField(
            controller: widget.controller,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            inputFormatters: widget.inputFormatters,
            textAlign: TextAlign.end,
            textDirection: TextDirection.ltr,
            decoration: decoration,
          )
        : AqarTextFormField(
            controller: widget.controller,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            inputFormatters: widget.inputFormatters,
            textAlign: TextAlign.end,
            textDirection: TextDirection.ltr,
            decoration: decoration,
            validator: widget.validator,
          );

    if (!widget.alignOpposite) return field;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: field,
      ),
    );
  }
}
