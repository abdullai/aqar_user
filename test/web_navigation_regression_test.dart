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

  test('browser history pops are not resynced as programmatic closes', () {
    final src = File('lib/core/navigation/web_in_app_nav.dart').readAsStringSync();
    final notePopStart = src.indexOf('static void notePop(');
    final historyCheck = src.indexOf('if (_fromHistory)', notePopStart);
    final programmaticCheck =
        src.indexOf('if (ProgrammaticPopGuard.isActive)', notePopStart);

    expect(notePopStart, isNonNegative);
    expect(historyCheck, greaterThan(notePopStart));
    expect(programmaticCheck, greaterThan(historyCheck));
  });

  test('map picker route is excluded from browser history syncing', () {
    final src =
        File('lib/core/navigation/web_in_app_nav.dart').readAsStringSync();

    expect(src.contains("route.settings.name == '/map-picker'"), isTrue);
    expect(src.split('_bypassesHistory(route)').length - 1, 2);
  });

  test('national address confirmation does not pop its parent form', () {
    final src = File('lib/screens/national_address_picker_screen.dart')
        .readAsStringSync();

    expect(src.contains("static const routeName = '/national-address-picker'"),
        isTrue);
    expect(src.contains('WebInAppNav.runProgrammaticPop('), isTrue);
    expect(src.contains('Navigator.of(context).pop('), isTrue);
    expect(src.contains('onSubmitted: (_) => _submitSearch()'), isTrue);
  });

  test('dashboard close only pops an open route, not a different tab', () {
    final src = File('lib/screens/user_dashboard.ui.dart').readAsStringSync();
    final popRouteStart = src.indexOf('bool _popDashboardBodyRoute()');
    final backHandlerStart =
        src.indexOf('bool _handleDashboardBack()', popRouteStart);

    expect(popRouteStart, isNonNegative);
    expect(backHandlerStart, greaterThan(popRouteStart));
    final closeHandler = src.substring(popRouteStart, backHandlerStart);
    expect(closeHandler.contains('bodyNav.pop()'), isTrue);
    expect(closeHandler.contains('_tabIndex = 0'), isFalse);
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
