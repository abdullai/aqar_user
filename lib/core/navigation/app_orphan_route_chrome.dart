import 'package:flutter/material.dart';

import 'post_auth_navigation.dart';
import 'scroll_driven_bar_visibility.dart';

/// شريط سفلي موحّد لمسارات تُبنى من [MaterialApp.routes] خارج [UserDashboard]
/// (روابط إشعارات، روابط عميقة، إلخ) حتى يبقى وصول واضح للوحة مع التبويبات.
///
/// لا يُستخدم لشاشات المصادقة (دخول، تسجيل، …).
class AppOrphanRouteChrome extends StatelessWidget {
  const AppOrphanRouteChrome({
    super.key,
    required this.lang,
    required this.child,
  });

  final String lang;
  final Widget child;

  static const double _stripHeight = 68;

  /// ارتفاع الشريط السفلي (مع SafeArea) لمسارات [AppOrphanRouteChrome].
  static double bottomInset(BuildContext context) => _stripHeight;

  bool get _isAr => lang.toLowerCase() != 'en';

  void _openDashboard(BuildContext context) {
    PostAuthNavigation.openDashboard(context);
  }

  Widget _bottomStrip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 12,
      shadowColor: Colors.black38,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.95),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _stripHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: FilledButton.tonalIcon(
              onPressed: () => _openDashboard(context),
              icon: const Icon(Icons.dashboard_outlined),
              label: Text(
                _isAr ? 'العودة للوحة (التبويبات)' : 'Back to app (tabs)',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollDrivenBarVisibility(
      enabled: false,
      bar: _bottomStrip(context),
      child: child,
    );
  }
}
