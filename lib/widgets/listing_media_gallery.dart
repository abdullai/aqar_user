import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/branding/branding_logo_image.dart';

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
    this.watermark,
    this.emptyChild,
  });

  final List<String> imageUrls;
  final bool isAr;
  final double aspectRatio;
  final double maxHeight;
  final double borderRadius;
  final BoxFit fit;
  final int initialIndex;
  final Widget? watermark;
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

  @override
  void initState() {
    super.initState();
    final n = _urls.length;
    _index = n == 0 ? 0 : widget.initialIndex.clamp(0, n - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(covariant ListingMediaGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls != widget.imageUrls ||
        oldWidget.initialIndex != widget.initialIndex) {
      final n = _urls.length;
      final next = n == 0 ? 0 : widget.initialIndex.clamp(0, n - 1);
      if (next != _index) {
        _index = next;
        if (_page.hasClients) {
          _page.jumpToPage(_index);
        }
      }
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final n = _urls.length;
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
    await showDialog<void>(
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

    if (urls.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: widget.emptyChild ??
                ColoredBox(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  child: const BrandingLogoImage(
                    fillFrame: true,
                    errorIcon: Icons.image_not_supported_outlined,
                  ),
                ),
          ),
        ),
      );
    }

    final frame = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _page,
                itemCount: urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  return GestureDetector(
                    onTap: () => _openLightbox(i),
                    child: CachedNetworkImage(
                      imageUrl: urls[i],
                      fit: widget.fit,
                      fadeInDuration: const Duration(milliseconds: 120),
                      memCacheWidth: kIsWeb ? 900 : 1400,
                      memCacheHeight: kIsWeb ? 650 : 1000,
                      placeholder: (_, __) => ColoredBox(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        child: const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => ColoredBox(
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
              if (widget.watermark != null) widget.watermark!,
              if (urls.length > 1) ...[
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      '${_index + 1} / ${urls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
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
                    onPressed: () => _openLightbox(_index),
                    icon: const Icon(Icons.zoom_in_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (urls.length <= 1) return frame;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        frame,
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final selected = i == _index;
              return GestureDetector(
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
                  child: CachedNetworkImage(
                    imageUrl: urls[i],
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
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.urls[i],
                      fit: BoxFit.contain,
                      memCacheWidth: kIsWeb ? 1600 : 2200,
                      errorWidget: (_, __, ___) => const Icon(
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
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
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
                  icon: const Icon(Icons.chevron_left, color: Colors.white, size: 36),
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
                  icon: const Icon(Icons.chevron_right, color: Colors.white, size: 36),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
