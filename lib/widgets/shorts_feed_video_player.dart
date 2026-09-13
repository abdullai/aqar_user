import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'shorts_video_audio_probe_stub.dart'
    if (dart.library.html) 'shorts_video_audio_probe_web.dart' as audio_probe;

/// يحمّل المقطع الحالي والتالي فقط ويتخلّص من البقية.
abstract final class ShortsVideoWarmPool {
  static final Map<String, VideoPlayerController> _ready = {};
  static final Set<String> _warming = {};
  static final Map<String, bool> audioByUrl = {};

  static VideoPlayerController? controllerFor(String url) => _ready[url];

  static bool isReady(String url) {
    final c = _ready[url];
    return c != null && c.value.isInitialized;
  }

  static Future<void> warm(String url) async {
    final u = url.trim();
    if (u.isEmpty || _ready.containsKey(u) || !_warming.add(u)) return;
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _warming.remove(u);
      return;
    }
    final vp = VideoPlayerController.networkUrl(uri);
    try {
      await vp.initialize();
      await vp.setLooping(true);
      await vp.setVolume(0);
      await vp.pause();
      _ready[u] = vp;
    } catch (_) {
      await vp.dispose();
    } finally {
      _warming.remove(u);
    }
  }

  static Future<void> retain(Set<String> keep) async {
    final drop = _ready.keys.where((k) => !keep.contains(k)).toList();
    for (final k in drop) {
      final c = _ready.remove(k);
      audioByUrl.remove(k);
      await c?.dispose();
    }
  }

  static Future<void> disposeAll() async {
    final all = _ready.values.toList();
    _ready.clear();
    _warming.clear();
    audioByUrl.clear();
    for (final c in all) {
      await c.dispose();
    }
  }
}

/// مشغّل غلاف الشورتز: يستعمل المجمّع، بدون تهيئة شرائح غير مطلوبة.
class ShortsFeedVideoPlayer extends StatefulWidget {
  const ShortsFeedVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.playing,
    required this.muted,
    this.onHasAudio,
    this.pooled = false,
  });

  final String videoUrl;
  final bool playing;
  final bool muted;
  final ValueChanged<bool>? onHasAudio;
  final bool pooled;

  @override
  State<ShortsFeedVideoPlayer> createState() => _ShortsFeedVideoPlayerState();
}

class _ShortsFeedVideoPlayerState extends State<ShortsFeedVideoPlayer> {
  VideoPlayerController? _vp;
  VideoPlayerController? _owned;
  bool _failed = false;
  bool _audioNotified = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant ShortsFeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _audioNotified = false;
      _attach();
      return;
    }
    _applyPlayback();
  }

  Future<void> _attach() async {
    _failed = false;
    final url = widget.videoUrl.trim();
    VideoPlayerController? vp;
    if (widget.pooled) {
      vp = ShortsVideoWarmPool.controllerFor(url);
      if (vp == null || !vp.value.isInitialized) {
        await ShortsVideoWarmPool.warm(url);
        if (!mounted) return;
        vp = ShortsVideoWarmPool.controllerFor(url);
      }
    } else {
      await _owned?.dispose();
      _owned = null;
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        if (mounted) setState(() => _failed = true);
        widget.onHasAudio?.call(false);
        return;
      }
      final created = VideoPlayerController.networkUrl(uri);
      try {
        await created.initialize();
        await created.setLooping(true);
        if (!mounted) {
          await created.dispose();
          return;
        }
        _owned = created;
        vp = created;
      } catch (_) {
        await created.dispose();
      }
    }
    if (vp == null || !vp.value.isInitialized) {
      if (mounted) setState(() => _failed = true);
      widget.onHasAudio?.call(false);
      return;
    }
    _vp = vp;
    if (mounted) setState(() {});
    await _applyPlayback();
    _emitAudio(vp);
  }

  Future<void> _applyPlayback() async {
    final vp = _vp;
    if (vp == null || !vp.value.isInitialized) return;
    try {
      await vp.setVolume(widget.muted ? 0 : 1);
      if (widget.playing) {
        if (!vp.value.isPlaying) await vp.play();
      } else if (vp.value.isPlaying) {
        await vp.pause();
      }
    } catch (_) {}
    if (mounted) setState(() {});
    if (widget.playing && !_audioNotified) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        final c = _vp;
        if (c != null) _emitAudio(c, forceProbe: true);
      });
    }
  }

  void _emitAudio(VideoPlayerController vp, {bool forceProbe = false}) {
    if (_audioNotified && !forceProbe) return;
    var has = true;
    if (kIsWeb) {
      final probed = audio_probe.probeHtmlVideoHasAudio();
      if (probed == null && !forceProbe) return;
      has = probed ?? false;
      if (!has && !forceProbe) return;
    } else {
      has = vp.value.isInitialized && vp.value.duration > Duration.zero;
    }
    ShortsVideoWarmPool.audioByUrl[widget.videoUrl] = has;
    _audioNotified = true;
    widget.onHasAudio?.call(has);
  }

  @override
  void dispose() {
    _vp = null;
    _owned?.dispose();
    _owned = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vp = _vp;
    if (vp != null && vp.value.isInitialized) {
      final sz = vp.value.size;
      return ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: sz.width <= 0 ? 9 : sz.width,
              height: sz.height <= 0 ? 16 : sz.height,
              child: VideoPlayer(vp),
            ),
          ),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: _failed
            ? const Icon(Icons.videocam_off_rounded, color: Colors.white38, size: 40)
            : const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white70,
                ),
              ),
      ),
    );
  }
}
