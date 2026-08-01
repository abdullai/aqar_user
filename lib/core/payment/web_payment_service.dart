/// Web Payment API — stub لمنصات غير الويب.
library;

export 'web_payment_service_stub.dart'
    if (dart.library.js_interop) 'web_payment_service_web.dart';
