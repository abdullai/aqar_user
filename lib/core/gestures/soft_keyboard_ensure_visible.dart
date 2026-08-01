import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../platform/viewport_scroll_policy.dart';

/// حل مركزي: عند التركيز على أي حقل نصي على الجوال / ويب الجوال،
/// يُمرَّر المحتوى ليبقي الحقل فوق لوحة المفاتيح.
///
/// لا يُمرَّر أثناء تحديد النص (يمنع رعشة الشاشة على ويب الجوال).
abstract final class AppSoftKeyboardEnsureVisible {
  static WidgetsBindingObserver? _observer;
  static VoidCallback? _focusListener;
  static int _scheduleGen = 0;
  static bool _installed = false;
  static Size? _lastViewSize;
  static DateTime? _lastScrollAt;

  static void install() {
    if (_installed) return;
    _installed = true;

    final observer = _SoftKeyboardMetricsObserver(
      onMetrics: () => scheduleEnsureVisible(fromMetrics: true),
    );
    WidgetsBinding.instance.addObserver(observer);
    _observer = observer;

    void onFocusChange() => scheduleEnsureVisible(fromMetrics: false);
    FocusManager.instance.addListener(onFocusChange);
    _focusListener = onFocusChange;
  }

  static void uninstall() {
    if (!_installed) return;
    _installed = false;
    _scheduleGen++;
    _lastViewSize = null;
    _lastScrollAt = null;

    final obs = _observer;
    if (obs != null) {
      WidgetsBinding.instance.removeObserver(obs);
      _observer = null;
    }
    final fl = _focusListener;
    if (fl != null) {
      FocusManager.instance.removeListener(fl);
      _focusListener = null;
    }
  }

  static void scheduleEnsureVisible({bool fromMetrics = false}) {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null || !ctx.mounted) return;
    if (!_isEditableFocus(focus)) return;
    // أثناء سحب التحديد: أي تمرير يسبب رعشة ويقطع التحديد.
    if (_hasActiveTextSelection(focus)) return;

    final mq = MediaQuery.of(ctx);
    final inset = mq.viewInsets.bottom;
    final compact = ViewportScrollPolicy.isCompactTouchLike(ctx);
    final sizeShrunk = _didViewportShrink(mq.size);

    // سطح مكتب عريض بدون كيبورد ظاهر: لا شيء.
    if (!compact && inset < 8 && !sizeShrunk) return;

    final gen = ++_scheduleGen;

    // ويب الجوال: تأخيرات أقل وأدق — التكرار الطويل كان يهز الشاشة.
    final delays = kIsWeb
        ? (fromMetrics
            ? const <int>[48, 160]
            : const <int>[70, 200])
        : (fromMetrics
            ? const <int>[16, 120]
            : const <int>[40, 160]);

    for (final ms in delays) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (gen != _scheduleGen) return;
        _ensureFocusedEditableVisible();
      });
    }
  }

  static bool _didViewportShrink(Size size) {
    final prev = _lastViewSize;
    _lastViewSize = size;
    if (prev == null) return false;
    return (prev.height - size.height) > 80;
  }

  static bool _isEditableFocus(FocusNode? node) {
    if (node?.context == null) return false;
    return node!.context!.findAncestorStateOfType<EditableTextState>() != null;
  }

  static bool _hasActiveTextSelection(FocusNode? node) {
    final state =
        node?.context?.findAncestorStateOfType<EditableTextState>();
    if (state == null) return false;
    try {
      final sel = state.widget.controller.selection;
      return sel.isValid && !sel.isCollapsed;
    } catch (_) {
      return false;
    }
  }

  static void _ensureFocusedEditableVisible() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null || !ctx.mounted) return;
    if (!_isEditableFocus(focus)) return;
    if (_hasActiveTextSelection(focus)) return;

    final route = ModalRoute.of(ctx);
    final inPopup = route is PopupRoute;
    // داخل حوار بدون Scrollable: لا تحرّك الـ Scaffold خلف الحوار (رعشة).
    if (inPopup && Scrollable.maybeOf(ctx) == null) return;

    final now = DateTime.now();
    final last = _lastScrollAt;
    if (last != null && now.difference(last).inMilliseconds < 280) {
      return;
    }

    final mq = MediaQuery.of(ctx);
    final inset = mq.viewInsets.bottom;
    final compact = ViewportScrollPolicy.isCompactTouchLike(ctx);

    if (_scrollIfObscured(ctx, mq)) {
      _lastScrollAt = now;
      return;
    }

    if (compact && inset > 8 && _fieldInLowerHalf(ctx, mq)) {
      try {
        Scrollable.ensureVisible(
          ctx,
          alignment: inPopup ? 0.08 : 0.14,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
        _lastScrollAt = now;
        return;
      } catch (_) {}
    }

    if (!compact && inset < 8) return;

    if (inset > 40) {
      try {
        Scrollable.ensureVisible(
          ctx,
          alignment: inPopup ? 0.1 : 0.16,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
        _lastScrollAt = now;
      } catch (_) {}
    }
  }

  static bool _fieldInLowerHalf(BuildContext ctx, MediaQueryData mq) {
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    if (!renderObject.attached) return false;
    try {
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final mid = top + renderObject.size.height / 2;
      return mid > mq.size.height * 0.48;
    } catch (_) {
      return false;
    }
  }

  static bool _scrollIfObscured(BuildContext ctx, MediaQueryData mq) {
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    if (!renderObject.attached) return false;

    Offset globalTopLeft;
    try {
      globalTopLeft = renderObject.localToGlobal(Offset.zero);
    } catch (_) {
      return false;
    }

    final fieldBottom = globalTopLeft.dy + renderObject.size.height;
    final screenBottom = mq.size.height;
    final compact = ViewportScrollPolicy.isCompactTouchLike(ctx);
    // لا نفترض كيبورداً وهمياً أثناء التحديد/بدون inset حقيقي — كان يمرّر باستمرار.
    final effectiveInset = mq.viewInsets.bottom > 8
        ? mq.viewInsets.bottom
        : 0.0;
    if (effectiveInset <= 0 && !compact) return false;
    if (effectiveInset <= 0) {
      // ويب جوال بدون inset: مرّر فقط إن كان الحقل تحت خط الأمان السفلي.
      // عتبة أعلى تقلّل الرعشة أثناء الكتابة العادية.
      final safe = screenBottom - (compact ? 160.0 : 48.0);
      if (fieldBottom <= safe) return false;
      final scrollable = Scrollable.maybeOf(ctx);
      if (scrollable == null) return false;
      final delta = fieldBottom - safe + 16;
      if (delta < 12) return false;
      try {
        scrollable.position.animateTo(
          (scrollable.position.pixels + delta)
              .clamp(0.0, scrollable.position.maxScrollExtent),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
        return true;
      } catch (_) {
        return false;
      }
    }

    final keyboardTop = screenBottom - effectiveInset;
    final comfort = compact ? 48.0 : 28.0;
    final overlap = fieldBottom + comfort - keyboardTop;
    if (overlap <= 2) return false;

    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable == null) {
      try {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.14,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        return true;
      } catch (_) {
        return false;
      }
    }
    try {
      scrollable.position.animateTo(
        (scrollable.position.pixels + overlap)
            .clamp(0.0, scrollable.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _SoftKeyboardMetricsObserver with WidgetsBindingObserver {
  _SoftKeyboardMetricsObserver({required this.onMetrics});
  final VoidCallback onMetrics;

  @override
  void didChangeMetrics() => onMetrics();
}
