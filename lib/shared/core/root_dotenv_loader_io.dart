import 'dart:io';

/// يقرأ `.env` من مجلد العمل أو بالصعود حتى جذر المشروع، أو بجانب التنفيذي.
Future<String?> tryReadOptionalProjectDotEnv() async {
  try {
    final seen = <String>{};
    final starts = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];
    for (final start in starts) {
      var d = start;
      for (var i = 0; i < 10; i++) {
        if (!seen.add(d.path)) break;
        final f = File('${d.path}${Platform.pathSeparator}.env');
        if (await f.exists()) return await f.readAsString();
        final parent = d.parent;
        if (parent.path == d.path) break;
        d = parent;
      }
    }
  } catch (_) {}
  return null;
}
