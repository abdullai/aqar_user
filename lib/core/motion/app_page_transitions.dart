import 'package:flutter/material.dart';

import 'app_motion_policy.dart';

/// انتقالات صفحات خفيفة (Fade / Slide) — بدون مكتبات خارجية.
abstract final class AppPageTransitions {
  static Route<T> fade<T extends Object?>(
    Widget page, {
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppMotionPolicy.userEnabled
          ? const Duration(milliseconds: 200)
          : Duration.zero,
      reverseTransitionDuration: AppMotionPolicy.userEnabled
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (!AppMotionPolicy.enabledOf(context)) return child;
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AppMotionPolicy.curve,
          ),
          child: child,
        );
      },
    );
  }

  static Route<T> slideUp<T extends Object?>(
    Widget page, {
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppMotionPolicy.userEnabled
          ? const Duration(milliseconds: 240)
          : Duration.zero,
      reverseTransitionDuration: AppMotionPolicy.userEnabled
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (!AppMotionPolicy.enabledOf(context)) return child;
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: AppMotionPolicy.curve,
        ));
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
    );
  }
}
