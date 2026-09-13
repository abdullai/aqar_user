import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<void> ensureGoogleMapsJsLoaded(String key) async {
  final k = key.trim();
  if (k.isEmpty) return;
  try {
    final google = web.window.getProperty('google'.toJS);
    if (google != null && !google.isUndefinedOrNull) {
      final maps = (google as JSObject).getProperty('maps'.toJS);
      if (maps != null && !maps.isUndefinedOrNull) return;
    }
  } catch (_) {}
  try {
    final fn = web.window.getProperty('aqarLoadGoogleMapsJs'.toJS);
    if (fn != null && !fn.isUndefinedOrNull) {
      final promise = (fn as JSFunction).callAsFunction(web.window, k.toJS);
      if (promise != null) {
        await (promise as JSPromise).toDart;
      }
      return;
    }
  } catch (_) {}
  if (web.document.querySelector('script[data-aqar-maps="1"]') != null) {
    return;
  }
  final c = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src =
        'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeComponent(k)}&libraries=places&loading=async'
    ..async = true;
  script.setAttribute('data-aqar-maps', '1');
  script.addEventListener(
    'load',
    (web.Event _) {
      if (!c.isCompleted) c.complete();
    }.toJS,
  );
  script.addEventListener(
    'error',
    (web.Event _) {
      if (!c.isCompleted) c.complete();
    }.toJS,
  );
  web.document.head?.append(script);
  await c.future.timeout(const Duration(seconds: 12), onTimeout: () {});
}
