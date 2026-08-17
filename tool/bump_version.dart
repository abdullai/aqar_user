// ignore_for_file: avoid_print
//
// يزيد إصدار التطبيق في pubspec.yaml — المصدر الوحيد الذي يقرأه Flutter لـ:
// - Android: versionName / versionCode
// - iOS: MARKETING_VERSION / CURRENT_PROJECT_VERSION
// - Web / Desktop: نفس الاسم والبناء عند flutter build
//
// استخدام (من جذر المشروع):
//   dart run tool/bump_version.dart              → يزيد +رقم البناء فقط (الأنسب لكل رفع متجر)
//   dart run tool/bump_version.dart --patch      → 1.0.0 → 1.0.1 ويزيد البناء
//   dart run tool/bump_version.dart --minor      → يزيد الإصدار الفرعي
//   dart run tool/bump_version.dart --major      → يزيد الإصدار الرئيسي
//   dart run tool/bump_version.dart --dry-run    → يعرض النتيجة دون كتابة
//   dart run tool/bump_version.dart --set-build=42 → يضبط رقم البناء يدوياً (لـ CI مثلاً)
//
// ثم البناء، مثلاً:
//   flutter build apk --release
//   flutter build appbundle --release
//   flutter build ipa
//   flutter build web

import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final bumpPatch = args.contains('--patch');
  final bumpMinor = args.contains('--minor');
  final bumpMajor = args.contains('--major');

  var n = 0;
  for (final a in args) {
    if (a.startsWith('--set-build=')) {
      n = int.tryParse(a.split('=').last) ?? -1;
      if (n < 0) {
        stderr.writeln('Invalid --set-build');
        exitCode = 1;
        return;
      }
    }
  }
  final setBuild = args.any((a) => a.startsWith('--set-build='));

  if (setBuild && (bumpPatch || bumpMinor || bumpMajor)) {
    stderr.writeln('Do not combine --set-build= with --patch/--minor/--major');
    exitCode = 1;
    return;
  }

  if ([bumpPatch, bumpMinor, bumpMajor].where((e) => e).length > 1) {
    stderr.writeln('Use only one of: --patch, --minor, --major');
    exitCode = 1;
    return;
  }

  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Run from project root (pubspec.yaml not found).');
    exitCode = 1;
    return;
  }

  final lines = pubspecFile.readAsStringSync().split('\n');
  var idx = -1;
  String? rawVersion;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('version:')) {
      idx = i;
      rawVersion = line.split('version:').last.trim();
      // يدعم تعليقاً في نفس السطر: version: 1.0.0+1  # comment
      final hash = rawVersion.indexOf('#');
      if (hash >= 0) rawVersion = rawVersion.substring(0, hash).trim();
      break;
    }
  }

  if (idx < 0 || rawVersion == null || rawVersion.isEmpty) {
    stderr.writeln('Could not find version: in pubspec.yaml');
    exitCode = 1;
    return;
  }

  try {
    final parsed = _parseVersion(rawVersion);
    final next = setBuild
        ? (name: parsed.name, build: n)
        : _bump(
            parsed,
            bumpMajor: bumpMajor,
            bumpMinor: bumpMinor,
            bumpPatch: bumpPatch,
          );

    final newLine = 'version: ${next.name}+${next.build}';
    lines[idx] = newLine;

    if (dryRun) {
      print('[dry-run] Would set: $newLine');
      return;
    }

    pubspecFile.writeAsStringSync(lines.join('\n'));
    print('Updated pubspec.yaml → $newLine');
  } on FormatException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}

({String name, int build}) _parseVersion(String raw) {
  final plus = raw.indexOf('+');
  if (plus < 0) {
    final name = raw.trim();
    final parts = name.split('.');
    if (parts.length != 3) {
      throw FormatException('Expected x.y.z or x.y.z+build, got: $raw');
    }
    return (name: name, build: 0);
  }
  final name = raw.substring(0, plus).trim();
  final buildStr = raw.substring(plus + 1).trim();
  final build = int.tryParse(buildStr);
  if (build == null) {
    throw FormatException('Invalid build number in: $raw');
  }
  return (name: name, build: build);
}

({String name, int build}) _bump(
  ({String name, int build}) v, {
  required bool bumpMajor,
  required bool bumpMinor,
  required bool bumpPatch,
}) {
  final parts = v.name.split('.');
  if (parts.length != 3) {
    throw FormatException('Expected semver x.y.z in: ${v.name}');
  }
  var x = int.parse(parts[0]);
  var y = int.parse(parts[1]);
  var z = int.parse(parts[2]);
  var build = v.build;

  if (bumpMajor) {
    x++;
    y = 0;
    z = 0;
    build++;
  } else if (bumpMinor) {
    y++;
    z = 0;
    build++;
  } else if (bumpPatch) {
    z++;
    build++;
  } else {
    build++;
  }

  return (name: '$x.$y.$z', build: build);
}
