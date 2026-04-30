import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Lightweight loading indicator: **no** `logoe.png` decode — shimmer + icon only.
/// (Splash / launcher may still use `assets/logoe.png` via native config — not this widget.)
class AppLogoLoading extends StatelessWidget {
  const AppLogoLoading({
    super.key,
    this.size = 96,
    this.compact = false,
  });

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHighest;
    final highlight =
        Color.lerp(cs.primary, cs.surface, compact ? 0.38 : 0.32) ??
            cs.primaryContainer;
    final iconSize = size * (compact ? 0.52 : 0.58);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: Duration(milliseconds: compact ? 950 : 1250),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.apartment_rounded,
          size: iconSize,
          color: Colors.white,
        ),
      ),
    );
  }
}
