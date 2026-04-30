import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/fast_login_service.dart';
import 'fast_login_offer_dialog.dart';

/// يعرض حوار اقتراح الدخول السريع مرة واحدة لكل جلسة مناسبة، وعند استئناف التطبيق إن حان وقت التذكير.
class FastLoginOfferHost extends StatefulWidget {
  const FastLoginOfferHost({
    super.key,
    required this.lang,
    required this.child,
  });

  final String lang;
  final Widget child;

  @override
  State<FastLoginOfferHost> createState() => _FastLoginOfferHostState();
}

class _FastLoginOfferHostState extends State<FastLoginOfferHost>
    with WidgetsBindingObserver {
  bool _busy = false;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryShow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tryShow();
    }
  }

  Future<void> _tryShow() async {
    if (kIsWeb || !mounted || _busy) return;
    if (!await FastLoginService.shouldShowScheduledReminder()) return;

    _busy = true;
    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await FastLoginOfferDialog.show(context, isAr: _isAr);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
