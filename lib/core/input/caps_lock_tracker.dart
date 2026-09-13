import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'caps_lock_platform.dart';
import 'caps_lock_probe.dart';
import 'caps_lock_signal.dart';

/// استدلال محافظ: لا يعلن ON إلا بدليل كافٍ.
///
/// Shift + حرف كبير = كتابة عادية (ليس Caps Lock).
/// حرف كبير بدون بت Shift موثوق = UNKNOWN (لوحة ناعمة / تصحيح تلقائي).
CapsLockSignal inferCapsFromLatinLetter(
  String ch, {
  bool? shiftPressed,
  bool treatUnshiftedUpperAsOn = false,
}) {
  if (ch.length != 1) return CapsLockSignal.unknown;
  final cu = ch.codeUnitAt(0);
  final isUpper = cu >= 65 && cu <= 90;
  final isLower = cu >= 97 && cu <= 122;
  if (!isUpper && !isLower) return CapsLockSignal.unknown;
  final shift = shiftPressed ?? HardwareKeyboard.instance.isShiftPressed;
  if (shift) {
    return isLower ? CapsLockSignal.on : CapsLockSignal.off;
  }
  if (isUpper) {
    return treatUnshiftedUpperAsOn
        ? CapsLockSignal.on
        : CapsLockSignal.unknown;
  }
  return CapsLockSignal.off;
}

/// يستنتج Caps من إدراج حرف لاتيني واحد فقط — اللصق/التصحيح المتعدد = UNKNOWN.
CapsLockSignal inferCapsFromLatinDelta(
  String previous,
  String next, {
  bool? shiftPressed,
  bool treatUnshiftedUpperAsOn = false,
}) {
  if (next.isEmpty) return CapsLockSignal.unknown;

  String? ch;
  if (next.length == previous.length + 1) {
    if (next.startsWith(previous)) {
      ch = next.substring(previous.length);
    } else if (next.endsWith(previous)) {
      ch = next.substring(0, next.length - previous.length);
    } else {
      for (var i = 0; i < next.length; i++) {
        if (i >= previous.length || next[i] != previous[i]) {
          ch = next[i];
          break;
        }
      }
    }
  } else if (next.length == 1 && previous != next) {
    ch = next;
  } else if (next.length == previous.length && next.isNotEmpty) {
    var diffs = 0;
    String? changed;
    for (var i = 0; i < next.length; i++) {
      if (next[i] == previous[i]) continue;
      diffs++;
      changed = next[i];
      if (diffs > 1) break;
    }
    if (diffs == 1) ch = changed;
  }
  if (ch == null || ch.length != 1) return CapsLockSignal.unknown;
  return inferCapsFromLatinLetter(
    ch,
    shiftPressed: shiftPressed,
    treatUnshiftedUpperAsOn: treatUnshiftedUpperAsOn,
  );
}

CapsLockSignal inferCapsFromKeyEvent(
  KeyEvent event, {
  bool? shiftPressed,
  bool treatUnshiftedUpperAsOn = false,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return CapsLockSignal.unknown;
  }
  final ch = event.character;
  if (ch == null || ch.length != 1) return CapsLockSignal.unknown;
  return inferCapsFromLatinLetter(
    ch,
    shiftPressed: shiftPressed,
    treatUnshiftedUpperAsOn: treatUnshiftedUpperAsOn,
  );
}

/// يتتبع Caps Lock لكل حقل: ON / OFF / UNKNOWN دون مسح استدلال الجوال بعتاد كاذب.
class CapsLockTracker {
  CapsLockTracker({
    required this.onChanged,
    this.readHardware,
    this.readBrowser,
    this.hardwareTrusted,
    this.preferBrowser,
    this.inferUnshiftedUpperAsOn,
  });

  final VoidCallback onChanged;

  @visibleForTesting
  CapsLockSignal Function()? readHardware;
  @visibleForTesting
  CapsLockSignal Function()? readBrowser;
  @visibleForTesting
  bool Function()? hardwareTrusted;
  @visibleForTesting
  bool Function()? preferBrowser;
  @visibleForTesting
  bool Function()? inferUnshiftedUpperAsOn;

  void bindSourceOverrides({
    CapsLockSignal Function()? readHardware,
    CapsLockSignal Function()? readBrowser,
    bool Function()? hardwareTrusted,
    bool Function()? preferBrowser,
    bool Function()? inferUnshiftedUpperAsOn,
  }) {
    this.readHardware = readHardware;
    this.readBrowser = readBrowser;
    this.hardwareTrusted = hardwareTrusted;
    this.preferBrowser = preferBrowser;
    this.inferUnshiftedUpperAsOn = inferUnshiftedUpperAsOn;
  }

  bool _attached = false;
  bool _focused = false;
  bool _keyHandlerAttached = false;
  Timer? _resyncTimer;
  Timer? _pollTimer;

  CapsLockSignal _hardware = CapsLockSignal.unknown;
  CapsLockSignal _browser = CapsLockSignal.unknown;
  CapsLockSignal _inferred = CapsLockSignal.unknown;
  CapsLockSignal _latched = CapsLockSignal.unknown;

  CapsLockSignal _ui = CapsLockSignal.unknown;

  bool get isAttached => _attached;
  bool get isFocused => _focused;

  /// الحالة المعروضة لهذا الحقل فقط وهو مركّز.
  CapsLockSignal get signal => _focused ? _resolve() : CapsLockSignal.unknown;

  bool get isOn => signal == CapsLockSignal.on;

  /// الحالة الداخلية بعد الدمج (للاختبارات) حتى مع فقدان التركيز.
  @visibleForTesting
  CapsLockSignal get resolvedInternal => _resolve();

  bool get _hwTrusted =>
      hardwareTrusted?.call() ?? defaultHardwareCapsTrusted();

  bool get _useBrowserFirst =>
      preferBrowser?.call() ?? defaultPreferBrowserCaps();

  CapsLockSignal _hwNow() =>
      readHardware?.call() ?? readHardwareCapsLockSignal();

  CapsLockSignal _browserNow() =>
      readBrowser?.call() ?? probeBrowserCapsLock();

  CapsLockSignal _resolve() {
    if (_useBrowserFirst) {
      if (_browser == CapsLockSignal.on) return CapsLockSignal.on;
      if (_browser == CapsLockSignal.off) return CapsLockSignal.off;
      if (_hardware == CapsLockSignal.on) return CapsLockSignal.on;
      if (_inferred != CapsLockSignal.unknown) return _inferred;
      return CapsLockSignal.unknown;
    }

    if (_hwTrusted) {
      if (_hardware == CapsLockSignal.on) return CapsLockSignal.on;
      if (_hardware == CapsLockSignal.off) return CapsLockSignal.off;
      if (_browser == CapsLockSignal.on) return CapsLockSignal.on;
      if (_browser == CapsLockSignal.off) return CapsLockSignal.off;
      if (_inferred != CapsLockSignal.unknown) return _inferred;
      return CapsLockSignal.unknown;
    }

    if (_browser == CapsLockSignal.on || _hardware == CapsLockSignal.on) {
      return CapsLockSignal.on;
    }
    if (_inferred != CapsLockSignal.unknown) return _inferred;
    if (_latched != CapsLockSignal.unknown) return _latched;
    if (_browser == CapsLockSignal.off) return CapsLockSignal.off;
    return CapsLockSignal.unknown;
  }

  void attach() {
    if (_attached) return;
    _attached = true;
    retainBrowserCapsLockProbe();
    refreshBrowserCapsLockCache();
    _sampleSources();
    _emitUi();
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _detachKeys();
    releaseBrowserCapsLockProbe();
  }

  void onFocusChanged(bool focused) {
    final was = _focused;
    _focused = focused;
    if (focused) {
      _attachKeys();
      refreshBrowserCapsLockCache();
      _sampleSources();
      _scheduleResync();
      _startPoll();
    } else {
      _resyncTimer?.cancel();
      _pollTimer?.cancel();
      _pollTimer = null;
      _detachKeys();
    }
    if (was != focused) {
      _emitUi();
    } else if (focused) {
      _emitUi();
    }
  }

  /// إدراج حرف لاتيني. لا تستدعِ [sync] بعده من الواجهة.
  void inferFromInsertedLatin(String previous, String next) {
    if (next.isEmpty) {
      _inferred = CapsLockSignal.unknown;
      _emitUi();
      return;
    }
    final inferred = inferCapsFromLatinDelta(
      previous,
      next,
      treatUnshiftedUpperAsOn: inferUnshiftedUpperAsOn?.call() ?? false,
    );
    if (inferred == CapsLockSignal.unknown) return;
    _inferred = inferred;
    _latched = CapsLockSignal.unknown;
    _emitUi();
  }

  void sync({bool immediate = true}) {
    _sampleSources();
    _emitUi();
    if (immediate) return;
  }

  void _sampleSources() {
    final hw = _hwNow();
    final br = _browserNow();
    _hardware = hw;
    _browser = br;

    // مصادر مؤكدة فقط تُلغي الاستدلال — عتاد OFF غير الموثوق لا يمسحه.
    if (_useBrowserFirst && br != CapsLockSignal.unknown) {
      _inferred = CapsLockSignal.unknown;
      _latched = CapsLockSignal.unknown;
    } else if (_hwTrusted && hw != CapsLockSignal.unknown) {
      _inferred = CapsLockSignal.unknown;
      _latched = CapsLockSignal.unknown;
    }
  }

  void _emitUi() {
    final next = signal;
    if (next == _ui) return;
    _ui = next;
    onChanged();
  }

  void _attachKeys() {
    if (_keyHandlerAttached) return;
    _keyHandlerAttached = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _detachKeys() {
    if (!_keyHandlerAttached) return;
    _keyHandlerAttached = false;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  @visibleForTesting
  bool debugHandleKey(KeyEvent event) => _onKey(event);

  bool _onKey(KeyEvent event) {
    if (!_focused) return false;

    if (event.logicalKey == LogicalKeyboardKey.capsLock) {
      if (event is KeyDownEvent) {
        final hw = _hwNow();
        final br = _browserNow();
        if (!_hwTrusted &&
            br == CapsLockSignal.unknown &&
            hw != CapsLockSignal.on) {
          final showingOn = _resolve() == CapsLockSignal.on;
          _latched = showingOn ? CapsLockSignal.off : CapsLockSignal.on;
          _inferred = CapsLockSignal.unknown;
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_attached || !_focused) return;
        _sampleSources();
        _emitUi();
        _scheduleResync();
      });
      return false;
    }

    final treatUpper = inferUnshiftedUpperAsOn?.call() ?? false;
    final fromChar = inferCapsFromKeyEvent(
      event,
      treatUnshiftedUpperAsOn: treatUpper,
    );
    // ويب الجوال: لا يُوثق بـ getModifierState — الحرف الكبير لحظياً هو المصدر.
    if (fromChar != CapsLockSignal.unknown &&
        (!_useBrowserFirst || treatUpper)) {
      _inferred = fromChar;
      _latched = CapsLockSignal.unknown;
      _emitUi();
      return false;
    }

    if (event is KeyDownEvent || event is KeyUpEvent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_attached || !_focused) return;
        _sampleSources();
        _emitUi();
      });
    }
    return false;
  }

  void _startPoll() {
    _pollTimer?.cancel();
    if (_hwTrusted && !_useBrowserFirst) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_attached || !_focused) {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      refreshBrowserCapsLockCache();
      _sampleSources();
      _emitUi();
    });
  }

  void _scheduleResync() {
    _resyncTimer?.cancel();
    if (!_useBrowserFirst && _hwTrusted) return;
    _resyncTimer = Timer(const Duration(milliseconds: 40), () {
      if (!_attached || !_focused) return;
      _sampleSources();
      _emitUi();
    });
  }
}
