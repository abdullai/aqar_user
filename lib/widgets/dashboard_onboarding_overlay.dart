import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'app_page_close_button.dart';

/// اتجاه سهم التلميح نحو العنصر المشروح.
enum DashboardCoachArrow {
  up,
  down,
  left,
  right,
  none,
}

/// خطوة جولة لوحة التحكم: [tabIndex] يطابق فهرس IndexedStack؛
/// إن كان null لا يُغيّر التبويب (أيقونات الشريط العلوي مثلاً).
class DashboardOnboardingStepData {
  const DashboardOnboardingStepData({
    required this.title,
    required this.body,
    this.tabIndex,
    this.arrow = DashboardCoachArrow.down,
    this.targetKey,

    /// موضع أفقي تقريبي للسهم (0=بداية، 1=نهاية) فوق شريط التنقل السفلي.
    this.navFraction,
  });

  final String title;
  final String body;
  final int? tabIndex;
  final DashboardCoachArrow arrow;
  final GlobalKey? targetKey;

  /// لخطوات الشريط السفلي: 0…1 من يسار الشاشة إلى يمينها (LTR).
  final double? navFraction;
}

/// جولة تعريفية عالمية: فقاعة شبه دائرية صغيرة + سهم يتحرك مع التبويب.
/// الضغط خارج الفقاعة = التالي (لا إغلاق). الإغلاق/التخطي فقط من الأزرار.
class DashboardOnboardingOverlay extends StatefulWidget {
  final AppLocalizations l10n;
  final List<DashboardOnboardingStepData> steps;
  final void Function(int tabIndex) onTabChange;
  final VoidCallback onComplete;
  final String partnerLine;
  final ValueChanged<double>? onBackdropPointerScroll;

  const DashboardOnboardingOverlay({
    super.key,
    required this.l10n,
    required this.steps,
    required this.onTabChange,
    required this.onComplete,
    required this.partnerLine,
    this.onBackdropPointerScroll,
  });

  @override
  State<DashboardOnboardingOverlay> createState() =>
      _DashboardOnboardingOverlayState();
}

class _DashboardOnboardingOverlayState extends State<DashboardOnboardingOverlay>
    with SingleTickerProviderStateMixin {
  int _pageIndex = 0;
  Rect? _targetRect;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    assert(widget.steps.isNotEmpty, 'DashboardOnboardingOverlay.steps');
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyTabForPage(0);
      _scheduleTargetMeasurement(0);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardOnboardingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.steps != widget.steps) {
      _scheduleTargetMeasurement(_pageIndex);
    }
  }

  void _scheduleTargetMeasurement(int page, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || page != _pageIndex) return;
      final targetKey = widget.steps[page].targetKey;
      final targetObject = targetKey?.currentContext?.findRenderObject();
      final overlayObject = context.findRenderObject();
      if (targetObject is RenderBox &&
          targetObject.attached &&
          overlayObject is RenderBox &&
          overlayObject.attached) {
        final targetOrigin = targetObject.localToGlobal(Offset.zero);
        final overlayOrigin = overlayObject.localToGlobal(Offset.zero);
        final nextRect = Rect.fromLTWH(
          targetOrigin.dx - overlayOrigin.dx,
          targetOrigin.dy - overlayOrigin.dy,
          targetObject.size.width,
          targetObject.size.height,
        );
        if (_targetRect != nextRect) {
          setState(() => _targetRect = nextRect);
        }
        return;
      }

      if (attempt < 6 && targetKey != null) {
        Future<void>.delayed(
          const Duration(milliseconds: 80),
          () => _scheduleTargetMeasurement(page, attempt: attempt + 1),
        );
      } else if (_targetRect != null) {
        setState(() => _targetRect = null);
      }
    });
  }

  void _applyTabForPage(int i) {
    if (i < 0 || i >= widget.steps.length) return;
    final t = widget.steps[i].tabIndex;
    if (t != null) widget.onTabChange(t);
  }

  Future<void> _goNext() async {
    if (_pageIndex >= widget.steps.length - 1) {
      _finishAll();
      return;
    }
    setState(() {
      _pageIndex += 1;
      _targetRect = null;
    });
    _applyTabForPage(_pageIndex);
    _scheduleTargetMeasurement(_pageIndex);
  }

  Future<void> _goBack() async {
    if (_pageIndex == 0) return;
    setState(() {
      _pageIndex -= 1;
      _targetRect = null;
    });
    _applyTabForPage(_pageIndex);
    _scheduleTargetMeasurement(_pageIndex);
  }

  void _finishAll() {
    widget.onComplete();
  }

  Alignment _bubbleAlignment(DashboardOnboardingStepData step, bool rtl) {
    switch (step.arrow) {
      case DashboardCoachArrow.up:
        final f = step.navFraction ?? 0.5;
        final x = rtl ? (1 - f) * 2 - 1 : f * 2 - 1;
        return Alignment(x.clamp(-0.85, 0.85), -0.68);
      case DashboardCoachArrow.down:
        final f = step.navFraction ?? 0.5;
        final x = rtl ? (1 - f) * 2 - 1 : f * 2 - 1;
        return Alignment(x.clamp(-0.85, 0.85), 0.58);
      case DashboardCoachArrow.left:
        return const Alignment(-0.72, 0.05);
      case DashboardCoachArrow.right:
        return const Alignment(0.72, 0.05);
      case DashboardCoachArrow.none:
        return Alignment.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return ScrollConfiguration(
      behavior: const AqarScrollBehavior(),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final step = widget.steps[_pageIndex];
            final n = widget.steps.length;
            final maxCardW =
                math.min(360.0, math.max(220.0, constraints.maxWidth - 24));
            final maxCardH = math.min(320.0, constraints.maxHeight - 24);
            final targetRect = _targetRect;
            final placeBelow = targetRect == null ||
                constraints.maxHeight - targetRect.bottom >= targetRect.top;
            final resolvedArrow = targetRect == null
                ? step.arrow
                : placeBelow
                    ? DashboardCoachArrow.up
                    : DashboardCoachArrow.down;
            final left = targetRect == null
                ? null
                : (targetRect.center.dx - maxCardW / 2)
                    .clamp(12.0, constraints.maxWidth - maxCardW - 12);
            final maxTop = math.max(
              12.0,
              constraints.maxHeight - maxCardH - 12,
            );
            final requestedTop = targetRect == null
                ? 12.0
                : placeBelow
                    ? targetRect.bottom + 12
                    : targetRect.top - maxCardH - 12;
            final top = requestedTop.clamp(12.0, maxTop);
            final bubble = ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxCardW,
                maxHeight: maxCardH,
              ),
              child: _CoachBubble(
                arrow: resolvedArrow,
                partnerLine: widget.partnerLine,
                title: step.title,
                body: step.body,
                stepLabel: t.onboardingStepCounter(_pageIndex + 1, n),
                progress: (_pageIndex + 1) / n,
                onClose: _finishAll,
                onSkip: _finishAll,
                onBack: _pageIndex > 0 ? () => unawaited(_goBack()) : null,
                onNext: () => unawaited(_goNext()),
                nextLabel:
                    _pageIndex < n - 1 ? t.onboardingNext : t.onboardingFinish,
                skipLabel: t.onboardingSkip,
                closeTooltip: t.onboardingClose,
                previousLabel: t.onboardingPrevious,
                colorScheme: cs,
                textTheme: textTheme,
              ),
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent) {
                        widget.onBackdropPointerScroll
                            ?.call(signal.scrollDelta.dy);
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: CustomPaint(
                        painter: _SpotlightBackdropPainter(
                          targetRect: targetRect,
                          scrimColor: cs.scrim.withValues(alpha: 0.78),
                          highlightColor: cs.primary,
                          pulseAnimation: _pulse,
                        ),
                      ),
                    ),
                  ),
                ),
                if (targetRect == null)
                  Align(
                    alignment: _bubbleAlignment(step, rtl),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: bubble,
                    ),
                  )
                else
                  Positioned(
                    left: left,
                    top: top,
                    width: maxCardW,
                    child: bubble,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SpotlightBackdropPainter extends CustomPainter {
  const _SpotlightBackdropPainter({
    required this.targetRect,
    required this.scrimColor,
    required this.highlightColor,
    required this.pulseAnimation,
  }) : super(repaint: pulseAnimation);

  final Rect? targetRect;
  final Color scrimColor;
  final Color highlightColor;
  final Animation<double> pulseAnimation;

  @override
  void paint(Canvas canvas, Size size) {
    final target = targetRect;
    final pulse = pulseAnimation.value;
    final scrim = Path()..addRect(Offset.zero & size);
    if (target != null) {
      final hole = RRect.fromRectAndRadius(
        target.inflate(8 + pulse * 2),
        const Radius.circular(20),
      );
      scrim
        ..fillType = PathFillType.evenOdd
        ..addRRect(hole);
      canvas.drawPath(scrim, Paint()..color = scrimColor);
      canvas.drawRRect(
        hole,
        Paint()
          ..color = highlightColor.withValues(alpha: 0.24 + pulse * 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawRRect(
        hole,
        Paint()
          ..color = highlightColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      return;
    }
    canvas.drawPath(scrim, Paint()..color = scrimColor);
  }

  @override
  bool shouldRepaint(covariant _SpotlightBackdropPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect ||
      oldDelegate.scrimColor != scrimColor ||
      oldDelegate.highlightColor != highlightColor ||
      oldDelegate.pulseAnimation != pulseAnimation;
}

class _CoachBubble extends StatelessWidget {
  const _CoachBubble({
    required this.arrow,
    required this.partnerLine,
    required this.title,
    required this.body,
    required this.stepLabel,
    required this.progress,
    required this.onClose,
    required this.onSkip,
    required this.onNext,
    required this.nextLabel,
    required this.skipLabel,
    required this.closeTooltip,
    required this.previousLabel,
    required this.colorScheme,
    required this.textTheme,
    this.onBack,
  });

  final DashboardCoachArrow arrow;
  final String partnerLine;
  final String title;
  final String body;
  final String stepLabel;
  final double progress;
  final VoidCallback onClose;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final String nextLabel;
  final String skipLabel;
  final String closeTooltip;
  final String previousLabel;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final arrowWidget = _ArrowGlyph(direction: arrow, color: cs.primary);

    final card = Material(
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: 0.32),
      color: cs.surface,
      shape: RoundedRectangleBorder(
        // شبه دائري عالمي (coach mark).
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    partnerLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                AppPageCloseButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  tooltip: closeTooltip,
                  onPressed: onClose,
                ),
              ],
            ),
            // عنوان التبويب / الموضوع أعلى، ثم فائدة موجزة أسفله.
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                height: 1.35,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress.clamp(0.05, 1.0),
                minHeight: 3.5,
                backgroundColor: cs.surfaceContainerHighest,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stepLabel,
              style: textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(skipLabel),
                ),
                const Spacer(),
                if (onBack != null)
                  TextButton(
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(previousLabel),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(nextLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    switch (arrow) {
      case DashboardCoachArrow.down:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [card, const SizedBox(height: 2), arrowWidget],
        );
      case DashboardCoachArrow.up:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [arrowWidget, const SizedBox(height: 2), card],
        );
      case DashboardCoachArrow.left:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            arrowWidget,
            const SizedBox(width: 2),
            Flexible(child: card),
          ],
        );
      case DashboardCoachArrow.right:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: card),
            const SizedBox(width: 2),
            arrowWidget,
          ],
        );
      case DashboardCoachArrow.none:
        return card;
    }
  }
}

class _ArrowGlyph extends StatelessWidget {
  const _ArrowGlyph({required this.direction, required this.color});

  final DashboardCoachArrow direction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (direction == DashboardCoachArrow.none) {
      return const SizedBox.shrink();
    }
    final angle = switch (direction) {
      DashboardCoachArrow.up => math.pi,
      DashboardCoachArrow.down => 0.0,
      DashboardCoachArrow.left => math.pi / 2,
      DashboardCoachArrow.right => -math.pi / 2,
      DashboardCoachArrow.none => 0.0,
    };
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Transform.rotate(
        angle: angle,
        child: Icon(
          Icons.arrow_drop_down_rounded,
          size: 34,
          color: color,
        ),
      ),
    );
  }
}
