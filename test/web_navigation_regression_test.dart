import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser forward replay does not hold navigation in replay mode', () {
    final src =
        File('lib/core/navigation/web_in_app_nav.dart').readAsStringSync();

    expect(src.contains('await root.push(route)'), isFalse);
    expect(src.contains('await n.push(route)'), isFalse);
    expect(src.contains('unawaited(root.push(route))'), isTrue);
    expect(src.contains('unawaited(n.push(route))'), isTrue);
  });

  test('programmatic history back is matched by its target entry', () {
    final src = File('lib/core/navigation/web_in_app_history_web.dart')
        .readAsStringSync();

    expect(src.contains('_programmaticBackTarget == i'), isTrue);
    expect(src.contains('_ignoreCount'), isFalse);
    expect(
        src.contains('_idx = 1;\n      webInAppHistoryTrapLeaving();'), isTrue);
  });

  test('mobile viewport restoration does not freeze stale pixel heights', () {
    final src = File('web/index.html').readAsStringSync();

    expect(src.contains('document.documentElement.style.height = h'), isFalse);
    expect(
        src.contains('window.addEventListener("scroll", pinViewport'), isFalse);
    expect(
        src.contains('visualViewport.addEventListener("scroll", pinViewport)'),
        isFalse);
    expect(src.contains('min-height: 100dvh;'), isTrue);
  });

  test('login and blocking overlay are replaced in one navigation action', () {
    final src = File('lib/screens/login_screen.dart').readAsStringSync();
    final verifyRoute = src.indexOf("name: '/verify'");
    final replaceStack =
        src.lastIndexOf('navigator.pushAndRemoveUntil(', verifyRoute);

    expect(verifyRoute, isNonNegative);
    expect(replaceStack, isNonNegative);
    expect(src.indexOf('dismissLoginOverlay();', verifyRoute), isNegative);
  });
}
