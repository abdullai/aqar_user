import 'package:flutter/material.dart';

/// انتقال فتح نموذج زر + : يعلو التبويبات بملء الشاشة (ويب ويندوز/جوال وتطبيق).
class PlusComposerPageRoute<T> extends PageRouteBuilder<T> {
  PlusComposerPageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          fullscreenDialog: true,
          opaque: true,
          barrierDismissible: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        );
}
