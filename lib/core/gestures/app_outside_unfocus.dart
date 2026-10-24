import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// يغلف التطبيق: ضغطة خارج حقل الإدخال تُغلق الكيبورد وتفكّ التركيز.
/// سحب زائد للأسفل عند رأس التمرير يفعل الشيء نفسه دون اعتراض التمرير العادي.
class AppOutsideUnfocus extends StatelessWidget {
  const AppOutsideUnfocus({super.key, required this.child});

  final Widget child;

  static void unfocusEditable() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;
    final ctx = focus.context;
    if (ctx == null || !ctx.mounted) return;
    if (ctx.findAncestorStateOfType<EditableTextState>() == null) return;
    focus.unfocus();
  }

  static void unfocusEditableFromOutsidePointer(PointerDownEvent event) {
    switch (event.kind) {
      case PointerDeviceKind.touch:
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        return;
      default:
        unfocusEditable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        if (n.metrics.pixels > 2) return false;
        final dy = n.dragDetails?.delta.dy ?? 0;
        if (n.overscroll < -4 || dy > 6) {
          unfocusEditable();
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: unfocusEditable,
        child: child,
      ),
    );
  }
}
