import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/branding/aqar_brand_colors.dart';
import '../core/l10n/locale_content.dart';
import 'aqar_marquee_text.dart';
import 'catalog_estate_card_body.dart';

/// بطاقة عقارية موحّدة (إعلان / طلب) — صورة أعلى البيانات في الشبكي والعمودي.
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

  /// متصل الآن / آخر ظهور تحت الصورة مباشرة (ليس فوقها).
  final Widget? underImage;

  /// شريط أعلى الصورة: مستعجل/عادي + طلب/إعلان + العنوان — بلا نص فوق الصورة.
  final Widget? topChrome;
  final bool webHoverShell;
  final double cardRadius;
  final bool fullWidthHeroImage;

  /// نسبة صورة/رأس البطاقة عند [fullWidthHeroImage] (الطلبات يمكن أن تكون أعرض وأقصر).
  final double heroAspectRatio;

  /// ارتفاع ثابت لصورة الرأس — يوحّد صفوف الشبكة عند تمدد البطاقات.
  final double? heroHeight;

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
    this.underImage,
    this.topChrome,
    this.webHoverShell = true,
    this.cardRadius = 24,
    this.fullWidthHeroImage = true,
    this.heroAspectRatio = 2.4,
    this.heroHeight,
  });

  @override
  Widget build(BuildContext context) {
    final inkContent = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (topChrome != null) ...[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 4, 6),
              child: topChrome!,
            ),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(imageCornerRadius),
            child: SizedBox(
              height: heroHeight ?? (fullWidthHeroImage ? 156.0 : 148.0),
              width: double.infinity,
              child: imageColumn,
            ),
          ),
          if (underImage != null) ...[
            const SizedBox(height: 6),
            underImage!,
          ],
          const SizedBox(height: 8),
          dataColumn,
        ],
      ),
    );

    Widget face({required bool fillHeight, double? maxHeight}) {
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
          height: fillHeight && maxHeight != null ? maxHeight : null,
          decoration: decoration,
          constraints: BoxConstraints(
            minHeight: fullWidthHeroImage ? 0 : 132,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(cardRadius),
                    bottom: hasTail ? Radius.zero : Radius.circular(cardRadius),
                  ),
                  mouseCursor: onCardTap != null
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  onTap: onCardTap,
                  onDoubleTap: onCardDoubleTap,
                  child: inkContent,
                ),
                if (fillHeight) const Spacer(),
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
        final h = constraints.maxHeight;
        // ارتفاع 0/ضئيل شائع مع IntrinsicHeight على ويب ويندوز — لا تملأ به البطاقة.
        final fillHeight = constraints.hasBoundedHeight &&
            h.isFinite &&
            h > 48 &&
            h < 8000;
        Widget core = face(
          fillHeight: fillHeight,
          maxHeight: fillHeight ? h : null,
        );

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

/// صف أعلى الصورة: شارات الأولوية/النوع ثم عنوان بتمرير عند الضيق.
class UnifiedCardTitleChrome extends StatelessWidget {
  const UnifiedCardTitleChrome({
    super.key,
    required this.isAr,
    required this.title,
    this.leading = const [],
  });

  final bool isAr;
  final String title;
  final List<Widget> leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lead = <Widget>[];
    for (var i = 0; i < leading.length; i++) {
      if (i > 0) lead.add(const SizedBox(width: 6));
      lead.add(leading[i]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ...lead,
        if (title.trim().isNotEmpty) ...[
          if (lead.isNotEmpty) const SizedBox(width: 8),
          Expanded(
            child: AqarMarqueeText(
              text: LocaleContent.forUi(title.trim(), isAr: isAr),
              height: 22,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                height: 1.2,
                letterSpacing: -0.12,
                color: CatalogReadableInk.title(cs),
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class UnifiedCardKindPill extends StatelessWidget {
  const UnifiedCardKindPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  factory UnifiedCardKindPill.forKind({
    required UnifiedCardKind kind,
    required bool isAr,
    required ColorScheme cs,
  }) {
    final colors = _kindColors(kind, cs);
    return UnifiedCardKindPill(
      label: kind == UnifiedCardKind.ad
          ? (isAr ? 'إعلان' : 'Listing')
          : (isAr ? 'طلب' : 'Request'),
      background: colors.background,
      foreground: colors.foreground,
    );
  }

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: foreground,
            height: 1.0,
            fontFamily: 'Cairo',
          ),
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

/// صف مواصفات: مساحة + منطقة + مدينة + حي بأيقونات، مع تقليص ذكي عند ضيق العرض.
class UnifiedCardSpecRow extends StatelessWidget {
  const UnifiedCardSpecRow({
    super.key,
    required this.bankColor,
    required this.areaText,
    required this.roomsText,
    this.districtText = '',
    this.regionText = '',
    this.cityText = '',
    this.locationParts = const [],
    this.extraChips = const [],
  });

  final Color bankColor;
  final String areaText;
  final String roomsText;
  final String districtText;
  final String regionText;
  final String cityText;
  /// مسار قديم: قائمة مسطّحة إن لم تُمرَّر حقول المنطقة/المدينة/الحي.
  final List<String> locationParts;
  final List<String> extraChips;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final isAr = Localizations.localeOf(context).languageCode != 'en';
    final chipFg = CatalogReadableInk.body(cs);
    final iconFg = isDark ? cs.primary : bankColor;
    final style = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      color: chipFg,
      height: 1.1,
      fontFamily: 'Cairo',
    );

    final region = LocaleContent.forUi(regionText.trim(), isAr: isAr);
    final city = LocaleContent.forUi(cityText.trim(), isAr: isAr);
    final district = LocaleContent.forUi(districtText.trim(), isAr: isAr);
    if (district.isEmpty &&
        region.isEmpty &&
        city.isEmpty &&
        locationParts.isNotEmpty) {
      final locs = LocaleContent.parts(locationParts, isAr: isAr);
      return _legacyJoinedRow(
        locs: locs,
        iconFg: iconFg,
        style: style,
        isAr: isAr,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        List<({IconData icon, String text})> buildChips({
          required bool withDistrict,
          required bool withRooms,
          required bool withExtras,
        }) {
          final out = <({IconData icon, String text})>[];
          final area = areaText.trim();
          if (area.isNotEmpty) {
            out.add((
              icon: Icons.square_foot_outlined,
              text: LocaleContent.forUi(area, isAr: isAr),
            ));
          }
          if (region.isNotEmpty) {
            out.add((icon: Icons.public_outlined, text: region));
          }
          if (city.isNotEmpty) {
            out.add((icon: Icons.location_city_outlined, text: city));
          }
          if (withDistrict && district.isNotEmpty) {
            out.add((icon: Icons.home_work_outlined, text: district));
          }
          if (withRooms && roomsText.trim().isNotEmpty) {
            out.add((
              icon: Icons.bed_outlined,
              text: LocaleContent.forUi(roomsText.trim(), isAr: isAr),
            ));
          }
          if (withExtras) {
            for (final e in extraChips) {
              final t = e.trim();
              if (t.isEmpty) continue;
              out.add((
                icon: Icons.circle,
                text: LocaleContent.forUi(t, isAr: isAr),
              ));
            }
          }
          return out;
        }

        final variants = <List<({IconData icon, String text})>>[
          buildChips(withDistrict: true, withRooms: true, withExtras: true),
          buildChips(withDistrict: false, withRooms: true, withExtras: true),
          buildChips(withDistrict: false, withRooms: true, withExtras: false),
          buildChips(withDistrict: false, withRooms: false, withExtras: false),
          [
            if (areaText.trim().isNotEmpty)
              (
                icon: Icons.square_foot_outlined,
                text: LocaleContent.forUi(areaText.trim(), isAr: isAr),
              ),
            if (region.isNotEmpty) (icon: Icons.public_outlined, text: region),
            if (city.isNotEmpty)
              (icon: Icons.location_city_outlined, text: city),
          ],
          [
            if (areaText.trim().isNotEmpty)
              (
                icon: Icons.square_foot_outlined,
                text: LocaleContent.forUi(areaText.trim(), isAr: isAr),
              ),
            if (city.isNotEmpty)
              (icon: Icons.location_city_outlined, text: city)
            else if (region.isNotEmpty)
              (icon: Icons.public_outlined, text: region),
          ],
          [
            if (areaText.trim().isNotEmpty)
              (
                icon: Icons.square_foot_outlined,
                text: LocaleContent.forUi(areaText.trim(), isAr: isAr),
              ),
          ],
        ];

        List<({IconData icon, String text})> chosen = const [];
        for (final v in variants) {
          if (v.isEmpty) continue;
          if (!maxW.isFinite ||
              maxW <= 0 ||
              _measureChips(v, style) <= maxW + 0.5) {
            chosen = v;
            break;
          }
        }
        if (chosen.isEmpty) return const SizedBox.shrink();
        return _chipsRow(chosen, iconFg: iconFg, style: style);
      },
    );
  }

  Widget _legacyJoinedRow({
    required List<String> locs,
    required Color iconFg,
    required TextStyle style,
    required bool isAr,
  }) {
    final chips = <({IconData icon, String text})>[];
    if (areaText.trim().isNotEmpty) {
      chips.add((
        icon: Icons.square_foot_outlined,
        text: LocaleContent.forUi(areaText.trim(), isAr: isAr),
      ));
    }
    if (locs.isNotEmpty) {
      chips.add((icon: Icons.place_outlined, text: locs.join(' · ')));
    }
    if (roomsText.trim().isNotEmpty) {
      chips.add((
        icon: Icons.bed_outlined,
        text: LocaleContent.forUi(roomsText.trim(), isAr: isAr),
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: _chipsRow(chips, iconFg: iconFg, style: style),
    );
  }

  static double _measureChips(
    List<({IconData icon, String text})> chips,
    TextStyle style,
  ) {
    var w = 0.0;
    for (var i = 0; i < chips.length; i++) {
      if (i > 0) w += 14;
      w += 15 + 3;
      final tp = TextPainter(
        text: TextSpan(text: chips[i].text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      w += tp.width;
    }
    return w;
  }

  static Widget _chipsRow(
    List<({IconData icon, String text})> chips, {
    required Color iconFg,
    required TextStyle style,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                '·',
                style: style.copyWith(
                  color: style.color?.withValues(alpha: 0.55),
                ),
              ),
            ),
          Icon(
            chips[i].icon,
            size: chips[i].icon == Icons.circle ? 6 : 15,
            color: iconFg,
          ),
          const SizedBox(width: 3),
          Text(
            chips[i].text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ],
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
