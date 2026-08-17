import 'package:flutter/material.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_logo_image.dart';

/// عنوان العلامة المتكيف — يصغّر/يكبّر حسب العرض دون التفاف على الجوال.
class ResponsiveBrandTitle extends StatelessWidget {
  const ResponsiveBrandTitle({
    super.key,
    this.isAr = true,
    this.showSubtitle = true,
    this.showLegalOnWide = true,
    this.alignment = Alignment.center,
    this.maxLines = 1,
  });

  final bool isAr;
  final bool showSubtitle;
  final bool showLegalOnWide;
  final Alignment alignment;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = AppBranding.displayNameForContext(context, isAr: isAr);
    final subtitle = AppBranding.taglineForContext(context, isAr: isAr);
    final titleSize = AppBranding.titleFontSize(context);
    final subtitleSize = AppBranding.subtitleFontSize(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Align(
      alignment: alignment,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment,
            child: Text(
              title,
              maxLines: maxLines,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: isAr ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
                color: cs.primary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (showSubtitle) ...[
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: alignment,
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: subtitleSize,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (showLegalOnWide && wide) ...[
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                AppBranding.legalNoticeLine(isAr: isAr),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontSize: subtitleSize * 0.85,
                  color: cs.outline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// شعار + عنوان متكيف (لشاشات الدخول والترحيب).
class ResponsiveAppLogo extends StatelessWidget {
  const ResponsiveAppLogo({
    super.key,
    this.isAr = true,
    this.size,
    this.showText = true,
  });

  final bool isAr;
  final double? size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final logoSize = size ?? AppBranding.logoSize(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandingLogoImage(
          size: logoSize,
          errorIcon: Icons.apartment_outlined,
        ),
        if (showText) ...[
          const SizedBox(height: 12),
          ResponsiveBrandTitle(isAr: isAr),
        ],
      ],
    );
  }
}
