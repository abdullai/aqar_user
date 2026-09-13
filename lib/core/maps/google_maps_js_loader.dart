import 'google_maps_js_loader_stub.dart'
    if (dart.library.js_interop) 'google_maps_js_loader_web.dart' as impl;

Future<void> ensureGoogleMapsJsLoaded(String key) =>
    impl.ensureGoogleMapsJsLoaded(key);
