import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_keyboard_inset.dart';

export 'app_keyboard_popups.dart'
    show
        AppKeyboardDialogPad,
        AppKeyboardReveal,
        showAppDialog,
        showAppModalBottomSheet;

/// يثبّت تخطيط الشاشة عند ظهور لوحة المفاتيح على الجوال وويب الجولات.
///
/// لوحة المفاتيح تُعامل كطبقة فوق المحتوى بدل تقليص الصفحة ورفع الحقول.
class AppKeyboardStableScope extends StatefulWidget {
  const AppKeyboardStableScope({super.key, required this.child});

  final Widget child;

  @override
  State<AppKeyboardStableScope> createState() => _AppKeyboardStableScopeState();
}

class _AppKeyboardStableScopeState extends State<AppKeyboardStableScope>
    with WidgetsBindingObserver {
  double _lockedH = 0;
  double _lockedW = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final view = View.maybeOf(context);
    final platformKb = AppKeyboardInset.platformBottomOf(context);
    final reportedKb = mq.viewInsets.bottom;
    final kb = reportedKb > 8 ? reportedKb : platformKb;
    if (kb < 8 && view == null) return widget.child;

    var height = mq.size.height;
    if (view != null) {
      final windowH = view.physicalSize.height / view.devicePixelRatio;
      if (kIsWeb) {
        final w = mq.size.width;
        if (_lockedW == 0 || (w - _lockedW).abs() > 48) {
          _lockedW = w;
          _lockedH = windowH > height ? windowH : height;
        } else if (windowH > _lockedH) {
          _lockedH = windowH;
        } else if (height > _lockedH) {
          _lockedH = height;
        }
        if (_lockedH > height + 8) height = _lockedH;
      } else if (windowH > height + 24) {
        height = windowH;
      }
    }

    return MediaQuery(
      data: mq.copyWith(
        size: Size(mq.size.width, height),
        viewInsets: EdgeInsets.zero,
        padding: mq.viewPadding,
      ),
      child: widget.child,
    );
  }
}

/// يرسّي الشيت في المساحة الظاهرة فوق لوحة المفاتيح (من أعلى الشاشة حتى الكيبورد).
class AppKeyboardSheetPad extends StatelessWidget {
  const AppKeyboardSheetPad({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final vis = AppKeyboardInset.visibleHeightOf(context);
    final mq = MediaQuery.of(context);
    final kbOpen = AppKeyboardInset.isOpen(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final capH = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : vis;
        final maxH = math.max(160.0, math.min(vis, capH));
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: maxH,
            width: mq.size.width,
            child: MediaQuery(
              data: mq.copyWith(
                size: Size(mq.size.width, maxH),
                viewInsets: EdgeInsets.zero,
                padding: mq.padding.copyWith(
                  bottom: kbOpen ? 0 : mq.padding.bottom,
                ),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxH,
                    maxWidth: mq.size.width,
                  ),
                  child: AppKeyboardLaneScope(child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
