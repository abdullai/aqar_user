import 'package:flutter/material.dart';

import '../core/gestures/app_keyboard_popups.dart';

/// حوار ما بعد النشر: أزرار متكيّفة، أيقونة حالة، ونص يطابق مسار الإعلان.
Future<String?> showAdaptivePostPublishDialog({
  required BuildContext context,
  required bool isAr,
  required String title,
  required String body,
  String? codeLine,
  String? statusChip,
  required List<AdaptivePostPublishAction> actions,
  IconData? leadingIcon,
  Color? accentColor,
}) {
  return showAppDialog<String>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final size = MediaQuery.sizeOf(ctx);
      final w = size.width;
      final stackActions = w < 640 || actions.length >= 3;
      final maxContentW = (w - (w < 420 ? 28 : 48)).clamp(220.0, 480.0);
      final accent = accentColor ?? const Color(0xFF0F766E);

      return AlertDialog(
        backgroundColor: cs.surface,
        elevation: 8,
        shadowColor: accent.withValues(alpha: 0.18),
        insetPadding: EdgeInsets.symmetric(
          horizontal: w < 420 ? 10 : 24,
          vertical: 18,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: accent.withValues(alpha: 0.14)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  leadingIcon ?? Icons.check_circle_rounded,
                  color: accent,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if ((statusChip ?? '').trim().isNotEmpty) ...[
              Align(
                alignment:
                    isAr ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.22)),
                  ),
                  child: Text(
                    statusChip!.trim(),
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      height: 1.2,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              title,
              maxLines: 3,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                height: 1.28,
                fontFamily: 'Cairo',
                fontSize: w < 380 ? 16 : 18,
                color: cs.onSurface,
              ),
            ),
          ],
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
                    height: 1.45,
                    fontFamily: 'Cairo',
                    fontSize: w < 380 ? 12.5 : 13.5,
                  ),
                ),
                if ((codeLine ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: SelectableText(
                        codeLine!.trim(),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          height: 1.3,
                          fontFamily: 'Cairo',
                        ),
                      ),
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

    void onPressed() => Navigator.pop(context, action.id);
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

    const pad = EdgeInsets.symmetric(vertical: 12, horizontal: 8);
    const styleBase = ButtonStyle(
      padding: WidgetStatePropertyAll(pad),
      minimumSize: WidgetStatePropertyAll(Size(0, 46)),
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
