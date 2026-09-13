import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  /// ماوس/مؤشر دقيق متصل حالياً (Windows، متصفح مكتبي، لوحة لمس خارجية).
  static bool hasFinePointer() =>
      RendererBinding.instance.mouseTracker.mouseIsConnected;

  static bool isFinePointerKind(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;

  static bool isTouchPointerKind(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.touch ||
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  /// شريط تمرير ظاهر: مؤشر دقيق (ماوس) أو سطح مكتب. مخفي على اللمس فقط.
  /// لا يعتمد على عرض الشاشة — نافذة ويندوز الضيقة تبقى بشريط إن وُجد ماوس.
  static bool showPersistentScrollbarResolved({
    required bool mouseConnected,
    required bool mobileWebUserAgent,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (mouseConnected) return true;
    if (mobileWebUserAgent) return false;
    if (!isWeb) {
      return platform == TargetPlatform.windows ||
          platform == TargetPlatform.linux ||
          platform == TargetPlatform.macOS ||
          platform == TargetPlatform.fuchsia;
    }
    return true;
  }

  static bool showPersistentScrollbar(BuildContext context) {
    return showPersistentScrollbarResolved(
      mouseConnected: hasFinePointer(),
      mobileWebUserAgent: isMobileWebUserAgent(),
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    );
  }

  /// جوال أصلي، أو متصفح جوال، أو شاشة ضيقة — لتخطيط الواجهة فقط.
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

  static bool isDesktopLike(BuildContext context) =>
      !isCompactTouchLike(context);
}
