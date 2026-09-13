import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/branding/branding_logo_image.dart';

/// إطار وسائط عالي الوضوح: كثافة شاشة، تباين خفيف للصور الباهتة، بدون ضغط إضافي.
class CrystalListingMedia extends StatelessWidget {
  const CrystalListingMedia({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.enhanceClarity = true,
    this.placeholder,
    this.error,
    this.logicalCacheWidth,
    this.logicalCacheHeight,
  });

  final String url;
  final BoxFit fit;
  final bool enhanceClarity;
  final Widget? placeholder;
  final Widget? error;
  final double? logicalCacheWidth;
  final double? logicalCacheHeight;

  /// مصفوفة تباين خفيفة — توضّح الصور الباهتة دون تدمير الألوان النقية.
  static const List<double> _clarityMatrix = <double>[
    1.07, 0, 0, 0, -8,
    0, 1.07, 0, 0, -8,
    0, 0, 1.08, 0, -7,
    0, 0, 0, 1, 0,
  ];

  static (int, int) cachePxFor(
    BuildContext context, {
    double? logicalW,
    double? logicalH,
  }) {
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio.clamp(1.0, 4.0);
    final size = mq.size;
    final w = (logicalW ?? size.width).clamp(160.0, 4096.0);
    final h = (logicalH ?? (w * 0.72)).clamp(120.0, 4096.0);
    final maxW = kIsWeb ? 2560 : 4096;
    final maxH = kIsWeb ? 1800 : 3072;
    return (
      (w * dpr * 1.15).round().clamp(480, maxW),
      (h * dpr * 1.15).round().clamp(360, maxH),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = url.trim();
    if (resolved.isEmpty ||
        !(resolved.startsWith('http://') || resolved.startsWith('https://'))) {
      return error ??
          const BrandingLogoImage(
            fillFrame: true,
            filterQuality: FilterQuality.high,
            errorIcon: Icons.image_not_supported_outlined,
          );
    }

    final (cw, ch) = cachePxFor(
      context,
      logicalW: logicalCacheWidth,
      logicalH: logicalCacheHeight,
    );

    Widget image = CachedNetworkImage(
      imageUrl: resolved,
      fit: fit,
      alignment: Alignment.center,
      fadeInDuration: const Duration(milliseconds: 90),
      fadeOutDuration: Duration.zero,
      filterQuality: FilterQuality.high,
      memCacheWidth: cw,
      memCacheHeight: ch,
      maxWidthDiskCache: cw,
      maxHeightDiskCache: ch,
      placeholder: (_, __) =>
          placeholder ??
          ColoredBox(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
          ),
      errorWidget: (_, __, ___) =>
          error ??
          const BrandingLogoImage(
            fillFrame: true,
            filterQuality: FilterQuality.high,
            errorIcon: Icons.broken_image_outlined,
          ),
    );

    if (enhanceClarity) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_clarityMatrix),
        child: image,
      );
    }

    return image;
  }
}
