import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

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
    /// موضع أفقي تقريبي للسهم (0=بداية، 1=نهاية) فوق شريط التنقل السفلي.
    this.navFraction,
  });

  final String title;
  final String body;
  final int? tabIndex;
  final DashboardCoachArrow arrow;

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
  final Duration autoAdvance;
  final ValueChanged<double>? onBackdropPointerScroll;

  const DashboardOnboardingOverlay({
    super.key,
    required this.l10n,
    required this.steps,
    required this.onTabChange,
    required this.onComplete,
    required this.partnerLine,
    this.autoAdvance = const Duration(seconds: 9),
    this.onBackdropPointerScroll,
  });

  @override
  State<DashboardOnboardingOverlay> createState() =>
      _DashboardOnboardingOverlayState();
}

class _DashboardOnboardingOverlayState extends State<DashboardOnboardingOverlay>
    with SingleTickerProviderStateMixin {
  int _pageIndex = 0;
  Timer? _autoTimer;
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
      _armAutoAdvance();
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _armAutoAdvance() {
    _autoTimer?.cancel();
    _autoTimer = Timer(widget.autoAdvance, () {
      if (!mounted) return;
      if (_pageIndex >= widget.steps.length - 1) {
        return;
      }
      unawaited(_goNext());
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
    setState(() => _pageIndex += 1);
    _applyTabForPage(_pageIndex);
    _armAutoAdvance();
  }

  Future<void> _goBack() async {
    if (_pageIndex == 0) return;
    setState(() => _pageIndex -= 1);
    _applyTabForPage(_pageIndex);
    _armAutoAdvance();
  }

  void _finishAll() {
    _autoTimer?.cancel();
    widget.onComplete();
  }

  void _onBackdropTap() {
    _autoTimer?.cancel();
    unawaited(_goNext());
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
    final step = widget.steps[_pageIndex];
    final n = widget.steps.length;
    final w = MediaQuery.sizeOf(context).width;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // فقاعة مضغوطة شبه دائرية — لا تغطي الشاشة.
    final maxCardW = (w * 0.78).clamp(240.0, 300.0);

    return ScrollConfiguration(
      behavior: const AqarScrollBehavior(),
      child: SafeArea(
        child: Stack(
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
                  onTap: _onBackdropTap,
                  child: ColoredBox(
                    // خلفية خفيفة حتى تبقى التبويبات مرئية خلف الفقاعة.
                    color: cs.scrim.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ),
            Align(
              alignment: _bubbleAlignment(step, rtl),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final lift = 1.0 + (_pulse.value * 0.014);
                    return Transform.scale(scale: lift, child: child);
                  },
                  child: GestureDetector(
                    onTap: () {},
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxCardW),
                      child: _CoachBubble(
                        arrow: step.arrow,
                        partnerLine: widget.partnerLine,
                        title: step.title,
                        body: step.body,
                        stepLabel: t.onboardingStepCounter(_pageIndex + 1, n),
                        progress: (_pageIndex + 1) / n,
                        onClose: _finishAll,
                        onSkip: _finishAll,
                        onBack: _pageIndex > 0
                            ? () {
                                _autoTimer?.cancel();
                                unawaited(_goBack());
                              }
                            : null,
                        onNext: () {
                          _autoTimer?.cancel();
                          unawaited(_goNext());
                        },
                        nextLabel: _pageIndex < n - 1
                            ? t.onboardingNext
                            : t.onboardingFinish,
                        skipLabel: t.onboardingSkip,
                        closeTooltip: t.onboardingClose,
                        previousLabel: t.onboardingPrevious,
                        colorScheme: cs,
                        textTheme: textTheme,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                IconButton(
                  tooltip: closeTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
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
