import 'package:flutter/material.dart';

/// شبكة بطاقات تتكيّف مع العرض (1→4 أعمدة تقريباً).
class ResponsivePropertyExtentGrid extends StatelessWidget {
  const ResponsivePropertyExtentGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minTileWidth = 280,
    this.spacing = 12,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minTileWidth;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth - padding.horizontal;
        final cols = (maxW / (minTileWidth + spacing)).floor().clamp(1, 6);
        final tileW = (maxW - spacing * (cols - 1)) / cols;
        return Padding(
          padding: padding,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: tileW / 220,
            ),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        );
      },
    );
  }
}
