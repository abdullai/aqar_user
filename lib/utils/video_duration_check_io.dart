import 'dart:io';

import 'package:video_player/video_player.dart';

Future<Duration?> readVideoDurationFromPath(String path) async {
  if (path.isEmpty) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  final c = VideoPlayerController.file(file);
  try {
    await c.initialize();
    return c.value.duration;
  } catch (_) {
    return null;
  } finally {
    await c.dispose();
  }
}
