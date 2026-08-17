import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/platform/viewport_scroll_policy.dart';

/// يربط [PrimaryScrollController] ويُظهر شريط تمرير ذكي على الويب (بما فيه جوال بشاشة كاملة).
class AqarPrimaryScrollScope extends StatefulWidget {
  const AqarPrimaryScrollScope({super.key, required this.child});

  final Widget child;

  @override
  State<AqarPrimaryScrollScope> createState() => _AqarPrimaryScrollScopeState();
}

class _AqarPrimaryScrollScopeState extends State<AqarPrimaryScrollScope> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = PrimaryScrollController(
      controller: _controller,
      child: widget.child,
    );
    if (!kIsWeb && !ViewportScrollPolicy.isDesktopLike(context)) return child;

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final compact = kIsWeb && ViewportScrollPolicy.isCompactTouchLike(context);
    return Scrollbar(
      controller: _controller,
      thumbVisibility: !compact,
      trackVisibility: !compact,
      thickness: compact ? 8 : 14,
      radius: const Radius.circular(14),
      interactive: true,
      scrollbarOrientation:
          rtl ? ScrollbarOrientation.right : ScrollbarOrientation.left,
      child: child,
    );
  }
}
