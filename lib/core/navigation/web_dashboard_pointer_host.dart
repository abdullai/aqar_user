import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_interaction_recovery.dart';

/// يُلفّ اللوحة على الويب ويزيل طبقات اللمس العالقة **مرة واحدة** بعد أول إطار —
/// ليس مع كل نقرة (كان يجمّد التبويبات).
class WebDashboardPointerHost extends StatefulWidget {
  const WebDashboardPointerHost({super.key, required this.child});

  final Widget child;

  @override
  State<WebDashboardPointerHost> createState() =>
      _WebDashboardPointerHostState();
}

class _WebDashboardPointerHostState extends State<WebDashboardPointerHost> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WebInteractionRecovery.dismissStuckOverlaysOnce();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
