import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/branding_logo_image.dart';
import '../core/listing/listing_media_urls.dart';

/// صورة غلاف طلب السوق أو شعار التطبيق عند غياب الصورة.
class MarketRequestLeadThumb extends StatelessWidget {
  const MarketRequestLeadThumb({
    super.key,
    required this.storagePath,
    this.defaultCoverUsed = false,
    this.size = 56,
    this.borderRadius = 12,
    this.width,
    this.height,
  });

  final String? storagePath;
  final bool defaultCoverUsed;
  final double size;
  final double borderRadius;

  /// عند التعيين يُستخدمان بدل [size] (مثلاً غلاف بطاقة بعرض/ارتفاع مختلفين).
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final boxW = width ?? size;
    final boxH = height ?? size;
    final raw = (storagePath ?? '').trim();

    Widget logoFallback() => ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: SizedBox(
            width: boxW,
            height: boxH,
            child: const BrandingLogoImage(
              fillFrame: true,
              filterQuality: FilterQuality.high,
              errorIcon: Icons.request_quote_outlined,
            ),
          ),
        );

    if (defaultCoverUsed || ListingMediaUrls.isSmartDefaultCoverPath(raw)) {
      return logoFallback();
    }
    final isHttp = raw.startsWith('http://') || raw.startsWith('https://');
    final url = isHttp
        ? raw
        : (raw.isNotEmpty
            ? Supabase.instance.client.storage
                .from('property-images')
                .getPublicUrl(raw)
            : '');

    if (url.isEmpty) return logoFallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: boxW,
        height: boxH,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 160),
          placeholder: (_, __) => Container(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            alignment: Alignment.center,
            child: SizedBox(
              width: boxW * 0.35,
              height: boxH * 0.35,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary.withValues(alpha: 0.6),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => logoFallback(),
        ),
      ),
    );
  }
}
