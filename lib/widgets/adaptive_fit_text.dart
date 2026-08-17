import 'package:flutter/material.dart';

/// نص يتكيّف مع العرض: سطر واحد بدون التفاف، يُصغَّر بلطف عند الضيق.
class AdaptiveFitText extends StatelessWidget {
  const AdaptiveFitText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.textAlign = TextAlign.center,
    this.minScale = 0.72,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;
  final double minScale;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: textAlign == TextAlign.start
          ? AlignmentDirectional.centerStart
          : Alignment.center,
      child: Text(
        text,
        maxLines: maxLines,
        softWrap: false,
        overflow: TextOverflow.visible,
        textAlign: textAlign,
        style: (style ?? const TextStyle()).copyWith(
          fontWeight: style?.fontWeight ?? FontWeight.w900,
          height: style?.height ?? 1.15,
          fontFamily: style?.fontFamily ?? 'Cairo',
        ),
      ),
    );
  }
}
