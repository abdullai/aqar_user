import 'package:flutter/material.dart';

import '../../screens/owner_individual_desk_page.dart';
import '../../screens/subscriptions/subscriptions_root_screen.dart';

/// مسارات تُفتح داخل [Navigator] جسم لوحة التحكم (بدون AppBar فرعي مكرر).
class DashboardEmbeddedRoute {
  DashboardEmbeddedRoute._();

  static const subscriptions = '/dashboard/subscriptions';
  static const subscriptionsCheckout = '/dashboard/subscriptions/checkout';
  static const subscriptionsAddCard = '/dashboard/subscriptions/add-card';

  static bool isEmbedded(BuildContext context) {
    final name = ModalRoute.of(context)?.settings.name ?? '';
    return name.startsWith('/dashboard/');
  }

  /// بدون AppBar فرعي: لوحة التحكم، «إدارتي»، أو مركز اشتراكات مضمّن.
  static bool shouldUseEmbeddedChrome(BuildContext context) {
    if (isEmbedded(context)) return true;
    if (context.findAncestorWidgetOfExactType<OwnerIndividualDeskPage>() !=
        null) {
      return true;
    }
    final hub =
        context.findAncestorWidgetOfExactType<SubscriptionsRootScreen>();
    if (hub != null && hub.embedAppBar) return true;
    return false;
  }
}
