// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

StreamSubscription<html.Event>? _vvResize;
StreamSubscription<html.Event>? _vvScroll;
StreamSubscription<html.Event>? _winResize;

/// Safari/Chrome للجوال: visualViewport يتقلّص مع الكيبورد بينما innerHeight يبقى.
double readWebVisualKeyboardInset() {
  try {
    final vv = html.window.visualViewport;
    if (vv == null) return 0;
    final inner = (html.window.innerHeight ?? 0).toDouble();
    final client =
        (html.document.documentElement?.clientHeight ?? 0).toDouble();
    final layout = inner > client ? inner : client;
    if (layout <= 0) return 0;
    final visual =
        (vv.height ?? 0).toDouble() + (vv.offsetTop ?? 0).toDouble();
    final inset = layout - visual;
    if (inset < 48) return 0;
    return inset;
  } catch (_) {
    return 0;
  }
}

void attachWebVisualKeyboardListener(void Function() onChange) {
  detachWebVisualKeyboardListener();
  void fire(html.Event _) => onChange();
  final vv = html.window.visualViewport;
  if (vv != null) {
    _vvResize = vv.onResize.listen(fire);
    _vvScroll = vv.onScroll.listen(fire);
  }
  _winResize = html.window.onResize.listen(fire);
}

void detachWebVisualKeyboardListener() {
  _vvResize?.cancel();
  _vvScroll?.cancel();
  _winResize?.cancel();
  _vvResize = null;
  _vvScroll = null;
  _winResize = null;
}
