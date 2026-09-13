import 'package:flutter/material.dart';

import '../core/listing/listing_media_urls.dart';
import 'shorts_feed_video_player.dart';

/// غلاف صفحتي: صورة أو فيديو حسب اختيار الغلاف، ثم صور بعرض الغلاف نفسه.
class MyPageCoverGallery extends StatefulWidget {
  const MyPageCoverGallery({
    super.key,
    required this.imageUrls,
    required this.isAr,
    this.videoUrl,
    this.coverPrefersVideo = false,
    this.borderRadius = 18,
  });

  final List<String> imageUrls;
  final String? videoUrl;
  final bool coverPrefersVideo;
  final bool isAr;
  final double borderRadius;

  @override
  State<MyPageCoverGallery> createState() => _MyPageCoverGalleryState();
}

class _MyPageCoverGalleryState extends State<MyPageCoverGallery> {
  int _imageIndex = 0;
  bool _showVideo = false;
  bool _paused = false;
  bool _muted = true;

  bool get _hasVideo {
    final v = (widget.videoUrl ?? '').trim();
    return v.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _showVideo = _hasVideo &&
        (widget.coverPrefersVideo || widget.imageUrls.isEmpty);
  }

  @override
  void didUpdateWidget(covariant MyPageCoverGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.coverPrefersVideo != widget.coverPrefersVideo) {
      _showVideo = _hasVideo &&
          (widget.coverPrefersVideo || widget.imageUrls.isEmpty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final images = widget.imageUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !ListingMediaUrls.isSmartDefaultCoverPath(e))
        .toList(growable: false);
    final hasCover = _showVideo || images.isNotEmpty;
    if (!hasCover) return const SizedBox.shrink();

    final i = images.isEmpty ? 0 : _imageIndex.clamp(0, images.length - 1);

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final coverH = (w * 0.56).clamp(188.0, 320.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: SizedBox(
                width: w,
                height: coverH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_showVideo && _hasVideo)
                      GestureDetector(
                        onTap: () => setState(() => _paused = !_paused),
                        child: ShortsFeedVideoPlayer(
                          videoUrl: widget.videoUrl!.trim(),
                          playing: !_paused,
                          muted: _muted,
                        ),
                      )
                    else if (images.isNotEmpty)
                      GestureDetector(
                        onTap: images.length > 1
                            ? () => setState(
                                  () => _imageIndex = (_imageIndex + 1) % images.length,
                                )
                            : null,
                        child: Image.network(
                          images[i],
                          fit: BoxFit.cover,
                          width: w,
                          height: coverH,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: cs.outline,
                            ),
                          ),
                        ),
                      )
                    else
                      ColoredBox(color: cs.surfaceContainerHighest),
                    if (_showVideo && _hasVideo)
                      PositionedDirectional(
                        end: 10,
                        bottom: 10,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: _muted
                                ? (widget.isAr ? 'تشغيل الصوت' : 'Unmute')
                                : (widget.isAr ? 'كتم' : 'Mute'),
                            onPressed: () => setState(() => _muted = !_muted),
                            icon: Icon(
                              _muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (_hasVideo && images.isNotEmpty)
                      PositionedDirectional(
                        start: 10,
                        bottom: 10,
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.black54,
                          label: Text(
                            _showVideo
                                ? (widget.isAr ? 'صور' : 'Photos')
                                : (widget.isAr ? 'فيديو' : 'Video'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () =>
                              setState(() => _showVideo = !_showVideo),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final vis = images.length.clamp(1, 5);
                  final thumbH =
                      (w / vis * 0.62).clamp(56.0, 88.0);
                  final thumbW = (w - (vis - 1) * 6) / vis;
                  Widget thumb(int n) {
                    final selected = !_showVideo && n == i;
                    return SizedBox(
                      width: thumbW,
                      height: thumbH,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() {
                            _showVideo = false;
                            _imageIndex = n;
                          }),
                          borderRadius: BorderRadius.circular(10),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? cs.primary
                                    : cs.outlineVariant
                                        .withValues(alpha: 0.4),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: Image.network(
                                images[n],
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                  color: cs.surfaceContainerHighest,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  if (images.length <= 5) {
                    return SizedBox(
                      height: thumbH,
                      width: w,
                      child: Row(
                        children: [
                          for (var n = 0; n < images.length; n++) ...[
                            if (n > 0) const SizedBox(width: 6),
                            Expanded(child: thumb(n)),
                          ],
                        ],
                      ),
                    );
                  }
                  return SizedBox(
                    height: thumbH,
                    width: w,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, n) => thumb(n),
                    ),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
