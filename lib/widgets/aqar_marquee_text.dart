import 'package:flutter/material.dart';

/// نص يمرّ إذا ضاق العرض (يثبت ثم يتحرك ثم يعيد)، وإلا يظهر سطراً واحداً.
class AqarMarqueeText extends StatefulWidget {
  const AqarMarqueeText({
    super.key,
    required this.text,
    this.style,
    this.height = 18,
  });

  final String text;
  final TextStyle? style;
  final double height;

  @override
  State<AqarMarqueeText> createState() => _AqarMarqueeTextState();
}

class _AqarMarqueeTextState extends State<AqarMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
  }

  @override
  void didUpdateWidget(covariant AqarMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          if (!maxW.isFinite || maxW <= 8) {
            return Text(
              widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            );
          }
          final tp = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
            ellipsis: '…',
          )..layout();
          final textW = tp.width;
          if (textW <= maxW + 1) {
            _ctrl.stop();
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: style,
              ),
            );
          }
          if (!_ctrl.isAnimating) {
            _ctrl.repeat();
          }
          final extra = textW - maxW + 24;
          return ClipRect(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                // يثبت في البداية والنهاية ثم يتحرك.
                final t = _ctrl.value;
                double u;
                if (t < 0.18) {
                  u = 0;
                } else if (t < 0.72) {
                  u = (t - 0.18) / 0.54;
                } else if (t < 0.88) {
                  u = 1;
                } else {
                  u = 1 - ((t - 0.88) / 0.12);
                }
                final dx = extra * u;
                final rtl = Directionality.of(context) == TextDirection.rtl;
                return Transform.translate(
                  offset: Offset(rtl ? dx : -dx, 0),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 1,
                    child: Text(
                      widget.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: style,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
