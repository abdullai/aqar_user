{{flutter_js}}
{{flutter_build_config}}

// بدون serviceWorkerSettings لا يُحمَّل flutter_service_worker.js — يتفادى:
// "prepareServiceWorker took more than 4000ms" وأخطاء التخزين المؤقت (مثل 206 مع Cache.put).
// يكمّل بناء `flutter build web --pwa-strategy=none` في firebase.json.
_flutter.loader.load({});
