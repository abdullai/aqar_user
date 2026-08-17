import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// تمرير بالأسهم / PageUp / Home على الويب وسطح المكتب، دون اعتراض حقول الإدخال.
abstract final class AppHardwareKeyboardScroll {
  static bool Function(KeyEvent)? _handler;

  static bool get enabled {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia =>
        true,
      _ => false,
    };
  }

  /// يُستدعى من جذر التطبيق؛ يُزال في [uninstall].
  static void install(GlobalKey<NavigatorState> navigatorKey) {
    if (!enabled) return;
    uninstall();
    _handler = (KeyEvent event) => _handle(event, navigatorKey);
    HardwareKeyboard.instance.addHandler(_handler!);
  }

  static void uninstall() {
    final h = _handler;
    if (h != null) {
      HardwareKeyboard.instance.removeHandler(h);
      _handler = null;
    }
  }

  static bool _isTextFieldFocus(FocusNode? node) {
    if (node?.context == null) return false;
    return node!.context!.findAncestorStateOfType<EditableTextState>() != null;
  }

  static ScrollPosition? _positionFromFocus(FocusNode? focus) {
    if (focus?.context == null) return null;
    final scrollable = Scrollable.maybeOf(focus!.context!);
    final p = scrollable?.position;
    if (p != null && p.hasPixels) return p;
    return null;
  }

  static ScrollPosition? _positionFromPrimary(
    GlobalKey<NavigatorState> navKey,
  ) {
    final ctx = navKey.currentState?.overlay?.context ?? navKey.currentContext;
    if (ctx == null) return null;
    final c = PrimaryScrollController.maybeOf(ctx);
    if (c != null && c.hasClients) return c.position;
    return null;
  }

  static ScrollPosition? _deepestScrollablePosition(Element root) {
    ScrollPosition? best;
    double bestArea = -1;

    void visit(Element element) {
      final widget = element.widget;
      if (widget is Scrollable) {
        final state = element.findAncestorStateOfType<ScrollableState>();
        final pos = state?.position;
        if (pos != null && pos.hasPixels && pos.maxScrollExtent > 0) {
          final box = element.renderObject;
          var area = 0.0;
          if (box is RenderBox && box.hasSize) {
            area = box.size.width * box.size.height;
          }
          if (area >= bestArea) {
            bestArea = area;
            best = pos;
          }
        }
      }
      element.visitChildElements(visit);
    }

    visit(root);
    return best;
  }

  static bool _handle(KeyEvent event, GlobalKey<NavigatorState> navKey) {
    if (event is KeyUpEvent) return false;

    final focus = FocusManager.instance.primaryFocus;
    if (_isTextFieldFocus(focus)) return false;

    final key = event.logicalKey;
    ScrollPosition? pos = _positionFromFocus(focus);
    pos ??= _positionFromPrimary(navKey);
    final rootContext =
        navKey.currentState?.overlay?.context ?? navKey.currentContext;
    if (pos == null && rootContext != null) {
      pos = _deepestScrollablePosition(rootContext as Element);
    }
    if (pos == null || !pos.hasPixels) return false;

    final viewport = pos.viewportDimension;
    final step = (viewport * 0.12).clamp(48.0, 160.0);

    double delta = 0;
    bool jumpMin = false;
    bool jumpMax = false;

    if (key == LogicalKeyboardKey.arrowDown) {
      delta = step;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      delta = -step;
    } else if (key == LogicalKeyboardKey.pageDown) {
      delta = viewport * 0.88;
    } else if (key == LogicalKeyboardKey.pageUp) {
      delta = -viewport * 0.88;
    } else if (key == LogicalKeyboardKey.home) {
      jumpMin = true;
    } else if (key == LogicalKeyboardKey.end) {
      jumpMax = true;
    } else {
      return false;
    }

    if (jumpMin) {
      pos.jumpTo(0);
      return true;
    }
    if (jumpMax) {
      pos.jumpTo(pos.maxScrollExtent);
      return true;
    }

    final next =
        (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent).toDouble();
    pos.jumpTo(next);
    return true;
  }
}
