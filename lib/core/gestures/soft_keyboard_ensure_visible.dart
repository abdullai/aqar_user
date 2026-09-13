import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_keyboard_inset.dart';
import 'app_keyboard_popups.dart';

/// حساب إزاحة التمرير لحقل فوق الكيبورد دون قفزة خارج الحارة الظاهرة.
abstract final class AppKeyboardFieldLane {
  /// موجبة = الحقل منخفض (مرّر للأسفل في المحتوى). `null` = لا تحرّك.
  static double? scrollDelta({
    required double fieldTop,
    required double fieldHeight,
    required double visibleTop,
    required double visibleBottom,
    required bool webSafe,
  }) {
    final fieldBottom = fieldTop + fieldHeight;
    if (visibleBottom <= visibleTop + 36) return null;

    final fullyVisible =
        fieldTop >= visibleTop - 0.5 && fieldBottom <= visibleBottom + 0.5;
    // ويب الجوال: إعادة التوسيط لحقل ظاهر أصلاً تُمرّر المستند مرتين فيطير للأعلى.
    if (fullyVisible) return null;

    var targetCenter = (visibleTop + visibleBottom) / 2;
    final fieldCenter = fieldTop + fieldHeight / 2;
    var delta = fieldCenter - targetCenter;

    var nextTop = fieldTop - delta;
    var nextBottom = nextTop + fieldHeight;
    if (nextTop < visibleTop) {
      delta -= visibleTop - nextTop;
      nextTop = fieldTop - delta;
      nextBottom = nextTop + fieldHeight;
    }
    if (nextBottom > visibleBottom) {
      delta += nextBottom - visibleBottom;
    }

    if (webSafe && delta < 0 && fieldTop >= visibleTop) {
      return null;
    }
    if (delta.abs() < 8) return null;
    return delta;
  }
}

/// سياسة عالمية: الصفحة لا تُرفع مع الكيبورد.
/// التمرير يضع الحقل في المساحة فوق اللوحة، أو يكشف القائمة أسفله.
/// حقل ملتصق بشريط سفلي (دردشة / تعليق) لا يُسحب لمنتصف الشاشة.
abstract final class AppSoftKeyboardEnsureVisible {
  static WidgetsBindingObserver? _observer;
  static VoidCallback? _focusListener;
  static int _scheduleGen = 0;
  static bool _installed = false;
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
    if (!_isEditableFocus(focus)) return;
    if (_hasActiveTextSelection(focus)) return;

    final gen = ++_scheduleGen;
    final delays = kIsWeb
        ? (fromMetrics
            ? const <int>[40, 120, 240, 400]
            : const <int>[60, 180, 320])
        : (fromMetrics ? const <int>[20, 100, 200] : const <int>[36, 140]);

    for (final ms in delays) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (gen != _scheduleGen) return;
        _revealIfCovered();
      });
    }
  }

  static bool _isEditableFocus(FocusNode? node) {
    if (node?.context == null) return false;
    return node!.context!.findAncestorStateOfType<EditableTextState>() != null;
  }

  static bool _hasActiveTextSelection(FocusNode? node) {
    final state = node?.context?.findAncestorStateOfType<EditableTextState>();
    if (state == null) return false;
    try {
      final sel = state.widget.controller.selection;
      return sel.isValid && !sel.isCollapsed;
    } catch (_) {
      return false;
    }
  }

  static void _revealIfCovered() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null || !ctx.mounted) return;
    if (!_isEditableFocus(focus)) return;
    if (_hasActiveTextSelection(focus)) return;

    final now = DateTime.now();
    final last = _lastScrollAt;
    if (last != null && now.difference(last).inMilliseconds < 120) return;

    if (_scrollFieldIntoLane(ctx)) {
      _lastScrollAt = now;
    }
  }

  static bool _scrollFieldIntoLane(BuildContext ctx) {
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    if (!renderObject.attached) return false;

    Offset globalTopLeft;
    try {
      globalTopLeft = renderObject.localToGlobal(Offset.zero);
    } catch (_) {
      return false;
    }

    final fieldH = renderObject.size.height;
    final fieldTop = globalTopLeft.dy;
    final fieldBottom = fieldTop + fieldH;
    final keyboardTop = AppKeyboardInset.keyboardTopOf(ctx);
    final padTop = MediaQuery.paddingOf(ctx).top;
    final extra = AppKeyboardReveal.extraBelowOf(ctx) +
        AppKeyboardInset.accessoryHeightOf(ctx);
    const comfort = 16.0;
    final visibleTop = padTop + 8;
    final visibleBottom = keyboardTop - comfort - extra;
    if (visibleBottom <= visibleTop + 36) return false;

    final overlap = fieldBottom + extra + comfort - keyboardTop;
    final dockedAboveKeyboard = overlap <= 2 &&
        fieldBottom >= keyboardTop - 120 &&
        fieldTop >= visibleTop;
    if (dockedAboveKeyboard) return false;

    final delta = AppKeyboardFieldLane.scrollDelta(
      fieldTop: fieldTop,
      fieldHeight: fieldH,
      visibleTop: visibleTop,
      visibleBottom: visibleBottom,
      webSafe: kIsWeb,
    );
    if (delta == null && overlap <= 1) return false;
    final move = delta ?? (overlap > 1 ? overlap : 0.0);
    if (move.abs() < 8 && overlap <= 1) return false;

    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable != null) {
      try {
        final pos = scrollable.position;
        final maxExtent = pos.maxScrollExtent < 0 ? 0.0 : pos.maxScrollExtent;
        final next = (pos.pixels + move).clamp(0.0, maxExtent);
        if ((next - pos.pixels).abs() >= 2) {
          pos.animateTo(
            next,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
          );
          return true;
        }
      } catch (_) {}
    }

    if (kIsWeb || overlap <= 1) return false;
    try {
      final fieldCenter = fieldTop + fieldH / 2;
      final alignment = fieldH >= (visibleBottom - visibleTop)
          ? 0.0
          : ((fieldCenter - visibleTop) / (visibleBottom - visibleTop))
              .clamp(0.0, 1.0);
      Scrollable.ensureVisible(
        ctx,
        alignment: 1.0 - alignment,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
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
