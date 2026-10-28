import 'package:flutter/material.dart';

import '../core/gestures/app_keyboard_inset.dart';

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
    final child = AppKeyboardPad(
      extra: AppKeyboardInset.isOpen(context) ? 12 : 0,
      child: PrimaryScrollController(
        controller: _controller,
        child: widget.child,
      ),
    );
    // شريط التمرير يأتي من AqarScrollBehavior (مصدر واحد، يمين/يسار حسب اللغة).
    return child;
  }
}
