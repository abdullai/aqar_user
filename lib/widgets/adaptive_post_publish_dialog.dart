import 'package:flutter/material.dart';

/// حوار ما بعد النشر: أزرار متكيّفة بدون التفاف مربك.
/// الشاشات الضيقة: عمود كامل العرض + نص يُصغَّر بلطف.
/// الشاشات العريضة: صف بأزرار متساوية.
Future<String?> showAdaptivePostPublishDialog({
  required BuildContext context,
  required bool isAr,
  required String title,
  required String body,
  String? codeLine,
  required List<AdaptivePostPublishAction> actions,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final size = MediaQuery.sizeOf(ctx);
      final w = size.width;
      // أقل من 640 أو ≥3 أزرار: عمود — يمنع التفاف النصوص على ويب الجوال.
      final stackActions = w < 640 || actions.length >= 3;
      final maxContentW = (w - (w < 420 ? 28 : 48)).clamp(220.0, 480.0);

      return AlertDialog(
        backgroundColor: cs.surface,
        insetPadding: EdgeInsets.symmetric(
          horizontal: w < 420 ? 10 : 24,
          vertical: 18,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          title,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            height: 1.25,
            fontFamily: 'Cairo',
            fontSize: w < 380 ? 16 : 18,
            color: cs.onSurface,
          ),
        ),
        content: SizedBox(
          width: maxContentW,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  body,
                  softWrap: true,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    fontFamily: 'Cairo',
                    fontSize: w < 380 ? 12.5 : 13.5,
                  ),
                ),
                if ((codeLine ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    codeLine!.trim(),
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                      height: 1.3,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (stackActions)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _AdaptiveActionButton(
                          action: actions[i],
                          expand: true,
                        ),
                      ],
                    ],
                  )
                else
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _AdaptiveActionButton(
                            action: actions[i],
                            expand: true,
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class AdaptivePostPublishAction {
  const AdaptivePostPublishAction({
    required this.id,
    required this.label,
    this.icon,
    this.filled = false,
    this.outlined = false,
  });

  final String id;
  final String label;
  final IconData? icon;
  final bool filled;
  final bool outlined;
}

class _AdaptiveActionButton extends StatelessWidget {
  const _AdaptiveActionButton({
    required this.action,
    this.expand = false,
  });

  final AdaptivePostPublishAction action;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        action.label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          height: 1.1,
          fontFamily: 'Cairo',
          fontSize: 14,
        ),
      ),
    );

    final onPressed = () => Navigator.pop(context, action.id);
    final child = action.icon == null
        ? label
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(action.icon, size: 18),
              const SizedBox(width: 6),
              Flexible(child: label),
            ],
          );

    final pad = const EdgeInsets.symmetric(vertical: 12, horizontal: 8);
    final styleBase = ButtonStyle(
      padding: WidgetStatePropertyAll(pad),
      minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    if (action.filled) {
      return FilledButton(
        onPressed: onPressed,
        style: styleBase,
        child: child,
      );
    }
    if (action.outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: styleBase,
        child: child,
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: styleBase,
      child: child,
    );
  }
}
