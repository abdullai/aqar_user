import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool? _cachedCaps;
int _refs = 0;
bool _listening = false;

JSFunction? _keyListener;
JSFunction? _pointerListener;
JSFunction? _inputListener;

bool _modifierStateUnreliable() {
  try {
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('android') ||
        ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod') ||
        ua.contains('mobile');
  } catch (_) {
    return true;
  }
}

void _inferFromLatinChar(String? ch, {required bool shift}) {
  if (ch == null || ch.length != 1) return;
  final cu = ch.codeUnitAt(0);
  final isUpper = cu >= 65 && cu <= 90;
  final isLower = cu >= 97 && cu <= 122;
  if (!isUpper && !isLower) return;
  if (shift) return;
  _cachedCaps = isUpper;
}

String? _jsString(web.Event e, String name) {
  try {
    final v = (e as JSObject).getProperty<JSAny?>(name.toJS);
    if (v == null) return null;
    return (v as JSString).toDart;
  } catch (_) {
    return null;
  }
}

bool _jsBool(web.Event e, String name) {
  try {
    final v = (e as JSObject).getProperty<JSAny?>(name.toJS);
    if (v == null) return false;
    return (v as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}

void _readModifier(web.Event e) {
  try {
    if (e is web.KeyboardEvent) {
      try {
        if (e.getModifierState('CapsLock')) {
          _cachedCaps = true;
          _inferFromLatinChar(e.key, shift: e.shiftKey);
          return;
        }
      } catch (_) {}
      _inferFromLatinChar(e.key, shift: e.shiftKey);
      if (_modifierStateUnreliable()) return;
      try {
        _cachedCaps = e.getModifierState('CapsLock');
      } catch (_) {}
      return;
    }
    if (e is web.MouseEvent) {
      if (_modifierStateUnreliable()) return;
      try {
        _cachedCaps = e.getModifierState('CapsLock');
      } catch (_) {}
    }
  } catch (_) {
    // بعض لوحات الجوال لا تدعم getModifierState.
  }
}

void _readTypedInput(web.Event e) {
  _inferFromLatinChar(_jsString(e, 'data'), shift: _jsBool(e, 'shiftKey'));
}

void _ensureDomCapsListener() {
  if (_listening) return;
  _listening = true;
  _keyListener = ((web.Event e) {
    _readModifier(e);
  }).toJS;
  _pointerListener = ((web.Event e) {
    _readModifier(e);
  }).toJS;
  _inputListener = ((web.Event e) {
    _readTypedInput(e);
  }).toJS;
  final capture = true.toJS;
  web.document.addEventListener('keydown', _keyListener, capture);
  web.document.addEventListener('keyup', _keyListener, capture);
  web.document.addEventListener('pointerdown', _pointerListener, capture);
  web.document.addEventListener('beforeinput', _inputListener, capture);
  web.document.addEventListener('input', _inputListener, capture);
}

void _tearDownDomCapsListener() {
  if (!_listening) return;
  final capture = true.toJS;
  if (_keyListener != null) {
    web.document.removeEventListener('keydown', _keyListener, capture);
    web.document.removeEventListener('keyup', _keyListener, capture);
  }
  if (_pointerListener != null) {
    web.document.removeEventListener('pointerdown', _pointerListener, capture);
  }
  if (_inputListener != null) {
    web.document.removeEventListener('beforeinput', _inputListener, capture);
    web.document.removeEventListener('input', _inputListener, capture);
  }
  _keyListener = null;
  _pointerListener = null;
  _inputListener = null;
  _listening = false;
}

bool? probeBrowserCapsLock() {
  if (_refs > 0) _ensureDomCapsListener();
  return _cachedCaps;
}

void retainBrowserCapsLockProbe() {
  _refs++;
  _ensureDomCapsListener();
}

void releaseBrowserCapsLockProbe() {
  if (_refs <= 0) return;
  _refs--;
  if (_refs == 0) {
    _tearDownDomCapsListener();
  }
}

void refreshBrowserCapsLockCache() {
  if (_refs > 0) _ensureDomCapsListener();
}
