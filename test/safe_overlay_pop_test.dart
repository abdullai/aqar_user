import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/navigation/safe_overlay_pop.dart';
import 'package:aqar_user/core/navigation/programmatic_pop_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SafeOverlayPop.popNested = null;
    SafeOverlayPop.canPopNested = null;
  });

  testWidgets('close does not switch tabs when there is no previous route',
      (tester) async {
    BuildContext? pageContext;
    var nestedPopCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('Current tab'));
          },
        ),
      ),
    );

    SafeOverlayPop.canPopNested = () => false;
    SafeOverlayPop.popNested = () {
      nestedPopCalls++;
      return true;
    };

    expect(SafeOverlayPop.pop(pageContext!), isFalse);
    expect(
      SafeOverlayPop.popLayer(nested: Navigator.of(pageContext!)),
      isFalse,
    );
    expect(nestedPopCalls, 0);
    expect(find.text('Current tab'), findsOneWidget);
  });

  testWidgets('close returns to the actual previous route under the pop guard',
      (tester) async {
    final observer = _ProgrammaticPopObserver();
    final openKey = UniqueKey();
    final closeKey = UniqueKey();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: openKey,
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => Builder(
                      builder: (routeContext) => Scaffold(
                        body: TextButton(
                          key: closeKey,
                          onPressed: () => SafeOverlayPop.pop(routeContext),
                          child: const Text('Close'),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(openKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(closeKey));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(observer.programmaticPopWasActive, isTrue);
  });
}

class _ProgrammaticPopObserver extends NavigatorObserver {
  bool programmaticPopWasActive = false;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    programmaticPopWasActive = ProgrammaticPopGuard.isActive;
  }
}
