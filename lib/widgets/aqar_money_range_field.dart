import 'package:flutter/material.dart';

import '../core/branding/aqar_brand_colors.dart';
import '../core/input/saudi_input_formatters.dart';
import 'saudi_riyal_symbol_icon.dart';

/// حقل سعر/مبلغ محدد من–إلى مع رمز الريال (عربي) أو SAR (إنجليزي).
class AqarMoneyRangeField extends StatelessWidget {
  const AqarMoneyRangeField({
    super.key,
    required this.isAr,
    required this.minInitial,
    required this.maxInitial,
    required this.onMinChanged,
    required this.onMaxChanged,
    this.minHint,
    this.maxHint,
    this.label,
  });

  final bool isAr;
  final String minInitial;
  final String maxInitial;
  final ValueChanged<String> onMinChanged;
  final ValueChanged<String> onMaxChanged;
  final String? minHint;
  final String? maxHint;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = label ?? (isAr ? 'المبلغ المحدد / السعر' : 'Specified amount / Price');

    InputDecoration deco({
      required String hint,
      required Widget suffix,
    }) {
      return InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AqarBrandColors.accent.withValues(alpha: 0.55),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AqarBrandColors.border.withValues(alpha: 0.9),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AqarBrandColors.border.withValues(alpha: 0.9),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AqarBrandColors.primary,
            width: 1.5,
          ),
        ),
        suffixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: suffix,
        ),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 36, minHeight: 24),
      );
    }

    Widget currencySuffix() {
      if (isAr) {
        return const SaudiRiyalSymbolIcon(
          size: 16,
          color: AqarBrandColors.primary,
        );
      }
      return Text(
        'SAR',
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: AqarBrandColors.primary,
          fontFamily: 'Cairo',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            fontFamily: 'Cairo',
            color: AqarBrandColors.dark,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: minInitial,
                keyboardType: TextInputType.number,
                inputFormatters: latinDecimalNumberFormatters(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                ),
                onChanged: onMinChanged,
                decoration: deco(
                  hint: minHint ?? (isAr ? 'من' : 'From'),
                  suffix: currencySuffix(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: maxInitial,
                keyboardType: TextInputType.number,
                inputFormatters: latinDecimalNumberFormatters(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                ),
                onChanged: onMaxChanged,
                decoration: deco(
                  hint: maxHint ?? (isAr ? 'إلى' : 'To'),
                  suffix: currencySuffix(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isAr
              ? 'نطاق المبلغ المحدد: الرقم ثم رمز الريال — بدون لفّ'
              : 'Specified amount range: number then SAR — no wrap',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
