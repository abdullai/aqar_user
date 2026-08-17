import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/branding/aqar_brand_colors.dart';

/// بطاقة عقارية موحّدة (إعلان / طلب) — صف بيانات+صورة أو صورة عريضة أعلى البيانات.
///
/// الصورة تمتد بارتفاع عمود البيانات (يمين المستخدم في العربية) دون فراغ أسفلها.
class UnifiedRealEstateCard extends StatelessWidget {
  static const double imageCornerRadius = 16;
  static const double minListCardHeight = 168;

  final BoxDecoration decoration;
  final bool isAr;
  final UnifiedCardKind kind;
  final Widget dataColumn;
  final Widget imageColumn;
  final VoidCallback? onCardTap;
  /// نقر مزدوج — إضافة/إزالة المفضلة (إعلانات).
  final VoidCallback? onCardDoubleTap;
  final Widget? footer;
  final Widget? belowMainRow;
  final bool webHoverShell;
  final double cardRadius;
  final bool fullWidthHeroImage;
  /// نسبة صورة/رأس البطاقة عند [fullWidthHeroImage] (الطلبات يمكن أن تكون أعرض وأقصر).
  final double heroAspectRatio;

  const UnifiedRealEstateCard({
    super.key,
    required this.decoration,
    required this.isAr,
    required this.kind,
    required this.dataColumn,
    required this.imageColumn,
    this.onCardTap,
    this.onCardDoubleTap,
    this.footer,
    this.belowMainRow,
    this.webHoverShell = true,
    this.cardRadius = 24,
    this.fullWidthHeroImage = false,
    this.heroAspectRatio = 2.4,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kindColors = _kindColors(kind, cs);

    final inkContent = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 6),
          child: fullWidthHeroImage
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(imageCornerRadius),
                      child: AspectRatio(
                        aspectRatio: heroAspectRatio,
                        child: imageColumn,
                      ),
                    ),
                    const SizedBox(height: 8),
                    dataColumn,
                  ],
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    var w = constraints.maxWidth;
                    if (!w.isFinite || w <= 0) {
                      final mq = MediaQuery.sizeOf(context).width;
                      w = (mq - 24).clamp(200.0, mq);
                    }
                    if (!w.isFinite || w <= 0) {
                      // لا تُرجع فراغاً قابلاً للضغط فقط — اعرض البيانات على الأقل.
                      return dataColumn;
                    }
                    final compact = w < 390;
                    final gapW = w < 340 ? 10.0 : 14.0;
                    // صورة أوضح بجانب البيانات (~45% مثل dealapp) — بيانات مريحة بجانبها.
                    const minDataW = 160.0;
                    final maxImg = (w - gapW - minDataW).clamp(120.0, 260.0);
                    final imgWidth = (w * (compact ? 0.40 : 0.46))
                        .clamp(compact ? 118.0 : 140.0, maxImg);
                    // IntrinsicHeight يعطي Row ارتفاعاً محدوداً حتى يعمل
                    // CrossAxisAlignment.stretch + StackFit.expand في الصورة
                    // دون Null check على الويب بعد إزالة equal-height.
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        textDirection: TextDirection.ltr,
                        children: _orderedMainAxis(
                          data: Expanded(
                            child: Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: isAr ? 2 : 0,
                                end: isAr ? 0 : 2,
                                top: 2,
                                bottom: 2,
                              ),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: dataColumn,
                              ),
                            ),
                          ),
                          gap: SizedBox(width: gapW),
                          image: SizedBox(
                            width: imgWidth,
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(imageCornerRadius),
                              child: imageColumn,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          top: 6,
          // زاوية الصورة دائماً (يمين المستخدم في العربية) — لا يغطي العنوان/التاريخ.
          left: isAr ? null : 6,
          right: isAr ? 6 : null,
          child: _KindPill(
            label: kind == UnifiedCardKind.ad
                ? (isAr ? 'إعلان' : 'Listing')
                : (isAr ? 'طلب' : 'Request'),
            background: kindColors.background,
            foreground: kindColors.foreground,
          ),
        ),
      ],
    );

    Widget face({required bool fillHeight}) {
      final hasTail = belowMainRow != null || footer != null;
      final tail = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (belowMainRow != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 6),
              child: belowMainRow!,
            ),
          if (footer != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
              child: footer!,
            )
          else if (belowMainRow != null)
            const SizedBox(height: 8),
        ],
      );

      return ClipRRect(
        borderRadius: BorderRadius.circular(cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: double.infinity,
          height: fillHeight ? double.infinity : null,
          decoration: decoration,
          constraints: const BoxConstraints(minHeight: minListCardHeight),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // بدون ClipRect — قصّ الارتفاع كان يغطي المبلغ ورقم الإعلان.
                InkWell(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(cardRadius),
                    bottom: hasTail
                        ? Radius.zero
                        : Radius.circular(cardRadius),
                  ),
                  mouseCursor: onCardTap != null
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  onTap: onCardTap,
                  onDoubleTap: onCardDoubleTap,
                  child: inkContent,
                ),
                if (fillHeight && hasTail) const Spacer(),
                if (hasTail)
                  Material(
                    type: MaterialType.transparency,
                    child: tail,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // لا تملأ الارتفاع بـ infinity داخل IntrinsicHeight — كان يُخفي البطاقات.
        // الصف يوحّد الارتفاع عبر stretch؛ البطاقة تبقى بمحتواها الطبيعي.
        Widget core = face(fillHeight: false);

        final hoverShell = footer == null &&
            belowMainRow == null &&
            (webHoverShell && !kIsWeb);
        if (hoverShell) {
          core = _WebHoverScaleShell(child: core);
        }
        return RepaintBoundary(child: core);
      },
    );
  }

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
      return const _KindColors(
        background: AqarBrandColors.primary,
        foreground: Colors.white,
      );
    case UnifiedCardKind.request:
      return const _KindColors(
        background: Color(0xFFEA580C),
        foreground: Colors.white,
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
    final labelWidget = Padding(
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
          fontFamily: 'Cairo',
        ),
      ),
    );
    return IgnorePointer(
      ignoring: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AqarBrandColors.gold.withValues(alpha: 0.55),
            width: 1.1,
          ),
        ),
        child: labelWidget,
      ),
    );
  }
}

/// صف مواصفات مريح — أيقونة + نص غامق بدون حدود/خلفيات متضاربة.
class UnifiedCardSpecRow extends StatelessWidget {
  const UnifiedCardSpecRow({
    super.key,
    required this.bankColor,
    required this.areaText,
    required this.roomsText,
    this.districtText = '',
    this.locationParts = const [],
    this.extraChips = const [],
  });

  final Color bankColor;
  final String areaText;
  final String roomsText;
  final String districtText;
  final List<String> locationParts;
  final List<String> extraChips;

  static const _locIcons = <IconData>[
    Icons.public_outlined,
    Icons.account_balance_outlined,
    Icons.location_city_outlined,
    Icons.holiday_village_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final chips = <({IconData? icon, String text})>[];
    if (areaText.trim().isNotEmpty) {
      chips.add((icon: Icons.straighten_outlined, text: areaText.trim()));
    }
    if (roomsText.trim().isNotEmpty) {
      chips.add((icon: Icons.bed_outlined, text: roomsText.trim()));
    }
    final locs = locationParts
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (locs.isNotEmpty) {
      for (var i = 0; i < locs.length; i++) {
        chips.add((
          icon: _locIcons[i.clamp(0, _locIcons.length - 1)],
          text: locs[i],
        ));
      }
    } else if (districtText.trim().isNotEmpty) {
      chips.add((
        icon: Icons.location_on_outlined,
        text: districtText.trim(),
      ));
    }
    for (final e in extraChips) {
      final t = e.trim();
      if (t.isNotEmpty) chips.add((icon: null, text: t));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    final chipFg = isDark ? cs.onSurface : const Color(0xFF0B1F1A);
    final iconFg = isDark ? cs.primary : bankColor;

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final chip in chips)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chip.icon != null) ...[
                Icon(chip.icon!, size: 15, color: iconFg),
                const SizedBox(width: 4),
              ] else ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AqarBrandColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                chip.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: chipFg,
                  height: 1.1,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
      ],
    );
  }
}

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
