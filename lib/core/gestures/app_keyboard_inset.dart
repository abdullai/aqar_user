import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_keyboard_web_metrics.dart';

/// مصدر واحد لارتفاع لوحة المفاتيح — شاشات، حوارات، وشيتات.
abstract final class AppKeyboardInset {
  static double bottomOf(BuildContext context) {
    if (AppKeyboardLaneScope.activeOf(context)) return 0;
    final scoped = AppKeyboardScope.maybeOf(context);
    if (scoped != null) return scoped;
    return rawInsetOf(context);
  }

  /// نفس [bottomOf] — للتوافق مع الشيتات التي تقرأ المنصة مباشرة.
  static double platformBottomOf(BuildContext context) => bottomOf(context);

  static EdgeInsets paddingOf(BuildContext context) {
    return EdgeInsets.only(bottom: bottomOf(context));
  }

  static bool isOpen(BuildContext context, {double threshold = 48}) {
    return bottomOf(context) > threshold;
  }

  static double rawInsetOf(BuildContext context) {
    final reported = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    final view = View.maybeOf(context);
    var fromView = 0.0;
    var inferred = 0.0;
    if (view != null && view.devicePixelRatio > 0) {
      final dpr = view.devicePixelRatio;
      fromView = view.viewInsets.bottom / dpr;
      final physH = view.physicalSize.height / dpr;
      final mqH = MediaQuery.maybeSizeOf(context)?.height ?? physH;
      if (physH > mqH + 24) inferred = physH - mqH;
    }
    final web = readWebVisualKeyboardInset();
    return math.max(
      math.max(reported, fromView),
      math.max(inferred, web),
    );
  }

  /// الارتفاع الظاهر فوق لوحة المفاتيح (من دون احتساب الكيبورد مرتين).
  static double visibleHeightOf(BuildContext context) {
    final mqH = MediaQuery.sizeOf(context).height;
    final kb = bottomOf(context);
    final view = View.maybeOf(context);
    if (view == null || view.devicePixelRatio <= 0) {
      return math.max(160.0, mqH - (kb > 8 ? kb : 0));
    }
    final dpr = view.devicePixelRatio;
    final physH = view.physicalSize.height / dpr;
    final viewKb = view.viewInsets.bottom / dpr;
    final kbUse = math.max(kb, viewKb);

    // MediaQuery سبق أن طابق الـ visual viewport.
    if (mqH + 32 < physH) {
      return math.max(160.0, mqH);
    }

    var aboveKb = physH - kbUse;
    if (kIsWeb && kbUse > 48) {
      aboveKb -= 8;
    }
    if (aboveKb > 120) return aboveKb;
    if (mqH > 120) return mqH;
    return math.max(160.0, mqH);
  }

  /// حدّ أعلى المحتوى قبل تغطية لوحة المفاتيح، بإحداثيات نافذة Flutter.
  static double keyboardTopOf(BuildContext context) {
    final layoutH = MediaQuery.sizeOf(context).height;
    final vis = visibleHeightOf(context);
    if (vis < layoutH - 8) return vis;
    return layoutH;
  }

  /// شريط أفق الإدخال فوق الكيبورد — مُعطَّل (لا يُخصم ارتفاع).
  static double accessoryHeightOf(BuildContext context) => 0;

  /// هامش خارج إطار التمرير ليطابق الحارة الظاهرة فوق الكيبورد.
  /// صفر عندما يكون ارتفاع التخطيط هو الحارة نفسها (ويب الجوال) حتى لا يموت المنفذ.
  static double layoutPadBottomOf(BuildContext context) {
    final kb = bottomOf(context);
    if (kb < 8) return 0;
    final mqH = MediaQuery.sizeOf(context).height;
    final vis = visibleHeightOf(context);
    if (mqH <= vis + 12) return 0;
    return math.min(kb, mqH - vis).clamp(0.0, mqH * 0.72);
  }

  /// هامش داخل محتوى التمرير: يُبقي maxScrollExtent > 0 ويسمح بتوسيط الحقل.
  static double scrollContentBottomOf(BuildContext context) {
    if (bottomOf(context) < 8) return 0;
    final vis = visibleHeightOf(context);
    return (vis * 0.36).clamp(80.0, 240.0);
  }

  static EdgeInsets scrollViewPadding(
    BuildContext context, {
    EdgeInsets base = const EdgeInsets.all(16),
  }) {
    return base.copyWith(bottom: base.bottom + scrollContentBottomOf(context));
  }

  /// الحقل المركّز داخل حوار/ورقة — نعيد viewInsets حتى ترفع Flutter الحوارات الخام.
  static bool editingInOverlay() {
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (ctx == null || !ctx.mounted) return false;
    if (ctx.findAncestorStateOfType<EditableTextState>() == null) {
      return false;
    }
    try {
      if (ModalRoute.of(ctx) is PopupRoute) return true;
    } catch (_) {}
    return ctx.findAncestorWidgetOfExactType<Dialog>() != null ||
        ctx.findAncestorWidgetOfExactType<BottomSheet>() != null;
  }
}

/// يغلف التطبيق في [MaterialApp.builder] حتى تقرأ كل الحقول نفس القيمة.
class AppKeyboardScope extends InheritedWidget {
  const AppKeyboardScope({
    super.key,
    required this.inset,
    required super.child,
  });

  final double inset;

  static double? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppKeyboardScope>()?.inset;
  }

  @override
  bool updateShouldNotify(AppKeyboardScope oldWidget) =>
      (oldWidget.inset - inset).abs() > 0.5;
}

/// الحوار/الشيت داخل الحارة الظاهرة فوق الكيبورد — لا تُضاف insets مرة ثانية.
class AppKeyboardLaneScope extends InheritedWidget {
  const AppKeyboardLaneScope({super.key, required super.child});

  static bool activeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppKeyboardLaneScope>() !=
      null;

  @override
  bool updateShouldNotify(AppKeyboardLaneScope oldWidget) => false;
}

/// يلتقط ارتفاع لوحة المفاتيح، يمنع رفع الصفحة، ويعيد الارتفاع على ويب الجوال.
class AppKeyboardHost extends StatefulWidget {
  const AppKeyboardHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppKeyboardHost> createState() => _AppKeyboardHostState();
}

class _AppKeyboardHostState extends State<AppKeyboardHost>
    with WidgetsBindingObserver {
  double _lastInset = -1;
  bool _lastOverlay = false;
  bool _frameScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusOrMetrics);
    attachWebVisualKeyboardListener(_onFocusOrMetrics);
  }

  @override
  void dispose() {
    detachWebVisualKeyboardListener();
    FocusManager.instance.removeListener(_onFocusOrMetrics);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _onFocusOrMetrics();

  void _onFocusOrMetrics() {
    if (!mounted || _frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!mounted) return;
      final inset = AppKeyboardInset.rawInsetOf(context);
      final overlay = AppKeyboardInset.editingInOverlay();
      if ((inset - _lastInset).abs() < 0.5 && overlay == _lastOverlay) {
        return;
      }
      _lastInset = inset;
      _lastOverlay = overlay;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = AppKeyboardInset.rawInsetOf(context);
    var height = mq.size.height;
    final view = View.maybeOf(context);
    if (view != null && view.devicePixelRatio > 0) {
      final windowH = view.physicalSize.height / view.devicePixelRatio;
      if (windowH > height + 24) height = windowH;
    }
    final restoreInsets =
        inset > 8 && AppKeyboardInset.editingInOverlay();
    return AppKeyboardScope(
      inset: inset,
      child: MediaQuery(
        data: mq.copyWith(
          size: Size(mq.size.width, height),
          viewInsets: restoreInsets
              ? EdgeInsets.only(bottom: inset)
              : EdgeInsets.zero,
          padding: mq.viewPadding,
        ),
        child: widget.child,
      ),
    );
  }
}

/// يمنع تكرار هامش الكيبورد إذا غلّف الأب المحتوى مسبقاً.
class AppKeyboardPadScope extends InheritedWidget {
  const AppKeyboardPadScope({super.key, required super.child});

  static bool maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppKeyboardPadScope>() !=
      null;

  @override
  bool updateShouldNotify(AppKeyboardPadScope oldWidget) => false;
}

/// هامش سفلي بمقدار لوحة المفاتيح — للشيتات والحوارات والصفحات القابلة للتمرير.
class AppKeyboardPad extends StatelessWidget {
  const AppKeyboardPad({
    super.key,
    required this.child,
    this.extra = 0,
  });

  final Widget child;
  final double extra;

  @override
  Widget build(BuildContext context) {
    if (AppKeyboardPadScope.maybeOf(context)) return child;
    final bottom = AppKeyboardInset.layoutPadBottomOf(context) + extra;
    final padded = bottom <= 0
        ? child
        : Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: child,
          );
    return AppKeyboardPadScope(child: padded);
  }
}
