import 'root_dotenv_loader_stub.dart'
    if (dart.library.io) 'root_dotenv_loader_io.dart' as _impl;

/// دمج اختياري مع `assets/env/default.env`: ملف `.env` في جذر المشروع (غير مرفوع مع Git).
Future<String?> tryReadOptionalProjectDotEnv() =>
    _impl.tryReadOptionalProjectDotEnv();
