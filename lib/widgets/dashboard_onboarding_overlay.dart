import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

/// خطوة جولة لوحة التحكم: [tabIndex] يطابق فهرس [IndexedStack] في لوحة التحكم؛
/// إن كان null لا يُغيّر التبويب (مثل شرح «إدارتي» دون فتح الشاشة).
class DashboardOnboardingStepData {
  const DashboardOnboardingStepData({
    required this.title,
    required this.body,
    this.tabIndex,
  });

  final String title;
  final String body;
  final int? tabIndex;
}

/// جولة تعريفية: [onTabChange] عند وجود [DashboardOnboardingStepData.tabIndex]،
/// [onComplete] عند «إنهاء» أو «تخطي» أو زر الإغلاق فقط (لا إغلاق بالضغط على الخلفية).
///
/// [onBackdropPointerScroll]: دلتا تمرير عمودية من عجلة/لوحة اللمس فوق الخلفية المعتمة
/// (يُمرَّر للمحتوى خلف الجولة دون تفعيل النقرات).
class DashboardOnboardingOverlay extends StatefulWidget {
  final AppLocalizations l10n;
  final List<DashboardOnboardingStepData> steps;
  final void Function(int tabIndex) onTabChange;
  final VoidCallback onComplete;

  /// `dy` نفس وحدات [PointerScrollEvent.scrollDelta.dy] (موجب نحو الأسفل).
  final ValueChanged<double>? onBackdropPointerScroll;

  const DashboardOnboardingOverlay({
    super.key,
    required this.l10n,
    required this.steps,
    required this.onTabChange,
    required this.onComplete,
    this.onBackdropPointerScroll,
  });

  @override
  State<DashboardOnboardingOverlay> createState() =>
      _DashboardOnboardingOverlayState();
}

class _DashboardOnboardingOverlayState extends State<DashboardOnboardingOverlay> {
  late final PageController _pageController;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    assert(widget.steps.isNotEmpty, 'DashboardOnboardingOverlay.steps');
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyTabForPage(0);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _applyTabForPage(int i) {
    if (i < 0 || i >= widget.steps.length) return;
    final t = widget.steps[i].tabIndex;
    if (t != null) {
      widget.onTabChange(t);
    }
  }

  void _goNext() {
    if (_pageIndex >= widget.steps.length - 1) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _goBack() {
    if (_pageIndex == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final step = widget.steps[_pageIndex];
    final n = widget.steps.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final pageH = math.max(
          160.0,
          math.min(360.0, maxH * 0.36),
        );

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
                      onTap: () {},
                      child: ColoredBox(
                        color: cs.scrim.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Material(
                      color: Colors.transparent,
                      child: GestureDetector(
                        onTap: () {},
                        child: Card(
                          elevation: 8,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 4, 4, 0),
                                child: Row(
                                  children: [
                                    Icon(Icons.explore_outlined,
                                        color: cs.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        step.title,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: t.onboardingClose,
                                      onPressed: widget.onComplete,
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14),
                                child: Row(
                                  children: List.generate(n, (i) {
                                    final active = i <= _pageIndex;
                                    return Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 2),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: active ? 1 : 0.15,
                                            minHeight: 4,
                                            backgroundColor:
                                                cs.surfaceContainerHighest,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                child: Text(
                                  t.onboardingStepCounter(_pageIndex + 1, n),
                                  style: textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: pageH,
                                child: PageView.builder(
                                  controller: _pageController,
                                  itemCount: widget.steps.length,
                                  onPageChanged: (i) {
                                    setState(() => _pageIndex = i);
                                    _applyTabForPage(i);
                                  },
                                  itemBuilder: (context, index) {
                                    return _stepBody(
                                      context,
                                      widget.steps[index].body,
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    10, 0, 10, 12),
                                child: Row(
                                  children: [
                                    TextButton(
                                      onPressed: widget.onComplete,
                                      child: Text(t.onboardingSkip),
                                    ),
                                    const Spacer(),
                                    if (_pageIndex > 0) ...[
                                      TextButton(
                                        onPressed: _goBack,
                                        child: Text(t.onboardingPrevious),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    if (_pageIndex < n - 1)
                                      FilledButton(
                                        onPressed: _goNext,
                                        child: Text(t.onboardingNext),
                                      )
                                    else
                                      FilledButton(
                                        onPressed: widget.onComplete,
                                        child: Text(t.onboardingFinish),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
      },
    );
  }

  Widget _stepBody(BuildContext context, String body) {
    final cs = Theme.of(context).colorScheme;
    final textScaler = MediaQuery.textScalerOf(context);
    const base = 14.0;
    final bodySize = textScaler.scale(base).clamp(12.0, 22.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          child: Text(
            body,
            textAlign: TextAlign.start,
            style: TextStyle(
              height: 1.45,
              fontSize: bodySize,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
