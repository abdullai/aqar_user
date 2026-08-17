import 'video_duration_check_stub.dart'
    if (dart.library.io) 'video_duration_check_io.dart' as vd_impl;

/// على الويب يعيد null (لا مسار ملف محلي موثوق).
Future<Duration?> readVideoDurationFromPath(String path) =>
    vd_impl.readVideoDurationFromPath(path);
