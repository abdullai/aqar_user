import 'package:aqar_user/core/input/caps_lock_signal.dart';
import 'package:aqar_user/core/input/caps_lock_tracker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CapsLockTracker', () {
    CapsLockSignal hw = CapsLockSignal.unknown;
    CapsLockSignal br = CapsLockSignal.unknown;
    var hwTrusted = false;
    var preferBrowser = false;
    var notifies = 0;

    late CapsLockTracker t;

    setUp(() {
      hw = CapsLockSignal.unknown;
      br = CapsLockSignal.unknown;
      hwTrusted = false;
      preferBrowser = false;
      notifies = 0;
      t = CapsLockTracker(
        onChanged: () => notifies++,
        readHardware: () => hw,
        readBrowser: () => br,
        hardwareTrusted: () => hwTrusted,
        preferBrowser: () => preferBrowser,
      );
      t.attach();
    });

    tearDown(() {
      t.detach();
    });

    test('OFF when unfocused even if internal ON', () {
      hwTrusted = true;
      hw = CapsLockSignal.on;
      t.sync();
      expect(t.signal, CapsLockSignal.unknown);
      expect(t.isOn, isFalse);
      expect(t.resolvedInternal, CapsLockSignal.on);
    });

    test('Focus with hardware ON shows ON when trusted', () {
      hwTrusted = true;
      hw = CapsLockSignal.on;
      t.onFocusChanged(true);
      expect(t.signal, CapsLockSignal.on);
      expect(t.isOn, isTrue);
    });

    test('Focus with hardware OFF shows OFF when trusted', () {
      hwTrusted = true;
      hw = CapsLockSignal.off;
      t.onFocusChanged(true);
      expect(t.signal, CapsLockSignal.off);
    });

    test('UNKNOWN when no sources', () {
      t.onFocusChanged(true);
      expect(t.signal, CapsLockSignal.unknown);
    });

    test('mobile untrusted hardware OFF does not wipe Latin inference', () {
      hwTrusted = false;
      preferBrowser = false;
      hw = CapsLockSignal.off;
      br = CapsLockSignal.unknown;
      t.onFocusChanged(true);
      t.inferFromInsertedLatin('', 'A');
      expect(t.signal, CapsLockSignal.unknown);
      t.sync();
      expect(t.signal, CapsLockSignal.unknown);
      t.inferFromInsertedLatin('A', 'Ab');
      expect(t.signal, CapsLockSignal.off);
      t.sync();
      expect(t.signal, CapsLockSignal.off);
    });

    test('browser beats trusted hardware which beats inference', () {
      preferBrowser = true;
      hwTrusted = true;
      br = CapsLockSignal.off;
      hw = CapsLockSignal.on;
      t.onFocusChanged(true);
      t.inferFromInsertedLatin('', 'a');
      t.sync();
      expect(t.signal, CapsLockSignal.off);

      br = CapsLockSignal.unknown;
      preferBrowser = false;
      hwTrusted = true;
      hw = CapsLockSignal.off;
      t.sync();
      t.inferFromInsertedLatin('', 'a');
      expect(t.signal, CapsLockSignal.off);

      hwTrusted = false;
      hw = CapsLockSignal.off;
      br = CapsLockSignal.unknown;
      t.inferFromInsertedLatin('a', 'ab');
      expect(t.signal, CapsLockSignal.off);
    });

    test('browser ON wins on desktop web path', () {
      preferBrowser = true;
      hwTrusted = false;
      br = CapsLockSignal.on;
      hw = CapsLockSignal.off;
      t.onFocusChanged(true);
      t.inferFromInsertedLatin('', 'a');
      t.sync();
      expect(t.signal, CapsLockSignal.on);
    });

    test('browser OFF wins on desktop web path', () {
      preferBrowser = true;
      br = CapsLockSignal.off;
      t.onFocusChanged(true);
      t.inferFromInsertedLatin('', 'A');
      t.sync();
      expect(t.signal, CapsLockSignal.off);
    });

    test('blur hides indicator then refocus restores confirmed ON', () {
      hwTrusted = true;
      hw = CapsLockSignal.on;
      t.onFocusChanged(true);
      expect(t.isOn, isTrue);
      t.onFocusChanged(false);
      expect(t.isOn, isFalse);
      expect(t.signal, CapsLockSignal.unknown);
      t.onFocusChanged(true);
      expect(t.isOn, isTrue);
    });

    test('toggle hardware ON then OFF while focused', () {
      hwTrusted = true;
      hw = CapsLockSignal.off;
      t.onFocusChanged(true);
      expect(t.signal, CapsLockSignal.off);
      hw = CapsLockSignal.on;
      t.sync();
      expect(t.signal, CapsLockSignal.on);
      hw = CapsLockSignal.off;
      t.sync();
      expect(t.signal, CapsLockSignal.off);
    });

    test('two trackers stay independent', () {
      final aOn = <CapsLockSignal>[];
      final bOn = <CapsLockSignal>[];
      final a = CapsLockTracker(
        onChanged: () {},
        readHardware: () => CapsLockSignal.on,
        readBrowser: () => CapsLockSignal.unknown,
        hardwareTrusted: () => true,
        preferBrowser: () => false,
      );
      final b = CapsLockTracker(
        onChanged: () {},
        readHardware: () => CapsLockSignal.off,
        readBrowser: () => CapsLockSignal.unknown,
        hardwareTrusted: () => true,
        preferBrowser: () => false,
      );
      a.attach();
      b.attach();
      a.onFocusChanged(true);
      b.onFocusChanged(true);
      aOn.add(a.signal);
      bOn.add(b.signal);
      a.onFocusChanged(false);
      expect(a.signal, CapsLockSignal.unknown);
      expect(b.signal, CapsLockSignal.off);
      a.detach();
      b.detach();
      expect(aOn.single, CapsLockSignal.on);
      expect(bOn.single, CapsLockSignal.off);
    });

    test('detach then attach does not throw', () {
      t.onFocusChanged(true);
      t.detach();
      expect(t.isAttached, isFalse);
      t.attach();
      t.onFocusChanged(true);
      expect(t.isAttached, isTrue);
    });

    test('does not notify when signal unchanged', () {
      hwTrusted = true;
      hw = CapsLockSignal.off;
      t.onFocusChanged(true);
      final n = notifies;
      t.sync();
      t.sync();
      expect(notifies, n);
    });

    test('soft keyboard unshifted uppercase is ON when enabled', () {
      expect(
        inferCapsFromLatinDelta('', 'A',
            shiftPressed: false, treatUnshiftedUpperAsOn: true),
        CapsLockSignal.on,
      );
      expect(
        inferCapsFromLatinDelta('', 'A',
            shiftPressed: false, treatUnshiftedUpperAsOn: false),
        CapsLockSignal.unknown,
      );
      expect(
        inferCapsFromLatinDelta('ab', 'A',
            shiftPressed: false, treatUnshiftedUpperAsOn: true),
        CapsLockSignal.on,
      );
      expect(
        inferCapsFromLatinDelta('Ab', 'AB',
            shiftPressed: false, treatUnshiftedUpperAsOn: true),
        CapsLockSignal.on,
      );
    });

    test('mobile tracker infers ON from unshifted capital', () {
      hwTrusted = false;
      preferBrowser = false;
      hw = CapsLockSignal.off;
      br = CapsLockSignal.unknown;
      t.bindSourceOverrides(
        readHardware: () => hw,
        readBrowser: () => br,
        hardwareTrusted: () => hwTrusted,
        preferBrowser: () => preferBrowser,
        inferUnshiftedUpperAsOn: () => true,
      );
      t.onFocusChanged(true);
      t.inferFromInsertedLatin('', 'A');
      expect(t.signal, CapsLockSignal.on);
    });

    test('mobile web key character infers ON even if browser reports OFF', () {
      hwTrusted = false;
      preferBrowser = false;
      hw = CapsLockSignal.off;
      br = CapsLockSignal.off;
      t.bindSourceOverrides(
        readHardware: () => hw,
        readBrowser: () => br,
        hardwareTrusted: () => hwTrusted,
        preferBrowser: () => preferBrowser,
        inferUnshiftedUpperAsOn: () => true,
      );
      t.onFocusChanged(true);
      t.debugHandleKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'A',
          timeStamp: Duration.zero,
        ),
      );
      expect(t.signal, CapsLockSignal.on);
    });

    test('inferCapsFromLatinDelta is conservative about Shift and capitals', () {
      expect(
        inferCapsFromLatinDelta('', 'A', shiftPressed: false),
        CapsLockSignal.unknown,
      );
      expect(
        inferCapsFromLatinDelta('', 'A', shiftPressed: true),
        CapsLockSignal.off,
      );
      expect(
        inferCapsFromLatinDelta('', 'a', shiftPressed: true),
        CapsLockSignal.on,
      );
      expect(
        inferCapsFromLatinDelta('', 'a', shiftPressed: false),
        CapsLockSignal.off,
      );
      expect(inferCapsFromLatinDelta('A', 'Ab', shiftPressed: false),
          CapsLockSignal.off);
      expect(inferCapsFromLatinDelta('', '1', shiftPressed: false),
          CapsLockSignal.unknown);
      expect(inferCapsFromLatinDelta('x', 'xAB', shiftPressed: false),
          CapsLockSignal.unknown);
    });

    test('untrusted CapsLock key latches ON then OFF', () {
      hwTrusted = false;
      preferBrowser = false;
      hw = CapsLockSignal.off;
      br = CapsLockSignal.unknown;
      t.onFocusChanged(true);
      expect(t.signal, CapsLockSignal.unknown);
      t.debugHandleKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.capsLock,
          logicalKey: LogicalKeyboardKey.capsLock,
          timeStamp: Duration.zero,
        ),
      );
      expect(t.signal, CapsLockSignal.on);
      t.debugHandleKey(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.capsLock,
          logicalKey: LogicalKeyboardKey.capsLock,
          timeStamp: Duration.zero,
        ),
      );
      expect(t.signal, CapsLockSignal.off);
    });
  });
}
