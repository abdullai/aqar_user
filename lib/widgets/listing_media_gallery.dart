import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/branding/branding_logo_image.dart';
import '../core/gestures/app_keyboard_popups.dart';
import 'crystal_listing_media.dart';
import 'app_page_close_button.dart';

/// معرض صور إعلان: غلاف أولاً، إطار بنسبة مناسبة، أسهم تنقّل، مصغّرات أسفل الإطار،
/// والضغط يفتح عرضاً قابلاً للتكبير.
class ListingMediaGallery extends StatefulWidget {
  const ListingMediaGallery({
    super.key,
    required this.imageUrls,
    this.isAr = true,
    this.aspectRatio = 16 / 10,
    this.maxHeight = 220,
    this.borderRadius = 0,
    this.fit = BoxFit.cover,
    this.initialIndex = 0,
    this.videoUrl,
    this.tourUrl,
    this.fillAvailableHeight = false,
    this.preferVideoFirst = false,
    this.mediaOwnerKey,
    this.onOpenVideo,
    this.onOpenTour,
    this.watermark,
    this.watermarkBuilder,
    this.emptyChild,
  });

  final List<String> imageUrls;
  final bool isAr;
  final double aspectRatio;
  final double maxHeight;
  final double borderRadius;
  final BoxFit fit;
  final int initialIndex;
  final String? videoUrl;
  final String? tourUrl;
  final bool fillAvailableHeight;
  final bool preferVideoFirst;
  final String? mediaOwnerKey;
  final VoidCallback? onOpenVideo;
  final VoidCallback? onOpenTour;
  final Widget? watermark;
  final Widget? Function(BuildContext context, int index)? watermarkBuilder;
  final Widget? emptyChild;

  @override
  State<ListingMediaGallery> createState() => _ListingMediaGalleryState();
}

class _ListingMediaGalleryState extends State<ListingMediaGallery> {
  late PageController _page;
  late int _index;

  List<String> get _urls => widget.imageUrls
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  bool get _hasVideo => (widget.videoUrl ?? '').trim().isNotEmpty;

  bool get _hasTour =>
      (widget.tourUrl ?? '').trim().isNotEmpty || widget.onOpenTour != null;

  int get _total => _urls.length + (_hasVideo ? 1 : 0) + (_hasTour ? 1 : 0);

  int get _videoIndex => widget.preferVideoFirst ? 0 : _urls.length;

  int get _tourIndex => _urls.length + (_hasVideo ? 1 : 0);

  int _imageIndexForSlide(int slideIndex) {
    if (_hasVideo && widget.preferVideoFirst) return slideIndex - 1;
    if (_hasVideo && slideIndex > _videoIndex) return slideIndex - 1;
    return slideIndex;
  }

  bool _isVideoSlide(int index) => _hasVideo && index == _videoIndex;

  bool _isTourSlide(int index) => _hasTour && index == _tourIndex;

  @override
  void initState() {
    super.initState();
    final n = _total;
    _index = n == 0 ? 0 : widget.initialIndex.clamp(0, n - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(covariant ListingMediaGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mediaChanged = oldWidget.mediaOwnerKey != widget.mediaOwnerKey ||
        !listEquals(oldWidget.imageUrls, widget.imageUrls) ||
        oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.tourUrl != widget.tourUrl ||
        oldWidget.preferVideoFirst != widget.preferVideoFirst;
    if (mediaChanged || oldWidget.initialIndex != widget.initialIndex) {
      final n = _total;
      final next = n == 0 ? 0 : widget.initialIndex.clamp(0, n - 1);
      _index = next;
      if (_page.hasClients) {
        _page.jumpToPage(_index);
      }
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final n = _total;
    if (n <= 1) return;
    final next = (_index + delta).clamp(0, n - 1);
    _page.animateToPage(
      next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openLightbox(int start) async {
    final urls = _urls;
    if (urls.isEmpty) return;
    await showAppDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => ListingImageLightbox(
        urls: urls,
        initialIndex: start.clamp(0, urls.length - 1),
        isAr: widget.isAr,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final urls = _urls;
    final total = _total;

    if (total == 0) {
      final empty = widget.emptyChild ??
          ColoredBox(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            child: const BrandingLogoImage(
              fillFrame: true,
              errorIcon: Icons.image_not_supported_outlined,
            ),
          );
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: widget.fillAvailableHeight
            ? SizedBox.expand(child: empty)
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxHeight),
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: empty,
                ),
              ),
      );
    }

    final slideContent = Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _page,
          itemCount: total,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) {
            if (_isVideoSlide(i) || _isTourSlide(i)) {
              final isVideo = _isVideoSlide(i);
              final onTap = isVideo ? widget.onOpenVideo : widget.onOpenTour;
              return Material(
                color: cs.surfaceContainerHighest,
                child: InkWell(
                  onTap: onTap,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isVideo
                              ? Icons.play_circle_fill_rounded
                              : Icons.threed_rotation_outlined,
                          size: 54,
                          color: cs.primary,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isVideo
                              ? (widget.isAr ? 'تشغيل الفيديو' : 'Play video')
                              : (widget.isAr ? 'فتح الجولة' : 'Open tour'),
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            final imageIndex = _imageIndexForSlide(i);
            return GestureDetector(
              onTap: () => _openLightbox(imageIndex),
              child: CrystalListingMedia(
                url: urls[imageIndex],
                fit: widget.fit,
                error: ColoredBox(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  child: const BrandingLogoImage(
                    fillFrame: true,
                    errorIcon: Icons.broken_image_outlined,
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.watermarkBuilder != null &&
            !_isVideoSlide(_index) &&
            !_isTourSlide(_index))
          widget.watermarkBuilder!(
                context,
                _imageIndexForSlide(_index),
              ) ??
              const SizedBox.shrink()
        else if (widget.watermark != null)
          widget.watermark!,
        if (total > 1) ...[
          Positioned(
            left: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: _NavChip(
                icon: Icons.chevron_left_rounded,
                onTap: () => _go(-1),
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: _NavChip(
                icon: Icons.chevron_right_rounded,
                onTap: () => _go(1),
              ),
            ),
          ),
        ],
        PositionedDirectional(
          top: 10,
          start: 10,
          child: Material(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                '${_index + 1} / $total',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
        if (!_isVideoSlide(_index) && !_isTourSlide(_index))
          PositionedDirectional(
            top: 8,
            end: 8,
            child: Material(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(999),
              child: IconButton(
                tooltip: widget.isAr ? 'تكبير الصورة' : 'Enlarge photo',
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                color: Colors.white,
                onPressed: () => _openLightbox(_imageIndexForSlide(_index)),
                icon: const Icon(Icons.zoom_in_rounded),
              ),
            ),
          ),
      ],
    );

    final frame = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: widget.fillAvailableHeight
          ? SizedBox.expand(child: slideContent)
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight),
              child: AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: slideContent,
              ),
            ),
    );

    if (total <= 1) return frame;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.fillAvailableHeight) Expanded(child: frame) else frame,
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: total,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final selected = i == _index;
              final isVideo = _isVideoSlide(i);
              final isTour = _isTourSlide(i);
              final tooltip = isVideo
                  ? (widget.isAr ? 'الفيديو' : 'Video')
                  : isTour
                      ? (widget.isAr ? 'الجولة' : 'Tour')
                      : (widget.isAr
                          ? 'الصورة ${_imageIndexForSlide(i) + 1}'
                          : 'Photo ${_imageIndexForSlide(i) + 1}');
              return Tooltip(
                message: tooltip,
                child: GestureDetector(
                  onTap: () {
                    _page.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        width: selected ? 2.2 : 1,
                        color: selected
                            ? const Color(0xFF0F766E)
                            : cs.outlineVariant.withValues(alpha: 0.75),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: isVideo || isTour
                        ? ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              isVideo
                                  ? Icons.play_arrow_rounded
                                  : Icons.threed_rotation_outlined,
                              size: 28,
                              color: cs.primary,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: urls[_imageIndexForSlide(i)],
                            fit: BoxFit.cover,
                            memCacheWidth: 220,
                            memCacheHeight: 160,
                            errorWidget: (_, __, ___) => ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

class ListingImageLightbox extends StatefulWidget {
  const ListingImageLightbox({
    super.key,
    required this.urls,
    required this.initialIndex,
    required this.isAr,
  });

  final List<String> urls;
  final int initialIndex;
  final bool isAr;

  @override
  State<ListingImageLightbox> createState() => _ListingImageLightboxState();
}

class _ListingImageLightboxState extends State<ListingImageLightbox> {
  late PageController _page;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _page,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                return InteractiveViewer(
                  minScale: 0.85,
                  maxScale: 8,
                  child: Center(
                    child: CrystalListingMedia(
                      url: widget.urls[i],
                      fit: BoxFit.contain,
                      enhanceClarity: true,
                      error: const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  AppPageCloseButton(
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1} / ${widget.urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Positioned(
              bottom: 16,
              left: 20,
              right: 20,
              child: Text(
                widget.isAr
                    ? 'قرّب بإصبعين لصورة بلورية — حتى 8× دون فقدان الصفاء'
                    : 'Pinch to zoom up to 8× — crystal-clear, no extra compression',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ),
            if (widget.urls.length > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _index <= 0
                      ? null
                      : () => _page.previousPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                  icon: const Icon(Icons.chevron_left,
                      color: Colors.white, size: 36),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: _index >= widget.urls.length - 1
                      ? null
                      : () => _page.nextPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                  icon: const Icon(Icons.chevron_right,
                      color: Colors.white, size: 36),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
