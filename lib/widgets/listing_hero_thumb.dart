import 'package:flutter/material.dart';

import '../core/branding/branding_logo_image.dart';
import 'crystal_listing_media.dart';

/// معاينة بطاقة موحّدة: رابط شبكة أو أصل التطبيق الافتراضي.
class ListingHeroThumb extends StatelessWidget {
  const ListingHeroThumb({
    super.key,
    this.networkUrl,
    required this.width,
    required this.height,
    this.borderRadius = 12,
    this.showVideoBadge = false,
  });

  final String? networkUrl;
  final double width;
  final double height;
  final double borderRadius;

  /// عند تفضيل الفيديو كغلاف (لا يوجد إطار شبكة للصورة).
  final bool showVideoBadge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolved = networkUrl?.trim();
    final hasNet = resolved != null &&
        resolved.isNotEmpty &&
        (resolved.startsWith('http://') || resolved.startsWith('https://'));

    Widget fallback() => BrandingLogoImage(
          fillFrame: true,
          filterQuality: FilterQuality.high,
          errorIcon: showVideoBadge
              ? Icons.videocam_outlined
              : Icons.image_not_supported_outlined,
        );

    final net = resolved;
    late final Widget core;
    if (net != null &&
        net.isNotEmpty &&
        (net.startsWith('http://') || net.startsWith('https://'))) {
      core = CrystalListingMedia(
        url: net,
        fit: BoxFit.cover,
        logicalCacheWidth: width,
        logicalCacheHeight: height,
        placeholder: ColoredBox(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Center(
            child: SizedBox(
              width: width * 0.28,
              height: height * 0.28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        error: fallback(),
      );
    } else {
      core = fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            core,
            if (showVideoBadge && hasNet)
              PositionedDirectional(
                end: 4,
                bottom: 4,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// عرض عرض/ارتفاع مصغّر متجاوب للقوائم (شاشات ضيقة).
(double, double) listingHeroThumbSizeForList(
  double screenWidth, {
  double horizontalPadding = 48,
  double maxSide = 108,
  double minSide = 64,
}) {
  final w = (screenWidth - horizontalPadding).clamp(minSide, maxSide);
  final h = (w * 0.82).clamp(56.0, 92.0);
  return (w, h);
}
