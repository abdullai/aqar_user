import 'package:flutter/material.dart';

/// لقطة مسار يمكن إعادة فتحها بسهم التقدّم في المتصفح.
class WebInAppReplay {
  const WebInAppReplay({
    required this.nested,
    this.materialBuilder,
    this.pageBuilder,
    this.settings = const RouteSettings(),
    this.fullscreenDialog = false,
  });

  final bool nested;
  final WidgetBuilder? materialBuilder;
  final RoutePageBuilder? pageBuilder;
  final RouteSettings settings;
  final bool fullscreenDialog;

  Route<dynamic>? toRoute() {
    final b = materialBuilder;
    if (b != null) {
      return MaterialPageRoute<dynamic>(
        builder: b,
        settings: settings,
        fullscreenDialog: fullscreenDialog,
      );
    }
    final p = pageBuilder;
    if (p != null) {
      return PageRouteBuilder<dynamic>(
        pageBuilder: p,
        settings: settings,
      );
    }
    return null;
  }
}
