import 'package:flutter/material.dart';

/// موافقة إلزامية على الشروط قبل النشر.
class TermsAcceptanceCheckbox extends StatelessWidget {
  const TermsAcceptanceCheckbox({
    super.key,
    required this.isAr,
    required this.value,
    required this.onChanged,
    this.onOpenTerms,
  });

  final bool isAr;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final VoidCallback? onOpenTerms;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      isAr
                          ? 'أوافق على '
                          : 'I agree to the ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    InkWell(
                      onTap: onOpenTerms,
                      child: Text(
                        isAr ? 'الشروط والأحكام' : 'Terms & Conditions',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w900,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      isAr ? ' قبل النشر.' : ' before publishing.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
