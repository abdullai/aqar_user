import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// بطاقة عقارية موحّدة (إعلان / طلب) — صف: بيانات + صورة مربّعة 1:1، وذيل أزرار اختياري.
class UnifiedRealEstateCard extends StatelessWidget {
  const UnifiedRealEstateCard({
    super.key,
    required this.decoration,
    required this.isAr,
    required this.kind,
    required this.dataColumn,
    required this.imageColumn,
    this.onCardTap,
    this.footer,
    this.webHoverShell = true,
    this.cardRadius = 20,
  });

  static const double imageCornerRadius = 15;
  static const double minListCardHeight = 190;

  final BoxDecoration decoration;
  final bool isAr;
  final UnifiedCardKind kind;
  final Widget dataColumn;
  final Widget imageColumn;
  final VoidCallback? onCardTap;
  final Widget? footer;
  final bool webHoverShell;
  final double cardRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kindColors = _kindColors(kind, cs);

    Widget core = Container(
      decoration: decoration,
      constraints: const BoxConstraints(minHeight: minListCardHeight),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(cardRadius),
                bottom:
                    footer == null ? Radius.circular(cardRadius) : Radius.zero,
              ),
              mouseCursor: onCardTap != null
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onTap: onCardTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(10, 12, 10, 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        if (!w.isFinite || w <= 0) {
                          return const SizedBox.shrink();
                        }
                        // بدون IntrinsicHeight + AspectRatio (يكسر الرئيسية على الويب وقد يبالغ بحجم الصورة على الجوال).
                        final compact = w < 390;
                        final imgSide = (w * (compact ? 0.34 : 0.38))
                            .clamp(compact ? 104.0 : 120.0, 240.0);
                        final gapW = w < 340 ? 7.0 : 10.0;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          textDirection: TextDirection.ltr,
                          children: _orderedMainAxis(
                            data: Expanded(
                              child: Align(
                                alignment: AlignmentDirectional.topStart,
                                child: dataColumn,
                              ),
                            ),
                            gap: SizedBox(width: gapW),
                            image: SizedBox(
                              width: imgSide,
                              height: imgSide,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  UnifiedRealEstateCard.imageCornerRadius,
                                ),
                                child: imageColumn,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: isAr ? 6 : null,
                    right: isAr ? null : 6,
                    child: _KindPill(
                      label: kind == UnifiedCardKind.ad
                          ? (isAr ? 'إعلان' : 'Listing')
                          : (isAr ? 'طلب' : 'Request'),
                      background: kindColors.background,
                      foreground: kindColors.foreground,
                    ),
                  ),
                ],
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 10, 8),
                child: footer!,
              ),
          ],
        ),
      ),
    );

    if (webHoverShell) {
      core = _WebHoverScaleShell(child: core);
    }
    return RepaintBoundary(child: core);
  }

  /// عربي: الصورة يمين المستخدم | إنجليزي: الصورة يسار المستخدم ([Row] باتجاه LTR ثابت).
  List<Widget> _orderedMainAxis({
    required Widget data,
    required Widget gap,
    required Widget image,
  }) {
    if (isAr) {
      return [data, gap, image];
    }
    return [image, gap, data];
  }
}

enum UnifiedCardKind { ad, request }

class _KindColors {
  const _KindColors({required this.background, required this.foreground});
  final Color background;
  final Color foreground;
}

_KindColors _kindColors(UnifiedCardKind kind, ColorScheme cs) {
  switch (kind) {
    case UnifiedCardKind.ad:
      return _KindColors(
        background:
            Color.lerp(cs.primaryContainer, Colors.green.shade700, 0.35) ??
                cs.primaryContainer,
        foreground: cs.onPrimaryContainer,
      );
    case UnifiedCardKind.request:
      return _KindColors(
        background:
            Color.lerp(cs.tertiaryContainer, Colors.orange.shade800, 0.42) ??
                cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
      );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        shadowColor: Colors.black26,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: foreground,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// صف أيقونات للمواصفات: مساحة | غرف | حي.
class UnifiedCardSpecRow extends StatelessWidget {
  const UnifiedCardSpecRow({
    super.key,
    required this.bankColor,
    required this.areaText,
    required this.roomsText,
    required this.districtText,
  });

  final Color bankColor;
  final String areaText;
  final String roomsText;
  final String districtText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final segments = <_SpecSeg>[];
    if (areaText.trim().isNotEmpty) {
      segments.add(_SpecSeg(Icons.straighten_outlined, areaText));
    }
    if (roomsText.trim().isNotEmpty) {
      segments.add(_SpecSeg(Icons.bed_outlined, roomsText));
    }
    if (districtText.trim().isNotEmpty) {
      segments.add(_SpecSeg(Icons.location_on_outlined, districtText));
    }
    if (segments.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '|',
                style: TextStyle(
                  color: cs.outline,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: _SpecCell(
              icon: segments[i].icon,
              text: segments[i].text,
              iconColor: bankColor,
              valueColor: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SpecSeg {
  const _SpecSeg(this.icon, this.text);
  final IconData icon;
  final String text;
}

class _SpecCell extends StatelessWidget {
  const _SpecCell({
    required this.icon,
    required this.text,
    required this.iconColor,
    required this.valueColor,
  });

  final IconData icon;
  final String text;
  final Color iconColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: valueColor,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// شارة كاميرا + عدد الصور — زاوية أسفل الصورة.
class UnifiedCardImagePhotoBadge extends StatelessWidget {
  const UnifiedCardImagePhotoBadge({
    super.key,
    required this.count,
    this.includesVideo = false,
  });

  final int count;
  final bool includesVideo;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final icon =
        includesVideo ? Icons.perm_media_outlined : Icons.photo_camera_outlined;
    return Material(
      color: Colors.black.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              '$count',
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// زر أيقونة دائرية شبه شفافة على الصورة.
class UnifiedCardImageCircleIconButton extends StatelessWidget {
  const UnifiedCardImageCircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.backgroundOpacity = 0.45,
    this.iconColor = Colors.white,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double backgroundOpacity;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: backgroundOpacity),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }
}

class _WebHoverScaleShell extends StatefulWidget {
  const _WebHoverScaleShell({required this.child});

  final Widget child;

  @override
  State<_WebHoverScaleShell> createState() => _WebHoverScaleShellState();
}

class _WebHoverScaleShellState extends State<_WebHoverScaleShell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.004 : 1.0,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
