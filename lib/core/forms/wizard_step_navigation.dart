import 'package:flutter/material.dart';

/// تنقّل معالجات متعددة الخطوات: إغلاق لوحة المفاتيح + العودة لأعلى الخطوة الجديدة.
abstract final class WizardStepNavigation {
  /// يمرّر محتوى الخطوة إلى الأعلى بعد الانتقال (التالي / السابق).
  ///
  /// يستدعي إطارين لاحقين حتى يكتمل بناء الخطوة الجديدة قبل التمرير.
  static void scrollToTop(
    ScrollController controller, {
    bool animate = true,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    void tryScroll() {
      if (!controller.hasClients) return;
      final pos = controller.position;
      if (!pos.hasPixels) return;
      final target = pos.minScrollExtent;
      if ((pos.pixels - target).abs() < 1) return;
      if (animate && pos.maxScrollExtent > 0) {
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      } else {
        controller.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll());
    });
  }
}
