import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../security/web_user_agent.dart';

/// سياسة إظهار شريط التمرير الذكي (سطح مكتب / جوال).
class ViewportScrollPolicy {
  ViewportScrollPolicy._();

  static const double compactBreakpoint = 700;

  static bool isMobileWebUserAgent() {
    if (!kIsWeb) return false;
    final ua = readWebUserAgentImpl().toLowerCase();
    return ua.contains('android') ||
        ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('mobile');
  }

  /// جوال أصلي، أو متصفح جوال، أو شاشة ضيقة.
  static bool isCompactTouchLike(BuildContext context) {
    if (!kIsWeb) {
      final p = defaultTargetPlatform;
      if (p == TargetPlatform.android || p == TargetPlatform.iOS) {
        return true;
      }
    } else if (isMobileWebUserAgent()) {
      return true;
    }
    final size = MediaQuery.sizeOf(context);
    if (size.width < compactBreakpoint) return true;
    if (!kIsWeb && size.shortestSide < compactBreakpoint) return true;
    return false;
  }

  static bool isDesktopLike(BuildContext context) => !isCompactTouchLike(context);
}
