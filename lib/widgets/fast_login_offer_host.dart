import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../services/fast_login_service.dart';
import 'fast_login_offer_dialog.dart';

/// يعرض حوار اقتراح الدخول السريع بعد جاهزية اللوحة (بعد بوابات ما بعد الدخول).
///
/// أفضل ممارسة أمنية/UX:
/// - التطبيق الأصلي (جوال): الأنسب — PIN + بصمة/وجه.
/// - ويب سطح المكتب (ويندوز/ماك/لينكس): PIN لإعادة فتح الجلسة بعد الخمول — مفيد ومقبول.
/// - ويب الجوال: لا نعرض الاقتراح (تجربة ضعيفة وأمان أقل من التطبيق).
class FastLoginOfferHost extends StatefulWidget {
  const FastLoginOfferHost({
    super.key,
    required this.lang,
    required this.child,
  });

  final String lang;
  final Widget child;

  /// منصات يُفضَّل عليها عرض اقتراح الدخول السريع.
  static bool get isPreferredOfferPlatform {
    if (!kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

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
    if (!mounted || _busy) return;
    if (!FastLoginOfferHost.isPreferredOfferPlatform) return;
    if (!await FastLoginService.shouldShowScheduledReminder()) return;

    _busy = true;
    try {
      // انتظر رسم اللوحة بعد اجتياز البوابات/فحص الملف في الخلفية.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      if (!await FastLoginService.shouldShowScheduledReminder()) return;
      await FastLoginOfferDialog.show(context, isAr: _isAr);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
