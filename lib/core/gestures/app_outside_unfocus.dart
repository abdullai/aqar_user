import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// يغلق التركيز خارج حقول الإدخال، أو عند السحب الزائد عند رأس التمرير.
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

  static bool _isInsideFocusedEditable(Offset globalPosition) {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null || !context.mounted) return false;
    final editable = context.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return false;

    final editableRenderObject = editable.context.findRenderObject();
    if (editableRenderObject is! RenderBox || !editableRenderObject.attached) {
      return false;
    }
    var fieldBox = editableRenderObject;
    RenderObject? ancestor = editableRenderObject.parent;
    while (ancestor != null) {
      if (ancestor is RenderBox &&
          (ancestor.size.height >= editableRenderObject.size.height + 16 ||
              ancestor.size.width >= editableRenderObject.size.width + 24)) {
        fieldBox = ancestor;
        break;
      }
      ancestor = ancestor.parent;
    }

    final localPosition = fieldBox.globalToLocal(globalPosition);
    return (Offset.zero & fieldBox.size).contains(localPosition);
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
        onTapUp: (details) {
          if (!_isInsideFocusedEditable(details.globalPosition)) {
            unfocusEditable();
          }
        },
        child: child,
      ),
    );
  }
}
