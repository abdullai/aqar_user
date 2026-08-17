import 'dart:async';

import 'package:flutter/material.dart';

import '../core/platform/viewport_scroll_policy.dart';

/// شريط تمرير سطح المكتب: ظاهر عند التمرير أو التمرير بالفأرة، مخفي على الجوال.
class AqarDesktopScrollbar extends StatefulWidget {
  const AqarDesktopScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.scrollbarOnRight = true,
    this.alwaysShowThumb = false,
  });

  final ScrollController controller;
  final Widget child;
  final bool scrollbarOnRight;

  /// للورقات الطويلة (بحث متقدم): إبقاء الإبهام ظاهراً بدل إخفائه بعد التمرير.
  final bool alwaysShowThumb;

  @override
  State<AqarDesktopScrollbar> createState() => _AqarDesktopScrollbarState();
}

class _AqarDesktopScrollbarState extends State<AqarDesktopScrollbar> {
  bool _hovering = false;
  bool _scrolling = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _markScrolling() {
    if (!_scrolling && mounted) {
      setState(() => _scrolling = true);
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _scrolling = false);
    });
  }

  bool get _thumbVisible =>
      widget.alwaysShowThumb || _hovering || _scrolling;

  @override
  Widget build(BuildContext context) {
    final desktop = ViewportScrollPolicy.isDesktopLike(context);
    if (!desktop) return widget.child;

    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovering = false);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification ||
              notification is ScrollUpdateNotification ||
              notification is OverscrollNotification) {
            _markScrolling();
          }
          return false;
        },
        child: Scrollbar(
          controller: widget.controller,
          thickness: 9,
          radius: const Radius.circular(12),
          scrollbarOrientation: widget.scrollbarOnRight
              ? ScrollbarOrientation.right
              : ScrollbarOrientation.left,
          thumbVisibility: _thumbVisible,
          trackVisibility: _thumbVisible,
          interactive: true,
          child: widget.child,
        ),
      ),
    );
  }
}
