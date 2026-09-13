import 'dart:convert';
import 'dart:io';

import 'app_runtime_env.dart';
import 'supabase_runtime_overrides.dart';

/// يحمّل `supabase_config.json` بجانب التنفيذي، أو من AppData، أو من جذر المشروع
/// (عند التشغيل من `build/windows/.../Release` يُصعد حتى يجد `web/supabase_config.json`).
Future<void> tryLoadDesktopSupabaseRuntimeConfig() async {
  try {
    for (final f in _candidateFiles()) {
      if (!await f.exists()) continue;
      final raw = (await f.readAsString()).trimLeft();
      if (raw.isEmpty || raw.startsWith('<')) continue;
      if (raw.startsWith('SUPABASE_') || raw.contains('\nSUPABASE_')) {
        _applyDotEnvLines(raw);
        return;
      }
      final dec = jsonDecode(raw);
      if (dec is Map) {
        final map = Map<String, dynamic>.from(dec);
        SupabaseRuntimeOverrides.applyFromJson(map);
        AppRuntimeEnv.mergeFromWebConfig(map);
        return;
      }
    }
  } catch (_) {}
}

void _applyDotEnvLines(String raw) {
  final map = <String, dynamic>{};
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i <= 0) continue;
    map[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  if (map.isEmpty) return;
  SupabaseRuntimeOverrides.applyFromJson(map);
  AppRuntimeEnv.mergeFromWebConfig(map);
}

Iterable<File> _candidateFiles() sync* {
  final names = ['supabase_config.json', '.env'];
  final dirs = <String>[];

  try {
    dirs.add(File(Platform.resolvedExecutable).parent.path);
  } catch (_) {}
  try {
    dirs.add(Directory.current.path);
  } catch (_) {}
  final appData = (Platform.environment['APPDATA'] ?? '').trim();
  if (appData.isNotEmpty) {
    dirs.add('$appData${Platform.pathSeparator}MawthuqLine');
  }

  final seen = <String>{};
  for (final start in dirs) {
    var d = Directory(start);
    for (var i = 0; i < 10; i++) {
      final path = d.path;
      if (!seen.add(path)) break;
      for (final n in names) {
        yield File('$path${Platform.pathSeparator}$n');
      }
      yield File(
        '$path${Platform.pathSeparator}web${Platform.pathSeparator}supabase_config.json',
      );
      final parent = d.parent;
      if (parent.path == path) break;
      d = parent;
    }
  }
}
