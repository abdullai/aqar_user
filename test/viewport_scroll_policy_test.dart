import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/platform/viewport_scroll_policy.dart';

void main() {
  group('ViewportScrollPolicy.showPersistentScrollbarResolved', () {
    test('mouse connected always shows a scrollbar', () {
      expect(
        ViewportScrollPolicy.showPersistentScrollbarResolved(
          mouseConnected: true,
          mobileWebUserAgent: true,
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('touch-only phone app hides the scrollbar', () {
      expect(
        ViewportScrollPolicy.showPersistentScrollbarResolved(
          mouseConnected: false,
          mobileWebUserAgent: false,
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        ViewportScrollPolicy.showPersistentScrollbarResolved(
          mouseConnected: false,
          mobileWebUserAgent: false,
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
    });

    test('Windows and desktop web show a scrollbar without a mouse yet', () {
      expect(
        ViewportScrollPolicy.showPersistentScrollbarResolved(
          mouseConnected: false,
          mobileWebUserAgent: false,
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
      expect(
        ViewportScrollPolicy.showPersistentScrollbarResolved(
          mouseConnected: false,
          mobileWebUserAgent: false,
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('mobile web UA hides the scrollbar when no mouse is connected', () {
      expect(
        ViewportScrollPolicy.showPersistentScrollbarResolved(
          mouseConnected: false,
          mobileWebUserAgent: true,
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });
  });
}
