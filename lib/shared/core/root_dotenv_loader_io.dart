import 'dart:io';

/// يقرأ [project_root/.env] عندما يكون مجلد العمل هو جذر المشروع (شائع مع `flutter run` على سطح المكتب).
/// على أجهزة iOS/Android غالباً لا يوجد الملف — استخدم `--dart-define` أو CI.
Future<String?> tryReadOptionalProjectDotEnv() async {
  try {
    final f = File.fromUri(
      Uri.directory(Directory.current.path).resolve('.env'),
    );
    if (await f.exists()) {
      return await f.readAsString();
    }
  } catch (_) {}
  return null;
}
