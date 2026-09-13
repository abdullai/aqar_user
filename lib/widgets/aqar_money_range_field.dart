import 'package:flutter/material.dart';

import '../core/branding/aqar_brand_colors.dart';
import '../core/input/saudi_input_formatters.dart';
import '../core/utils/app_money.dart';
import 'aqar_text_field.dart';
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
      required Widget currency,
    }) {
      final iconPad = Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          alignment: Alignment.center,
          child: currency,
        ),
      );
      return InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AqarBrandColors.wash(cs).withValues(alpha: 0.55),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AqarBrandColors.frame(cs).withValues(alpha: 0.9),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AqarBrandColors.frame(cs).withValues(alpha: 0.9),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AqarBrandColors.primary,
            width: 1.5,
          ),
        ),
        suffixIcon: iconPad,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 40,
          maxHeight: 48,
        ),
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
        AppMoney.sarUiSuffix(isAr: false),
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w900,
          color: AqarBrandColors.primary,
          fontFamily: 'Cairo',
          height: 1.0,
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
            color: AqarBrandColors.ink(cs),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AqarTextFormField(
                initialValue: minInitial,
                keyboardType: TextInputType.number,
                inputFormatters: latinDecimalNumberFormatters(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                ),
                textAlign: TextAlign.end,
                textDirection: TextDirection.ltr,
                onChanged: onMinChanged,
                decoration: deco(
                  hint: minHint ?? (isAr ? 'من' : 'From'),
                  currency: currencySuffix(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AqarTextFormField(
                initialValue: maxInitial,
                keyboardType: TextInputType.number,
                inputFormatters: latinDecimalNumberFormatters(),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                ),
                textAlign: TextAlign.end,
                textDirection: TextDirection.ltr,
                onChanged: onMaxChanged,
                decoration: deco(
                  hint: maxHint ?? (isAr ? 'إلى' : 'To'),
                  currency: currencySuffix(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isAr
              ? 'نطاق المبلغ المحدد: رمز الريال ثم الرقم — بدون لفّ'
              : 'Specified amount range: SAR then the number — no wrap',
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
