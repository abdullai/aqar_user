/// معالجة 3DS لميسّر على الويب (نافذة منبثقة + postMessage).
library;

export 'moyasar_web_3ds_stub.dart'
    if (dart.library.html) 'moyasar_web_3ds_web.dart';
