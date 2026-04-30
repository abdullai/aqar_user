import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer loading aligned with theme primary (accent) + surface — no bitmap assets.
class AqarShimmer {
  AqarShimmer._();

  static Widget wrap(BuildContext context, {required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHighest;
    final highlight = Color.lerp(cs.primary, cs.surface, 0.42) ?? cs.primaryContainer;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1300),
      child: child,
    );
  }
}

/// Skeleton approximating a property list card (image + text lines).
class PropertyCardSkeleton extends StatelessWidget {
  const PropertyCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bone = cs.surfaceContainerHigh.withValues(alpha: 0.9);
    return AqarShimmer.wrap(
      context,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 108,
                height: 88,
                decoration: BoxDecoration(
                  color: bone,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 16,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: bone,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 14,
                      width: 160,
                      decoration: BoxDecoration(
                        color: bone,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: bone,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrollable list of [PropertyCardSkeleton] for home / grid loading states.
class PropertyCardSkeletonList extends StatelessWidget {
  const PropertyCardSkeletonList({
    super.key,
    this.count = 5,
    this.topPadding = 8,
    this.header,
    this.bottomPadding = 24,
  });

  final int count;
  final double topPadding;
  final double bottomPadding;

  /// Optional title / message above the skeleton cards (e.g. tab-specific loading).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < count; i++) ...[
          const PropertyCardSkeleton(),
          if (i < count - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Shaped like a cart / reservation row: thumbnail + two text lines.
class CartRowSkeleton extends StatelessWidget {
  const CartRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bone = cs.surfaceContainerHigh.withValues(alpha: 0.9);
    return AqarShimmer.wrap(
      context,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: bone,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: bone,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 12,
                      width: 140,
                      decoration: BoxDecoration(
                        color: bone,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List of [CartRowSkeleton] for cart / reservations tab loading.
class CartRowSkeletonList extends StatelessWidget {
  const CartRowSkeletonList({
    super.key,
    this.count = 4,
    this.topPadding = 12,
  });

  final int count;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(12, topPadding, 12, 24),
      children: [
        for (var i = 0; i < count; i++) ...[
          const CartRowSkeleton(),
          if (i < count - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}
