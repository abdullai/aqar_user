import 'package:flutter/material.dart';

import '../../screens/owner_individual_desk_page.dart';
import '../../screens/subscriptions/subscriptions_root_screen.dart';

/// مسارات تُفتح داخل [Navigator] جسم لوحة التحكم.
class DashboardEmbeddedRoute {
  DashboardEmbeddedRoute._();

  static const subscriptions = '/dashboard/subscriptions';
  static const subscriptionsCheckout = '/dashboard/subscriptions/checkout';
  static const subscriptionsAddCard = '/dashboard/subscriptions/add-card';
  static const settings = '/dashboard/settings';
  static const favorites = '/dashboard/favorites';
  static const deskOrganization = '/desk/organization';
  static const deskOwner = '/desk/owner';

  /// تبويب رئيسي داخل المظلة: بلا زر X بجوار الاسم في شريط الترحيب.
  static bool isMainShellHub(String? name) {
    switch ((name ?? '').trim()) {
      case deskOrganization:
      case deskOwner:
      case settings:
      case subscriptions:
      case favorites:
        return true;
      case '/marketInsights':
        return true;
      case '/inAppNotifications':
        return true;
      default:
        return (name ?? '').contains('communication');
    }
  }

  static bool isEmbedded(BuildContext context) {
    final name = ModalRoute.of(context)?.settings.name ?? '';
    return name.startsWith('/dashboard/');
  }

  /// إخفاء AppBar الفرعي فقط إذا كان الأب يعرض شريط إغلاق مسبقاً
  /// (تبويب داخل إدارتي / اشتراكات مضمّنة). مسار `/dashboard/` وحده لا يخفي الإغلاق.
  static bool isPaymentOverlayName(String? name) {
    final n = (name ?? '').trim().toLowerCase();
    return n.contains('/checkout') ||
        n.contains('/add-card') ||
        n.contains('moyasar') ||
        n.contains('plan-details') ||
        n.startsWith('/payments/');
  }

  static bool shouldUseEmbeddedChrome(BuildContext context) {
    final routeName = ModalRoute.of(context)?.settings.name;
    if (isPaymentOverlayName(routeName) ||
        (routeName ?? '').toLowerCase().contains('/support')) {
      return false;
    }
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
