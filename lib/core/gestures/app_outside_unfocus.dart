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

  static bool hasNonCollapsedSelection() {
    final focus = FocusManager.instance.primaryFocus;
    final state = focus?.context?.findAncestorStateOfType<EditableTextState>();
    if (state == null) return false;
    try {
      final sel = state.widget.controller.selection;
      return sel.isValid && !sel.isCollapsed;
    } catch (_) {
      return false;
    }
  }

  static bool pointerHitsFocusedEditable(Offset global) {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null || !ctx.mounted) return false;
    final state = ctx.findAncestorStateOfType<EditableTextState>();
    if (state == null) return false;
    final box = state.context.findRenderObject() ?? ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    try {
      final origin = box.localToGlobal(Offset.zero);
      return (origin & box.size).inflate(48).contains(global);
    } catch (_) {
      return false;
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
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          switch (e.kind) {
            case PointerDeviceKind.touch:
            case PointerDeviceKind.mouse:
            case PointerDeviceKind.stylus:
            case PointerDeviceKind.invertedStylus:
              break;
            default:
              return;
          }
          if (hasNonCollapsedSelection()) return;
          if (pointerHitsFocusedEditable(e.position)) return;
          unfocusEditable();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: unfocusEditable,
          child: child,
        ),
      ),
    );
  }
}
