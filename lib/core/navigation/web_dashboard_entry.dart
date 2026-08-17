import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'post_auth_navigation.dart';
import 'start_router_controller.dart';
import 'web_dashboard_hash.dart';
import 'web_interaction_recovery.dart';

/// على الويب: `#/userDashboard` يُعيد التوجيه إلى `/` مع تحديث [StartRouter] —
/// بناء [UserDashboard] كمسار جذر منفصل كان يُجمّد Chrome/Edge.
class WebDashboardEntryRedirect extends StatefulWidget {
  const WebDashboardEntryRedirect({super.key, required this.lang});

  final String lang;

  @override
  State<WebDashboardEntryRedirect> createState() =>
      _WebDashboardEntryRedirectState();
}

class _WebDashboardEntryRedirectState extends State<WebDashboardEntryRedirect> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirect());
  }

  Future<void> _redirect() async {
    if (!kIsWeb) return;
    await PostAuthNavigation.prepareForDashboardEntry();
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    if (!await StartRouterController.refreshInPlaceIfRegistered()) {
      nav.pushNamedAndRemoveUntil('/', (route) => false);
    }
    syncWebDashboardHashInAddressBar();
    WebInteractionRecovery.scheduleDashboardRecovery();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
