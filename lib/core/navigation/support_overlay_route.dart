import 'package:flutter/material.dart';

/// الدعم الفني فوق كل التبويبات — X يعيد الشاشة التي أتى منها المستخدم.
abstract final class SupportOverlay {
  static const routeName = '/support/hub';

  static bool isOverlayName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    return n == routeName || n.startsWith('/support/');
  }

  static Future<T?> push<T>(
    BuildContext context, {
    required Widget page,
    String? name,
  }) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute<T>(
        builder: (_) => page,
        settings: RouteSettings(name: name ?? routeName),
        fullscreenDialog: true,
      ),
    );
  }
}
