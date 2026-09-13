import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_keyboard_inset.dart';
import 'app_keyboard_stable.dart';

/// مساحة إضافية تحت الحقل (قائمة اقتراح/نتائج) تُحسب عند إظهار الحقل فوق الكيبورد.
class AppKeyboardReveal extends InheritedWidget {
  const AppKeyboardReveal({
    super.key,
    required this.below,
    required super.child,
  });

  final double below;

  static double extraBelowOf(BuildContext context) {
    final el = context
        .getElementForInheritedWidgetOfExactType<AppKeyboardReveal>();
    final w = el?.widget;
    return w is AppKeyboardReveal ? w.below : 0;
  }

  @override
  bool updateShouldNotify(AppKeyboardReveal oldWidget) =>
      oldWidget.below != below;
}

/// حوارات متمركزة في المساحة الظاهرة فوق الكيبورد (لا وسط الشاشة الكاملة).
class AppKeyboardDialogPad extends StatelessWidget {
  const AppKeyboardDialogPad({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final vis = AppKeyboardInset.visibleHeightOf(context);
    final mq = MediaQuery.of(context);
    final maxW = math.min(720.0, mq.size.width - 16);
    return LayoutBuilder(
      builder: (context, constraints) {
        final capH = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : vis;
        final maxH = math.max(160.0, math.min(vis, capH));
        final topSafe = mq.viewPadding.top;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: maxH,
            width: mq.size.width,
            child: MediaQuery(
              data: mq.copyWith(
                size: Size(mq.size.width, maxH),
                viewInsets: EdgeInsets.zero,
              ),
              child: Padding(
                padding: EdgeInsets.only(top: topSafe > 8 ? topSafe : 0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(160.0, maxH - (topSafe > 8 ? topSafe : 0)),
                      maxWidth: maxW,
                      minWidth: math.min(maxW, mq.size.width - 16),
                    ),
                    child: AppKeyboardLaneScope(child: child),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// بديل [showModalBottomSheet]: كل ورقة تُحصر في المساحة فوق الكيبورد.
Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => AppKeyboardSheetPad(child: builder(ctx)),
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: false,
    routeSettings: routeSettings,
  );
}

/// بديل [showDialog]: الحوار يبقى فوق الكيبورد.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => AppKeyboardDialogPad(child: builder(ctx)),
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: false,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
  );
}
