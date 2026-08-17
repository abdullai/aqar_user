import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// فيديو مضمّن مع شريط Chewie (تشغيل/إيقاف/تقديم/سرعة/ملء الشاشة).
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
  ChewieController? _chewie;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (mounted) setState(() {});
      return;
    }
    final vp = VideoPlayerController.networkUrl(uri);
    try {
      await vp.initialize();
      if (!mounted) {
        await vp.dispose();
        return;
      }
      final chewie = ChewieController(
        videoPlayerController: vp,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowPlaybackSpeedChanging: true,
      );
      setState(() {
        _vp = vp;
        _chewie = chewie;
      });
    } catch (_) {
      await vp.dispose();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _vp?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _chewie;
    if (c != null) {
      return ColoredBox(
        color: Colors.black,
        child: Chewie(controller: c),
      );
    }
    return ColoredBox(
      color: Colors.black.withOpacity(0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.isAr ? 'جارٍ تحميل الفيديو…' : 'Loading video…',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
