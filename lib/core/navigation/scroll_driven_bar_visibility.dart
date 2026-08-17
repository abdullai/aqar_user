import 'dart:async';

import 'package:flutter/material.dart';

/// إظهار/إخفاء شريط سفلي (أو علوي) عند التمرير — سريع وذكي مع إظهار عند التوقف.
class ScrollDrivenBarVisibility extends StatefulWidget {
  const ScrollDrivenBarVisibility({
    super.key,
    required this.child,
    required this.bar,
    this.enabled = true,
    this.hideDeltaThreshold = 6,
    this.showDelayOnStop = const Duration(milliseconds: 60),
    this.slideDuration = const Duration(milliseconds: 130),
  });

  final Widget child;
  final Widget bar;
  final bool enabled;
  final double hideDeltaThreshold;
  final Duration showDelayOnStop;
  final Duration slideDuration;

  @override
  State<ScrollDrivenBarVisibility> createState() =>
      _ScrollDrivenBarVisibilityState();
}

class _ScrollDrivenBarVisibilityState extends State<ScrollDrivenBarVisibility> {
  bool _visible = true;
  Timer? _revealTimer;

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  void _setVisible(bool v) {
    if (_visible == v) return;
    setState(() => _visible = v);
  }

  void _scheduleReveal() {
    _revealTimer?.cancel();
    _revealTimer = Timer(widget.showDelayOnStop, () {
      if (mounted) _setVisible(true);
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (!widget.enabled || !mounted) return false;

    if (n is ScrollUpdateNotification) {
      final d = n.scrollDelta;
      if (d == null) return false;
      if (d > widget.hideDeltaThreshold) {
        _revealTimer?.cancel();
        _setVisible(false);
      } else if (d < -widget.hideDeltaThreshold) {
        _revealTimer?.cancel();
        _setVisible(true);
      }
    } else if (n is ScrollEndNotification) {
      _scheduleReveal();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
        ClipRect(
          child: AnimatedSlide(
            duration: widget.slideDuration,
            curve: Curves.easeOutCubic,
            offset: _visible ? Offset.zero : const Offset(0, 1.12),
            child: widget.bar,
          ),
        ),
      ],
    );
  }
}

/// مزوّد حالة لإخفاء [Scaffold.bottomNavigationBar] داخل جسم واحد.
mixin ScrollDrivenBottomNavMixin<T extends StatefulWidget> on State<T> {
  bool bottomNavSlideVisible = true;
  Timer? _bottomNavRevealTimer;

  static const Duration kBottomNavSlideDuration = Duration(milliseconds: 130);

  @override
  void dispose() {
    _bottomNavRevealTimer?.cancel();
    super.dispose();
  }

  bool handleScrollForBottomNav(
    ScrollNotification n, {
    bool enabled = false,
    double hideThreshold = 6,
  }) {
    if (!enabled || !mounted) return false;

    if (n is ScrollUpdateNotification) {
      final d = n.scrollDelta;
      if (d == null) return false;
      if (d > hideThreshold) {
        _bottomNavRevealTimer?.cancel();
        if (bottomNavSlideVisible) {
          setState(() => bottomNavSlideVisible = false);
        }
      } else if (d < -hideThreshold) {
        _bottomNavRevealTimer?.cancel();
        if (!bottomNavSlideVisible) {
          setState(() => bottomNavSlideVisible = true);
        }
      }
    } else if (n is ScrollEndNotification) {
      _bottomNavRevealTimer?.cancel();
      _bottomNavRevealTimer = Timer(const Duration(milliseconds: 60), () {
        if (mounted && !bottomNavSlideVisible) {
          setState(() => bottomNavSlideVisible = true);
        }
      });
    }
    return false;
  }

  void showBottomNavImmediately() {
    _bottomNavRevealTimer?.cancel();
    if (!bottomNavSlideVisible) {
      setState(() => bottomNavSlideVisible = true);
    }
  }
}
