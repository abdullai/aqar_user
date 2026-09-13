import 'dart:html' as html;

/// يفحص عناصر <video> في الصفحة: مسارات صوت أو بايتات مفكوكة.
bool? probeHtmlVideoHasAudio() {
  final nodes = html.document.querySelectorAll('video');
  if (nodes.isEmpty) return null;
  var sawVideo = false;
  for (final node in nodes) {
    if (node is! html.VideoElement) continue;
    sawVideo = true;
    final dyn = node as dynamic;
    try {
      if (dyn.mozHasAudio == true) return true;
    } catch (_) {}
    try {
      final n = dyn.webkitAudioDecodedByteCount;
      if (n is num && n > 0) return true;
    } catch (_) {}
    try {
      final t = dyn.audioTracks;
      if (t != null && t.length > 0) return true;
    } catch (_) {}
  }
  return sawVideo ? false : null;
}
