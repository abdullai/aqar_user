import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/platform/viewport_scroll_policy.dart';

class _AqarScrollbarScope extends InheritedWidget {
  const _AqarScrollbarScope({required super.child});

  @override
  bool updateShouldNotify(_AqarScrollbarScope oldWidget) => false;
}

/// شريط التمرير الموحّد للمشروع (ويب / ويندوز / الشاشات الكبيرة).
/// - عربي (RTL): على يمين المستخدم، إنجليزي (LTR): على يساره.
/// - يحجز مساحة جانبية خاصة به فلا يغطي البطاقات أو الحقول.
/// - شريط واحد فقط لكل منطقة تمرير: المتداخلة داخل شريط آخر لا تضيف شريطاً ثانياً.
/// - مخفي على اللمس فقط.
class AqarDesktopScrollbar extends StatefulWidget {
  const AqarDesktopScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
    this.alwaysShowThumb = false,
  });

  final ScrollController controller;
  final Widget child;
  final Axis axis;

  /// للورقات الطويلة (بحث متقدم): إبقاء المسار ظاهراً دائماً.
  final bool alwaysShowThumb;

  static const double gutter = 14;

  /// هل يوجد شريط تمرير أب يغطي هذه المنطقة (يمنع تكرار الأشرطة).
  static bool hasAncestorScrollbar(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<_AqarScrollbarScope>() !=
          null ||
      context.findAncestorWidgetOfExactType<Scrollbar>() != null;

  @override
  State<AqarDesktopScrollbar> createState() => _AqarDesktopScrollbarState();
}

/// بديل لـ `Scrollbar` اليدوي في الشاشات: لا يرسم شيئاً، والشريط يأتي من
/// [AqarDesktopScrollbar] عبر ScrollBehavior (مصدر واحد، يمين/يسار حسب اللغة).
class AqarScrollbarShell extends StatelessWidget {
  const AqarScrollbarShell({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
  });

  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;

  @override
  Widget build(BuildContext context) => child;
}

class _AqarDesktopScrollbarState extends State<AqarDesktopScrollbar> {
  bool _hovering = false;
  bool _finePointer = false;

  @override
  void initState() {
    super.initState();
    _finePointer = ViewportScrollPolicy.hasFinePointer();
  }

  void _notePointer(PointerDeviceKind kind) {
    if (!ViewportScrollPolicy.isFinePointerKind(kind) || _finePointer) {
      return;
    }
    if (mounted) setState(() => _finePointer = true);
  }

  bool get _showBar =>
      _finePointer || ViewportScrollPolicy.showPersistentScrollbar(context);

  @override
  Widget build(BuildContext context) {
    Widget bar = widget.child;
    if (_showBar) {
      final vertical = widget.axis == Axis.vertical;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final orientation = vertical
          ? (rtl ? ScrollbarOrientation.right : ScrollbarOrientation.left)
          : ScrollbarOrientation.bottom;
      const gutter = AqarDesktopScrollbar.gutter;
      final padding = vertical
          ? (rtl
              ? const EdgeInsets.only(right: gutter)
              : const EdgeInsets.only(left: gutter))
          : const EdgeInsets.only(bottom: gutter);
      bar = MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovering = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovering = false);
        },
        child: Scrollbar(
          controller: widget.controller,
          thickness: _hovering ? 12 : 8,
          radius: const Radius.circular(14),
          scrollbarOrientation: orientation,
          thumbVisibility: true,
          trackVisibility: _hovering || widget.alwaysShowThumb,
          interactive: true,
          child: Padding(padding: padding, child: widget.child),
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (e) => _notePointer(e.kind),
      onPointerDown: (e) => _notePointer(e.kind),
      onPointerSignal: (e) => _notePointer(e.kind),
      child: _AqarScrollbarScope(child: bar),
    );
  }
}
