import 'package:aqar_user/core/input/caps_lock_signal.dart';
import 'package:aqar_user/core/input/smart_keyboard_formatter.dart';
import 'package:aqar_user/l10n/app_localizations.dart';
import 'package:aqar_user/widgets/caps_aware_password_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(
  Widget child, {
  TextDirection dir = TextDirection.ltr,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ar'), Locale('en')],
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: dir,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

CapsAwarePasswordField _field({
  required TextEditingController controller,
  FocusNode? focusNode,
  bool isAr = false,
  CapsLockSignal signal = CapsLockSignal.on,
  bool useText = true,
}) {
  return CapsAwarePasswordField(
    controller: controller,
    focusNode: focusNode,
    isAr: isAr,
    debugReadHardware: () => signal,
    debugReadBrowser: () => signal,
    debugHardwareTrusted: () => false,
    debugPreferBrowser: () => true,
    debugUseTextUnderField: useText,
    debugInferSoftCaps: !useText,
  );
}

void main() {
  testWidgets('shows Caps Lock is ON under field when ON', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(_field(controller: c), size: const Size(1366, 768)),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('Caps Lock is ON'), findsOneWidget);
    expect(find.byType(AnimatedOpacity), findsNothing);
    final hint = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(CapsLockHintText),
        matching: find.byType(Opacity),
      ),
    );
    expect(hint.opacity, 1);
  });

  testWidgets('hides hint when OFF', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(
        _field(controller: c, signal: CapsLockSignal.off),
        size: const Size(1366, 768),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('Caps Lock is ON'), findsNothing);
    final hint = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(CapsLockHintText),
        matching: find.byType(Opacity),
      ),
    );
    expect(hint.opacity, 0);
  });

  testWidgets('UNKNOWN does not claim Caps Lock ON', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(
        _field(controller: c, signal: CapsLockSignal.unknown),
        size: const Size(1366, 768),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('Caps Lock is ON'), findsNothing);
    expect(find.text('Caps Lock مفعّل'), findsNothing);
    await tester.enterText(find.byType(TextField), 'A');
    await tester.pump();
    expect(find.text('Caps Lock is ON'), findsNothing);
    expect(c.text, 'A');
  });

  testWidgets('RTL Arabic label from l10n', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(
        _field(controller: c, isAr: true),
        dir: TextDirection.rtl,
        locale: const Locale('ar'),
        size: const Size(1366, 768),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('Caps Lock مفعّل'), findsOneWidget);
  });

  testWidgets('three fields: only focused field shows ON', (tester) async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final c3 = TextEditingController();
    final f1 = FocusNode();
    final f2 = FocusNode();
    final f3 = FocusNode();
    addTearDown(() {
      c1.dispose();
      c2.dispose();
      c3.dispose();
      f1.dispose();
      f2.dispose();
      f3.dispose();
    });
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            _field(controller: c1, focusNode: f1),
            _field(controller: c2, focusNode: f2),
            _field(controller: c3, focusNode: f3),
          ],
        ),
        size: const Size(1366, 768),
      ),
    );
    await tester.tap(find.byType(TextField).at(0));
    await tester.pump();
    expect(f1.hasFocus, isTrue);
    expect(find.text('Caps Lock is ON'), findsOneWidget);
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    expect(f2.hasFocus, isTrue);
    expect(find.text('Caps Lock is ON'), findsOneWidget);
    await tester.tap(find.byType(TextField).at(2));
    await tester.pump();
    expect(f3.hasFocus, isTrue);
    expect(find.text('Caps Lock is ON'), findsOneWidget);
    f3.unfocus();
    await tester.pump();
    expect(find.text('Caps Lock is ON'), findsNothing);
    f1.requestFocus();
    await tester.pump();
    expect(find.text('Caps Lock is ON'), findsOneWidget);
  });

  testWidgets('rebuild and dispose while focused', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(_field(controller: c)));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pumpWidget(
      _wrap(_field(controller: c, signal: CapsLockSignal.off)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('does not mutate password case', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(_field(controller: c, signal: CapsLockSignal.unknown)),
    );
    await tester.enterText(find.byType(TextField), 'AbC');
    expect(c.text, 'AbC');
  });

  testWidgets('mobile glyph appears when Caps Lock is ON', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(
        _field(controller: c, useText: false),
        size: const Size(390, 844),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byIcon(Icons.keyboard_capslock_rounded),
              matching: find.byType(Opacity),
            ).first,
          )
          .opacity,
      1,
    );
  });

  testWidgets('mobile glyph infers ON after typing unshifted capital',
      (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(
        CapsAwarePasswordField(
          controller: c,
          isAr: false,
          debugReadHardware: () => CapsLockSignal.off,
          debugReadBrowser: () => CapsLockSignal.unknown,
          debugHardwareTrusted: () => false,
          debugPreferBrowser: () => false,
          debugUseTextUnderField: false,
          debugInferSoftCaps: true,
        ),
        size: const Size(390, 844),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'A');
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byIcon(Icons.keyboard_capslock_rounded),
              matching: find.byType(Opacity),
            ).first,
          )
          .opacity,
      1,
    );
  });

  testWidgets('mobile glyph path does not reserve hint height', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(
        _field(controller: c, useText: false),
        size: const Size(390, 844),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.byType(CapsLockHintText), findsNothing);
    expect(find.byIcon(Icons.keyboard_capslock_rounded), findsOneWidget);
  });

  testWidgets('small and large layouts', (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    for (final size in const [Size(320, 568), Size(1920, 1080)]) {
      await tester.pumpWidget(
        _wrap(_field(controller: c), size: size),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.byType(CapsAwarePasswordField), findsOneWidget);
    }
  });

  testWidgets('toggle visibility does not change password text', (tester) async {
    final c = TextEditingController(text: 'AbC');
    var obscure = true;
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return CapsAwarePasswordField(
              controller: c,
              obscureText: obscure,
              onToggleObscure: () => setState(() => obscure = !obscure),
              isAr: false,
              debugReadHardware: () => CapsLockSignal.off,
              debugReadBrowser: () => CapsLockSignal.off,
              debugHardwareTrusted: () => true,
              debugPreferBrowser: () => false,
              debugUseTextUnderField: true,
            );
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('Show'));
    await tester.pump();
    expect(c.text, 'AbC');
  });
}
