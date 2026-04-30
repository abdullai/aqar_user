import 'package:flutter/material.dart';

/// ألوان/حدود موحّدة لمجموعات الحقول (نفس منطق البطاقات في [AppTheme]).
abstract final class FieldGroupTheme {
  static BoxDecoration boxDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;
    final frameBlend = Color.alphaBlend(
      accent.withValues(alpha: cs.brightness == Brightness.dark ? 0.32 : 0.24),
      cs.outlineVariant.withValues(alpha: 0.55),
    );
    final fill = cs.surfaceContainerHighest.withValues(
      alpha: cs.brightness == Brightness.dark ? 0.42 : 0.55,
    );
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: frameBlend, width: 1),
      color: fill,
    );
  }
}

/// إطار موحّد لمجموعات الحقول (يستخدم [FieldGroupTheme]).
class FieldGroupFrame extends StatelessWidget {
  const FieldGroupFrame({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: FieldGroupTheme.boxDecoration(context),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
