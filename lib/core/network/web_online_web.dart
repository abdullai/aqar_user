// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

bool readWebNavigatorOnLine() {
  try {
    return html.window.navigator.onLine ?? true;
  } catch (_) {
    return true;
  }
}

Stream<bool> webOnlineStatusStream() {
  final controller = StreamController<bool>.broadcast();
  void emit() {
    if (!controller.isClosed) controller.add(readWebNavigatorOnLine());
  }

  final on = html.window.onOnline.listen((_) => emit());
  final off = html.window.onOffline.listen((_) => emit());
  controller
    ..onListen = emit
    ..onCancel = () {
      on.cancel();
      off.cancel();
    };
  return controller.stream;
}
