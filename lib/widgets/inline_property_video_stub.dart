import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// واجهة ويب: مشغل مضمّن داخل البطاقة.
class InlinePropertyVideoPlayerImpl extends StatefulWidget {
  final String videoUrl;
  final bool isAr;

  const InlinePropertyVideoPlayerImpl({
    super.key,
    required this.videoUrl,
    required this.isAr,
  });

  @override
  State<InlinePropertyVideoPlayerImpl> createState() =>
      _InlinePropertyVideoPlayerImplState();
}

class _InlinePropertyVideoPlayerImplState
    extends State<InlinePropertyVideoPlayerImpl> {
  VideoPlayerController? _vp;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final vp = VideoPlayerController.networkUrl(uri);
    try {
      await vp.initialize();
      await vp.setLooping(true);
      if (!mounted) {
        await vp.dispose();
        return;
      }
      setState(() => _vp = vp);
    } catch (_) {
      await vp.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _vp?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vp = _vp;
    if (vp != null && vp.value.isInitialized) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: vp.value.size.width,
                height: vp.value.size.height,
                child: VideoPlayer(vp),
              ),
            ),
            Center(
              child: IconButton.filled(
                iconSize: 42,
                onPressed: () async {
                  if (vp.value.isPlaying) {
                    await vp.pause();
                  } else {
                    await vp.play();
                  }
                  if (mounted) setState(() {});
                },
                icon: Icon(
                  vp.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.88),
      child: Center(
        child: _failed
            ? Text(
                widget.isAr ? 'تعذر تشغيل الفيديو' : 'Video unavailable',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              )
            : const CircularProgressIndicator(color: Colors.white70),
      ),
    );
  }
}
