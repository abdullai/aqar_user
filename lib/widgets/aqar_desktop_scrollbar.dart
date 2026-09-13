import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/platform/viewport_scroll_policy.dart';

/// شريط تمرير سطح المكتب: ظاهر مع الماوس/المؤشر الدقيق، مخفي على اللمس فقط.
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
  bool _finePointer = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _finePointer = ViewportScrollPolicy.hasFinePointer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _notePointer(PointerDeviceKind kind) {
    if (!ViewportScrollPolicy.isFinePointerKind(kind) || _finePointer) {
      return;
    }
    if (mounted) setState(() => _finePointer = true);
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

  bool get _showBar =>
      _finePointer || ViewportScrollPolicy.showPersistentScrollbar(context);

  bool get _thumbVisible =>
      widget.alwaysShowThumb || _hovering || _scrolling;

  @override
  Widget build(BuildContext context) {
    final bar = !_showBar
        ? widget.child
        : MouseRegion(
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
                thickness: _hovering || _scrolling ? 12 : 8,
                radius: const Radius.circular(14),
                scrollbarOrientation: widget.scrollbarOnRight
                    ? ScrollbarOrientation.right
                    : ScrollbarOrientation.left,
                thumbVisibility: _thumbVisible,
                trackVisibility:
                    _thumbVisible && (_hovering || widget.alwaysShowThumb),
                interactive: true,
                child: widget.child,
              ),
            ),
          );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (e) => _notePointer(e.kind),
      onPointerDown: (e) => _notePointer(e.kind),
      onPointerSignal: (e) => _notePointer(e.kind),
      child: bar,
    );
  }
}
