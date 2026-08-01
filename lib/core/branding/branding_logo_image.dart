import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_branding.dart';

/// يحمّل بايتات الشعار الذكي (PDF، مشاركة، إلخ).
Future<Uint8List?> loadBrandingLogoBytes() async {
  try {
    final data = await rootBundle.load(AppBranding.primaryLogoAsset);
    return data.buffer.asUint8List();
  } catch (_) {
    if (AppBranding.primaryLogoAsset == AppBranding.establishmentLogoAsset) {
      return null;
    }
    try {
      final data = await rootBundle.load(AppBranding.establishmentLogoAsset);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}

/// شعار/صورة العلامة المتكيفة — [AppBranding.primaryLogoAsset].
class BrandingLogoImage extends StatelessWidget {
  const BrandingLogoImage({
    super.key,
    this.width,
    this.height,
    this.size,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.high,
    this.semanticLabel,
    this.errorIcon,
    /// املأ إطار الغلاف بالكامل (بطاقات/معرض) بدل شعار صغير في الوسط.
    this.fillFrame = false,
  });

  final double? width;
  final double? height;
  final double? size;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final String? semanticLabel;
  final IconData? errorIcon;
  final bool fillFrame;

  @override
  Widget build(BuildContext context) {
    final dim = size ?? width ?? height ?? AppBranding.logoSize(context);
    final w = width ?? dim;
    final h = height ?? dim;
    final cs = Theme.of(context).colorScheme;
    // غلاف ذكي: الشعار كاملاً داخل الإطار (contain) — cover كان يقطع الشعار.
    final effectiveFit = fillFrame ? BoxFit.contain : fit;
    final asset = AppBranding.bootLogoAsset(context);

    final image = Image.asset(
      asset,
      width: fillFrame ? null : w,
      height: fillFrame ? null : h,
      fit: effectiveFit,
      alignment: Alignment.center,
      filterQuality: filterQuality,
      errorBuilder: (_, __, ___) {
        final fallback = asset == AppBranding.establishmentLogoAsset
            ? AppBranding.nativeAppLogoAsset
            : AppBranding.establishmentLogoAsset;
        return Image.asset(
          fallback,
          width: fillFrame ? null : w,
          height: fillFrame ? null : h,
          fit: effectiveFit,
          alignment: Alignment.center,
          filterQuality: filterQuality,
          semanticLabel: semanticLabel,
          errorBuilder: (_, __, ___) => Icon(
            errorIcon ?? Icons.apartment_outlined,
            size: (w < h ? w : h) * 0.45,
            color: cs.primary,
          ),
        );
      },
      semanticLabel: semanticLabel,
    );

    if (!fillFrame) return image;

    return ColoredBox(
      color: Color.alphaBlend(
        cs.primary.withValues(alpha: 0.06),
        cs.surfaceContainerHighest.withValues(alpha: 0.55),
      ),
      child: SizedBox.expand(
        child: Padding(
          // هامش خفيف حتى يظهر الشعار كاملاً ومنسّقاً داخل إطار البطاقة.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: image,
        ),
      ),
    );
  }
}
