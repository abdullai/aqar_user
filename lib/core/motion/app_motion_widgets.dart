import 'package:flutter/material.dart';

import 'app_motion_policy.dart';

/// أيقونة تتضخم قليلاً عند الاختيار — خفيف ومحسوس على الجوال/الويب.
class MotionSelectedIcon extends StatelessWidget {
  const MotionSelectedIcon({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppMotionPolicy.enabledOf(context)) return child;
    return AnimatedScale(
      scale: selected ? 1.05 : 1.0,
      duration: AppMotionPolicy.durationOf(context),
      curve: AppMotionPolicy.curve,
      child: child,
    );
  }
}
