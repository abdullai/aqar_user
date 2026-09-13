import 'package:flutter/material.dart';

import 'safe_overlay_pop.dart';

/// شاشة دفع / ملخص خدمة فوق كل التبويبات — X يعيد الشاشة السابقة.
abstract final class PaymentOverlay {
  static Future<T?> push<T>(
    BuildContext context, {
    required Widget page,
    String? name,
  }) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute<T>(
        builder: (_) => page,
        settings: RouteSettings(name: name ?? '/payments/overlay'),
        fullscreenDialog: true,
      ),
    );
  }
}

/// يمنع رجوع المتصفح أثناء المعالجة ويوجّه الإغلاق إلى [SafeOverlayPop].
class PaymentPopGuard extends StatelessWidget {
  const PaymentPopGuard({
    super.key,
    required this.child,
    this.busy = false,
  });

  final Widget child;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || busy) return;
        SafeOverlayPop.pop(context);
      },
      child: child,
    );
  }
}
