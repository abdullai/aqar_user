import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/widgets/app_page_close_button.dart';

void main() {
  testWidgets('close X sits at the start edge in RTL and LTR', (tester) async {
    Future<void> pumpDir(TextDirection dir) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: dir,
            child: Scaffold(
              body: SizedBox(
                width: 320,
                height: 80,
                child: AppPageCloseButton.startCorner(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpDir(TextDirection.ltr);
    final ltrX = tester.getTopLeft(find.byType(AppPageCloseButton)).dx;

    await pumpDir(TextDirection.rtl);
    final rtlX = tester.getTopLeft(find.byType(AppPageCloseButton)).dx;

    expect(ltrX, lessThan(rtlX));
  });

  testWidgets('default close pops only the overlay, not the shell',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: AppPageCloseButton(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AppPageCloseButton), findsOneWidget);

    await tester.tap(find.byType(AppPageCloseButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(AppPageCloseButton), findsNothing);
  });

  testWidgets('leadingOf is hidden on the shell and shown on an overlay',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              leading: AppPageCloseButton.leadingOf(context),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AppPageCloseButton), findsNothing);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              leading: AppPageCloseButton.leadingOf(context),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppPageCloseButton), findsOneWidget);
  });
}
